import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Color primaryBlue = const Color(0xFF2533AE);

  ///  Toggle password visibility
  bool _obscurePassword = true;

  ///  Validation states
  bool hasUppercase = false;
  bool hasNumber = false;
  bool hasSpecialChar = false;
  bool hasMinLength = false;

  ///  VALIDATE PASSWORD LIVE
  void _validatePassword(String password) {
    setState(() {
      hasUppercase = password.contains(RegExp(r'[A-Z]'));
      hasNumber = password.contains(RegExp(r'[0-9]'));
      hasSpecialChar =
          password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
      hasMinLength = password.length >= 8;
    });
  }



  ///  SIGNUP FUNCTION
  Future<void> _signup() async {
    if (!(hasUppercase && hasNumber && hasSpecialChar && hasMinLength)) {
      _showError("Please meet all password requirements.");
      return;
    }

    try {
      await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!context.mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } catch (e) {
      _showError(e.toString());
    }
  }


  ///  CLEAN ERROR HANDLER
  void _showError(String msg) {
    String cleanMessage = msg;

    if (msg.contains("email-already-in-use")) {
      cleanMessage = "This email is already registered.";
    } else if (msg.contains("invalid-email")) {
      cleanMessage = "Please enter a valid email address.";
    } else if (msg.contains("weak-password")) {
      cleanMessage = "Password should be at least 6 characters.";
    } else if (msg.contains("network")) {
      cleanMessage = "Check your internet connection.";
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(cleanMessage),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  ///  INPUT STYLE (same theme as login)
  InputDecoration _inputStyle(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white.withOpacity(0.95),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: primaryBlue.withOpacity(0.25),
          width: 1.2,
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: primaryBlue,
          width: 1.6,
        ),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.red.withOpacity(0.7),
        ),
      ),

      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    );
  }

   ///  RULE UI
  Widget _buildRule(String text, bool isValid) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: isValid ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: isValid
                  ? Colors.green
                  : Colors.black.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        ///  BACKGROUND GRADIENT
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFEAF4FF),
              Color(0xFFBFDDF7),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),

        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: primaryBlue.withOpacity(0.08),
                        blurRadius: 25,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),

                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      ///  TITLE
                      Text(
                        "Create Account",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: primaryBlue,
                        ),
                      ),

                      const SizedBox(height: 25),

                      /// NAME
                      TextField(
                        controller: _nameController,
                        decoration: _inputStyle("Full Name"),
                      ),

                      const SizedBox(height: 15),

                      /// EMAIL
                      TextField(
                        controller: _emailController,
                        decoration: _inputStyle("Email"),
                      ),

                      const SizedBox(height: 15),

                      /// PASSWORD ( view  VALIDATION)
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        onChanged: _validatePassword,
                        decoration: _inputStyle("Password").copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: primaryBlue,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 25),

                       ///  RULES
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildRule("At least 8 characters", hasMinLength),
                          _buildRule("1 uppercase letter", hasUppercase),
                          _buildRule("1 number", hasNumber),
                          _buildRule("1 special character", hasSpecialChar),
                        ],
                      ),
                      const SizedBox(height: 25),
                      
                      /// SIGN UP BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _signup,
                          child: const Text(
                            "Sign Up",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      /// LOGIN NAV
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: Text.rich(
  TextSpan(
    text: "Already have an account? ",
    style: TextStyle(color: Colors.black.withOpacity(0.7)),
    children: [
      TextSpan(
        text: "Login",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: primaryBlue,
        ),
      ),
    ],
  ),
),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}