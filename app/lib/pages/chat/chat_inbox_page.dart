import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/model/chat_message.dart';
import 'package:localsend_app/pages/chat/chat_page.dart';
import 'package:localsend_app/provider/chat_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class ChatInboxPage extends StatefulWidget {
  const ChatInboxPage({super.key});

  @override
  State<ChatInboxPage> createState() => _ChatInboxPageState();
}

class _ChatInboxPageState extends State<ChatInboxPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        context.ref.notifier(chatProvider).loadConversations().catchError((Object error) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load conversations')));
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversations = context.ref.watch(chatProvider);
    final online = {
      for (final device in context.ref.watch(nearbyDevicesProvider).allDevices.values) device.fingerprint.toUpperCase(): device,
    };
    final favorites = {
      for (final device in context.ref.watch(favoritesProvider)) device.fingerprint.toUpperCase(): device.alias,
    };
    final fingerprints = {...conversations.keys, ...online.keys, ...favorites.keys}.toList()
      ..sort((a, b) {
        final aTime = conversations[a]?.lastOrNull?.timestamp;
        final bTime = conversations[b]?.lastOrNull?.timestamp;
        if (aTime == null && bTime == null) return a.compareTo(b);
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: fingerprints.isEmpty
          ? const Center(child: Text('No conversations yet. Nearby devices will appear here.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: fingerprints.length,
              itemBuilder: (context, index) {
                final fingerprint = fingerprints[index];
                final device = online[fingerprint];
                final alias = device?.alias ?? favorites[fingerprint] ?? fingerprint.substring(0, 12);
                final lastMessage = conversations[fingerprint]?.lastOrNull;
                final available = device?.channels.whereType<HttpChannel>().any((channel) => channel.https) ?? false;
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.chat_bubble_outline)),
                    title: Text(alias, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      lastMessage == null
                          ? 'No messages yet'
                          : lastMessage.type == ChatMessageType.file
                          ? 'File: ${lastMessage.content.split(RegExp(r'[/\\]')).last}'
                          : lastMessage.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      device == null
                          ? 'Offline'
                          : available
                          ? 'Online'
                          : 'Chat unavailable',
                    ),
                    onTap: () async => await context.push(() => ChatPage(fingerprint: fingerprint, alias: alias)),
                  ),
                );
              },
            ),
    );
  }
}
