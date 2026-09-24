import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// A signed-in user, mapped from firebase_auth's [fb.User] so the rest of the
/// app doesn't depend on the firebase_auth API surface directly.
class AppUser {
  const AppUser({
    required this.uid,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;
}

/// Thrown by [AuthService.signInWithGoogle] when Firebase isn't configured or
/// the provider fails; [message] is user-facing.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thin wrapper around FirebaseAuth + google_sign_in that degrades gracefully
/// to "guest mode" (no user, [isConfigured] false) when no Firebase project
/// has been configured yet — see lib/firebase_options.dart and
/// docs/firebase-setup.md.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// True when Firebase.initializeApp succeeded (Firebase.apps.isNotEmpty).
  bool get isConfigured => Firebase.apps.isNotEmpty;

  /// Current user; null when signed out or unconfigured. Screens listen with
  /// ValueListenableBuilder.
  final ValueNotifier<AppUser?> user = ValueNotifier<AppUser?>(null);

  StreamSubscription<fb.User?>? _authSubscription;
  bool _googleSignInInitialized = false;

  /// Call once after Firebase init (or its failure) to start mirroring
  /// FirebaseAuth.userChanges(). Idempotent — safe to call more than once.
  void start() {
    if (_authSubscription != null) {
      return; // already started
    }
    if (!isConfigured) {
      user.value = null;
      return;
    }
    _authSubscription = fb.FirebaseAuth.instance.userChanges().listen((
      fb.User? firebaseUser,
    ) {
      user.value = firebaseUser == null
          ? null
          : AppUser(
              uid: firebaseUser.uid,
              displayName: firebaseUser.displayName,
              email: firebaseUser.email,
              photoUrl: firebaseUser.photoURL,
            );
    });
  }

  /// Signs in with Google via Firebase Auth. Throws [AuthException] with a
  /// friendly, user-facing message on failure (never the raw platform error).
  Future<void> signInWithGoogle() async {
    if (!isConfigured) {
      throw const AuthException(
        "Sign-in isn't set up in this build yet. See docs/firebase-setup.md.",
      );
    }
    try {
      if (kIsWeb) {
        // signInWithPopup drives the entire OAuth flow itself on web; no
        // google_sign_in package interaction needed (see firebase_api_notes).
        await fb.FirebaseAuth.instance.signInWithPopup(fb.GoogleAuthProvider());
        return;
      }

      await _ensureGoogleSignInInitialized();
      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate();
      final String? idToken = account.authentication.idToken;
      if (idToken == null) {
        debugPrint(
          'AuthService.signInWithGoogle: Google returned no idToken '
          '(check serverClientId on Android / GIDClientID on iOS).',
        );
        throw const AuthException(
          "Google sign-in didn't return a token. Check the Android/iOS "
          "client ID setup in docs/firebase-setup.md.",
        );
      }
      final credential = fb.GoogleAuthProvider.credential(idToken: idToken);
      await fb.FirebaseAuth.instance.signInWithCredential(credential);
    } on fb.FirebaseAuthException catch (e, stackTrace) {
      debugPrint(
        'AuthService.signInWithGoogle FirebaseAuthException '
        '${e.code}: ${e.message}\n$stackTrace',
      );
      throw AuthException(_friendlyFirebaseAuthMessage(e));
    } on GoogleSignInException catch (e, stackTrace) {
      debugPrint(
        'AuthService.signInWithGoogle GoogleSignInException: $e\n$stackTrace',
      );
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException('Sign-in was cancelled.');
      }
      throw const AuthException("Sign-in failed. See docs/firebase-setup.md.");
    } on AuthException {
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('AuthService.signInWithGoogle error: $e\n$stackTrace');
      throw const AuthException("Sign-in failed. See docs/firebase-setup.md.");
    }
  }

  Future<void> signOut() async {
    try {
      await fb.FirebaseAuth.instance.signOut();
    } catch (e, stackTrace) {
      debugPrint('AuthService.signOut FirebaseAuth error: $e\n$stackTrace');
    }
    if (!kIsWeb) {
      try {
        // initialize() must complete before any other GoogleSignIn method
        // runs (e.g. after FirebaseAuth restores a session across app
        // restarts, before signOut() is ever called on this instance).
        await _ensureGoogleSignInInitialized();
        await GoogleSignIn.instance.signOut();
      } catch (e, stackTrace) {
        debugPrint('AuthService.signOut GoogleSignIn error: $e\n$stackTrace');
      }
    }
  }

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    // Must be called exactly once, awaited, before any other GoogleSignIn
    // method. Relies on native config files (google-services.json /
    // GoogleService-Info.plist) written by `flutterfire configure` for
    // clientId/serverClientId — see docs/firebase-setup.md.
    await GoogleSignIn.instance.initialize();
    _googleSignInInitialized = true;
  }

  String _friendlyFirebaseAuthMessage(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'popup-closed-by-user':
      case 'canceled':
        return 'Sign-in was cancelled.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a '
            'different sign-in method.';
      case 'operation-not-allowed':
        return "Google sign-in isn't enabled for this Firebase project yet.";
      default:
        return 'Sign-in failed. See docs/firebase-setup.md.';
    }
  }
}
