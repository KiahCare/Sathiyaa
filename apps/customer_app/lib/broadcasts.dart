// A message sent to everybody, as it arrives at one person's phone.
//
// The admin console has been able to send these for a long time, and the
// server has had the whole delivery half -- a recipients table, an unread
// count, a mark-as-read endpoint -- since the broadcast_recipients migration.
// Neither app ever called any of it. An admin sent a message, the console
// reported it delivered to 412 people, and 412 people were shown nothing.
//
// This is the model both apps read them back with. Shared, and copied by
// _builds/sync-design.ps1, so the two do not drift on a field name.

/// One message from Sathiyaa.
class Broadcast {
  final String id;
  final String title;
  final String message;
  final String? imageUrl;
  final DateTime sentAt;

  /// Whether this phone has opened it. Read state lives on the server, not on
  /// the device, so it is the same on a reinstall and the console's unread
  /// figure means something.
  bool read;

  Broadcast({
    required this.id,
    required this.title,
    required this.message,
    required this.sentAt,
    this.imageUrl,
    this.read = false,
  });

  factory Broadcast.fromJson(Map m) => Broadcast(
        id: '${m['id']}',
        title: '${m['title'] ?? ''}',
        message: '${m['message'] ?? ''}',
        imageUrl: (m['imageUrl'] as String?)?.isEmpty ?? true
            ? null
            : m['imageUrl'] as String?,
        sentAt: DateTime.tryParse('${m['sentAt']}')?.toLocal() ?? DateTime.now(),
        read: m['read'] == true,
      );
}
