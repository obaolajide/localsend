import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/model/chat_message.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One JSON file per peer. Writes for the same peer run in order.
class ChatStore {
  static final _fingerprintPattern = RegExp(r'^[0-9A-F]{64}$');
  static final _historyFilePattern = RegExp(r'^chat_([0-9A-Fa-f]{64})\.json$');
  final _pending = <String, Future<void>>{};
  final Future<Directory> Function() _documentsDirectory;

  ChatStore({Future<Directory> Function()? documentsDirectory}) : _documentsDirectory = documentsDirectory ?? getApplicationDocumentsDirectory;

  String _normalize(String fingerprint) {
    final normalized = fingerprint.toUpperCase();
    if (!_fingerprintPattern.hasMatch(normalized)) {
      throw ArgumentError.value(fingerprint, 'fingerprint', 'Invalid device fingerprint');
    }
    return normalized;
  }

  Future<File> _file(String fingerprint) async {
    final directory = await _documentsDirectory();
    return File(p.join(directory.path, 'chat_$fingerprint.json'));
  }

  Future<List<ChatMessage>> load(String fingerprint) async {
    final key = _normalize(fingerprint);
    await _pending[key];
    return _read(await _file(key));
  }

  /// Finds saved conversations without requiring the peers to be online.
  Future<Map<String, List<ChatMessage>>> loadConversations() async {
    final directory = await _documentsDirectory();
    if (!await directory.exists()) return {};
    final result = <String, List<ChatMessage>>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final match = _historyFilePattern.firstMatch(p.basename(entity.path));
      if (match == null) continue;
      final fingerprint = match.group(1)!.toUpperCase();
      final messages = await load(fingerprint);
      if (messages.isNotEmpty) result[fingerprint] = messages;
    }
    return result;
  }

  Future<List<ChatMessage>> append(String fingerprint, ChatMessage message) {
    final key = _normalize(fingerprint);
    final result = (_pending[key] ?? Future<void>.value()).then((_) async {
      final file = await _file(key);
      final messages = await _read(file);
      if (messages.any((item) => item.id == message.id)) return messages;
      final updated = [...messages, message];
      final trimmed = updated.length > 1000 ? updated.sublist(updated.length - 1000) : updated;
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(trimmed.map((item) => item.toJson()).toList()), flush: true);
      await temporary.rename(file.path);
      return trimmed;
    });
    _pending[key] = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<ChatMessage>> _read(File file) async {
    if (!await file.exists()) return [];
    try {
      final entries = jsonDecode(await file.readAsString()) as List<dynamic>;
      return entries.map((entry) => ChatMessage.fromJson(entry as Map<String, dynamic>)).toList();
    } catch (_) {
      final bad = File('${file.path}.bad');
      if (await bad.exists()) await bad.delete();
      await file.rename(bad.path);
      return [];
    }
  }
}
