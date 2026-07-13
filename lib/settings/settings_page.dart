import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_fyp_application/auth/login_page.dart';
import '../utils/cloudinary_cleanup.dart';
import '../notifications/notification_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final user = FirebaseAuth.instance.currentUser;
  final Color primaryBlue = const Color(0xFF2533AE);

  bool medicationReminder = false;
  bool healthReminder = false;
  TimeOfDay? healthReminderTime;
  bool isLoading = true;

  bool get _isGoogleUser =>
      user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

  DocumentReference get _settingsRef => FirebaseFirestore.instance
      .collection('patients')
      .doc(user!.uid)
      .collection('settings')
      .doc('preferences');

  DocumentReference get _patientRef =>
      FirebaseFirestore.instance.collection('patients').doc(user!.uid);

  /// Reference to this user's med_reminders subcollection (in the
  /// "users" collection — where report.dart writes reminder data).
  CollectionReference get _medRemindersRef => FirebaseFirestore.instance
      .collection('users')
      .doc(user!.uid)
      .collection('med_reminders');

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      await user!.reload();
    } catch (_) {}
    final refreshedUser = FirebaseAuth.instance.currentUser;

    final doc = await _settingsRef.get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      medicationReminder = data['medicationReminder'] ?? false;
    } else {
      await _settingsRef.set({"medicationReminder": false});
    }

    final patientSnap = await _patientRef.get();
    final patientData = patientSnap.data() as Map<String, dynamic>?;
    if (patientData != null) {
      healthReminder = patientData['reminderEnabled'] as bool? ?? false;
      final timeMap = patientData['reminderTime'] as Map<String, dynamic>?;
      if (timeMap != null) {
        final h = timeMap['hour'] as int?;
        final m = timeMap['minute'] as int?;
        if (h != null && m != null) {
          healthReminderTime = TimeOfDay(hour: h, minute: m);
        }
      }
    }

    if (refreshedUser != null) {
      final patientDoc = await _patientRef.get();
      final pd = patientDoc.data() as Map<String, dynamic>?;
      if (patientDoc.exists && pd?['email'] != refreshedUser.email) {
        await _patientRef.update({'email': refreshedUser.email});
      }
    }

    if (!mounted) return;
    setState(() => isLoading = false);
  }

  Future<void> _updateSetting(String key, bool value) async {
    await _settingsRef.set({key: value}, SetOptions(merge: true));
  }

  /// Cancels every OS-level medication reminder for this user.
  /// Called when the master "Medication Reminders" toggle is turned OFF
  /// so that notifications already scheduled with AlarmManager are
  /// actually silenced — deleting Firestore docs alone doesn't do that.
  Future<void> _cancelAllMedNotifications() async {
    final snapshot = await _medRemindersRef.get();
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final medTimesCounts = <String, int>{};
      data.forEach((medName, val) {
        final times =
            (val as Map<String, dynamic>)['times'] as List<dynamic>?;
        medTimesCounts[medName] = times?.length ?? 4;
      });
      await NotificationService()
          .cancelAllRemindersForReport(doc.id, medTimesCounts);
    }
  }

  /// Cancels ALL OS-level notifications for this user — both medication
  /// reminders and the daily health reminder. Called at logout so
  /// notifications don't keep firing on a shared device after sign-out.
  /// Must be called BEFORE signOut() since we need the uid to find the
  /// user's reminders in Firestore.
  Future<void> _cancelAllNotificationsForCurrentUser() async {
    // Cancel all medication reminders
    try {
      await _cancelAllMedNotifications();
    } catch (_) {}

    // Cancel the daily health reminder too — _cancelAllMedNotifications()
    // only touches med reminders; the health reminder is a separate
    // AlarmManager entry that also needs to be explicitly cancelled.
    try {
      await NotificationService().cancelDailyHealthReminder();
    } catch (_) {}
  }

  Future<void> _updateHealthReminder({
    required bool enabled,
    TimeOfDay? time,
  }) async {
    final effectiveTime = time ?? healthReminderTime;

    await _patientRef.set({
      'reminderEnabled': enabled,
      if (effectiveTime != null)
        'reminderTime': {
          'hour': effectiveTime.hour,
          'minute': effectiveTime.minute,
        },
    }, SetOptions(merge: true));

    if (enabled && effectiveTime != null) {
      await NotificationService().scheduleDailyHealthReminder(effectiveTime);
    } else {
      await NotificationService().cancelDailyHealthReminder();
    }

    if (!mounted) return;
    setState(() {
      healthReminder = enabled;
      if (effectiveTime != null) healthReminderTime = effectiveTime;
    });
  }

  Future<UserCredential> _reauthenticateWithPassword(String password) async {
    final credential = EmailAuthProvider.credential(
      email: user!.email!,
      password: password,
    );
    return await user!.reauthenticateWithCredential(credential);
  }

  Future<UserCredential> _reauthenticateWithGoogle() async {
    final googleSignIn = GoogleSignIn();
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'sign-in-cancelled',
        message: 'Google sign-in was cancelled.',
      );
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
    return await user!.reauthenticateWithCredential(credential);
  }

  Future<void> _deleteCloudinaryImages() async {
    final uid = user!.uid;
    final urls = <String>{};

    final patientDoc = await _patientRef.get();
    final patientData = patientDoc.data() as Map<String, dynamic>?;
    final profileImage = patientData?['profileImage'] as String?;
    if (profileImage != null) urls.add(profileImage);

    final folders = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('folders')
        .get();
    for (final folder in folders.docs) {
      final reports = await folder.reference.collection('reports').get();
      for (final report in reports.docs) {
        final imageUrl = report.data()['imageUrl'] as String?;
        if (imageUrl != null) urls.add(imageUrl);
      }
    }

    await deleteCloudinaryImages(urls);
  }

  Future<void> _deleteFirestoreData() async {
    final firestore = FirebaseFirestore.instance;
    final uid = user!.uid;

    final userRef = firestore.collection('users').doc(uid);

    final List<DocumentReference> toDelete = [];

    final logs = await _patientRef.collection('daily_logs').get();
    toDelete.addAll(logs.docs.map((d) => d.reference));
    toDelete.add(_settingsRef);
    toDelete.add(_patientRef);

    final reminders = await userRef.collection('med_reminders').get();
    toDelete.addAll(reminders.docs.map((d) => d.reference));

    for (final reminderDoc in reminders.docs) {
      final data = reminderDoc.data() as Map<String, dynamic>;
      final medTimesCounts = <String, int>{};
      data.forEach((medName, val) {
        final times =
            (val as Map<String, dynamic>)['times'] as List<dynamic>?;
        medTimesCounts[medName] = times?.length ?? 4;
      });
      await NotificationService()
          .cancelAllRemindersForReport(reminderDoc.id, medTimesCounts);
    }

    final folders = await userRef.collection('folders').get();
    for (final folder in folders.docs) {
      final reports = await folder.reference.collection('reports').get();
      toDelete.addAll(reports.docs.map((d) => d.reference));
      toDelete.add(folder.reference);
    }
    toDelete.add(userRef);

    const chunkSize = 450;
    for (var i = 0; i < toDelete.length; i += chunkSize) {
      final chunk = toDelete.skip(i).take(chunkSize);
      final batch = firestore.batch();
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return "That password is incorrect.";
      case 'requires-recent-login':
        return "Please confirm your identity again and retry.";
      case 'weak-password':
        return "Password should be at least 6 characters.";
      case 'email-already-in-use':
        return "That email is already in use by another account.";
      case 'invalid-email':
        return "Please enter a valid email address.";
      case 'sign-in-cancelled':
        return "Google sign-in was cancelled.";
      default:
        return e.message ?? "Something went wrong. Please try again.";
    }
  }

  void _showGoogleManagedDialog({
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK", style: TextStyle(color: primaryBlue)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primaryBlue.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primaryBlue, width: 1.5),
      ),
    );
  }

  // =======================
  // CHANGE PASSWORD
  // =======================
  void _changePassword() {
    if (_isGoogleUser) {
      _showGoogleManagedDialog(
        title: "Change Password",
        message:
            "This account signs in with Google, so there's no separate app "
            "password to change. Manage your password from your Google "
            "Account settings instead.",
      );
      return;
    }

    final current = TextEditingController();
    final pass = TextEditingController();
    final confirm = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20,
            left: 16,
            right: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Change Password",
                  style: TextStyle(
                      color: primaryBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 18)),
              const SizedBox(height: 15),
              TextField(
                  controller: current,
                  obscureText: true,
                  decoration: _inputStyle("Current Password")),
              const SizedBox(height: 10),
              TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: _inputStyle("New Password")),
              const SizedBox(height: 10),
              TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration: _inputStyle("Confirm New Password")),
              const SizedBox(height: 15),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (current.text.trim().isEmpty ||
                      pass.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Please fill in all fields")),
                    );
                    return;
                  }
                  if (pass.text != confirm.text) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Passwords do not match")),
                    );
                    return;
                  }
                  try {
                    await _reauthenticateWithPassword(current.text.trim());
                    await user!.updatePassword(pass.text.trim());
                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Password updated")),
                    );
                  } on FirebaseAuthException catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_friendlyError(e))),
                    );
                  } catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error: $e")),
                    );
                  }
                },
                child: const Text("Update Password",
                    style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // =======================
  // UPDATE EMAIL
  // =======================
  void _updateEmail() {
    if (_isGoogleUser) {
      _showGoogleManagedDialog(
        title: "Update Email",
        message:
            "This account signs in with Google, so its email is managed by "
            "your Google Account, not by this app.",
      );
      return;
    }

    final email = TextEditingController();
    final pass = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20,
            left: 16,
            right: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Update Email",
                  style: TextStyle(
                      color: primaryBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 18)),
              const SizedBox(height: 15),
              TextField(
                  controller: email,
                  decoration: _inputStyle("New Email")),
              const SizedBox(height: 10),
              TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: _inputStyle("Password")),
              const SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (email.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Enter a new email")),
                    );
                    return;
                  }
                  try {
                    await _reauthenticateWithPassword(pass.text.trim());
                    await user!.verifyBeforeUpdateEmail(email.text.trim());
                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Verification link sent. Your email updates once you confirm it.",
                        ),
                      ),
                    );
                  } on FirebaseAuthException catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_friendlyError(e))),
                    );
                  } catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error: $e")),
                    );
                  }
                },
                child: const Text("Update Email",
                    style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // =======================
  // DELETE ACCOUNT
  // =======================
  void _deleteAccount() {
    final pass = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20,
            left: 16,
            right: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Delete Account",
                  style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                "This permanently deletes your account, profile, health "
                "logs, uploaded reports, and medication reminders. This "
                "can't be undone.",
                style: TextStyle(
                    color: Colors.black.withOpacity(0.6), fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (!_isGoogleUser) ...[
                TextField(
                    controller: pass,
                    obscureText: true,
                    decoration: _inputStyle("Password")),
                const SizedBox(height: 10),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    "You'll be asked to confirm with Google before deleting.",
                    style: TextStyle(
                        color: Colors.black.withOpacity(0.5), fontSize: 12),
                  ),
                ),
              const SizedBox(height: 5),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  try {
                    if (_isGoogleUser) {
                      await _reauthenticateWithGoogle();
                    } else {
                      await _reauthenticateWithPassword(pass.text.trim());
                    }
                    await _deleteCloudinaryImages();
                    await _deleteFirestoreData();
                    await user!.delete();

                    if (!mounted) return;
                    Navigator.pop(context);
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false,
                    );
                  } on FirebaseAuthException catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_friendlyError(e))),
                    );
                  } catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error: $e")),
                    );
                  }
                },
                child: const Text("Delete Account",
                    style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
    String? subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryBlue.withOpacity(0.1)),
      ),
      child: ListTile(
        leading: Icon(icon, color: color ?? primaryBlue),
        title: Text(title,
            style: TextStyle(color: Colors.black.withOpacity(0.75))),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: TextStyle(
                    color: Colors.black.withOpacity(0.4), fontSize: 12))
            : null,
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryBlue.withOpacity(0.1)),
      ),
      child: SwitchListTile(
        activeColor: primaryBlue,
        title: Text(title),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF4FF),
      appBar: AppBar(
        backgroundColor: primaryBlue,
        title: const Text("Settings", style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [

                /// ACCOUNT
                Text("Account",
                    style: TextStyle(
                        color: primaryBlue, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),

                _tile(
                  icon: Icons.lock_outline,
                  title: "Change Password",
                  subtitle: _isGoogleUser ? "Managed by Google" : null,
                  onTap: _changePassword,
                ),
                _tile(
                  icon: Icons.email_outlined,
                  title: "Update Email",
                  subtitle: _isGoogleUser ? "Managed by Google" : null,
                  onTap: _updateEmail,
                ),
                _tile(
                  icon: Icons.delete_outline,
                  title: "Delete Account",
                  color: Colors.red,
                  onTap: _deleteAccount,
                ),

                const SizedBox(height: 10),

                /// NOTIFICATIONS
                Text("Notifications",
                    style: TextStyle(
                        color: primaryBlue, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),

                // ── Master medication-reminder toggle ────────────────────
                // Turning this OFF cancels every OS-level med notification
                // that report.dart may have already scheduled. Without
                // this, the toggle would only affect future saves in
                // report.dart — notifications already registered with
                // AlarmManager would keep firing regardless.
                _switchTile(
                  title: "Medication Reminders",
                  value: medicationReminder,
                  onChanged: (val) async {
                    setState(() => medicationReminder = val);
                    await _updateSetting("medicationReminder", val);

                    if (val) {
                      // Turning ON — request exact-alarm permission now
                      // that the user has deliberately opted in.
                      await NotificationService()
                          .requestExactAlarmPermission();

                      final exactAllowed = await NotificationService()
                          .canScheduleExactAlarms();
                      if (!exactAllowed && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Reminders are on. Some phones block the exact-time "
                              "permission for sideloaded apps — reminders will still "
                              "fire, just within a few minutes of the set time. "
                              "(To unlock exact timing: App info → ⋮ menu → "
                              "Allow restricted settings → enable Alarms & Reminders.)",
                            ),
                            duration: Duration(seconds: 6),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } else {
                      // Turning OFF — cancel every already-scheduled med
                      // notification so the user stops receiving them
                      // immediately, not just "next time they save in
                      // report.dart".
                      await _cancelAllMedNotifications();
                    }
                  },
                ),

                const SizedBox(height: 4),

                // ── Daily health-entry reminder ──────────────────────────
                _switchTile(
                  title: "Daily Health Entry Reminder",
                  value: healthReminder,
                  onChanged: (val) async {
                    if (val) {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: healthReminderTime ??
                            const TimeOfDay(hour: 20, minute: 0),
                        helpText: "What time should we remind you?",
                      );
                      if (picked == null) return;
                      await _updateHealthReminder(
                          enabled: true, time: picked);
                    } else {
                      await _updateHealthReminder(enabled: false);
                    }
                  },
                ),

                if (healthReminder && healthReminderTime != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: primaryBlue.withOpacity(0.1)),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.access_time, color: primaryBlue),
                      title: Text(
                        "Reminder at ${healthReminderTime!.format(context)}",
                        style: TextStyle(
                            color: Colors.black.withOpacity(0.75),
                            fontSize: 14),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: healthReminderTime!,
                            helpText: "Choose a new reminder time",
                          );
                          if (picked == null) return;
                          await _updateHealthReminder(
                              enabled: true, time: picked);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    "Reminder updated to ${picked.format(context)}"),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        child: Text("Change",
                            style: TextStyle(color: primaryBlue)),
                      ),
                    ),
                  ),

                const SizedBox(height: 10),

                /// LOGOUT
                _tile(
                  icon: Icons.logout,
                  title: "Logout",
                  color: Colors.red,
                  onTap: () async {
                    // Cancel ALL OS notifications (med reminders + daily
                    // health reminder) before signing out — once signed out
                    // we lose the uid needed to find this user's data, and
                    // AlarmManager entries would keep firing on the device
                    // even after logout.
                    await _cancelAllNotificationsForCurrentUser();

                    if (_isGoogleUser) {
                      try {
                        await GoogleSignIn().disconnect();
                      } catch (_) {}
                    }
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
    );
  }
}