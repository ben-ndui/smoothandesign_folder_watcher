import 'dart:async';

import 'package:flutter/services.dart';

/// Type de changement détecté par FSEvents sur un fichier surveillé.
enum FolderFileChangeType { created, modified, removed, renamed, unknown }

/// Un changement détecté dans le dossier surveillé.
class FolderFileChange {
  const FolderFileChange({required this.path, required this.type});

  final String path;
  final FolderFileChangeType type;
}

/// Un fichier listé dans le dossier surveillé.
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

/// Choisir et surveiller un dossier local sur macOS.
///
/// Porté du prototype Xplor (Ben NDUI, 26/01/2024, `DirectorySurveillance.swift`) :
/// le moteur FSEvents est repris tel quel côté natif, mais [pickDirectory]
/// ouvre désormais un vrai sélecteur natif (`NSOpenPanel`) — le prototype
/// d'origine faisait taper le chemin du dossier à la main dans un champ
/// texte, et n'avait jamais câblé l'envoi des fichiers détectés.
class SmoothFolderWatcher {
  SmoothFolderWatcher._();

  static const MethodChannel _methods =
      MethodChannel('smoothandesign_folder_watcher/methods');
  static const EventChannel _events =
      EventChannel('smoothandesign_folder_watcher/events');

  static Stream<FolderFileChange>? _changes;

  /// Ouvre le sélecteur de dossier natif. `null` si l'utilisateur annule.
  static Future<String?> pickDirectory() {
    return _methods.invokeMethod<String>('pickDirectory');
  }

  /// Liste le contenu actuel du dossier (non récursif).
  static Future<List<WatchedFile>> listFiles(String path) async {
    final raw =
        await _methods.invokeMethod<List<dynamic>>('listFiles', {'path': path});
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

  /// Démarre la surveillance du dossier — les changements arrivent sur
  /// [changes]. Un seul dossier surveillé à la fois : un nouvel appel
  /// remplace la surveillance précédente côté natif.
  static Future<void> startWatching(String path) {
    return _methods.invokeMethod('startWatching', {'path': path});
  }

  static Future<void> stopWatching() {
    return _methods.invokeMethod('stopWatching');
  }

  /// Flux des changements détectés depuis le dernier [startWatching].
  static Stream<FolderFileChange> get changes {
    return _changes ??= _events.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return FolderFileChange(
        path: map['path'] as String,
        type: _parseType(map['type'] as String),
      );
    });
  }

  static FolderFileChangeType _parseType(String raw) {
    return FolderFileChangeType.values.firstWhere(
      (t) => t.name == raw,
      orElse: () => FolderFileChangeType.unknown,
    );
  }
}
