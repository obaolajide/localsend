import 'dart:async';
import 'dart:convert';

import 'package:localsend_app/model/chat_message.dart';
import 'package:localsend_app/provider/chat_store.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

final chatProvider = NotifierProvider<ChatService, Map<String, List<ChatMessage>>>((ref) => ChatService());
final _logger = Logger('Chat');

class ChatService extends Notifier<Map<String, List<ChatMessage>>> {
  final _store = ChatStore();
  final _loads = <String, Future<void>>{};
  static const _uuid = Uuid();

  @override
  Map<String, List<ChatMessage>> init() => {};

  Future<void> load(String fingerprint) {
    final key = fingerprint.toUpperCase();
    return _loads.putIfAbsent(key, () async {
      try {
        final messages = await _store.load(key);
        state = {...state, key: List.unmodifiable(messages)};
      } catch (_) {
        unawaited(_loads.remove(key) ?? Future<void>.value());
        rethrow;
      }
    });
  }

  Future<void> loadConversations() async {
    final conversations = await _store.loadConversations();
    state = {
      ...conversations.map((key, value) => MapEntry(key, List<ChatMessage>.unmodifiable(value))),
      ...state,
    };
  }

  /// Returns a visible error on failure; a successful send is then saved locally.
  Future<String?> sendText(Device target, String text) async {
    final content = text.trim();
    if (content.isEmpty || utf8.encode(content).length > 4096) return 'Message must be between 1 and 4096 bytes';
    if (!target.channels.whereType<HttpChannel>().any((channel) => channel.https)) return 'Chat requires encryption';
    final message = ChatMessage(
      id: _uuid.v4(),
      timestamp: DateTime.now().toUtc(),
      isSender: true,
      type: ChatMessageType.text,
      content: content,
    );
    try {
      final stream = ref
          .redux(parentIsolateProvider)
          .dispatchTakeResult(
            IsolateHttpChatSendAction(
              device: target,
              messageId: message.id,
              timestamp: message.timestamp.toIso8601String(),
              content: content,
            ),
          );
      HttpChatSentEvent? outcome;
      await for (final event in stream) {
        if (event is HttpChatSentEvent) outcome = event;
      }
      if (outcome == null || outcome.error != null) return outcome?.error ?? 'Failed to send message';
      await _append(target.fingerprint, message);
      return null;
    } catch (_) {
      return 'Failed to send message';
    }
  }

  void onReceived(HttpServerChatReceivedEvent event) {
    final fingerprint = event.certFingerprint.toUpperCase();
    final nearby = ref.read(nearbyDevicesProvider).allDevices.values.any((device) => device.fingerprint.toUpperCase() == fingerprint);
    final favorite = ref.read(favoritesProvider).any((device) => device.fingerprint.toUpperCase() == fingerprint);
    if (!nearby && !favorite) return;
    unawaited(
      _append(
        fingerprint,
        ChatMessage(id: event.id, timestamp: DateTime.now().toUtc(), isSender: false, type: ChatMessageType.text, content: event.content),
      ).catchError((Object error, StackTrace stackTrace) {
        _logger.warning('Could not save received chat message', error, stackTrace);
      }),
    );
  }

  Future<void> addFileMessage(String fingerprint, String path, {required bool isSender, required String messageId}) {
    return _append(
      fingerprint,
      ChatMessage(id: messageId, timestamp: DateTime.now().toUtc(), isSender: isSender, type: ChatMessageType.file, content: path),
    );
  }

  Future<void> _append(String fingerprint, ChatMessage message) async {
    final key = fingerprint.toUpperCase();
    final messages = await _store.append(key, message);
    state = {...state, key: List.unmodifiable(messages)};
  }
}
