import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fyp_application/auth/login_page.dart';
import 'package:flutter_fyp_application/main_scaffold.dart';
import 'dart:async';
import 'dart:math';
import 'onboarding/onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'notifications/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Don't await this — notification setup (and especially the exact-alarm
  // permission screen below) must never be able to block the app from
  // ever showing its UI. scheduleMedReminders() already falls back to
  // inexact scheduling if exact-alarm permission isn't granted, so this
  // can safely happen in the background after the UI is already up.
  NotificationService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const SplashPage(),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late AnimationController _bgController;
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _pulseController;
  late AnimationController _particleController;

  late Animation<double> _bgScale;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;
  late Animation<double> _pulse;
  late Animation<double> _ringExpand;
  late Animation<double> _ringFade;

  @override
  void initState() {
    super.initState();

    // Background soft zoom
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _bgScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _bgController, curve: Curves.easeInOut),
    );

    // Logo entrance
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _logoController,
          curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    // Ring ripple (runs once after logo appears)
    _ringExpand = Tween<double>(begin: 0.8, end: 1.6).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOut),
    );
    _ringFade = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOut),
    );

    // Text entrance
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );

    // Heartbeat pulse on logo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulse = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Particle float
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) => _startSequence());
  }

  Future<void> _startSequence() async {
    _bgController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 700));
    _textController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _pulseController.repeat(reverse: true);
    await Future.delayed(const Duration(seconds: 3));
    _navigateAfterSplash();
  }

  Future<void> _navigateAfterSplash() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('privacyAccepted') ?? false;
    final user = FirebaseAuth.instance.currentUser;
    if (!mounted) return;
    if (!accepted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const OnboardingPage()));
      return;
    }
    if (user != null) {
      // Re-register the daily health reminder in case it was wiped by a
      // device reboot or app reinstall (AlarmManager entries don't survive
      // either). Best-effort — never let a Firestore hiccup block navigation.
      NotificationService.restoreHealthReminderIfEnabled(user.uid)
          .catchError((_) {});
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainScaffold()));
      return;
    }
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  @override
  void dispose() {
    _bgController.dispose();
    _logoController.dispose();
    _textController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final logoSize = size.width * 0.28;

    return Scaffold(
      backgroundColor: const Color(0xFFEAF4FF),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _bgController,
          _logoController,
          _textController,
          _pulseController,
          _particleController,
        ]),
        builder: (context, _) {
          return Stack(
            children: [
              // ── Background circles (depth) ──
              Transform.scale(
                scale: _bgScale.value,
                child: Stack(
                  children: [
                    Positioned(
                      top: -size.height * 0.15,
                      right: -size.width * 0.2,
                      child: Container(
                        width: size.width * 0.75,
                        height: size.width * 0.75,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2533AE).withOpacity(0.07),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -size.height * 0.1,
                      left: -size.width * 0.25,
                      child: Container(
                        width: size.width * 0.85,
                        height: size.width * 0.85,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF6EA8FF).withOpacity(0.10),
                        ),
                      ),
                    ),
                    // Bottom wave strip
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: CustomPaint(
                        size: Size(size.width, size.height * 0.22),
                        painter:
                            _WaveStripPainter(_particleController.value),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Floating dots ──
              ..._buildParticleDots(size),

              // ── Center content ──
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ring ripple + logo
                    SizedBox(
                      width: logoSize * 2,
                      height: logoSize * 2,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer ripple ring
                          Opacity(
                            opacity: _ringFade.value,
                            child: Transform.scale(
                              scale: _ringExpand.value,
                              child: Container(
                                width: logoSize * 1.2,
                                height: logoSize * 1.2,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF2533AE)
                                        .withOpacity(0.3),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Soft glow behind logo
                          Container(
                            width: logoSize * 1.1,
                            height: logoSize * 1.1,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  const Color(0xFF2533AE).withOpacity(0.06),
                            ),
                          ),
                          // Logo with heartbeat pulse
                          FadeTransition(
                            opacity: _logoFade,
                            child: Transform.scale(
                              scale: _logoScale.value * _pulse.value,
                              child: Image.asset(
                                'assets/logo/logo.png',
                                width: logoSize,
                                height: logoSize,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // App name + tagline
                    FadeTransition(
                      opacity: _textFade,
                      child: SlideTransition(
                        position: _textSlide,
                        child: Column(
                          children: [
                            Text(
                              "Curely",
                              style: GoogleFonts.poppins(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF2533AE),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Your Health Companion",
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF2533AE)
                                    .withOpacity(0.55),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Loading dots at bottom ──
              Positioned(
                bottom: size.height * 0.08,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _textFade,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (i) {
                      final delay = i * 0.33;
                      final t =
                          (_particleController.value + delay) % 1.0;
                      final scale = 0.6 + 0.4 * sin(t * pi);
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        child: Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF2533AE)
                                  .withOpacity(0.3 + 0.5 * scale),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildParticleDots(Size size) {
    final dots = [
      [0.12, 0.18, 5.0],
      [0.82, 0.12, 4.0],
      [0.22, 0.72, 3.5],
      [0.75, 0.68, 5.0],
      [0.50, 0.10, 3.0],
      [0.88, 0.42, 4.0],
      [0.06, 0.55, 3.5],
    ];

    return dots.map((d) {
      final t = (_particleController.value + d[0]) % 1.0;
      final floatY = sin(t * 2 * pi) * 8;
      return Positioned(
        left: size.width * d[0],
        top: size.height * d[1] + floatY,
        child: Container(
          width: d[2],
          height: d[2],
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2533AE).withOpacity(0.15),
          ),
        ),
      );
    }).toList();
  }
}

// ── Gentle wave strip at bottom ──
class _WaveStripPainter extends CustomPainter {
  final double progress;
  _WaveStripPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = const Color(0xFFBFDDF7).withOpacity(0.55)
      ..style = PaintingStyle.fill;
    final paint2 = Paint()
      ..color = const Color(0xFF6EA8FF).withOpacity(0.20)
      ..style = PaintingStyle.fill;

    _drawWave(canvas, size, paint1, 0.55, 0.0);
    _drawWave(canvas, size, paint2, 0.70, 0.5);
  }

  void _drawWave(Canvas canvas, Size size, Paint paint, double heightFactor,
      double phaseOffset) {
    final path = Path();
    final waveH = size.height * heightFactor;
    path.moveTo(0, waveH);
    for (double x = 0; x <= size.width; x++) {
      final y = waveH -
          18 *
              sin((x / size.width * 2 * pi) +
                  (progress + phaseOffset) * 2 * pi);
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WaveStripPainter old) => true;
}