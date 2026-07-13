import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../notifications/notification_service.dart';

class DailyHealthEntryPage extends StatefulWidget {
  const DailyHealthEntryPage({super.key});

  @override
  State<DailyHealthEntryPage> createState() => _DailyHealthEntryPageState();
}

class _DailyHealthEntryPageState extends State<DailyHealthEntryPage> {
  final user = FirebaseAuth.instance.currentUser;
  final _formKey = GlobalKey<FormState>();

  final systolicController = TextEditingController();
  final diastolicController = TextEditingController();
  final glucoseController = TextEditingController();
  final tempController = TextEditingController();
  final waterController = TextEditingController();
  final sleepController = TextEditingController();

  bool isLoading = false;
  bool isCheckingEntry = true;
  bool alreadySubmittedToday = false;

  final Color primaryBlue = const Color(0xFF2533AE);

  /// Returns today's date as a string key e.g. "2026-06-20"
  String get _todayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _checkTodayEntry();
  }

  /// Check if the user has already submitted an entry for today
  Future<void> _checkTodayEntry() async {
    final doc = await FirebaseFirestore.instance
        .collection('patients')
        .doc(user!.uid)
        .collection('daily_logs')
        .doc(_todayKey)
        .get();

    setState(() {
      alreadySubmittedToday = doc.exists;
      isCheckingEntry = false;
    });
  }

  Future<void> saveData() async {
    // Stop here if any field is empty, non-numeric, or out of a sane
    // physiological range — previously an empty form could be saved as a
    // valid entry, and the dashboard would parse the blanks as 0 and show
    // false "Low Glucose / Low Blood Pressure / Low Temperature" alerts.
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => isLoading = true);

    try {
      // Use today's date as the document ID — guarantees one entry per day
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(user!.uid)
          .collection('daily_logs')
          .doc(_todayKey)
          .set({
        "systolic": systolicController.text.trim(),
        "diastolic": diastolicController.text.trim(),
        "glucose": glucoseController.text.trim(),
        "temperature": tempController.text.trim(),
        "water": waterController.text.trim(),
        "sleep": sleepController.text.trim(),
        "timestamp": FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Without this, a failed write (no connection, permission error,
      // etc.) left isLoading stuck at true forever — the button looked
      // frozen with no explanation. Now we reset state and tell the user.
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              "Couldn't save your entry. Check your connection and try again."),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => isLoading = false);

    // Only ever ask this once — previously there was no check at all, so
    // it popped up after every single day's entry, even for someone who'd
    // already answered (yes or no) on a previous day.
    bool alreadyAsked = false;
    try {
      final patientDoc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(user!.uid)
          .get();
      alreadyAsked =
          (patientDoc.data()?['reminderPromptShown'] as bool?) ?? false;
    } catch (_) {
      // If we can't tell whether they've already been asked, err on the
      // side of NOT asking again rather than risk nagging daily due to a
      // flaky connection.
      alreadyAsked = true;
    }

    if (!alreadyAsked) {
      // Properly await the dialog instead of firing-and-forgetting it.
      // Previously the unconditional Navigator.pop(context) right after
      // showDialog() popped the dialog route itself (since it was now on
      // top of the stack) instead of leaving this page, so the prompt
      // flashed shut instantly and the page never navigated back.
      final wantsReminder = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          // Explicit white — without this it was inheriting Flutter's
          // default Material 3 dialog surface color, which (since this
          // app's ThemeData never sets a custom colorScheme) defaults to
          // a purple-tinted palette and showed up as pinkish here, even
          // though every other screen in the app hardcodes the blue
          // theme directly and never hit this default.
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.notifications_outlined, color: primaryBlue),
              const SizedBox(width: 8),
              const Text("Daily Reminder"),
            ],
          ),
          content: const Text(
              "Would you like to be reminded daily to enter your health data?"),
          actions: [
            TextButton(
              // Pop the dialog's own context, with a result, rather than
              // the page's — this only ever closes the dialog.
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text("No Thanks", style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Yes, Remind Me", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      // Record that they've been asked — regardless of their answer —
      // so this never shows again after today, one way or the other.
      try {
        await FirebaseFirestore.instance
            .collection('patients')
            .doc(user!.uid)
            .set({
          "reminderPromptShown": true,
          "reminderEnabled": wantsReminder == true,
        }, SetOptions(merge: true));
      } catch (_) {
        // Best-effort — the health entry itself already saved successfully,
        // so a failure here shouldn't block leaving the page.
      }

      if (wantsReminder == true && mounted) {
        // Let them pick a time rather than guessing one for them — same
        // approach as the manual time-setting on medication reminders.
        final pickedTime = await showTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 20, minute: 0),
          helpText: "What time should we remind you?",
        );

        if (pickedTime != null) {
          try {
            await FirebaseFirestore.instance
                .collection('patients')
                .doc(user!.uid)
                .set({
              "reminderTime": {
                "hour": pickedTime.hour,
                "minute": pickedTime.minute,
              },
            }, SetOptions(merge: true));

            // This is the part that was missing entirely before — the
            // flag was being saved to Firestore, but nothing ever
            // actually scheduled a notification, so "Yes, Remind Me"
            // silently did nothing. Now it actually registers a daily
            // reminder with the OS.
            await NotificationService().scheduleDailyHealthReminder(pickedTime);
          } catch (_) {
            // Best-effort — same reasoning as above.
          }
        }
      }
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  /// Validates a vital-sign field: required, must be numeric, and must
  /// fall within a physiologically plausible range so obviously-wrong or
  /// empty input can't be saved as today's reading.
  String? Function(String?) _vitalValidator(String label, {required num min, required num max}) {
    return (value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return "Required";
      final n = num.tryParse(trimmed);
      if (n == null) return "Enter a number";
      if (n < min || n > max) return "$min–$max range";
      return null;
    };
  }

  InputDecoration _inputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 13),
      prefixIcon: Icon(icon, color: primaryBlue),
      filled: true,
      fillColor: Colors.white.withOpacity(0.95),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: primaryBlue.withOpacity(0.25), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: primaryBlue, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    required num min,
    required num max,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 13),
        decoration: _inputStyle(label, icon),
        validator: _vitalValidator(label, min: min, max: max),
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 4),
      child: Row(
        children: [
          Icon(icon, color: primaryBlue, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: primaryBlue.withOpacity(0.75),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: primaryBlue.withOpacity(0.15), thickness: 1)),
        ],
      ),
    );
  }

  /// Shown when the user has already submitted today
  Widget _buildAlreadySubmitted() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primaryBlue.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(Icons.check_circle_rounded, color: primaryBlue, size: 64),
            ),
            const SizedBox(height: 28),
            Text(
              "Already logged today!",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: primaryBlue,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "You've already submitted your health data for today. Come back tomorrow to log your next entry.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black.withOpacity(0.5),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: primaryBlue),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text("Go Back", style: TextStyle(color: primaryBlue)),
            ),
          ],
        ),
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
                        child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: primaryBlue),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Daily Health Entry",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: primaryBlue,
                          ),
                        ),
                        Text(
                          "Log today's vitals and wellness data",
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
                child: isCheckingEntry
                    ? const Center(child: CircularProgressIndicator())
                    : alreadySubmittedToday
                        ? _buildAlreadySubmitted()
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
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
                              child: Form(
                                key: _formKey,
                                child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionHeader("BLOOD PRESSURE", Icons.favorite_border_rounded),
                                  _buildField("Systolic (mmHg)", systolicController, Icons.arrow_upward_rounded, min: 60, max: 250),
                                  _buildField("Diastolic (mmHg)", diastolicController, Icons.arrow_downward_rounded, min: 40, max: 150),

                                  _buildSectionHeader("BLOOD & VITALS", Icons.bloodtype_outlined),
                                  _buildField("Blood Sugar (mg/dL)", glucoseController, Icons.water_drop_outlined, min: 20, max: 600),
                                  _buildField("Temperature (°C)", tempController, Icons.thermostat_outlined, min: 30, max: 45),

                                  _buildSectionHeader("LIFESTYLE", Icons.self_improvement_outlined),
                                  _buildField("Water Intake (glasses)", waterController, Icons.local_drink_outlined, min: 0, max: 20),
                                  _buildField("Sleep Hours", sleepController, Icons.bedtime_outlined, min: 0, max: 24),

                                  const SizedBox(height: 10),

                                  SizedBox(
                                    width: double.infinity,
                                    height: 55,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryBlue,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      onPressed: isLoading ? null : saveData,
                                      child: isLoading
                                          ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : const Text(
                                              "Save Entry",
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.white,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                                ),
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}