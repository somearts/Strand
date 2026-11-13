import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import '../social/cloud_store.dart';
import 'account.dart';
import 'auth_config.dart';

/// The one place Strand talks to Firebase Authentication.
///
/// Email and password only in this iteration. Accounts are created by Firebase,
/// passwords are hashed by Firebase and never touch this app's storage, and the
/// session is restored by the native SDK on the next launch.
///
/// A build with no Firebase values is a supported state, not a broken one. The
/// app opens and reads sleep normally; [isConfigured] is false and the account
/// screens say what is missing instead of faking a login.
class StrandAuth extends ChangeNotifier {
  StrandAuth._();

  static final StrandAuth instance = StrandAuth._();

  FirebaseAuth? _auth;
  bool _initialised = false;
  bool _configured = false;
  bool _busy = false;
  String? _error;
  String? _configurationNote;
  StreamSubscription<User?>? _subscription;

  bool get isInitialised => _initialised;
  bool get isConfigured => _configured;
  bool get busy => _busy;
  String? get error => _error;

  /// A sentence naming what this build is missing, or null when it is complete.
  String? get configurationNote => _configurationNote;

  /// The cached profile. Present even before Firebase answers, so the greeting
  /// is correct on the first frame after a cold start.
  Account? get account => Storage.account;

  bool get signedIn => _auth?.currentUser != null;

  String get greetingName => account?.greetingName ?? '';

  /// Prepare Firebase once, at startup.
  Future<void> init() async {
    if (_initialised) return;
    try {
      await _initializeFirebase();
      _configured = true;
      _auth = FirebaseAuth.instance;
      _subscription = _auth!.authStateChanges().listen(_onAuthChanged);
      final User? current = _auth!.currentUser;
      if (current != null) {
        await _cacheProfile(current);
      }
    } on FirebaseException catch (e) {
      _configured = false;
      _configurationNote = _configurationSentence(e);
    } catch (_) {
      _configured = false;
      _configurationNote = _configurationSentence(null);
    } finally {
      _initialised = true;
      notifyListeners();
    }
  }

  Future<void> _initializeFirebase() async {
    try {
      // Works when a google-services.json was compiled in.
      await Firebase.initializeApp();
    } on FirebaseException {
      // Otherwise fall back to the values supplied at build time. Without
      // either, this throws and the app reports that sign-in is unconfigured.
      if (!AuthConfig.hasFirebaseOptions) rethrow;
      await Firebase.initializeApp(options: AuthConfig.options);
    }
  }

  Future<bool> createAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    if (!_guard()) return false;
    _begin();
    try {
      final UserCredential credential = await _auth!
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
      final User? user = credential.user;
      if (user == null) {
        _error = 'The account could not be created. Please try again.';
        return false;
      }
      try {
        await user.updateDisplayName(name.trim());
      } catch (_) {}
      try {
        await user.reload();
      } catch (_) {}
      await _cacheProfile(_auth!.currentUser ?? user, fallbackName: name);
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _messageFor(e);
      return false;
    } catch (_) {
      _error = 'The account could not be created. Please try again.';
      return false;
    } finally {
      _end();
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    if (!_guard()) return false;
    _begin();
    try {
      final UserCredential credential = await _auth!.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final User? user = credential.user;
      if (user != null) await _cacheProfile(user);
      return user != null;
    } on FirebaseAuthException catch (e) {
      _error = _messageFor(e);
      return false;
    } catch (_) {
      _error = 'Sign-in failed. Please try again.';
      return false;
    } finally {
      _end();
    }
  }

  /// Ends the Firebase session and forgets the cached name.
  ///
  /// Sleep records are deliberately untouched: they belong to the device, and
  /// signing out must never make someone's own nights disappear.
  Future<void> signOut() async {
    _begin();
    try {
      await _auth?.signOut();
      await Storage.clearAccount();
    } finally {
      _end();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Renames the cached account locally and tells listeners, so a name change
  /// shows up everywhere the app reads [account] without waiting for Firebase.
  Future<void> updateAccountName(String name) async {
    final Account? current = account;
    if (current == null) return;
    await Storage.saveAccount(
      Account(uid: current.uid, name: name.trim(), email: current.email),
    );
    notifyListeners();
  }

  bool _guard() {
    if (!_configured) {
      _error =
          _configurationNote ?? 'Sign-in is not configured in this build.';
      notifyListeners();
      return false;
    }
    return true;
  }

  void _begin() {
    _busy = true;
    _error = null;
    notifyListeners();
  }

  void _end() {
    _busy = false;
    notifyListeners();
  }

  Future<void> _onAuthChanged(User? user) async {
    if (user == null) {
      if (Storage.account != null) await Storage.clearAccount();
      notifyListeners();
      return;
    }
    await _cacheProfile(user);
    notifyListeners();
  }

  Future<void> _cacheProfile(User user, {String? fallbackName}) async {
    final String? displayName = user.displayName?.trim();
    final String? existing =
        Storage.account?.uid == user.uid ? Storage.account?.name : null;
    final String email = user.email?.trim() ?? '';
    final String name = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (existing != null && existing.trim().isNotEmpty)
            ? existing
            : (fallbackName != null && fallbackName.trim().isNotEmpty)
                ? fallbackName.trim()
                : email.split('@').first;

    await Storage.saveAccount(
      Account(uid: user.uid, name: name, email: email),
    );
    notifyListeners();

    // The cloud profile is what makes someone findable by email. It is written
    // best-effort: a network failure must not make sign-in itself fail.
    if (email.isNotEmpty) {
      unawaited(
        CloudStore.ensureProfile(uid: user.uid, name: name, email: email)
            .catchError((Object _) {}),
      );
    }
  }

  String _configurationSentence(FirebaseException? e) {
    final String detail = e?.code == 'invalid-api-key'
        ? ' The API key in this build is not valid.'
        : '';
    final List<String> missing = AuthConfig.missingValues;
    final String missingText = missing.isEmpty
        ? ''
        : ' Missing: ${missing.join(', ')}.';
    return 'Sign-in is not configured in this build. Provide the Firebase '
        'project values at build time to enable it.$missingText$detail '
        'See auth_config.dart for the exact build command.';
  }

  String _messageFor(FirebaseAuthException e) {
    return switch (e.code) {
      'invalid-email' => 'That email address does not look right.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' => 'No account was found for that email.',
      'wrong-password' || 'invalid-credential' =>
        'The email or password is incorrect.',
      'email-already-in-use' =>
        'An account with that email already exists. Sign in instead.',
      'weak-password' => 'Use a password with at least 6 characters.',
      'network-request-failed' =>
        'No connection. Check your network and try again.',
      'too-many-requests' =>
        'Too many attempts. Wait a moment and try again.',
      'account-exists-with-different-credential' =>
        'That email already uses a different sign-in method.',
      'operation-not-allowed' =>
        'Email sign-in is not enabled for the Firebase project.',
      'requires-recent-login' => 'Sign in again to continue.',
      _ => 'Sign-in failed. Please try again.',
    };
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
