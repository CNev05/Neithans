import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/db_service.dart';
import '../utils/toast.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _pwdCtl = TextEditingController();
  final _confirmPwdCtl = TextEditingController();

  bool _loading = false;
  bool _obscurePwd = true;
  bool _obscureConfirmPwd = true;

  @override
  void dispose() {
    _nameCtl.dispose();
    _phoneCtl.dispose();
    _pwdCtl.dispose();
    _confirmPwdCtl.dispose();
    super.dispose();
  }

  void _showCustomToast(String message, {bool isError = true}) {
    if (!mounted) return;
    AppToast.show(context, message, isError: isError);
  }

  void _showOtpDialog(
      String phone, String name, String password, String verificationId) {
    final otpController = TextEditingController();
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text("Verify Registration",
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("A verification code was sent to +63 $phone"),
              const SizedBox(height: 16),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    letterSpacing: 8,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6)
                ],
                decoration: const InputDecoration(
                    hintText: "000000", border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: isVerifying ? null : () => Navigator.pop(context),
                child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B6E5C)),
              onPressed: isVerifying
                  ? null
                  : () async {
                      final input = otpController.text.trim();
                      if (input.length != 6) return;

                      final dialogContext = context;
                      setDialogState(() => isVerifying = true);

                      try {
                        final auth = Provider.of<AuthService>(dialogContext,
                            listen: false);
                        final creds = await auth.signUpWithPhoneOtp(
                          phone: phone,
                          password: password,
                          name: name,
                          verificationId: verificationId,
                          smsCode: input,
                        );
                        final uid = creds.user?.uid;

                        if (uid != null) {
                          await DBService.saveProfile({
                            'id': uid,
                            'ownerId': uid,
                            'name': name,
                            'phone': '+63 $phone',
                            'email': '$phone@neithans.app',
                            'photoPath': null,
                          });
                        }

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        Navigator.pop(dialogContext);
                        _showCustomToast("Account created successfully!",
                            isError: false);
                      } catch (e) {
                        setDialogState(() => isVerifying = false);
                        if (mounted) {
                          _showCustomToast(e.toString());
                        }
                      }
                    },
              child: isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text("Verify & Create",
                      style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF8B6E5C)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person_add_outlined,
                    size: 80, color: Color(0xFF8B6E5C)),
                const SizedBox(height: 20),
                const Text(
                  'Create Account',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8B6E5C)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Verify your phone number to start.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _nameCtl,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'))
                  ],
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty)
                      return 'Please enter your name';
                    if (value.trim().length < 3) return 'Name too short';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Contact Number',
                    prefixIcon: const Icon(Icons.phone_android_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    prefixText: '+63 ',
                  ),
                  onChanged: (value) {
                    if (value.startsWith('0')) {
                      _phoneCtl.text = value.substring(1);
                      _phoneCtl.selection = TextSelection.fromPosition(
                          TextPosition(offset: _phoneCtl.text.length));
                    }
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Please enter phone number';
                    if (value.length != 10) return 'Must be exactly 10 digits';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pwdCtl,
                  obscureText: _obscurePwd,
                  decoration: InputDecoration(
                    labelText: 'Create Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePwd
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscurePwd = !_obscurePwd),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Please enter password';
                    if (value.length < 8)
                      return 'Password must be at least 8 characters';
                    if (!RegExp(r'[A-Z]').hasMatch(value))
                      return 'Must contain at least one uppercase letter';
                    if (!RegExp(r'[0-9]').hasMatch(value))
                      return 'Must contain at least one number';
                    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]').hasMatch(value))
                      return 'Must contain at least one special character';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPwdCtl,
                  obscureText: _obscureConfirmPwd,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPwd
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setState(
                          () => _obscureConfirmPwd = !_obscureConfirmPwd),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Please confirm password';
                    if (value != _pwdCtl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B6E5C),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _loading
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;

                            final name = _nameCtl.text.trim();
                            final phone = _phoneCtl.text.trim();
                            final password = _pwdCtl.text.trim();

                            setState(() => _loading = true);
                            try {
                              if (await DBService.getProfileByPhone(
                                      '+63 $phone') !=
                                  null) {
                                _showCustomToast(
                                    "This phone number is already registered.");
                                setState(() => _loading = false);
                                return;
                              }

                              final auth = Provider.of<AuthService>(context,
                                  listen: false);
                              final verificationId =
                                  await auth.sendPhoneOtp(phone);
                              if (mounted) {
                                _showOtpDialog(
                                    phone, name, password, verificationId);
                              }
                            } catch (e) {
                              _showCustomToast('Error: $e');
                            } finally {
                              if (mounted) setState(() => _loading = false);
                            }
                          },
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Verify & Sign Up',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
