import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import '../patient/daily_health_entry_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

// ================= PURE HEALTH-METRIC LOGIC =================
// Pulled out of _DashboardScreenState (which is private to this file and
// can't be referenced from a test file) and made top-level instead, so
// they can be unit tested directly — see test/dashboard_logic_test.dart.
// None of these depend on Firebase, widget state, or anything else that
// needs mocking; they're pure functions of their inputs.

double parseValue(Map<String, dynamic> d, String key) =>
    double.tryParse(d[key]?.toString() ?? "0") ?? 0;

String bpStatus(int sys, int dia) {
  if (sys > 140 || dia > 90) return "High Blood Pressure ⚠️";
  if (sys < 90 || dia < 60) return "Low Blood Pressure ⚠️";
  return "Blood Pressure Normal";
}

String glucoseStatus(double g) {
  if (g > 140) return "High Glucose ⚠️";
  if (g < 70) return "Low Glucose ⚠️";
  return "Glucose Normal";
}

String tempStatus(double t) {
  if (t >= 38.0) return "Fever Detected ⚠️";
  if (t < 35) return "Low Temperature ⚠️";
  return "Temperature Normal";
}

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onMenuTap;
  const DashboardScreen({super.key, this.onMenuTap});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  Future<Uint8List?> _captureWidget(GlobalKey key) async {
  try {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}



  final user = FirebaseAuth.instance.currentUser;

  // Created once here instead of being called inline inside build() via
  // `stream: getUser()` — calling .snapshots() fresh on every rebuild
  // dropped the old Firestore listener and opened a new one each time,
  // even for rebuilds that had nothing to do with the patient's profile
  // data. getData() below is left alone on purpose: it depends on
  // selectedRange, which genuinely needs to change the query when the
  // user switches between daily/weekly/monthly.
  late final Stream<DocumentSnapshot> _userStream = getUser();

  String selectedMetric = "glucose";
  String selectedRange = "weekly";

  // ================= THEME =================
  static const Color primaryBlue = Color(0xFF2533AE);
  static const Color accentBlue = Color(0xFF6EA8FF);
  static const LinearGradient bgGradient = LinearGradient(
    colors: [Color(0xFFEAF4FF), Color(0xFFBFDDF7)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF6EA8FF), Color(0xFF2533AE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );


final GlobalKey _dailyCardKey = GlobalKey();
final GlobalKey _trendCardKey = GlobalKey();
  


  // ================= METRIC CONFIG =================
  static const Map<String, _MetricConfig> metricConfig = {
    "glucose": _MetricConfig(
      label: "Glucose",
      unit: "mg/dL",
      icon: Icons.water_drop_rounded,
      color: Color(0xFF6EA8FF),
      min: 70,
      max: 140,
    ),
    "temperature": _MetricConfig(
      label: "Temperature",
      unit: "°C",
      icon: Icons.thermostat_rounded,
      color: Color(0xFFFF7043),
      min: 35,
      max: 38,
    ),
    "systolic": _MetricConfig(
      label: "Systolic BP",
      unit: "mmHg",
      icon: Icons.favorite_rounded,
      color: Color(0xFFEC407A),
      min: 90,
      max: 140,
    ),
    "diastolic": _MetricConfig(
      label: "Diastolic BP",
      unit: "mmHg",
      icon: Icons.monitor_heart_rounded,
      color: Color(0xFFAB47BC),
      min: 60,
      max: 90,
    ),
    "water": _MetricConfig(
      label: "Water",
      unit: "glasses",
      icon: Icons.local_drink_rounded,
      color: Color(0xFF26C6DA),
      min: 0,
      max: 8,
    ),
    "sleep": _MetricConfig(
      label: "Sleep",
      unit: "hrs",
      icon: Icons.bedtime_rounded,
      color: Color(0xFF5C6BC0),
      min: 7,
      max: 9,
    ),
  };

  // ================= STREAMS =================
  Stream<DocumentSnapshot> getUser() => FirebaseFirestore.instance
      .collection('patients')
      .doc(user!.uid)
      .snapshots();

  Stream<List<Map<String, dynamic>>> getData() {
    final DateTime now = DateTime.now();
    final DateTime startDate = now.subtract(Duration(
      days: selectedRange == "daily" ? 1 : selectedRange == "weekly" ? 7 : 30,
    ));
    return FirebaseFirestore.instance
        .collection('patients')
        .doc(user!.uid)
        .collection('daily_logs')
        .where('timestamp', isGreaterThan: startDate)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((e) => e.data()).toList());
  }

  Future<void> _shareStats() async {
  try {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Generating PDF…",
            style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
      final Uint8List? dailyBytes = await _captureWidget(_dailyCardKey);
    final Uint8List? trendBytes = await _captureWidget(_trendCardKey);


    final snap = await FirebaseFirestore.instance
        .collection('patients')
        .doc(user!.uid)
        .collection('daily_logs')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    final userDoc = await FirebaseFirestore.instance
        .collection('patients')
        .doc(user!.uid)
        .get();

    final userData = userDoc.data() ?? {};
    final latest = snap.docs.isNotEmpty ? snap.docs.first.data() : null;

    final name = userData['name'] ?? 'Patient';
    final bmi = userData['bmi']?.toString() ?? '—';
    final height = userData['height']?.toString() ?? '—';
    final weight = userData['weight']?.toString() ?? '—';
    final glucose = latest?['glucose']?.toString() ?? '—';
    final systolic = latest?['systolic']?.toString() ?? '—';
    final diastolic = latest?['diastolic']?.toString() ?? '—';
    final temp = latest?['temperature']?.toString() ?? '—';
    final water = latest?['water']?.toString() ?? '—';
    final sleep = latest?['sleep']?.toString() ?? '—';

    final now = DateTime.now();
    final dateStr =
        "${now.day}/${now.month}/${now.year}  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    String statusFor(String label, String val) {
      if (label == "Glucose") {
        final v = double.tryParse(val) ?? 0;
        if (v > 140) return "High";
        if (v < 70) return "Low";
        return "Normal";
      }
      if (label == "Temperature") {
        final v = double.tryParse(val) ?? 0;
        if (v >= 38.0) return "Fever";
        if (v < 35) return "Low";
        return "Normal";
      }
      if (label == "Blood Pressure") {
        final s = int.tryParse(systolic) ?? 0;
        final d = int.tryParse(diastolic) ?? 0;
        if (s > 140 || d > 90) return "High";
        if (s < 90 || d < 60) return "Low";
        return "Normal";
      }
      return "—";
    }

    PdfColor statusColor(String status) {
      if (status == "Normal") return PdfColor.fromHex('#16A34A');
      if (status == "High" || status == "Fever") return PdfColor.fromHex('#DC2626');
      if (status == "Low") return PdfColor.fromHex('#D97706');
      return PdfColor.fromHex('#8A97B8');
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [

          // ── HEADER BANNER ──
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#2533AE'),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Health Dashboard Report",
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text("Generated: $dateStr",
                    style: pw.TextStyle(
                        color: PdfColors.white, fontSize: 10)),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          // ── PATIENT PROFILE ──
          _pdfSectionTitle("Patient Profile"),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F0F4FF'),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _pdfProfileStat("Name", name),
                _pdfProfileStat("Height", "${height} cm"),
                _pdfProfileStat("Weight", "${weight} kg"),
                _pdfProfileStat("BMI", bmi),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          // ── LATEST READINGS ──
          _pdfSectionTitle("Latest Health Readings"),
          pw.SizedBox(height: 8),

          _pdfReadingRow(
            label: "Blood Pressure",
            value: "$systolic/$diastolic mmHg",
            status: statusFor("Blood Pressure", ""),
            statusCol: statusColor(statusFor("Blood Pressure", "")),
          ),
          _pdfReadingRow(
            label: "Glucose",
            value: "$glucose mg/dL",
            status: statusFor("Glucose", glucose),
            statusCol: statusColor(statusFor("Glucose", glucose)),
          ),
          _pdfReadingRow(
            label: "Temperature",
            value: "$temp °C",
            status: statusFor("Temperature", temp),
            statusCol: statusColor(statusFor("Temperature", temp)),
          ),
          _pdfReadingRow(
            label: "Water Intake",
            value: "$water glasses",
            status: "—",
            statusCol: PdfColor.fromHex('#8A97B8'),
          ),
          _pdfReadingRow(
            label: "Sleep",
            value: "$sleep hrs",
            status: "—",
            statusCol: PdfColor.fromHex('#8A97B8'),
          ),

          pw.SizedBox(height: 20),

          // ── Daily chart screenshot ──
          if (dailyBytes != null) ...[
            _pdfSectionTitle(
                "Today's Reading — ${metricConfig[selectedMetric]!.label}"),
            pw.SizedBox(height: 10),
            pw.Container(
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(12),
                border:
                    pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
              ),
              child: pw.ClipRRect(
                horizontalRadius: 12,
                verticalRadius: 12,
                child: pw.Image(pw.MemoryImage(dailyBytes),
                    fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 20),
          ],


          // ── Trend chart screenshot ──
          if (trendBytes != null) ...[
            _pdfSectionTitle(
                "${selectedRange == 'weekly' ? '7-Day' : '30-Day'} Trend — ${metricConfig[selectedMetric]!.label}"),
            pw.SizedBox(height: 10),
            pw.Container(
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(12),
                border:
                    pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
              ),
              child: pw.ClipRRect(
                horizontalRadius: 12,
                verticalRadius: 12,
                child: pw.Image(pw.MemoryImage(trendBytes),
                    fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 20),
          ],

          // ── FOOTER ──
          pw.Divider(color: PdfColor.fromHex('#E2E8F0')),
          pw.SizedBox(height: 8),
          pw.Text(
            "This report is generated automatically and is intended for personal reference only.",
            style: const pw.TextStyle(
                fontSize: 9, color: PdfColors.grey),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${name.replaceAll(' ', '_')}_health_report.pdf');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: '$name — Health Dashboard Report',
      text: 'Health report for $name',
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to generate PDF: $e",
              style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
} //// remove

// ── PDF helpers (add these as private methods in the same class) ──

pw.Widget _pdfSectionTitle(String title) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(left: 8),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        left: pw.BorderSide(color: PdfColor.fromHex('#2533AE'), width: 3),
      ),
    ),
    child: pw.Text(title,
        style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#1A2236'))),
  );
}

pw.Widget _pdfProfileStat(String label, String value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label,
          style: const pw.TextStyle(
              fontSize: 9, color: PdfColors.grey)),
      pw.SizedBox(height: 3),
      pw.Text(value,
          style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1A2236'))),
    ],
  );
}

pw.Widget _pdfReadingRow({
  required String label,
  required String value,
  required String status,
  required PdfColor statusCol,
}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 8),
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.8),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#2533AE'))),
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 11,
                color: PdfColor.fromHex('#1A2236'))),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: pw.BoxDecoration(
            color: statusCol == PdfColor.fromHex('#16A34A')
                ? PdfColor.fromHex('#F0FDF4')
                : statusCol == PdfColor.fromHex('#DC2626')
                    ? PdfColor.fromHex('#FEF2F2')
                    : PdfColor.fromHex('#FFFBEB'),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(status,
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: statusCol)),
        ),
      ],
    ),
  );
}



  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // FAB removed — entry button is inline in scroll content
      body: Container(
        decoration: const BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _appHeader(),
              Expanded(
                child: StreamBuilder(
                  stream: _userStream,
                  builder: (ctx, userSnap) {
                    if (!userSnap.hasData) {
                      return const Center(
                          child:
                              CircularProgressIndicator(color: primaryBlue));
                    }
                    final userData =
                        userSnap.data!.data() as Map<String, dynamic>? ?? {};

                    return StreamBuilder(
                      stream: getData(),
                      builder: (ctx, snap) {
                        if (!snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: primaryBlue));
                        }
                        final data = snap.data!;
                        final latest = data.isNotEmpty ? data.first : null;

                        return SingleChildScrollView(
                          padding:
                              const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          child: Column(
                            children: [
                              _patientHeroCard(userData),
                              const SizedBox(height: 14),
                              if (latest != null) _warningsRow(latest),
                              const SizedBox(height: 14),
                              _kpiRow(latest),
                              const SizedBox(height: 14),
                              
                              
                              _chartSection(data, latest),
                              const SizedBox(height: 16),
                              _entryButton(),
                            ],
                          ),
                        );
                      },
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

  // ================= APP HEADER =================
  Widget _appHeader() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: primaryBlue,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: primaryBlue.withOpacity(0.25),
                blurRadius: 20,
                offset: const Offset(0, 8)),
          ],
        ),
        child: SizedBox(
          height: 43,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              
  GestureDetector(
  onTap: widget.onMenuTap,
  child: Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.menu_rounded,
        color: Colors.white, size: 22),
  ),
),

              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Health Dashboard',
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.white)),
                  Text('Your daily health overview',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.white70)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= PATIENT HERO CARD =================
  Widget _patientHeroCard(Map<String, dynamic> d) {
    final double bmi =
        double.tryParse(d['bmi']?.toString() ?? "0") ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: primaryBlue.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
  radius: 26,
  backgroundColor: Colors.white.withOpacity(0.2),
  child: const Icon(
    Icons.person_rounded,
    color: Colors.white,
    size: 28,
  ),
),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d['name'] ?? "Patient",
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('● Active Profile',
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 11)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 0.5, color: Colors.white.withOpacity(0.25)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: _bmiGauge(bmi)),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _heroStat("${d['height'] ?? '-'}", "Height (cm)"),
                    const SizedBox(height: 14),
                    Container(
                        height: 0.5,
                        color: Colors.white.withOpacity(0.2)),
                    const SizedBox(height: 14),
                    _heroStat("${d['weight'] ?? '-'}", "Weight (kg)"),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================= BMI GAUGE WIDGET =================
  Widget _bmiGauge(double bmi) {
    final String category;
    final Color zoneColor;
    if (bmi <= 0) {
      category = "No Data";
      zoneColor = Colors.white54;
    } else if (bmi < 18.5) {
      category = "Underweight";
      zoneColor = const Color(0xFF93C5FD);
    } else if (bmi < 25.0) {
      category = "Normal";
      zoneColor = const Color(0xFF6EE7B7);
    } else if (bmi < 30.0) {
      category = "Overweight";
      zoneColor = const Color(0xFFFBBF24);
    } else {
      category = "Obese";
      zoneColor = const Color(0xFFFCA5A5);
    }

    return Column(
      children: [
        SizedBox(
          height: 100,
          child: CustomPaint(
            painter: BmiGaugePainter(bmi: bmi),
            size: const Size(double.infinity, 100),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          bmi > 0 ? bmi.toStringAsFixed(1) : "—",
          style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w600,
              height: 1),
        ),
        const SizedBox(height: 4),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: zoneColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: zoneColor.withOpacity(0.7), width: 0.8),
          ),
          child: Text(category,
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 2),
        Text("BMI",
            style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.6), fontSize: 10)),
      ],
    );
  }

  Widget _heroStat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Text(label,
            style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.65), fontSize: 10),
            textAlign: TextAlign.center),
      ],
    );
  }

  // ================= WARNINGS ROW =================
  Widget _warningsRow(Map<String, dynamic> d) {
  final statuses = [
    bpStatus(
      int.tryParse(d['systolic']?.toString() ?? "0") ?? 0,
      int.tryParse(d['diastolic']?.toString() ?? "0") ?? 0,
    ),
    glucoseStatus(double.tryParse(d['glucose']?.toString() ?? "0") ?? 0),
    tempStatus(double.tryParse(d['temperature']?.toString() ?? "0") ?? 0),
  ];
  return SizedBox(
    height: 42,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: statuses.map(_warnChip).toList(),
    ),
  );
}

