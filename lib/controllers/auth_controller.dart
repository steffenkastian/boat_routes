import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

// Mirrors LiveLocationController's shape: a small ChangeNotifier wrapping a
// Firebase stream. Each screen that needs auth state creates its own
// instance — all reflect the same underlying FirebaseAuth state, so no
// lifted/shared instance is needed.
class AuthController extends ChangeNotifier {
  AuthController(this._authService) {
    _sub = _authService.authStateChanges.listen(_onAuthChanged);
  }

  final AuthService _authService;
  StreamSubscription<User?>? _sub;

  User? currentUser;
  bool isAdmin = false;
  String? error;
  bool isBusy = false;
  bool _disposed = false;

  Future<void> _onAuthChanged(User? user) async {
    currentUser = user;
    isAdmin = false;
    notifyListeners();

    if (user == null) return;
    isAdmin = await _authService.fetchIsAdmin(user.uid);
    // fetchIsAdmin's Firestore read can still be in flight if whatever
    // owns this controller gets disposed first (e.g. a widget-tree rebuild
    // above MainShell, or hot restart) — notifying after dispose() throws.
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      error = e.message ?? 'Anmeldung fehlgeschlagen';
    } catch (e) {
      error = 'Anmeldung fehlgeschlagen';
    } finally {
      isBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> signUpWithEmail(String email, String password) =>
      _run(() => _authService.signUpWithEmail(email, password));

  Future<void> signInWithEmail(String email, String password) =>
      _run(() => _authService.signInWithEmail(email, password));

  Future<void> signInWithGoogle() => _run(_authService.signInWithGoogle);

  Future<void> signOut() => _run(_authService.signOut);

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
