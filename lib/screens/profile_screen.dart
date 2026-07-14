import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthController(AuthService());
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onAuthChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _auth.currentUser != null ? _buildSignedIn() : _buildSignedOut(),
      ),
    );
  }

  Widget _buildSignedIn() {
    final user = _auth.currentUser!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