Widget _warnChip(String text) {
  final isAlert = text.contains("⚠️");
  // Strip emoji from display text — icon handles the alert signal
  final displayText = text.replaceAll("⚠️", "").trim();
  return Container(
    margin: const EdgeInsets.only(right: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: isAlert
          ? Colors.red.withOpacity(0.1)
          : Colors.green.withOpacity(0.1),
      border: Border.all(
        color: isAlert
            ? Colors.red.withOpacity(0.3)
            : Colors.green.withOpacity(0.3),
        width: 0.8,
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isAlert ? Icons.warning_rounded : Icons.check_circle_rounded,
          color: isAlert ? Colors.red : Colors.green,
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(displayText,
            style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isAlert
                    ? Colors.red.shade700
                    : Colors.green.shade700)),
      ],
    ),
  );
}

  // ================= KPI ROW =================
  Widget _kpiRow(Map<String, dynamic>? d) {
    if (d == null) {
      return Row(children: [
        _kpi("BP", "—", null),
        _kpi("Glucose", "—", null),
        _kpi("Temp", "—", null),
      ]);
    }
    final gVal =
        double.tryParse(d['glucose']?.toString() ?? "0") ?? 0;
    final tVal =
        double.tryParse(d['temperature']?.toString() ?? "0") ?? 0;
    return Row(
      children: [
        _kpi("Blood Pressure",
            "${d['systolic'] ?? '—'}/${d['diastolic'] ?? '—'}", null),
        _kpi("Glucose", d['glucose']?.toString() ?? "—",
            gVal > 140 || gVal < 70 ? Colors.red : Colors.green),
        _kpi("Temperature", "${d['temperature'] ?? '—'}°",
            tVal >= 38.0 || tVal < 35 ? Colors.red : Colors.green),
      ],
    );
  }

  Widget _kpi(String title, String value, Color? statusColor) {
  return Expanded(
    child: Container(
      height: 90, //  FORCE equal height
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, //  center everything
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              color: const Color(0xFF8A97B8),
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 6),

          //  HANDLE LONG BP TEXT
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                fontSize: 16, // slightly increased
                color: const Color(0xFF1A2236),
              ),
            ),
          ),

          if (statusColor != null) ...[
            const SizedBox(height: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

  // ================= METRIC CHIPS =================
  Widget _metricChipsSection() {
    final list = [
      "glucose",
      "temperature",
      "systolic",
      "diastolic",
      "water",
      "sleep"
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('METRIC',
              style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8A97B8),
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: list.map((m) {
              final active = selectedMetric == m;
              return GestureDetector(
                onTap: () => setState(() => selectedMetric = m),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: active ? cardGradient : null,
                    color: active ? null : const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: active
                        ? [
                            BoxShadow(
                                color: primaryBlue.withOpacity(0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3))
                          ]
                        : null,
                  ),
                  child: Text(
                    m[0].toUpperCase() + m.substring(1),
                    style: GoogleFonts.poppins(
                      color: active
                          ? Colors.white
                          : const Color(0xFF8A97B8),
                      fontSize: 12,
                      fontWeight: active
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ================= CHART SECTION =================
  Widget _chartSection(List<Map<String, dynamic>> data, Map<String, dynamic>? latest) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            selectedRange == "daily"
                ? "Today's Reading"
                : selectedRange == "weekly"
                    ? "7-Day Trend"
                    : "30-Day Trend",
            style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A2236)),
          ),
          // Share button
          GestureDetector(
            onTap: _shareStats,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.ios_share_rounded, size: 14, color: primaryBlue),
                  const SizedBox(width: 5),
                  Text("Share",
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: primaryBlue)),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      // Dropdowns on their own full-width row
      Row(
        children: [
          Expanded(child: _metricDropdown()),
          const SizedBox(width: 8),
          Expanded(child: _rangeDropdown()),
        ],
      ),
      const SizedBox(height: 10),
      if (selectedRange == "daily")
        _dailyMetricCard(latest)
      else
        _trendChartCard(data),
    ],
  );
}

Widget _metricDropdown() {
  final metrics = metricConfig.keys.toList();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      gradient: cardGradient,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: primaryBlue.withOpacity(0.25),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selectedMetric,
        isDense: true,

        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Colors.white,
          size: 18,
        ),

        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(14),

        //  CLOSED STATE (white)
        selectedItemBuilder: (context) {
          return metrics.map((m) {
            return Text(
              metricConfig[m]!.label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            );
          }).toList();
        },

        //  OPEN MENU (blue text)
        items: metrics.map((m) {
          return DropdownMenuItem(
            value: m,
            child: Text(
              metricConfig[m]!.label,
              style: GoogleFonts.poppins(
                color: primaryBlue,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }).toList(),

        onChanged: (val) {
          if (val != null) setState(() => selectedMetric = val);
        },
      ),
    ),
  );
}





  // ================= RANGE DROPDOWN =================
