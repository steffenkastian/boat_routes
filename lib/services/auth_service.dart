import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_sign_in;

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _users = FirebaseFirestore.instance.collection('users');
  bool _googleSignInInitialized = false;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signUpWithEmail(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) await ensureUserProfile(user);
  }

  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // signInWithPopup only works on Flutter Web (it needs a browser window to
  // pop up) — Android/iOS have no such concept and go through the native
  // google_sign_in flow instead, exchanging its idToken for a Firebase
  // credential.
  Future<void> signInWithGoogle() async {
    final UserCredential credential;
    if (kIsWeb) {
      credential = await _auth.signInWithPopup(GoogleAuthProvider());
    } else {
      final signIn = google_sign_in.GoogleSignIn.instance;
      if (!_googleSignInInitialized) {
        await signIn.initialize();
        _googleSignInInitialized = true;
      }
      final account = await signIn.authenticate();
      final idToken = account.authentication.idToken;
      credential = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    }
    final user = credential.user;
    if (user != null) await ensureUserProfile(user);
  }

  Future<void> signOut() => _auth.signOut();

  // Creates users/{uid} with isAdmin: false on first sign-in — isAdmin can
  // only ever be flipped afterwards by editing the document directly in the
  // Firestore console, never from client code (enforced by firestore.rules).
  Future<void> ensureUserProfile(User user) async {
    final doc = _users.doc(user.uid);
    final snapshot = await doc.get();
    if (snapshot.exists) return;
    await doc.set({
      'email': user.email,
      'isAdmin': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> fetchIsAdmin(String uid) async {
    final snapshot = await _users.doc(uid).get();
    return snapshot.data()?['isAdmin'] == true;
  }

  // Admin-only (see firestore.rules' broadened users/{userId} read rule) —
  // a count() aggregation avoids downloading every profile doc just to
  // count them.
  Future<int> fetchUserCount() async {
    final snapshot = await _users.count().get();
    return snapshot.count ?? 0;
  }
}
