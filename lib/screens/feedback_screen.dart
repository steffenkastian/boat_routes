import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../models/feedback_item.dart';
import '../models/feedback_reply.dart';
import '../services/auth_service.dart';
import '../services/feedback_service.dart';
import '../widgets/prompt_message_dialog.dart';

// The public wishes/feedback board — readable by anyone, even signed out;
// posting a wish requires being signed in; replying is admin-only. See
// FeedbackService and firestore.rules for the enforced access model.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _feedbackService = FeedbackService();
  final _auth = AuthController(AuthService());

  List<FeedbackItem>? _items;
  final Map<String, List<FeedbackReply>> _repliesById = {};
  final Set<String> _loadingRepliesFor = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    _load();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    super.dispose();
  }

  void _onAuthChanged() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _feedbackService.loadFeedback();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Wünsche konnten nicht geladen werden.';
      });
    }
  }

  Future<void> _loadReplies(String feedbackId) async {
    if (_repliesById.containsKey(feedbackId) ||
        _loadingRepliesFor.contains(feedbackId)) {
      return;
    }
    setState(() => _loadingRepliesFor.add(feedbackId));
    try {
      final replies = await _feedbackService.loadReplies(feedbackId);
      if (!mounted) return;
      setState(() {
        _repliesById[feedbackId] = replies;
        _loadingRepliesFor.remove(feedbackId);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRepliesFor.remove(feedbackId));
    }
  }

  Future<void> _postFeedback() async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zum Posten eines Wunsches bitte zuerst einloggen.'),
        ),
      );
      return;
    }
    final message = await promptForMessage(
      context,
      title: 'Neuer Wunsch',
      hint: 'Was wünschst du dir?',
    );
    if (message == null) return;

    try {
      await _feedbackService.postFeedback(
        message,
        uid: user.uid,
        email: user.email ?? '',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wunsch konnte nicht gespeichert werden.')),
      );
      return;
    }
    if (!mounted) return;
    await _load();
  }

  Future<void> _postReply(String feedbackId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final message = await promptForMessage(
      context,
      title: 'Antworten',
      hint: 'Deine Antwort',
      confirmLabel: 'Antworten',
    );
    if (message == null) return;

    try {
      await _feedbackService.postReply(
        feedbackId,
        message,
        uid: user.uid,
        email: user.email ?? '',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Antwort konnte nicht gespeichert werden.')),
      );
      return;
    }
    if (!mounted) return;
    _repliesById.remove(feedbackId);
    await _loadReplies(feedbackId);
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wünsche & Feedback')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _postFeedback,
        icon: const Icon(Icons.add),
        label: const Text('Neuer Wunsch'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Text(error)),
        ],
      );
    }
    final items = _items ?? const [];
    if (items.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(child: Text('Noch keine Wünsche vorhanden.')),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final replies = _repliesById[item.id];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Text(item.message),
            subtitle: Text('${item.authorEmail} · ${_formatDate(item.createdAt)}'),
            onExpansionChanged: (expanded) {
              if (expanded) _loadReplies(item.id);
            },
            children: [
              if (_loadingRepliesFor.contains(item.id))
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                )
              else ...[
                for (final reply in replies ?? const <FeedbackReply>[])
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reply.authorEmail,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        Text(reply.message),
                      ],
                    ),
                  ),
                if (_auth.isAdmin)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _postReply(item.id),
                        icon: const Icon(Icons.reply),
                        label: const Text('Antworten'),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
