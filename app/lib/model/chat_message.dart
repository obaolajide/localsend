enum ChatMessageType { text, file }

class ChatMessage {
  final String id;
  final DateTime timestamp;
  final bool isSender;
  final ChatMessageType type;
  final String content;

  const ChatMessage({required this.id, required this.timestamp, required this.isSender, required this.type, required this.content});

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
    isSender: json['isSender'] as bool,
    type: ChatMessageType.values.byName(json['type'] as String),
    content: json['content'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'isSender': isSender,
    'type': type.name,
    'content': content,
  };
}
