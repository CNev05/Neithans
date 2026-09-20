import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthState {
  final bool signedIn;
  final String? uid;
  final String? role;
  AuthState({required this.signedIn, this.uid, this.role});
}

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _controller = StreamController<AuthState>.broadcast();
  StreamSubscription<User?>? _authStateSubscription;
  String? _devRoleOverride;

  AuthService() {
    _setupAuthListener();
  }

  void _setupAuthListener() {
    _authStateSubscription?.cancel();
    _authStateSubscription = _auth.authStateChanges().listen(
      (user) async {
        if (user == null) {
          _controller.add(AuthState(signedIn: false));
          return;
        }

        final idTokenResult = await user.getIdTokenResult(true);
        final claims = idTokenResult.claims ?? {};
        final role = claims['superadmin'] == true
          ? 'superadmin'
          : claims['owner'] == true
            ? 'owner'
            : null;

        _controller.add(AuthState(
          signedIn: true,
          uid: user.uid,
          role: kDebugMode ? (_devRoleOverride ?? role) : role));
      },
    );
  }

  String _getVirtualEmail(String phone) => "$phone@neithans.app";

  String _handleAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'We couldn\'t find an account with this phone number. Please check the number or sign up.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'network-request-failed':
        return 'Connection error. Please check your internet and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes before trying again.';
      case 'quota-exceeded':
        return 'The Firebase SMS limit has been reached for today. Please try again tomorrow or add billing to the Firebase project.';
      case 'billing-not-enabled':
        return 'Firebase SMS requires billing for this project. Add a billing account in Firebase Console and try again.';
      case 'app-not-authorized':
        return 'This Android app is not authorized for Firebase Phone Auth. Verify the package name and SHA-1 in Firebase Console, then reinstall the app.';
      case 'captcha-check-failed':
        return 'Firebase could not verify this device. Check Google Play services and try again.';
      case 'invalid-phone-number':
        return 'Please enter a valid Philippine mobile number.';
      case 'invalid-verification-code':
        return 'The OTP is incorrect. Please check the code and try again.';
      case 'session-expired':
        return 'This OTP has expired. Request a new code and try again.';
      case 'operation-not-allowed':
        if ((e.message ?? '').toLowerCase().contains('region') ||
            (e.message ?? '').toLowerCase().contains('sms')) {
          return 'SMS verification is not enabled for the Philippines. In Firebase Console, open Authentication > Sign-in method > Phone, enable the provider, and allow the Philippines (+63) SMS region.';
        }
        return 'This Firebase sign-in method is disabled. Enable the Phone provider in Firebase Console.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support for help.';
      default:
        return 'Firebase sign-in failed (${e.code}). Please try again.';
    }
  }

  Future<UserCredential> signInWithPassword(
      String phone, String password) async {
    try {
      final email = _getVirtualEmail(phone);
      return await _auth.signInWithEmailAndPassword(
          email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (e) {
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  Future<UserCredential> signUp(
      String phone, String password, String name) async {
    try {
      final email = _getVirtualEmail(phone);
      return await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw 'This phone number is already registered. Try logging in instead.';
      }
      throw _handleAuthError(e);
    } catch (e) {
      throw 'We couldn\'t create your account. Please try again later.';
    }
  }

  Future<String> sendPhoneOtp(String phone) async {
    final completer = Completer<String>();
    final normalizedPhone = '+63${phone.replaceAll(RegExp(r'\D'), '')}';

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: normalizedPhone,
        verificationCompleted: (_) {},
        verificationFailed: (e) {
          if (!completer.isCompleted)
            completer.completeError(_handleAuthError(e));
        },
        codeSent: (verificationId, _) {
          if (!completer.isCompleted) completer.complete(verificationId);
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!completer.isCompleted) completer.complete(verificationId);
        },
      );
      return await completer.future;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    }
  }

  Future<UserCredential> signUpWithPhoneOtp({
    required String phone,
    required String password,
    required String name,
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final phoneCredential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(phoneCredential);

      if (userCredential.additionalUserInfo?.isNewUser != true) {
        await _auth.signOut();
        throw 'This phone number is already registered. Try logging in instead.';
      }

      final emailCredential = EmailAuthProvider.credential(
        email: _getVirtualEmail(phone),
        password: password,
      );
      final linkedCredential =
          await userCredential.user!.linkWithCredential(emailCredential);
      await linkedCredential.user?.updateDisplayName(name);
      return linkedCredential;
    } on FirebaseAuthException catch (e) {
      await _auth.signOut();
      if (e.code == 'email-already-in-use' ||
          e.code == 'credential-already-in-use') {
        throw 'This phone number is already registered. Try logging in instead.';
      }
      throw _handleAuthError(e);
    }
  }

  static String? validatePhone(String? phone) {
    if (phone == null || phone.isEmpty)
      return 'Please enter your phone number.';
    if (!RegExp(r'^(9)\d{9}$').hasMatch(phone))
      return 'Please enter a valid 10-digit phone number.';
    return null;
  }

  Stream<AuthState> get authState => _controller.stream;
  String? get currentUserUid => _auth.currentUser?.uid;

  Future<void> signOut() async {
    _devRoleOverride = null;
    await _auth.signOut();
    _controller.add(AuthState(signedIn: false));
  }

  void dispose() {
    _authStateSubscription?.cancel();
    _controller.close();
  }
}
