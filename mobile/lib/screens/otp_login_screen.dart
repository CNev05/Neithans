import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/otp_login_provider.dart';

class OtpLoginScreen extends StatelessWidget {
  const OtpLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OtpLoginProvider(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Login with OTP'),
        ),
        body: Consumer<OtpLoginProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            switch (provider.currentStep) {
              case OtpLoginStep.phoneInput:
                return const PhoneInputStep();
              case OtpLoginStep.otpVerification:
                return const OtpVerificationStep();
            }
          },
        ),
      ),
    );
  }
}

class PhoneInputStep extends StatefulWidget {
  const PhoneInputStep({super.key});

  @override
  State<PhoneInputStep> createState() => _PhoneInputStepState();
}

class _PhoneInputStepState extends State<PhoneInputStep> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<OtpLoginProvider>(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const Icon(Icons.sms_outlined, size: 80, color: Color(0xFF8B6E5C)),
            const SizedBox(height: 20),
            const Text(
              "OTP Verification",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "We will send a one-time password to your mobile number.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            TextFormField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                prefixText: '+63 ',
                hintText: '9XXXXXXXXX',
                prefixIcon: const Icon(Icons.phone_android_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Please enter your phone number';
                if (!RegExp(r'^\d{10}$').hasMatch(value)) return 'Enter a valid 10-digit number';
                return null;
              },
            ),
            const SizedBox(height: 24),
            if (provider.errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                child: Text(provider.errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B6E5C), 
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: provider.isLoading ? null : () async {
                  if (_formKey.currentState!.validate()) {
                    await provider.setPhoneNumber(_phoneController.text);
                    await provider.sendOtp();
                  }
                },
                child: const Text('Send OTP Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OtpVerificationStep extends StatefulWidget {
  const OtpVerificationStep({super.key});

  @override
  State<OtpVerificationStep> createState() => _OtpVerificationStepState();
}

class _OtpVerificationStepState extends State<OtpVerificationStep> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<OtpLoginProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Icon(Icons.mark_email_read_outlined, size: 80, color: Color(0xFF8B6E5C)),
          const SizedBox(height: 20),
          const Text('Verification Code', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('Enter the 6-digit OTP sent to your phone', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 40),
          Row(
            children: List.generate(6, (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: index == 0 ? 0 : 6),
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      counterText: "",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF8B6E5C), width: 2)),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty && index < 5) {
                        _focusNodes[index + 1].requestFocus();
                      } else if (value.isEmpty && index > 0) {
                        _focusNodes[index - 1].requestFocus();
                      }
                      setState(() {});
                    },
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 30),
          if (provider.secondsRemaining > 0)
            Text("Resend code in ${provider.secondsRemaining}s", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
          else
            TextButton(
              onPressed: provider.isLoading ? null : () => provider.sendOtp(),
              child: const Text("Resend OTP", style: TextStyle(color: Color(0xFF8B6E5C), fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          const SizedBox(height: 20),
          if (provider.errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
              child: Text(provider.errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B6E5C), 
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: provider.isLoading || _otp.length < 6 ? null : () async {
                await provider.verifyOtp(_otp);
              },
              child: const Text('Verify & Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
