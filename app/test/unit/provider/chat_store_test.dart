import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/chat_message.dart';
import 'package:localsend_app/provider/chat_store.dart';

const fingerprint = 'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899';

ChatMessage message(String id) => ChatMessage(
  id: id,
  timestamp: DateTime.utc(2026, 10, 6),
  isSender: true,
  type: ChatMessageType.text,
  content: id,
);

void main() {
  test('serializes concurrent appends and ignores duplicate ids', () async {
    final directory = await Directory.systemTemp.createTemp('localsend-chat-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ChatStore(documentsDirectory: () async => directory);

    await Future.wait([
      store.append(fingerprint, message('first')),
      store.append(fingerprint, message('second')),
      store.append(fingerprint, message('first')),
    ]);

    expect((await store.load(fingerprint)).map((item) => item.id), ['first', 'second']);
    expect(await File('${directory.path}${Platform.pathSeparator}chat_$fingerprint.json').exists(), isTrue);
  });

  test('rejects unsafe fingerprints before constructing a path', () async {
    final directory = await Directory.systemTemp.createTemp('localsend-chat-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ChatStore(documentsDirectory: () async => directory);
    expect(() => store.append('../outside', message('bad')), throwsArgumentError);
  });

  test('quarantines corrupt history and starts a fresh conversation', () async {
    final directory = await Directory.systemTemp.createTemp('localsend-chat-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}chat_$fingerprint.json');
    await file.writeAsString('broken JSON');
    final store = ChatStore(documentsDirectory: () async => directory);

    expect(await store.load(fingerprint), isEmpty);
    expect(await File('${file.path}.bad').readAsString(), 'broken JSON');
    await store.append(fingerprint, message('new'));
    expect((await store.load(fingerprint)).single.id, 'new');
  });

  test('finds saved conversations while peers are offline', () async {
    final directory = await Directory.systemTemp.createTemp('localsend-chat-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ChatStore(documentsDirectory: () async => directory);
    await store.append(fingerprint, message('saved'));
    await File('${directory.path}${Platform.pathSeparator}unrelated.json').writeAsString('{}');

    final conversations = await ChatStore(documentsDirectory: () async => directory).loadConversations();
    expect(conversations.keys, [fingerprint]);
    expect(conversations[fingerprint]!.single.content, 'saved');
  });
}
