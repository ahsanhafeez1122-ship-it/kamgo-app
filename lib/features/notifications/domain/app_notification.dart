class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    this.body,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: j['type'] as String,
        title: j['title'] as String,
        body: j['body'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        readAt: j['read_at'] == null ? null : DateTime.parse(j['read_at'] as String),
      );

  final String id;
  final String type;
  final String title;
  final String? body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;
}

abstract interface class NotificationsRepository {
  Future<List<AppNotification>> latest({int limit = 30});
  Future<void> markAllRead();
}
