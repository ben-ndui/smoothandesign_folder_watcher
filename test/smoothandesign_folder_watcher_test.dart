import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoothandesign_folder_watcher/smoothandesign_folder_watcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('smoothandesign_folder_watcher/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];
  final fakeBookmark = Uint8List.fromList([1, 2, 3, 4]);

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'pickDirectory':
          return {
            'path': '/Users/ingenieur/Enregistrements',
            'bookmark': fakeBookmark,
          };
        case 'listFiles':
          return [
            {
              'name': 'mix_final.wav',
              'path': '/Users/ingenieur/Enregistrements/mix_final.wav',
              'modifiedAtEpochSeconds': 1735689600,
              'sizeBytes': 204800,
            },
          ];
        case 'startWatching':
        case 'stopWatching':
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
  });

  test('pickDirectory renvoie le chemin ET le bookmark security-scoped', () async {
    final picked = await SmoothFolderWatcher.pickDirectory();

    expect(picked, isNotNull);
    expect(picked!.path, '/Users/ingenieur/Enregistrements');
    expect(picked.bookmark, fakeBookmark);
    expect(calls.single.method, 'pickDirectory');
  });

  test('pickDirectory renvoie null quand l\'utilisateur annule', () async {
    messenger.setMockMethodCallHandler(methods, (call) async => null);

    final picked = await SmoothFolderWatcher.pickDirectory();

    expect(picked, isNull);
  });

  test('listFiles reconstruit les WatchedFile depuis la réponse native', () async {
    final files = await SmoothFolderWatcher.listFiles(fakeBookmark);

    expect(files, hasLength(1));
    expect(files.single.name, 'mix_final.wav');
    expect(files.single.sizeBytes, 204800);
    expect(files.single.modifiedAt, DateTime.fromMillisecondsSinceEpoch(1735689600 * 1000));
    expect(calls.single.arguments, {'bookmark': fakeBookmark});
  });

  test('listFiles renvoie une liste vide dossier sans fichier (pas null, pas d\'exception)', () async {
    messenger.setMockMethodCallHandler(methods, (call) async => <dynamic>[]);

    final files = await SmoothFolderWatcher.listFiles(fakeBookmark);

    expect(files, isEmpty);
  });

  test('startWatching transmet le bookmark au natif, pas un simple chemin', () async {
    await SmoothFolderWatcher.startWatching(fakeBookmark);

    expect(calls.single.method, 'startWatching');
    expect(calls.single.arguments, {'bookmark': fakeBookmark});
  });

  test('stopWatching ne transmet aucun argument', () async {
    await SmoothFolderWatcher.stopWatching();

    expect(calls.single.method, 'stopWatching');
  });
}
