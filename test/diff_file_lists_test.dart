import 'package:flutter_test/flutter_test.dart';
import 'package:smoothandesign_folder_watcher/smoothandesign_folder_watcher.dart';

/// [diffFileLists] simule [SmoothFolderWatcher.changes] par polling sur
/// iOS/Android (pas de FSEvents) — ce test verrouille qu'il détecte les
/// trois cas (apparition, modification, disparition), pas seulement celui
/// qu'on aurait pensé à tester en premier.
void main() {
  WatchedFile file(String name, {int sizeBytes = 100, DateTime? modifiedAt}) {
    return WatchedFile(
      name: name,
      path: '/dossier/$name',
      modifiedAt: modifiedAt ?? DateTime(2026, 10, 30),
      sizeBytes: sizeBytes,
    );
  }

  test('un nouveau fichier -> created', () {
    final changes = diffFileLists(previous: const [], current: [file('mix.wav')]);

    expect(changes, hasLength(1));
    expect(changes.single.path, '/dossier/mix.wav');
    expect(changes.single.type, FolderFileChangeType.created);
  });

  test('taille qui change -> modified (même date de modification)', () {
    final before = file('mix.wav', sizeBytes: 100, modifiedAt: DateTime(2026, 10, 30));
    final after = file('mix.wav', sizeBytes: 500, modifiedAt: DateTime(2026, 10, 30));

    final changes = diffFileLists(previous: [before], current: [after]);

    expect(changes.single.type, FolderFileChangeType.modified);
  });

  test('date de modification qui change -> modified', () {
    final before = file('mix.wav', modifiedAt: DateTime(2026, 10, 30, 10, 0));
    final after = file('mix.wav', modifiedAt: DateTime(2026, 10, 30, 10, 5));

    final changes = diffFileLists(previous: [before], current: [after]);

    expect(changes.single.type, FolderFileChangeType.modified);
  });

  test('fichier disparu -> removed', () {
    final changes = diffFileLists(previous: [file('ancien.wav')], current: const []);

    expect(changes.single.path, '/dossier/ancien.wav');
    expect(changes.single.type, FolderFileChangeType.removed);
  });

  test('aucun changement -> liste vide, pas un faux "modified"', () {
    final f = file('stable.wav');

    final changes = diffFileLists(previous: [f], current: [f]);

    expect(changes, isEmpty);
  });

  test('plusieurs changements simultanés sont tous rapportés', () {
    final changes = diffFileLists(
      previous: [file('reste.wav'), file('disparu.wav')],
      current: [file('reste.wav'), file('nouveau.wav')],
    );

    expect(changes, hasLength(2));
    expect(changes.map((c) => c.type), containsAll([
      FolderFileChangeType.created,
      FolderFileChangeType.removed,
    ]));
  });
}