Widget _rangeDropdown() {
  final ranges = ["daily", "weekly", "monthly"];

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      gradient: cardGradient,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: primaryBlue.withOpacity(0.25),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selectedRange,
        isDense: true,

        //  Icon stays white
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Colors.white,
          size: 18,
        ),

        //  Dropdown menu background
        dropdownColor: Colors.white,

        //  Rounded dropdown
        borderRadius: BorderRadius.circular(14),

        //  CLOSED STATE TEXT (white)
        selectedItemBuilder: (context) {
          return ranges.map((r) {
            return Text(
              r[0].toUpperCase() + r.substring(1),
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            );
          }).toList();
        },

        //  OPEN DROPDOWN ITEMS (blue text)
        items: ranges.map((r) {
          return DropdownMenuItem(
            value: r,
            child: Text(
              r[0].toUpperCase() + r.substring(1),
              style: GoogleFonts.poppins(
                color: primaryBlue,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }).toList(),

        onChanged: (val) {
          if (val != null) setState(() => selectedRange = val);
        },
      ),
    ),
  );
}

  // ================= DAILY — SELECTED METRIC CARD ONLY =================
  Widget _dailyMetricCard(Map<String, dynamic>? d) {
    final cfg = metricConfig[selectedMetric]!;
    final rawVal = d?[selectedMetric]?.toString() ?? "—";
    final current = double.tryParse(rawVal) ?? 0;
    final hasData = current > 0;

    final bool isAlert =
        hasData && (current < cfg.min || current > cfg.max);
    final double progress = cfg.max > cfg.min
        ? ((current - cfg.min) / (cfg.max - cfg.min)).clamp(0.0, 1.0)
        : 0.0;

    String statusMsg;
    if (!hasData) {
      statusMsg = "No entry logged today";
    } else if (isAlert) {
      statusMsg =
          current < cfg.min ? "Below normal range" : "Above normal range";
    } else {
      statusMsg = "Within healthy range";
    }


    return RepaintBoundary(
      key: _dailyCardKey,
    child: Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: cfg.color.withOpacity(0.15),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
        border: isAlert
            ? Border.all(color: Colors.red.withOpacity(0.25), width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + label row
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cfg.color.withOpacity(0.7),
                      cfg.color,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: cfg.color.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Icon(cfg.icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cfg.label,
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A2236))),
                    Text("Today's value",
                        style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: const Color(0xFF8A97B8))),
                  ],
                ),
              ),
              if (isAlert)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.red.withOpacity(0.3), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.red, size: 13),
                      const SizedBox(width: 4),
                      Text("Alert",
                          style: GoogleFonts.poppins(
                              color: Colors.red,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 22),

          // Big value display
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rawVal,
                style: GoogleFonts.poppins(
                    fontSize: 38,
                    fontWeight: FontWeight.w400,
                    color: isAlert ? Colors.red : cfg.color,
                    height: 1),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 6),
                child: Text(cfg.unit,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: const Color(0xFF8A97B8),
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Status indicator
          Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: isAlert ? Colors.red : Colors.green,
                      shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(statusMsg,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: isAlert
                          ? Colors.red.shade600
                          : Colors.green.shade600,
                      fontWeight: FontWeight.w500)),
            ],
          ),

          const SizedBox(height: 16),

          // Range bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("${cfg.min.toInt()} ${cfg.unit}",
                  style: GoogleFonts.poppins(
                      fontSize: 9, color: const Color(0xFF8A97B8))),
              Text("Normal range",
                  style: GoogleFonts.poppins(
                      fontSize: 9, color: const Color(0xFF8A97B8))),
              Text("${cfg.max.toInt()} ${cfg.unit}",
                  style: GoogleFonts.poppins(
                      fontSize: 9, color: const Color(0xFF8A97B8))),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: hasData ? progress : 0,
              minHeight: 8,
              backgroundColor: cfg.color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                  isAlert ? Colors.red : cfg.color),
            ),
          ),
        ],
      ),
    ));
    
  }

  // ================= TREND CHART CARD =================
  Widget _trendChartCard(List<Map<String, dynamic>> data) {
    final chronoData = data.reversed.toList();
    final values =
        chronoData.map((e) => parseValue(e, selectedMetric)).toList();

    final labels = chronoData.map((e) {
      try {
        final ts = e['timestamp'];
        final DateTime dt =
            ts is Timestamp ? ts.toDate() : DateTime.now();
        return "${dt.day}/${dt.month}";
      } catch (_) {
        return "—";
      }
    }).toList();

    final cfg = metricConfig[selectedMetric]!;
    final avg = values.isNotEmpty
        ? values.reduce((a, b) => a + b) / values.length
        : 0.0;
    final maxV = values.isNotEmpty
        ? values.reduce((a, b) => a > b ? a : b)
        : 0.0;
    final minV = values.isNotEmpty
        ? values.reduce((a, b) => a < b ? a : b)
        : 0.0;




    return RepaintBoundary(
  key: _trendCardKey,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cfg.label,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                          color: const Color(0xFF1A2236))),
                  Text(
                      selectedRange == "weekly"
                          ? "Past 7 days"
                          : "Past 30 days",
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: const Color(0xFF8A97B8))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: cfg.color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: cfg.color.withOpacity(0.2), width: 0.8),
                ),
                child: Column(
                  children: [
                    Text(avg.toStringAsFixed(1),
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: cfg.color)),
                    Text("avg",
                        style: GoogleFonts.poppins(
                            fontSize: 9,
                            color: const Color(0xFF8A97B8))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniStat("HIGH", maxV.toStringAsFixed(1), Colors.red),
              const SizedBox(width: 16),
              _miniStat("LOW", minV.toStringAsFixed(1),
                  const Color(0xFF4CAF50)),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.grey.withOpacity(0.12), height: 1),
          const SizedBox(height: 14),
          if (values.length < 2)
            SizedBox(
              height: 160,
              child: Center(
                child: Text("Not enough data",
                    style: GoogleFonts.poppins(
                        color: const Color(0xFF8A97B8))),
              ),
            )
          else
            SizedBox(
              height: 160,
              child: CustomPaint(
                painter: ImprovedChartPainter(
                    values: values,
                    labels: labels,
                    accentColor: cfg.color),
                size: Size.infinite,
              ),
            ),
        ],
      ),
    ));
  }

  Widget _miniStat(String label, String value, Color color) {
    return Row(
      children: [
        Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text("$label  ",
            style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8A97B8),
                letterSpacing: 0.5)),
        Text(value,
            style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color)),
      ],
    );
  }

  // ================= ENTRY BUTTON (inline, bottom of scroll) =================
  Widget _entryButton() {
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const DailyHealthEntryPage())),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: primaryBlue,
               
                offset: const Offset(0, 6))
          ],
        ),
        child: Center(
  child: Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.add_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
      const SizedBox(width: 10),
      Text(
        "Log Today's Health",
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1, // 🔥 helps vertical alignment
        ),
      ),
    ],
  ),
),
      ),
    );
  }
}

