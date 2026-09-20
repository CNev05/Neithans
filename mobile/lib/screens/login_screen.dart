import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'otp_login_screen.dart';
import '../utils/toast.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtl = TextEditingController();
  final _pwdCtl = TextEditingController();
  bool _loading = false;
  bool _obscurePwd = true;

  void _showCustomToast(String message, {bool isError = true}) {
    if (!mounted) return;
    AppToast.show(context, message, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 60.0),
          child: Column(
            children: [
              Image.asset('assets/icon/app_icon.png', height: 150, errorBuilder: (c, e, s) => const Icon(Icons.home_work, size: 80, color: Color(0xFF8B6E5C))),
              const SizedBox(height: 20),
              const Text('Neithans', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF8B6E5C))),
              const SizedBox(height: 40),
              TextField(
                controller: _phoneCtl,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                decoration: const InputDecoration(labelText: 'Phone Number', prefixText: '+63 ', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pwdCtl,
                obscureText: _obscurePwd,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePwd ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B6E5C), foregroundColor: Colors.white),
                  onPressed: _loading ? null : () async {
                    final phone = _phoneCtl.text.trim();
                    if (AuthService.validatePhone(phone) != null) {
                      _showCustomToast('Valid phone required'); return;
                    }
                    setState(() => _loading = true);
                    try {
                      await auth.signInWithPassword(phone, _pwdCtl.text.trim());
                    } catch (e) {
                      _showCustomToast(e.toString());
                    } finally {
                      if (mounted) setState(() => _loading = false);
                    }
                  },
                  child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Login'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OtpLoginScreen())),
                child: const Text("Login with OTP Code", style: TextStyle(color: Color(0xFF8B6E5C))),
              ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                child: const Text("Don't have an account? Sign Up", style: TextStyle(color: Color(0xFF8B6E5C))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
