import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'signup_page.dart';
import 'forgot_password_page.dart';
import '../main_scaffold.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../patient/patient_info_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Color primaryBlue = const Color(0xFF2533AE);

  ///  LOGIN
  Future<void> _login() async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await _checkUserAndNavigate();
    } catch (e) {
      _showError(e.toString());
    }
  }

  ///  USER ROUTING LOGIC
  Future<void> _checkUserAndNavigate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('patients')
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PatientInfoPage()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScaffold()),
      );
    }
  }

  ///  GOOGLE SIGN IN
  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();

      // Force a clean session: v6.3.0+ of google_sign_in caches the last
      // signed-in account internally. Reusing a stale cached account can
      // produce confusing Firebase errors (including provider-linking
      // errors) on subsequent sign-in attempts, even though this code
      // never calls linkWithCredential. Signing out first guarantees the
      // account picker always returns a fresh, valid session.
      try {
        await googleSignIn.signOut();
      } catch (_) {
        // No previous session to sign out of — safe to ignore.
      }

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!context.mounted) return;

      await _checkUserAndNavigate();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        _showError(
            "This email is already registered with a different sign-in method. "
            "Please log in using that method instead.");
      } else {
        _showError(e.message ?? e.code);
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  ///  CLEAN ERROR HANDLER (IMPROVED)
  void _showError(String msg) {
    String cleanMessage = msg;

    if (msg.contains("user-not-found")) {
      cleanMessage = "No account found for this email.";
    } else if (msg.contains("wrong-password")) {
      cleanMessage = "Incorrect password. Please try again.";
    } else if (msg.contains("invalid-email")) {
      cleanMessage = "Please enter a valid email address.";
    } else if (msg.contains("too-many-requests")) {
      cleanMessage = "Too many attempts. Try again later.";
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

  ///  INPUT STYLE (your theme preserved)
  InputDecoration _inputStyle(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white.withOpacity(0.95),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: const Color(0xFF2533AE).withOpacity(0.25),
          width: 1.2,
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFF2533AE),
          width: 1.6,
        ),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.red.withOpacity(0.7),
          width: 1.2,
        ),
      ),

      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Colors.red,
          width: 1.6,
        ),
      ),

      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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

                      Text(
                        "Welcome!",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: primaryBlue,
                        ),
                      ),

                      const SizedBox(height: 25),

                      TextField(
                        controller: _emailController,
                        decoration: _inputStyle("Email"),
                      ),

                      const SizedBox(height: 15),

                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: _inputStyle("Password"),
                      ),

                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ForgotPasswordPage(),
                              ),
                            );
                          },
                          child: Text(
                            "Forgot Password?",
                            style: TextStyle(color: primaryBlue),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

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
                          onPressed: _login,
                          child: const Text(
                            "Login",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryBlue,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(
                            color: primaryBlue.withOpacity(0.3),
                          ),
                        ),
                        icon: const Icon(Icons.g_mobiledata, size: 30),
                        label: const Text("Continue with Google"),
                        onPressed: _signInWithGoogle,
                      ),

                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account? "),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SignupPage(),
                                ),
                              );
                            },
                            child: Text(
                              "Sign Up",
                              style: TextStyle(
                                color: primaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
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