import 'package:cloud_firestore/cloud_firestore.dart';

// A single entry on the public wishes/feedback board — see FeedbackService.
class FeedbackItem {
  FeedbackItem({
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

  factory FeedbackItem.fromDoc(String id, Map<String, dynamic> json) =>
      FeedbackItem(
        id: id,
        authorUid: json['authorUid'] as String? ?? '',
        authorEmail: json['authorEmail'] as String? ?? '',
        message: json['message'] as String? ?? '',
        createdAt:
            (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}
