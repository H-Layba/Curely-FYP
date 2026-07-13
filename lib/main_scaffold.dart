import 'package:flutter/material.dart';
import 'dashboard/dashboard.dart';
import 'reports/report.dart';
import 'diet_model/diet.dart';
import 'chatbot_model/chatbot.dart';
import 'profile/profile_page.dart';
import 'auth/login_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'settings/settings_page.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'emergency/emergency_page.dart';
import 'about/about_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notifications/notification_service.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final Color primaryBlue = const Color(0xFF2533AE);

  final List<Widget> _screens = [
    DashboardScreen(),
    ReportsScreen(),
    DietScreen(),
    ChatbotScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Reschedule all notifications for the current user on every fresh
    // MainScaffold mount — this covers three cases:
    //   1. Normal login:        login_page → MainScaffold (initState runs)
    //   2. App restart:         saved Firebase session → MainScaffold (initState runs)
    //   3. Logout → re-login:   new MainScaffold pushed → initState runs again
    // AlarmManager entries don't survive logout or device reboot, so we
    // always rebuild them from the preferences saved in Firestore.
    _rescheduleNotificationsOnLogin();
  }

  /// Rebuilds all OS-level notifications from Firestore on login/relaunch.
  /// Checks the master medication toggle before scheduling med reminders
  /// so a user who had it turned off doesn't suddenly start getting them.
  Future<void> _rescheduleNotificationsOnLogin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // ── 1. Check master medication reminder toggle ───────────────────────
    bool masterMedEnabled = true;
    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(uid)
          .collection('settings')
          .doc('preferences')
          .get();
      if (settingsDoc.exists) {
        masterMedEnabled =
            (settingsDoc.data() as Map<String, dynamic>)['medicationReminder']
                    as bool? ??
                true;
      }
    } catch (_) {}

    // ── 2. Reschedule medication reminders (only if master toggle is on) ─
    if (masterMedEnabled) {
      try {
        final reminders = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('med_reminders')
            .get();

        for (final doc in reminders.docs) {
          final data = doc.data() as Map<String, dynamic>;
          for (final entry in data.entries) {
            final medName = entry.key;
            final medData = entry.value as Map<String, dynamic>;
            final enabled = medData['enabled'] as bool? ?? false;
            if (!enabled) continue;

            final timesRaw = medData['times'] as List<dynamic>?;
            if (timesRaw == null || timesRaw.isEmpty) continue;

            final times = timesRaw
                .map((t) => TimeOfDay(
                      hour: (t as Map<String, dynamic>)['hour'] as int,
                      minute: t['minute'] as int,
                    ))
                .toList();

            final baseId =
                NotificationService.makeBaseId(doc.id, medName);

            await NotificationService().scheduleMedReminders(
              notificationBaseId: baseId,
              medName: medName,
              times: times,
            );
          }
        }
      } catch (_) {}
    }

    // ── 3. Reschedule daily health reminder ──────────────────────────────
    try {
      final patientDoc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(uid)
          .get();

      final data = patientDoc.data() as Map<String, dynamic>?;
      if (data == null) return;

      final reminderEnabled = data['reminderEnabled'] as bool? ?? false;
      if (!reminderEnabled) return;

      final timeMap = data['reminderTime'] as Map<String, dynamic>?;
      if (timeMap == null) return;

      final h = timeMap['hour'] as int?;
      final m = timeMap['minute'] as int?;
      if (h == null || m == null) return;

      await NotificationService()
          .scheduleDailyHealthReminder(TimeOfDay(hour: h, minute: m));
    } catch (_) {}
  }

  /// Cancels ALL OS-level notifications for the current user before
  /// sign-out so they don't keep firing on a shared device after logout.
  /// Must be called BEFORE signOut() — once signed out we lose the uid
  /// needed to find this user's reminders in Firestore.
  Future<void> _cancelAllNotificationsForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Cancel all medication reminders across every report
    try {
      final reminders = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('med_reminders')
          .get();

      for (final doc in reminders.docs) {
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
    } catch (_) {}

    // Cancel the daily health reminder
    try {
      await NotificationService().cancelDailyHealthReminder();
    } catch (_) {}
  }

  void _logout() async {
    // Cancel all OS-level notifications BEFORE signing out — once signed
    // out we lose the uid needed to look up which notifications belong to
    // this user. Without this, a logged-out account's reminders keep
    // firing on the device forever.
    await _cancelAllNotificationsForCurrentUser();

    // Only attempt to disconnect Google if this session actually signed in
    // via Google — disconnect() throws if there's no active Google session,
    // and since that wasn't caught, it used to abort everything below it
    // (Firebase sign-out, navigation) for every email/password account.
    // That's why Logout silently did nothing for non-Google users.
    final isGoogleUser = FirebaseAuth.instance.currentUser?.providerData
            .any((p) => p.providerId == 'google.com') ??
        false;

    if (isGoogleUser) {
      try {
        await GoogleSignIn().disconnect();
      } catch (_) {
        // Best-effort — a Google-side hiccup should never block sign-out.
      }
    }

    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _openPage(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: color ?? primaryBlue,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: Colors.black.withOpacity(0.75),
          fontWeight: FontWeight.w500,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      horizontalTitleGap: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      splashColor: primaryBlue.withOpacity(0.08),
      hoverColor: primaryBlue.withOpacity(0.05),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      extendBody: true,

      ///  DRAWER (UPGRADED)
      drawer: Drawer(
        child: Container(
          color: const Color(0xFFEAF4FF),
          child: ListView(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                decoration: BoxDecoration(
                  color: primaryBlue,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset(
                      'assets/logo/logo.png',
                      height: 54,
                      width: 54,
                    ),
                    SizedBox(height: 10),
                    Text(
                      "Curely",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "Your Health Companion",
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              /// 👤 PROFILE
              _drawerItem(
                icon: Icons.person_outline,
                title: "Profile",
                onTap: () {
                  Navigator.pop(context);
                  _openPage(const ProfilePage());
                },
              ),

              const SizedBox(height: 6),

              /// ⚙️ SETTINGS
              _drawerItem(
                icon: Icons.settings_outlined,
                title: "Settings",
                onTap: () => _openPage(const SettingsPage()),
              ),

              /// ℹ️ ABOUT
              _drawerItem(
                icon: Icons.info_outline,
                title: "About App",
                onTap: () {
                  Navigator.pop(context);
                  _openPage(const AboutPage());
                },
              ),

              const SizedBox(height: 6),

              /// 🚨 EMERGENCY (highlighted)
              _drawerItem(
                icon: Icons.emergency,
                title: "Emergency",
                color: Colors.redAccent,
                onTap: () {
                  Navigator.pop(context);
                  _openPage(const EmergencyPage());
                },
              ),

              const SizedBox(height: 16),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text("Logout"),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),

      ///  BODY
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
        child: IndexedStack(
          index: _currentIndex,
          children: [
            DashboardScreen(
              onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            const ReportsScreen(),
            const DietScreen(),
            const ChatbotScreen(),
          ],
        ),
      ),

      ///  MODERN NAV BAR
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
      _NavItem(icon: Icons.description_rounded, label: 'Reports'),
      _NavItem(icon: Icons.restaurant_rounded, label: 'Diet'),
      _NavItem(icon: Icons.chat_bubble_rounded, label: 'Chatbot'),
    ];

    return SizedBox(
      height: 80, //  enough space to avoid overflow
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          ///  FLAT BACKGROUND BAR (no bottom rounding)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF2533AE),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryBlue.withOpacity(0.25),
                    blurRadius: 15,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
            ),
          ),

          ///  ITEMS
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (i) {
                final isActive = _currentIndex == i;

                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = i),
                  child: SizedBox(
                    width: 70,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.none,
                      children: [
                        ///  CUTOUT EFFECT (hides bar behind circle)
                        ///  CUTOUT (slightly bigger + lower)
                        if (isActive)
                          Positioned(
                            top: -6, // ⬅️ lowered from -18
                            child: Container(
                              height: 54, // ⬅️ slightly bigger than circle
                              width: 54,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFBFDDF7), // your background color
                              ),
                            ),
                          ),

                        ///  ACTIVE CIRCLE (perfectly aligned inside cutout)
                        if (isActive)
                          Positioned(
                            top: -8, //  lowered slightly more than cutout for overlap
                            child: Container(
                              height: 52,
                              width: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF6EA8FF), // refined highlight
                                    Color(0xFF2533AE), // your primary blue (stronger match)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.4),
                                    blurRadius: 8,
                                  ),
                                  BoxShadow(
                                    color: primaryBlue.withOpacity(0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Icon(
                                items[i].icon,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),

                        ///  CONTENT (icon + label)
                        Positioned(
                          bottom: 8,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isActive)
                                Icon(
                                  items[i].icon,
                                  color: Colors.white.withOpacity(0.7),
                                  size: 22,
                                ),
                              const SizedBox(height: 4),
                              Text(
                                items[i].label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(
                                    isActive ? 1 : 0.7,
                                  ),
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}