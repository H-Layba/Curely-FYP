import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../profile/profile_page.dart';

const String kEmergencyNumber = "1122";

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key});

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  static const Color primaryBlue = Color(0xFF2533AE);
  static const Color emergencyRed = Color(0xFFE03B3B);

  final user = FirebaseAuth.instance.currentUser;

  Future<void> _callEmergencyServices() async {
    final uri = Uri(scheme: 'tel', path: kEmergencyNumber);
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) _showCantDialFallback();
    } catch (_) {
      if (mounted) _showCantDialFallback();
    }
  }

  void _showCantDialFallback() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Couldn't open the dialer — call $kEmergencyNumber directly."),
        backgroundColor: emergencyRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

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
                          "Emergency",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: primaryBlue,
                          ),
                        ),
                        Text(
                          "Medical ID & quick call",
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
                child: user == null
                    ? const Center(child: Text("Not signed in"))
                    : StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('patients')
                            .doc(user!.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final data =
                              (snapshot.data?.data() as Map<String, dynamic>?) ??
                                  {};
                          return ListView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            children: [
                              _callButton(),
                              const SizedBox(height: 16),
                              _medicalIdCard(data),
                              const SizedBox(height: 12),
                              _editProfileNote(context),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _callButton() {
    return Material(
      color: emergencyRed,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _callEmergencyServices,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: emergencyRed.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              const Icon(Icons.call_rounded, color: Colors.white, size: 30),
              const SizedBox(height: 8),
              const Text(
                "Call Emergency Services",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                kEmergencyNumber,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _medicalIdCard(Map<String, dynamic> data) {
    final name = (data['name'] as String?)?.trim();
    final age = data['age'];
    final bloodType = data['bloodType'] as String?;
    final allergies = List<String>.from(data['allergies'] ?? const []);
    final conditions = List<String>.from(data['chronicDisease'] ?? const []);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryBlue.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.badge_outlined,
                    color: primaryBlue, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                "Medical ID",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A2236),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (name != null && name.isNotEmpty) _idRow("Name", name),
          if (age != null) _idRow("Age", "$age"),
          _idRow(
            "Blood Type",
            (bloodType == null || bloodType.isEmpty)
                ? "Not recorded"
                : bloodType,
          ),
          const SizedBox(height: 14),
          _chipSection(
            label: "Allergies",
            items: allergies,
            emptyText: "No allergies recorded",
            chipColor: emergencyRed,
          ),
          const SizedBox(height: 14),
          _chipSection(
            label: "Chronic Conditions",
            items: conditions,
            emptyText: "No chronic conditions recorded",
            chipColor: primaryBlue,
          ),
        ],
      ),
    );
  }

  Widget _idRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF8A97B8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1A2236),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipSection({
    required String label,
    required List<String> items,
    required String emptyText,
    required Color chipColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF8A97B8),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(
            emptyText,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFB0BAD0),
              fontStyle: FontStyle.italic,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map((item) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: chipColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: chipColor.withOpacity(0.25)),
                      ),
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: chipColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ))
                .toList(),
          ),
      ],
    );
  }

  Widget _editProfileNote(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 16, color: Color(0xFF8A97B8)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            "This is pulled from your profile. Keep it current so it's useful in an emergency.",
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.black.withOpacity(0.45),
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          ),
          child: Text(
            "Edit",
            style: TextStyle(
              fontSize: 12.5,
              color: primaryBlue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}