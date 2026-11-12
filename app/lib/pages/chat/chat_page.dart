import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localsend_app/model/chat_message.dart';
import 'package:localsend_app/provider/chat_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';

const _background = Color(0xFF10151C);
const _panel = Color(0xFF1C2631);
const _accent = Color(0xFF72D4C8);

class ChatPage extends StatefulWidget {
  final String fingerprint;
  final String alias;

  const ChatPage({required this.fingerprint, required this.alias, super.key});

  ChatPage.forDevice({required Device device, super.key}) : fingerprint = device.fingerprint, alias = device.alias;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          context.ref.notifier(chatProvider).load(widget.fingerprint).catchError((Object error) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load chat history')));
          }),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final device = _onlineDevice();
    if (device == null) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final error = await context.ref.notifier(chatProvider).sendText(device, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error == null) {
      _controller.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Device? _onlineDevice() {
    for (final device in context.ref.read(nearbyDevicesProvider).allDevices.values) {
      if (device.fingerprint.toUpperCase() == widget.fingerprint.toUpperCase()) return device;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final messages = context.ref.watch(chatProvider)[widget.fingerprint.toUpperCase()] ?? const <ChatMessage>[];
    final onlineDevice = context.ref
        .watch(nearbyDevicesProvider)
        .allDevices
        .values
        .where((device) => device.fingerprint.toUpperCase() == widget.fingerprint.toUpperCase())
        .firstOrNull;
    final canSend = onlineDevice?.channels.whereType<HttpChannel>().any((channel) => channel.https) ?? false;
    final alias = onlineDevice?.alias ?? widget.alias;
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _background,
        colorScheme: const ColorScheme.dark(primary: _accent, surface: _background),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _background,
          titleSpacing: 0,
          title: Row(
            children: [
              _Avatar(alias: alias, fingerprint: widget.fingerprint),
              const SizedBox(width: 12),
              Expanded(child: Text(alias, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? const Center(
                        child: Text('No messages yet', style: TextStyle(color: Colors.white54)),
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        itemCount: messages.length,
                        itemBuilder: (context, index) => _MessageItem(message: messages[messages.length - index - 1]),
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: const BoxDecoration(
                  color: _panel,
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: canSend && !_sending,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: canSend
                              ? 'Message $alias'
                              : onlineDevice == null
                              ? 'Device offline'
                              : 'Chat requires encryption',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Send message',
                      onPressed: canSend && !_sending ? _send : null,
                      icon: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String alias;
  final String fingerprint;

  const _Avatar({required this.alias, required this.fingerprint});

  @override
  Widget build(BuildContext context) {
    final hue = fingerprint.length >= 6 ? int.tryParse(fingerprint.substring(0, 6), radix: 16) ?? 0 : 0;
    final color = HSVColor.fromAHSV(1, (hue % 360).toDouble(), 0.45, 0.62).toColor();
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(
        alias.isEmpty ? '?' : alias[0].toUpperCase(),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

class _MessageItem extends StatelessWidget {
  final ChatMessage message;

  const _MessageItem({required this.message});

  @override
  Widget build(BuildContext context) {
    final outgoing = message.isSender;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: message.type == ChatMessageType.text
              ? DecoratedBox(
                  decoration: BoxDecoration(color: outgoing ? const Color(0xFF276D69) : _panel, borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Text(message.content, style: const TextStyle(fontSize: 15, height: 1.35)),
                  ),
                )
              : _FileCard(path: message.content),
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final String path;

  const _FileCard({required this.path});

  @override
  Widget build(BuildContext context) {
    final isContentUri = path.startsWith('content://');
    return InkWell(
      onTap: () => openFile(context, FileType.other, path),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, color: _accent, size: 30),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.basename(path),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (!isContentUri)
                    FutureBuilder<FileStat>(
                      future: File(path).stat(),
                      builder: (context, snapshot) {
                        final stat = snapshot.data;
                        final label = stat == null || stat.type == FileSystemEntityType.notFound ? 'File missing' : _size(stat.size);
                        return Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12));
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