// ================= IMPROVED CHART PAINTER =================
class ImprovedChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color accentColor;

  const ImprovedChartPainter({
    required this.values,
    required this.labels,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    const double bottomPad = 28.0;
    const double topPad = 8.0;
    final chartH = size.height - bottomPad - topPad;

    final double maxV = values.reduce((a, b) => a > b ? a : b);
    final double minV = values.reduce((a, b) => a < b ? a : b);
    final double range = (maxV - minV) == 0 ? 1 : (maxV - minV);
    final double step = size.width / (values.length - 1);

    double yPos(double val) =>
        topPad + chartH - ((val - minV) / range * chartH);

    final pts = List.generate(
        values.length, (i) => Offset(i * step, yPos(values[i])));

    // Grid
    final gridPaint = Paint()
      ..color = const Color(0xFFE8EEFF)
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final gy = topPad + (chartH / 3) * i;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
    }

    // Bezier
    final linePath = Path();
    linePath.moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      final cpX = pts[i - 1].dx + (pts[i].dx - pts[i - 1].dx) / 2;
      linePath.cubicTo(
          cpX, pts[i - 1].dy, cpX, pts[i].dy, pts[i].dx, pts[i].dy);
    }

    // Fill
    final fillPath = Path()..addPath(linePath, Offset.zero);
    fillPath.lineTo(pts.last.dx, topPad + chartH);
    fillPath.lineTo(pts.first.dx, topPad + chartH);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accentColor.withOpacity(0.22),
            accentColor.withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
    canvas.drawPath(
      linePath,
      Paint()
        ..shader = LinearGradient(colors: [
          accentColor.withOpacity(0.7),
          accentColor,
        ]).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Dots + date labels
    final dotFill = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    final dotBorder = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final int stride = values.length > 10 ? (values.length / 7).ceil() : 1;

    for (int i = 0; i < pts.length; i++) {
      final pt = pts[i];
      canvas.drawCircle(pt, 4.0, dotFill);
      canvas.drawCircle(pt, 4.0, dotBorder);

      if (i % stride == 0 && i < labels.length) {
        final tp = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: const TextStyle(
                color: Color(0xFF8A97B8),
                fontSize: 9,
                fontWeight: FontWeight.w500),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
            canvas, Offset(pt.dx - tp.width / 2, topPad + chartH + 8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant ImprovedChartPainter old) =>
      old.values != values || old.labels != labels;
}

// ================= BMI GAUGE PAINTER =================
// Clean speedometer — no text labels on arc, on-theme soft colors
class BmiGaugePainter extends CustomPainter {
  final double bmi;
  const BmiGaugePainter({required this.bmi});

  static const double _minBmi = 10.0;
  static const double _maxBmi = 40.0;

  static const List<_Zone> _zones = [
    _Zone(0.000, 0.283, Color(0xFF93C5FD)), // Underweight – sky blue
    _Zone(0.283, 0.500, Color(0xFF6EE7B7)), // Normal     – mint
    _Zone(0.500, 0.667, Color(0xFFFBBF24)), // Overweight – amber
    _Zone(0.667, 1.000, Color(0xFFFCA5A5)), // Obese      – soft rose
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height - 4;
    final radius = size.width * 0.42;
    const strokeW = 14.0;
    const gap = 0.04;

    const arcStart = math.pi;
    const arcSweep = math.pi;

    // Background track
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      arcStart,
      arcSweep,
      false,
      Paint()
        ..color = Colors.white.withOpacity(0.1)
        ..strokeWidth = strokeW + 4
        ..style = PaintingStyle.stroke,
    );

    // Zone arcs
    for (final z in _zones) {
      final start = arcStart + z.start * arcSweep + gap / 2;
      final sweep = (z.end - z.start) * arcSweep - gap;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        start,
        sweep,
        false,
        Paint()
          ..color = z.color
          ..strokeWidth = strokeW
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.butt,
      );
    }

    // Needle
    final clamped = bmi.clamp(_minBmi, _maxBmi);
    final fraction = (clamped - _minBmi) / (_maxBmi - _minBmi);
    final angle = arcStart + fraction * arcSweep;
    final needleLen = radius - strokeW / 2 - 6;
    final nx = cx + needleLen * math.cos(angle);
    final ny = cy + needleLen * math.sin(angle);

    canvas.drawLine(
      Offset(cx + 1, cy + 1),
      Offset(nx + 1, ny + 1),
      Paint()
        ..color = Colors.black.withOpacity(0.2)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      Offset(cx, cy),
      Offset(nx, ny),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // Pivot
    canvas.drawCircle(Offset(cx, cy), 9.5,
        Paint()..color = Colors.white.withOpacity(0.25));
    canvas.drawCircle(Offset(cx, cy), 7.0, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx, cy), 4.5,
        Paint()..color = const Color(0xFF2533AE));
  }

  @override
  bool shouldRepaint(covariant BmiGaugePainter old) => old.bmi != bmi;
}

// ================= MODELS =================
class _MetricConfig {
  final String label;
  final String unit;
  final IconData icon;
  final Color color;
  final double min;
  final double max;

  const _MetricConfig({
    required this.label,
    required this.unit,
    required this.icon,
    required this.color,
    required this.min,
    required this.max,
  });
}

class _Zone {
  final double start;
  final double end;
  final Color color;
  const _Zone(this.start, this.end, this.color);
}