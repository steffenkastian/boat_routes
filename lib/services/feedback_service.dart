import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/feedback_item.dart';
import '../models/feedback_reply.dart';

// The public wishes/feedback board: anyone can read it (even signed out),
// posting a wish requires being signed in, and replying requires being an
// admin — see firestore.rules for the enforced shape.
class FeedbackService {
  CollectionReference<Map<String, dynamic>> get _feedback =>
      FirebaseFirestore.instance.collection('feedback');

  CollectionReference<Map<String, dynamic>> _replies(String feedbackId) =>
      _feedback.doc(feedbackId).collection('replies');

  Future<String> postFeedback(
    String message, {
    required String uid,
    required String email,
  }) async {
    final doc = await _feedback.add({
      'authorUid': uid,
      'authorEmail': email,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<List<FeedbackItem>> loadFeedback() async {
    final snapshot =
        await _feedback.orderBy('createdAt', descending: true).get();
    return snapshot.docs
        .map((doc) => FeedbackItem.fromDoc(doc.id, doc.data()))
        .toList();
  }

  Future<void> postReply(
    String feedbackId,
    String message, {
    required String uid,
    required String email,
  }) => _replies(feedbackId).add({
        'authorUid': uid,
        'authorEmail': email,
        'message': message,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<List<FeedbackReply>> loadReplies(String feedbackId) async {
    final snapshot =
        await _replies(feedbackId).orderBy('createdAt').get();
    return snapshot.docs
        .map((doc) => FeedbackReply.fromDoc(doc.id, doc.data()))
        .toList();
  }
}
