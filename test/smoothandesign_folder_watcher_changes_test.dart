import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoothandesign_folder_watcher/smoothandesign_folder_watcher.dart';

/// Le natif encode un type de changement FSEvents en String (`created`,
/// `modified`, `removed`, `renamed`) — ce test verrouille que le Dart les
/// comprend TOUS, pas seulement celui qu'on a pensé à tester en premier.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const events = EventChannel('smoothandesign_folder_watcher/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void emit(Map<String, dynamic> payload) {
    final codec = events.codec;
    messenger.handlePlatformMessage(
      events.name,
      codec.encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  setUp(() {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {},
        onCancel: (arguments) {},
      ),
    );
  });

  tearDown(() {
    messenger.setMockStreamHandler(events, null);
  });

  Future<FolderFileChange> firstChange() {
    return SmoothFolderWatcher.changes.first;
  }

  test('created', () async {
    final future = firstChange();
    emit({'path': '/a/mix.wav', 'type': 'created'});
    expect((await future).type, FolderFileChangeType.created);
  });

  test('modified', () async {
    final future = firstChange();
    emit({'path': '/a/mix.wav', 'type': 'modified'});
    expect((await future).type, FolderFileChangeType.modified);
  });

  test('removed', () async {
    final future = firstChange();
    emit({'path': '/a/mix.wav', 'type': 'removed'});
    expect((await future).type, FolderFileChangeType.removed);
  });

  test('renamed', () async {
    final future = firstChange();
    emit({'path': '/a/mix.wav', 'type': 'renamed'});
    expect((await future).type, FolderFileChangeType.renamed);
  });

  test('un type natif inconnu retombe sur unknown plutôt que de planter', () async {
    final future = firstChange();
    emit({'path': '/a/mix.wav', 'type': 'something-new-from-a-future-macos'});
    expect((await future).type, FolderFileChangeType.unknown);
  });

  test('le chemin est transmis tel quel', () async {
    final future = firstChange();
    emit({'path': '/a/mix.wav', 'type': 'created'});
    expect((await future).path, '/a/mix.wav');
  });
}
