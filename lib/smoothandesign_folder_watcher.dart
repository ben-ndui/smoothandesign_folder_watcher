import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Type de changement détecté sur un fichier surveillé.
///
/// Sur macOS, directement rapporté par FSEvents. Sur iOS/Android — qui
/// n'ont pas d'équivalent public pour un dossier arbitraire — calculé côté
/// Dart en comparant deux [listFiles] successifs (voir [diffFileLists]).
enum FolderFileChangeType { created, modified, removed, renamed, unknown }

/// Un changement détecté dans le dossier surveillé.
class FolderFileChange {
  const FolderFileChange({required this.path, required this.type});

  final String path;
  final FolderFileChangeType type;
}

/// Un fichier listé dans le dossier surveillé.
///
/// [path] est un identifiant stable pour CE fichier, à repasser à
/// [listFiles]/[resolveLocalPath] — sa forme dépend de la plateforme
/// (chemin disque réel sur macOS/iOS, `content://` URI sur Android).
class WatchedFile {
  const WatchedFile({
    required this.name,
    required this.path,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final String name;
  final String path;
  final DateTime modifiedAt;
  final int sizeBytes;
}

/// Un dossier choisi par [SmoothFolderWatcher.pickDirectory].
///
/// [bookmark] permet de relire ce dossier après un relancement de l'app :
/// security-scoped bookmark sur macOS/iOS (l'accès accordé par le sélecteur
/// natif ne survit pas à la session sans lui), URI de l'arbre SAF encodée
/// en UTF-8 sur Android (permission persistée via
/// `takePersistableUriPermission`). [bookmark] doit donc être persisté (ex.
/// `base64Encode(bookmark)`) et repassé tel quel à [listFiles] /
/// [startWatching], même après un redémarrage de l'app.
class PickedDirectory {
  const PickedDirectory({required this.path, required this.bookmark});

  final String path;
  final Uint8List bookmark;
}

/// Choisir et surveiller un dossier local : macOS, iOS, Android.
///
/// Porté du prototype Xplor (Ben NDUI, 26/01/2024, `DirectorySurveillance.swift`) :
/// le moteur FSEvents est repris tel quel côté natif macOS, mais
/// [pickDirectory] ouvre désormais un vrai sélecteur natif au lieu de faire
/// taper le chemin à la main.
///
/// ⚠️ Seul macOS a une surveillance en temps réel (FSEvents). iOS et Android
/// n'exposent aucune API publique équivalente pour un dossier arbitraire —
/// [startWatching] y relit [listFiles] toutes les 5 secondes et calcule les
/// changements côté Dart ([diffFileLists]). [changes] a donc la même
/// signature partout, mais pas la même latence : quasi instantané sur
/// macOS, jusqu'à 5 secondes de retard ailleurs.
class SmoothFolderWatcher {
  SmoothFolderWatcher._();

  static const MethodChannel _methods =
      MethodChannel('smoothandesign_folder_watcher/methods');
  static const EventChannel _events =
      EventChannel('smoothandesign_folder_watcher/events');

  static const Duration pollInterval = Duration(seconds: 5);

  static Stream<FolderFileChange>? _nativeChanges;
  static StreamController<FolderFileChange>? _pollController;
  static Timer? _pollTimer;
  static List<WatchedFile> _lastPoll = const [];

  /// `true` sur macOS, seule plateforme avec un vrai moteur de surveillance
  /// natif (FSEvents). Exposé pour que l'app appelante puisse, si elle le
  /// souhaite, informer l'utilisateur que la mise à jour n'est pas instantanée.
  static bool get supportsLiveWatch => Platform.isMacOS;

  /// Ouvre le sélecteur de dossier natif. `null` si l'utilisateur annule.
  static Future<PickedDirectory?> pickDirectory() async {
    final raw = await _methods.invokeMethod<Map<dynamic, dynamic>>('pickDirectory');
    if (raw == null) return null;
    return PickedDirectory(
      path: raw['path'] as String,
      bookmark: (raw['bookmark'] as Uint8List),
    );
  }

  /// Liste le contenu actuel du dossier (non récursif).
  static Future<List<WatchedFile>> listFiles(Uint8List bookmark) async {
    final raw = await _methods.invokeMethod<List<dynamic>>(
      'listFiles',
      {'bookmark': bookmark},
    );
    if (raw == null) return const [];
    return raw.map((entry) {
      final map = Map<String, dynamic>.from(entry as Map);
      return WatchedFile(
        name: map['name'] as String,
        path: map['path'] as String,
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(
          ((map['modifiedAtEpochSeconds'] as num) * 1000).round(),
        ),
        sizeBytes: (map['sizeBytes'] as num).toInt(),
      );
    }).toList();
  }

  /// Donne un chemin disque réel et durablement lisible pour [file], prêt
  /// pour un upload (`File(path).readAsBytes()`).
  ///
  /// Sur macOS, [file.path] est déjà un chemin réel et l'accès reste ouvert
  /// tant que [startWatching] n'a pas été arrêté par [stopWatching] — rien
  /// à faire. Sur iOS, l'accès security-scoped n'est ouvert que le temps de
  /// [listFiles] : une copie dans le cache de l'app est nécessaire pour lire
  /// le fichier plus tard. Sur Android, [file.path] est une `content://`
  /// URI, jamais un chemin disque — la copie est la SEULE façon d'obtenir
  /// un fichier exploitable par le reste de l'app (upload, partage...).
  static Future<String> resolveLocalPath({
    required Uint8List bookmark,
    required WatchedFile file,
  }) async {
    if (Platform.isMacOS) return file.path;
    final localPath = await _methods.invokeMethod<String>('copyToLocalFile', {
      'bookmark': bookmark,
      'fileUri': file.path,
    });
    return localPath!;
  }

  /// Démarre la surveillance du dossier — les changements arrivent sur
  /// [changes]. Un seul dossier surveillé à la fois : un nouvel appel
  /// remplace la surveillance précédente.
  static Future<void> startWatching(Uint8List bookmark) async {
    if (supportsLiveWatch) {
      await _methods.invokeMethod('startWatching', {'bookmark': bookmark});
      return;
    }
    await _startPolling(bookmark);
  }

  static Future<void> stopWatching() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (supportsLiveWatch) {
      await _methods.invokeMethod('stopWatching');
    }
  }

  /// Flux des changements détectés depuis le dernier [startWatching].
  static Stream<FolderFileChange> get changes {
    if (supportsLiveWatch) {
      return _nativeChanges ??= _events.receiveBroadcastStream().map((event) {
        final map = Map<String, dynamic>.from(event as Map);
        return FolderFileChange(
          path: map['path'] as String,
          type: _parseType(map['type'] as String),
        );
      });
    }
    return (_pollController ??= StreamController<FolderFileChange>.broadcast()).stream;
  }

  static Future<void> _startPolling(Uint8List bookmark) async {
    _pollTimer?.cancel();
    _pollController ??= StreamController<FolderFileChange>.broadcast();
    _lastPoll = await listFiles(bookmark);
    _pollTimer = Timer.periodic(pollInterval, (_) async {
      final current = await listFiles(bookmark);
      for (final change in diffFileLists(previous: _lastPoll, current: current)) {
        _pollController?.add(change);
      }
      _lastPoll = current;
    });
  }

  static FolderFileChangeType _parseType(String raw) {
    return FolderFileChangeType.values.firstWhere(
      (t) => t.name == raw,
      orElse: () => FolderFileChangeType.unknown,
    );
  }
}

/// Compare deux listings successifs et renvoie les changements entre les
/// deux — c'est ce que le polling iOS/Android utilise pour simuler
/// [SmoothFolderWatcher.changes] en l'absence de surveillance native.
/// Fonction pure, testable indépendamment du Timer.
List<FolderFileChange> diffFileLists({
  required List<WatchedFile> previous,
  required List<WatchedFile> current,
}) {
  final previousByPath = {for (final f in previous) f.path: f};
  final currentByPath = {for (final f in current) f.path: f};
  final changes = <FolderFileChange>[];

  for (final entry in currentByPath.entries) {
    final before = previousByPath[entry.key];
    if (before == null) {
      changes.add(FolderFileChange(path: entry.key, type: FolderFileChangeType.created));
    } else if (before.modifiedAt != entry.value.modifiedAt || before.sizeBytes != entry.value.sizeBytes) {
      changes.add(FolderFileChange(path: entry.key, type: FolderFileChangeType.modified));
    }
  }
  for (final path in previousByPath.keys) {
    if (!currentByPath.containsKey(path)) {
      changes.add(FolderFileChange(path: path, type: FolderFileChangeType.removed));
    }
  }
  return changes;
}
