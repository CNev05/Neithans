import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'db_service.dart';

enum OtpLoginStep { phoneInput, otpVerification }

class OtpLoginProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  OtpLoginStep _currentStep = OtpLoginStep.phoneInput;
  String _phoneNumber = '';
  String _verificationId = '';
  bool _isLoading = false;
  String? _errorMessage;
  bool _isSuperAdmin = false;

  // Rate limiting timer
  Timer? _timer;
  int _secondsRemaining = 0;

  OtpLoginStep get currentStep => _currentStep;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get secondsRemaining => _secondsRemaining;
  bool get canResend => _secondsRemaining == 0;
  bool get isSuperAdmin => _isSuperAdmin;

  OtpLoginProvider() {
    _restoreState();
  }

  Future<void> _restoreState() async {
    try {
      final pending = await DBService.getPendingAuth();
      if (pending != null) {
        _phoneNumber = pending['phone'] ?? '';
        _verificationId = pending['verificationId'] ?? '';
        final stepStr = pending['step'] ?? 'phoneInput';
        _currentStep = OtpLoginStep.values.firstWhere(
          (e) => e.toString().split('.').last == stepStr,
          orElse: () => OtpLoginStep.phoneInput,
        );

        // Check if we should resume a timer
        final updatedAt = pending['updatedAt'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        final diff = (now - updatedAt) ~/ 1000;
        if (diff < 60) {
          _startTimer(60 - diff);
        }
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error restoring state: $e");
    }
  }

  Future<void> _saveState() async {
    try {
      await DBService.savePendingAuth({
        'phone': _phoneNumber,
        'verificationId': _verificationId,
        'step': _currentStep.toString().split('.').last,
      });
    } catch (e) {
      debugPrint("Error saving state: $e");
    }
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    _secondsRemaining = seconds;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        _secondsRemaining--;
        notifyListeners();
      } else {
        _timer?.cancel();
      }
    });
  }

  Future<void> setPhoneNumber(String phone) async {
    _phoneNumber = phone;
    final sanitized = _sanitizePhoneNumber(phone);
    await _checkIfAdmin(sanitized);
  }

  Future<void> _checkIfAdmin(String sanitizedPhone) async {
    // Superadmin access is determined by Firebase Auth claims after sign-in.
    // Admin documents are keyed by UID, so phone-number lookups are invalid.
    _isSuperAdmin = false;
    notifyListeners();
  }

  String _sanitizePhoneNumber(String phone) {
    String clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.startsWith('63')) clean = clean.substring(2);
    if (clean.startsWith('0')) clean = clean.substring(1);
    return clean;
  }

  Future<bool> sendOtp() async {
    if (!canResend) return false;

    if (_isSuperAdmin) {
      _errorMessage = "Super Admin accounts are managed through the Web Portal for extra security. Please use your computer to log in.";
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      
      bool isNone = false;
      if (connectivityResult is List) {
        isNone = (connectivityResult as List).contains(ConnectivityResult.none);
      } else {
        isNone = connectivityResult == ConnectivityResult.none;
      }

      if (isNone) {
        _errorMessage = "It looks like you're offline. Please check your internet connection and try again.";
        return false;
      }

      final Completer<bool> completer = Completer<bool>();
      final sanitizedPhone = _sanitizePhoneNumber(_phoneNumber);

      await _auth.verifyPhoneNumber(
        phoneNumber: '+63$sanitizedPhone',
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
          await DBService.clearPendingAuth();
        },
        verificationFailed: (FirebaseAuthException e) {
          if (e.code == 'invalid-phone-number') {
            _errorMessage = "We couldn't recognize this phone number. Please double-check it and try again.";
          } else if (e.code == 'too-many-requests') {
            _errorMessage = "You've tried too many times. Please wait a few minutes before trying again.";
          } else if (e.code == 'operation-not-allowed' &&
              (e.message ?? '').toLowerCase().contains('region')) {
            _errorMessage = 'SMS verification for the Philippines is disabled. The app administrator must enable Phone Auth and the Philippines (+63) SMS region in Firebase Console.';
          } else if (e.code == 'billing-not-enabled' || e.code == 'sms-capacity-exceeded') {
            _errorMessage = "We're having trouble sending text messages right now. Please try again in a few minutes.";
          } else {
            _errorMessage = "We couldn't send the code. Please check your signal and try once more.";
          }
          if (!completer.isCompleted) completer.complete(false);
          notifyListeners();
        },
        codeSent: (String verificationId, int? resendToken) async {
          _verificationId = verificationId;
          _currentStep = OtpLoginStep.otpVerification;
          _startTimer(60);
          await _saveState();
          if (!completer.isCompleted) completer.complete(true);
          notifyListeners();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );

      return await completer.future;
    } catch (e) {
      _errorMessage = "Something went wrong while sending the code. Please check your connection and try again.";
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String otp) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );

      await _auth.signInWithCredential(credential);
      await DBService.clearPendingAuth();
      _timer?.cancel();
      _secondsRemaining = 0;
      
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-verification-code') {
        _errorMessage = "The code you entered doesn't match. Please check the SMS we sent and try again.";
      } else if (e.code == 'session-expired') {
        _errorMessage = "This code has expired. Please request a new one to continue.";
      } else {
        _errorMessage = "We couldn't verify the code. Please make sure it's correct and try again.";
      }
      return false;
    } catch (e) {
      _errorMessage = "A small error occurred. Please try typing the code again.";
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
