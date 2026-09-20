import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class _OtpEntry {
  final String otp;
  final DateTime expiry;
  int attempts;
  _OtpEntry(this.otp)
      : expiry = DateTime.now().add(const Duration(minutes: 5)),
        attempts = 0;
  bool get isExpired => DateTime.now().isAfter(expiry);
}

class SmsService {
  // Per-phone OTP store: phone → entry
  static final Map<String, _OtpEntry> _otpStore = {};

  // Per-phone rate limit: phone → last OTP sent time
  static final Map<String, DateTime> _lastOtpSent = {};

  /// Strips all non-digit characters then prefixes +63 for a consistent map key.
  static String _normalizeKey(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('63')) return '+$digits';
    if (digits.startsWith('0')) return '+63${digits.substring(1)}';
    return '+63$digits';
  }

  static Future<bool> sendSms({required String to, required String message}) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('sendDirectSms')
          .call({'to': _normalizeKey(to), 'message': message.trim()});
      return result.data is Map && result.data['success'] == true;
    } on FirebaseFunctionsException catch (error) {
      if (kDebugMode) debugPrint('SMS function failed: ${error.code}');
      return false;
    } catch (error) {
      if (kDebugMode) debugPrint('SMS request failed: $error');
      return false;
    }
  }

  /// Sends a 6-digit OTP to [phone]. Stores it per-phone with a 5-minute expiry.
  /// Enforces a 60-second cooldown per phone to prevent abuse.
  static Future<void> sendOtp(String phone) async {
    final key = _normalizeKey(phone);

    final lastSent = _lastOtpSent[key];
    if (lastSent != null) {
      final elapsed = DateTime.now().difference(lastSent).inSeconds;
      if (elapsed < 60) {
        throw 'Please wait ${60 - elapsed} seconds before requesting a new code.';
      }
    }

    final otp = (Random.secure().nextInt(900000) + 100000).toString();
    _otpStore[key] = _OtpEntry(otp);
    _lastOtpSent[key] = DateTime.now();

    final message = 'Your Neithans verification code is: $otp. Valid for 5 minutes. Do not share this code.';
    final success = await sendSms(to: phone, message: message);
    if (!success) throw 'Failed to send OTP. Please check your number or try again.';
  }

  /// Verifies the OTP for [phone]. Returns false after 5 wrong attempts or expiry.
  static Future<bool> verifyOtp(String phone, String input) async {
    final key = _normalizeKey(phone);
    final entry = _otpStore[key];
    if (entry == null) return false;

    if (entry.isExpired) {
      _otpStore.remove(key);
      return false;
    }

    entry.attempts++;
    if (entry.attempts > 5) {
      _otpStore.remove(key);
      return false;
    }

    if (entry.otp == input) {
      _otpStore.remove(key);
      return true;
    }
    return false;
  }

  /// Clears any stored OTP for [phone] (call on logout or cancel).
  static void clearOtp(String phone) {
    _otpStore.remove(_normalizeKey(phone));
  }
}
