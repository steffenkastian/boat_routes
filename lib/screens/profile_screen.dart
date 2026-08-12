import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../models/shared_item.dart';
import '../services/auth_service.dart';
import '../services/share_service.dart';
import 'admin_stats_screen.dart';
import 'feedback_screen.dart';
import 'shared_item_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthController(AuthService());
  final _shareService = ShareService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _sharedWithMeForEmail;
  List<SharedItem>? _sharedWithMe;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    _loadSharedWithMe();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    setState(() {});
    _loadSharedWithMe();
  }

  Future<void> _loadSharedWithMe() async {
    final email = _auth.currentUser?.email;
    if (email == null) {
      setState(() {
        _sharedWithMe = null;
        _sharedWithMeForEmail = null;
      });
      return;
    }
    // Guards against a stale response landing after the account switched.
    if (email == _sharedWithMeForEmail) return;
    _sharedWithMeForEmail = email;
    List<SharedItem> items;
    try {
      items = await _shareService.loadSharedWithMe(email);
    } catch (_) {
      // Un-marks this email so the next auth-change/rebuild can retry —
      // otherwise a single transient failure (or a rules mismatch) would
      // leave "Mit dir geteilt" permanently empty for the rest of the
      // session with no way to recover short of signing out and back in.
      if (_sharedWithMeForEmail == email) _sharedWithMeForEmail = null;
      return;
    }
    if (!mounted || email != _auth.currentUser?.email) return;
    setState(() => _sharedWithMe = items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: _auth.currentUser != null
                  ? _buildSignedIn()
                  : _buildSignedOut(),
            ),
            // Shown regardless of login state — the feedback board is
            // readable by anyone, only posting requires being signed in
            // (enforced inside FeedbackScreen itself).
            const Divider(),
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: const Text('Wünsche & Feedback'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FeedbackScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedIn() {
    final user = _auth.currentUser!;
    final sharedWithMe = _sharedWithMe;
    return ListView(
      children: [
        Text('Angemeldet als', style: Theme.of(context).textTheme.bodySmall),
        Text(user.email ?? user.uid, style: Theme.of(context).textTheme.titleMedium),
        if (_auth.isAdmin)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Admin', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _auth.isBusy ? null : _auth.signOut,
          child: const Text('Abmelden'),
        ),
        if (_auth.isAdmin) ...[
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bar_chart),
            title: const Text('Statistik'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AdminStatsScreen()),
            ),
          ),
        ],
        if (sharedWithMe != null && sharedWithMe.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text('Mit dir geteilt', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          ...sharedWithMe.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (item.type) {
                SharedItemType.route => Icons.route,
                SharedItemType.tour => Icons.directions_boat,
                SharedItemType.folder => Icons.folder,
                SharedItemType.routeFolder => Icons.folder_special,
              }),
              title: Text(item.name),
              subtitle: Text('von ${item.ownerEmail}'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SharedItemScreen(item: item),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSignedOut() {
    return ListView(
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-Mail'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Passwort'),
        ),
        if (_auth.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_auth.error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _auth.isBusy ? null : _signIn,
                child: const Text('Anmelden'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _auth.isBusy ? null : _signUp,
                child: const Text('Registrieren'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Row(children: [
          Expanded(child: Divider()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('oder'),
          ),
          Expanded(child: Divider()),
        ]),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _auth.isBusy ? null : _auth.signInWithGoogle,
          icon: const Icon(Icons.g_mobiledata),
          label: const Text('Mit Google anmelden'),
        ),
      ],
    );
  }

  void _signIn() {
    _auth.signInWithEmail(
      _emailController.text.trim(),
      _passwordController.text,
    );
  }

  void _signUp() {
    _auth.signUpWithEmail(
      _emailController.text.trim(),
      _passwordController.text,
    );
  }
}
