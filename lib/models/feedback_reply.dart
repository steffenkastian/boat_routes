import 'package:cloud_firestore/cloud_firestore.dart';

// An admin's reply to a FeedbackItem — see FeedbackService.
class FeedbackReply {
  FeedbackReply({
    required this.id,
    required this.authorUid,
    required this.authorEmail,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String authorUid;
  final String authorEmail;
  final String message;
  final DateTime createdAt;

  factory FeedbackReply.fromDoc(String id, Map<String, dynamic> json) =>
      FeedbackReply(
        id: id,
        authorUid: json['authorUid'] as String? ?? '',
        authorEmail: json['authorEmail'] as String? ?? '',
        message: json['message'] as String? ?? '',
        createdAt:
            (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}
