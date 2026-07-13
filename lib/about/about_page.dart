import 'package:flutter/material.dart';
import '../onboarding/privacy_policy_screen.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const Color primaryBlue = Color(0xFF2533AE);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF4FF), Color(0xFFBFDDF7)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── HEADER ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: primaryBlue.withOpacity(0.2)),
                        ),
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            size: 16, color: primaryBlue),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "About App",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: primaryBlue,
                          ),
                        ),
                        Text(
                          "Curely — Version 1.0.0",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── BODY ─────────────────────────────────────────────────
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    // Logo + app name
                    Center(
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/logo/logo.png',
                            height: 60,
                            width: 60,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Curely",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A2236),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Your Health Companion",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black.withOpacity(0.45),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    _section(
                      title: "What Curely does",
                      body:
                          "Curely helps you keep track of your health in one place — "
                          "upload prescriptions and medical reports, set "
                          "medication reminders so you never miss a dose, log daily "
                          "health metrics, get diet guidance, and chat with a health "
                          "assistant for quick questions.",
                    ),

                    const SizedBox(height: 14),

                    _section(
                      title: "Your data",
                      body:
                          "Your medical information stays tied to your account and is "
                          "used only to power the features above — reminders, your "
                          "Medical ID in the Emergency section, and your reports. You "
                          "can review what's collected and how it's handled in the "
                          "Privacy Policy below.",
                    ),

                    const SizedBox(height: 18),

                    _linkTile(
                      context,
                      icon: Icons.privacy_tip_outlined,
                      label: "Privacy Policy",
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PrivacyPolicyScreen()),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Center(
                      child: Text(
                        "Built as a Final Year Project, with care for everyday health tracking.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.black.withOpacity(0.35),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryBlue.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: primaryBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: Colors.black.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkTile(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Material(
      color: Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primaryBlue.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Icon(icon, color: primaryBlue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A2236),
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: Color(0xFFB0BAD0)),
            ],
          ),
        ),
      ),
    );
  }
}