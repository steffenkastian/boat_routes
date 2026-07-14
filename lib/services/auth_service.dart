import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _users = FirebaseFirestore.instance.collection('users');

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

  Future<void> signInWithGoogle() async {
    final credential = await _auth.signInWithPopup(GoogleAuthProvider());
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
}
