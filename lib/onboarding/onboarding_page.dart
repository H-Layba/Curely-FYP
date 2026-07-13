import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'privacy_policy_screen.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  final PageController _controller = PageController();
  int _currentPage = 0;

  late AnimationController _glowController;
  late Animation<double> _glowAnim;

  final Color primaryBlue = const Color(0xFF2533AE);

  final List<Map<String, dynamic>> _slides = [
    {
      "title": "Unified Health Vault",
      "desc":
          "All your prescriptions, lab reports, and medical records stored securely in one place that you fully control.",
      "icon": Icons.folder_shared_rounded,
    },
    {
      "title": "Smart Document Scanner",
      "desc":
          "Automatically extracts medicines and health data from prescriptions and reports using AI text recognition.",
      "icon": Icons.document_scanner_rounded,
    },
    {
      "title": "AI Health Insights",
      "desc":
          "Get personalized diet plans, medicine reminders, and interactive dashboards to track your health progress.",
      "icon": Icons.insights_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();

    ///  Glow pulse animation
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _glowAnim = Tween<double>(begin: 0.10, end: 0.25).animate(
      CurvedAnimation(
        parent: _glowController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [

          ///  BACKGROUND
          Container(
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
          ),

          ///  SOFT WAVE BASE
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF6F8FEA).withOpacity(0.15),
                    Color(0xFF6F8FEA).withOpacity(0.05),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [

                /// 🔵 Skip
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton(
                    onPressed: _finishOnboarding,
                    child: Text(
                      "Skip",
                      style: TextStyle(
                        color: primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _slides.length,
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    itemBuilder: (context, index) {
                      final slide = _slides[index];

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [

                            /// 🔵 ICON WITH PULSING GLOW
                            AnimatedBuilder(
                              animation: _glowAnim,
                              builder: (context, child) {
                                return Container(
                                  height: 120,
                                  width: 120,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.85),
                                    shape: BoxShape.circle,

                                    /// 🔵 PULSING GLOW
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF2533AE)
                                            .withOpacity(_glowAnim.value),
                                        blurRadius: 25,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: child,
                                );
                              },
                              child: Icon(
                                slide["icon"],
                                size: 60,
                                color: primaryBlue,
                              ),
                            ),

                            const SizedBox(height: 40),

                            /// 🔵 TITLE
                            Text(
                              slide["title"],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: primaryBlue,
                              ),
                            ),

                            const SizedBox(height: 12),

                            /// 🔵 DESCRIPTION
                            Text(
                              slide["desc"],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                ///  DOTS
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _slides.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 16 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? primaryBlue
                            : primaryBlue.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                ///  BUTTON
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 20),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    onPressed: () {
                      if (_currentPage < _slides.length - 1) {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.fastOutSlowIn,
                        );
                      } else {
                        _finishOnboarding();
                      }
                    },
                    child: Text(
                      _currentPage < _slides.length - 1
                          ? "Next"
                          : "Get Started",
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seenOnboarding', true);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
    );
  }
}