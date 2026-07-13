// lib/reports/report.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../notifications/notification_service.dart';
import '../utils/cloudinary_cleanup.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const String BASE_URL = "https://backend-g8y6.onrender.com";

  final ImagePicker _picker = ImagePicker();
  final user = FirebaseAuth.instance.currentUser;

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

  String? selectedFolderId;
  String searchQuery = "";

  CollectionReference get foldersRef => FirebaseFirestore.instance
      .collection('users')
      .doc(user!.uid)
      .collection('folders');

  // =========================
  // TEXT CLEANING
  // =========================
  static String cleanExtractedText(String raw) {
    String text = raw.replaceAll(RegExp(r'```json\s*', multiLine: true), '');
    text = text.replaceAll(RegExp(r'```\s*', multiLine: true), '');
    text = text.replaceAll(RegExp(r'[{}\[\]"]'), '');
    text = text.replaceAll(RegExp(r',\s*\n'), '\n');
    text = text.replaceAll(',', '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  // =========================
  // MEDICATION PARSING
  // =========================
  static List<Map<String, String>> parseMedications(String rawText) {
    final text = cleanExtractedText(rawText);
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final sectionHeaderRegex = RegExp(
      r'^(medicines?|medications?|drugs?|prescriptions?|prescribed[_\s]?(medicines|drugs)?)$',
      caseSensitive: false,
    );
    final nameKeyRegex = RegExp(
      r'^(name|medicine[_\s]?name|drug[_\s]?name|medication)$',
      caseSensitive: false,
    );
    final dosageKeyRegex = RegExp(
      r'^(dosage|dose|strength|quantity|amount|mg)$',
      caseSensitive: false,
    );
    final freqKeyRegex = RegExp(
      r'^(frequency|freq|times|daily|per[_\s]?day|schedule|intake|interval|how[_\s]?often)$',
      caseSensitive: false,
    );
    final standaloneMedLineRegex = RegExp(
      r'^(medicine|medication|drug|tablet|capsule|syrup|injection|rx|prescribed|med)$',
      caseSensitive: false,
    );
    final instructionContinuationRegex = RegExp(
      r'^(then|before|after|with|without|until|continue|continued|stop|'
      r'discontinue|next|follow[\s-]?up|as needed|when needed|every|each|'
      r'take|apply|use|po|orally|for \d)\b'
      r'|\b(\d+\s*times?|once|twice|thrice|daily|per\s*day|a\s*day|'
      r'morning|evening|night|noon|afternoon|bedtime|hourly)\b',
      caseSensitive: false,
    );

    final meds = <Map<String, String>>[];

    int sectionStart = -1;
    for (int i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final headerKey =
          raw.endsWith(':') ? raw.substring(0, raw.length - 1).trim() : raw;
      if (sectionHeaderRegex.hasMatch(headerKey)) {
        sectionStart = i + 1;
        break;
      }
    }

    if (sectionStart != -1) {
      String? pendingName;
      String? pendingDosage;
      String? pendingFreq;

      void flush() {
        if (pendingName != null && pendingName!.trim().isNotEmpty) {
          final fullName = (pendingDosage != null && pendingDosage!.isNotEmpty)
              ? '${pendingName!.trim()} (${pendingDosage!.trim()})'
              : pendingName!.trim();
          meds.add({'name': fullName, 'frequency': pendingFreq ?? ''});
        }
        pendingName = null;
        pendingDosage = null;
        pendingFreq = null;
      }

      for (int i = sectionStart; i < lines.length; i++) {
        final line = lines[i];
        final colonIdx = line.indexOf(':');

        if (colonIdx <= 0) {
          if (pendingName != null &&
              instructionContinuationRegex.hasMatch(line)) {
            pendingFreq = (pendingFreq == null || pendingFreq!.isEmpty)
                ? line
                : '${pendingFreq!}, $line';
            continue;
          }
          flush();
          pendingName = line;
          continue;
        }

        final key = line.substring(0, colonIdx).trim();
        final value = line.substring(colonIdx + 1).trim();
        if (value.isEmpty) continue;

        if (nameKeyRegex.hasMatch(key)) {
          flush();
          pendingName = value;
        } else if (dosageKeyRegex.hasMatch(key)) {
          pendingDosage = value;
        } else if (freqKeyRegex.hasMatch(key)) {
          pendingFreq = value;
        } else {
          continue;
        }
      }
      flush();
    }

    if (meds.isEmpty) {
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final colonIdx = line.indexOf(':');
        if (colonIdx <= 0) continue;

        final key = line.substring(0, colonIdx).trim();
        final value = line.substring(colonIdx + 1).trim();
        if (value.isEmpty || !standaloneMedLineRegex.hasMatch(key)) continue;

        String freq = '';
        for (int j = i + 1; j < lines.length && j <= i + 2; j++) {
          final nColon = lines[j].indexOf(':');
          if (nColon <= 0) continue;
          final nKey = lines[j].substring(0, nColon).trim();
          final nVal = lines[j].substring(nColon + 1).trim();
          if (freqKeyRegex.hasMatch(nKey) && nVal.isNotEmpty) {
            freq = nVal;
            break;
          }
        }
        meds.add({'name': value, 'frequency': freq});
      }
    }

    final seen = <String>{};
    return meds.where((m) => seen.add(m['name']!.toLowerCase())).toList();
  }

  // =========================
  // CLOUDINARY UPLOAD
  // =========================
  Future<String?> uploadToCloudinary(File file) async {
    const cloudName = "dp1ciw5d9";
    const uploadPreset = "reports";
    final url =
        Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");
    final request = http.MultipartRequest("POST", url);
    request.fields['upload_preset'] = uploadPreset;
    request.files.add(await http.MultipartFile.fromPath("file", file.path));
    final response = await request.send();
    final res = await response.stream.bytesToString();
    final jsonData = json.decode(res);
    return jsonData["secure_url"];
  }

  // =========================
  // PICK FILE / CAMERA
  // =========================
  Future<File?> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) return File(result.files.single.path!);
    return null;
  }

  Future<File?> _captureImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) return File(image.path);
    return null;
  }

  // =========================
  // CREATE FOLDER
  // =========================
  Future<void> _createFolder() async {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => _StyledDialog(
        title: "New Folder",
        icon: Icons.create_new_folder_rounded,
        child: _StyledTextField(controller: controller, hint: "Folder name"),
        actions: [
          _DialogCancelButton(onTap: () => Navigator.pop(context)),
          _DialogConfirmButton(
            label: "Create",
            onTap: () async {
              if (controller.text.trim().isEmpty) return;
              await foldersRef.add({
                "name": controller.text.trim(),
                "createdAt": FieldValue.serverTimestamp(),
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // =========================
  // FULL REPORT BOTTOM SHEET
  // =========================
  void _showFullReport(BuildContext context, String rawText) {
    final text = cleanExtractedText(rawText);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDE3F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.article_rounded,
                              color: primaryBlue, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text("Extracted Report",
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1A2236))),
                      ],
                    ),
                  ),
                  Divider(color: Colors.grey.withOpacity(0.12), height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: controller,
                      padding: const EdgeInsets.all(20),
                      child: _buildExtractedContent(text),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExtractedContent(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final colonIdx = line.indexOf(':');
        if (colonIdx > 0 && colonIdx < line.length - 1) {
          final key = line.substring(0, colonIdx).trim();
          final value = line.substring(colonIdx + 1).trim();
          return _ExtractedRow(label: key, value: value);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(line,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: const Color(0xFF4A5568),
                  height: 1.6)),
        );
      }).toList(),
    );
  }

  // =========================
  // UPLOAD
  // =========================
  Future<void> _upload(File file) async {
    final folders = await foldersRef.get();
    if (folders.docs.isEmpty) {
      _snack("Create a folder first");
      return;
    }
    if (selectedFolderId == null) {
      _snack("Select a folder first");
      return;
    }

    try {
      final imageUrl = await uploadToCloudinary(file);

      var request =
          http.MultipartRequest('POST', Uri.parse("$BASE_URL/extract"));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      var response = await request.send();
      var raw = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception("OCR failed: $raw");
      }

      String cleanedText = "";
      try {
        final jsonData = json.decode(raw);
        final extracted = jsonData['data'];

        String formatAny(dynamic data) {
          if (data is Map) {
            return data.entries.map((e) => "${e.key}: ${e.value}").join("\n");
          } else if (data is List) {
            return data.map((e) => formatAny(e)).join("\n\n");
          } else {
            return data.toString();
          }
        }

        cleanedText = formatAny(extracted);
      } catch (_) {
        cleanedText = raw;
      }

      final existing = await foldersRef
          .doc(selectedFolderId)
          .collection('reports')
          .get();
      final reportNumber = existing.docs.length + 1;

      await foldersRef.doc(selectedFolderId).collection('reports').add({
        'imageUrl': imageUrl,
        'data': cleanedText,
        'label': 'Report #$reportNumber',
        'timestamp': FieldValue.serverTimestamp(),
      });

      _snack("Report uploaded successfully", success: true);
    } catch (e) {
      _snack("Error: $e", success: false);
    }
  }

  // =========================
  // MED REMINDER BOTTOM SHEET
  // =========================
  void _showMedReminderSheet(
    BuildContext context, {
    required String reportId,
    required String rawText,
  }) {
    final meds = parseMedications(rawText);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MedReminderSheet(
        meds: meds,
        reportId: reportId,
        userId: user!.uid,
        foldersRef: foldersRef,
      ),
    );
  }

  // =========================
  // PDF SHARE (folder)
  // =========================
  Future<void> _shareFolderAsPdf(
      String folderName, List<QueryDocumentSnapshot> docs) async {
    try {
      _snack("Generating PDF…", success: true);
      final pdf = pw.Document();

      for (int i = 0; i < docs.length; i++) {
        final data = docs[i].data() as Map<String, dynamic>;
        final imageUrl = data['imageUrl'] as String?;
        final text = cleanExtractedText(data['data'] ?? "");

        pw.ImageProvider? pwImage;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          try {
            final resp = await http.get(Uri.parse(imageUrl));
            if (resp.statusCode == 200) {
              pwImage = pw.MemoryImage(resp.bodyBytes);
            }
          } catch (_) {}
        }

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (ctx) => [
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#2533AE'),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  "$folderName — Report ${i + 1}",
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 16),
              if (pwImage != null) ...[
                pw.Image(pwImage, height: 280, fit: pw.BoxFit.contain),
                pw.SizedBox(height: 16),
              ],
              pw.Divider(color: PdfColor.fromHex('#E2E8F0')),
              pw.SizedBox(height: 12),
              pw.Text("Extracted Information",
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#1A2236'))),
              pw.SizedBox(height: 8),
              ...text
                  .split('\n')
                  .where((l) => l.trim().isNotEmpty)
                  .map((line) {
                final colonIdx = line.indexOf(':');
                if (colonIdx > 0) {
                  final key = line.substring(0, colonIdx).trim();
                  final val = line.substring(colonIdx + 1).trim();
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: 130,
                          child: pw.Text(key,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11,
                                  color: PdfColor.fromHex('#2533AE'))),
                        ),
                        pw.Text(": ",
                            style: pw.TextStyle(
                                fontSize: 11,
                                color: PdfColor.fromHex('#8A97B8'))),
                        pw.Expanded(
                          child: pw.Text(val,
                              style: pw.TextStyle(
                                  fontSize: 11,
                                  color: PdfColor.fromHex('#4A5568'))),
                        ),
                      ],
                    ),
                  );
                }
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(line,
                      style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColor.fromHex('#4A5568'))),
                );
              }).toList(),
            ],
          ),
        );
      }

      final bytes = await pdf.save();
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/${folderName.replaceAll(' ', '_')}_reports.pdf');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: '$folderName — Medical Reports',
        text: 'Sharing $folderName medical reports',
      );
    } catch (e) {
      _snack("Failed to generate PDF: $e", success: false);
    }
  }

  // =========================
  // SINGLE REPORT PDF SHARE
  // =========================
  Future<void> _shareReportAsPdf(
      String reportLabel, String? imageUrl, String rawText) async {
    try {
      _snack("Generating PDF…", success: true);
      final text = cleanExtractedText(rawText);
      final pdf = pw.Document();

      pw.ImageProvider? pwImage;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final resp = await http.get(Uri.parse(imageUrl));
          if (resp.statusCode == 200) {
            pwImage = pw.MemoryImage(resp.bodyBytes);
          }
        } catch (_) {}
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (ctx) => [
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#2533AE'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Text(reportLabel,
                  style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 16),
            if (pwImage != null) ...[
              pw.Image(pwImage, height: 280, fit: pw.BoxFit.contain),
              pw.SizedBox(height: 16),
            ],
            pw.Divider(color: PdfColor.fromHex('#E2E8F0')),
            pw.SizedBox(height: 12),
            pw.Text("Extracted Information",
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#1A2236'))),
            pw.SizedBox(height: 8),
            ...text
                .split('\n')
                .where((l) => l.trim().isNotEmpty)
                .map((line) {
              final colonIdx = line.indexOf(':');
              if (colonIdx > 0) {
                final key = line.substring(0, colonIdx).trim();
                final val = line.substring(colonIdx + 1).trim();
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 130,
                        child: pw.Text(key,
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 11,
                                color: PdfColor.fromHex('#2533AE'))),
                      ),
                      pw.Text(": ",
                          style: pw.TextStyle(
                              fontSize: 11,
                              color: PdfColor.fromHex('#8A97B8'))),
                      pw.Expanded(
                        child: pw.Text(val,
                            style: pw.TextStyle(
                                fontSize: 11,
                                color: PdfColor.fromHex('#4A5568'))),
                      ),
                    ],
                  ),
                );
              }
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(line,
                    style: pw.TextStyle(
                        fontSize: 11, color: PdfColor.fromHex('#4A5568'))),
              );
            }).toList(),
          ],
        ),
      );

      final bytes = await pdf.save();
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/${reportLabel.replaceAll(' ', '_')}.pdf');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: reportLabel,
        text: 'Sharing medical report',
      );
    } catch (e) {
      _snack("Failed to generate PDF: $e", success: false);
    }
  }

  // =========================
  // FOLDER ACTIONS
  // =========================
  void _showFolderActions(String folderId, String folderName,
      List<QueryDocumentSnapshot> reports) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 4),
              Text(folderName,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: const Color(0xFF1A2236))),
              const SizedBox(height: 12),
              _actionTile(
                icon: Icons.edit_outlined,
                label: "Rename Folder",
                color: primaryBlue,
                onTap: () {
                  Navigator.pop(context);
                  _renameFolder(folderId, folderName);
                },
              ),
              _actionTile(
                icon: Icons.picture_as_pdf_outlined,
                label: "Share Folder as PDF",
                color: primaryBlue,
                onTap: () {
                  Navigator.pop(context);
                  _shareFolderAsPdf(folderName, reports);
                },
              ),
              _actionTile(
                icon: Icons.delete_outline,
                label: "Delete Folder",
                color: Colors.red.shade400,
                onTap: () async {
                  Navigator.pop(context);
                  final imageUrls = reports
                      .map((r) =>
                          (r.data() as Map<String, dynamic>)['imageUrl']
                              as String?)
                      .toList();
                  await deleteCloudinaryImages(imageUrls);
                  for (final report in reports) {
                    await _cleanupRemindersForReport(report.id);
                    await report.reference.delete();
                  }
                  await foldersRef.doc(folderId).delete();
                  if (selectedFolderId == folderId) {
                    setState(() => selectedFolderId = null);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================
  // MED REMINDER CLEANUP
  // =========================
  Future<void> _cleanupRemindersForReport(String reportId) async {
    final remindersDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('med_reminders')
        .doc(reportId);

    final snap = await remindersDoc.get();
    if (snap.exists) {
      final data = snap.data() as Map<String, dynamic>;
      final medTimesCounts = <String, int>{};
      data.forEach((medName, val) {
        final times = (val as Map<String, dynamic>)['times'] as List<dynamic>?;
        medTimesCounts[medName] = times?.length ?? 4;
      });
      await NotificationService()
          .cancelAllRemindersForReport(reportId, medTimesCounts);
      await remindersDoc.delete();
    }
  }

  // =========================
  // REPORT CARD ACTIONS
  // =========================
  void _showReportActions(
    BuildContext context, {
    required String reportId,
    required String folderId,
    required String reportLabel,
    required String? imageUrl,
    required String rawText,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 4),
              Text(reportLabel,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: const Color(0xFF1A2236))),
              const SizedBox(height: 12),
              _actionTile(
                icon: Icons.drive_file_rename_outline_rounded,
                label: "Rename Report",
                color: primaryBlue,
                onTap: () {
                  Navigator.pop(context);
                  _renameReport(reportId, folderId, reportLabel);
                },
              ),
              _actionTile(
                icon: Icons.picture_as_pdf_outlined,
                label: "Share as PDF",
                color: primaryBlue,
                onTap: () {
                  Navigator.pop(context);
                  _shareReportAsPdf(reportLabel, imageUrl, rawText);
                },
              ),
              _actionTile(
                icon: Icons.delete_outline,
                label: "Delete Report",
                color: Colors.red.shade400,
                onTap: () async {
                  Navigator.pop(context);
                  await deleteCloudinaryImages([imageUrl]);
                  await _cleanupRemindersForReport(reportId);
                  await foldersRef
                      .doc(folderId)
                      .collection('reports')
                      .doc(reportId)
                      .delete();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _renameReport(String reportId, String folderId, String currentLabel) {
    final controller = TextEditingController(text: currentLabel);
    showDialog(
      context: context,
      builder: (_) => _StyledDialog(
        title: "Rename Report",
        icon: Icons.drive_file_rename_outline_rounded,
        child: _StyledTextField(controller: controller, hint: "Report name"),
        actions: [
          _DialogCancelButton(onTap: () => Navigator.pop(context)),
          _DialogConfirmButton(
            label: "Save",
            onTap: () async {
              await foldersRef
                  .doc(folderId)
                  .collection('reports')
                  .doc(reportId)
                  .update({"label": controller.text.trim()});
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: GoogleFonts.poppins(
              color: color, fontWeight: FontWeight.w500, fontSize: 14)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  void _renameFolder(String folderId, String oldName) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (_) => _StyledDialog(
        title: "Rename Folder",
        icon: Icons.drive_file_rename_outline_rounded,
        child: _StyledTextField(controller: controller, hint: "Folder name"),
        actions: [
          _DialogCancelButton(onTap: () => Navigator.pop(context)),
          _DialogConfirmButton(
            label: "Save",
            onTap: () async {
              await foldersRef
                  .doc(folderId)
                  .update({"name": controller.text.trim()});
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // =========================
  // UPLOAD OPTIONS SHEET
  // =========================
  void _showUploadOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return StreamBuilder(
          stream: foldersRef.snapshots(),
          builder: (context, snapshot) {
            final hasFolders = (snapshot.data?.docs ?? []).isNotEmpty;
            final hasSelection = selectedFolderId != null;

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetHandle(),
                  if (!hasFolders) ...[
                    Text("No folders yet",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: const Color(0xFF1A2236))),
                    const SizedBox(height: 6),
                    Text("Create a folder first to upload reports",
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: const Color(0xFF8A97B8)),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    _actionTile(
                      icon: Icons.create_new_folder_outlined,
                      label: "Create Folder",
                      color: primaryBlue,
                      onTap: () {
                        Navigator.pop(context);
                        _createFolder();
                      },
                    ),
                  ] else if (!hasSelection) ...[
                    Text("Select a folder first",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: const Color(0xFF1A2236))),
                    const SizedBox(height: 6),
                    Text("Tap a folder above to select it, then upload",
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: const Color(0xFF8A97B8)),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    _actionTile(
                      icon: Icons.create_new_folder_outlined,
                      label: "Create New Folder",
                      color: primaryBlue,
                      onTap: () {
                        Navigator.pop(context);
                        _createFolder();
                      },
                    ),
                  ] else ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Add Your File",
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: const Color(0xFF1A2236))),
                    ),
                    const SizedBox(height: 12),
                    _actionTile(
                      icon: Icons.upload_file_outlined,
                      label: "Upload File",
                      color: primaryBlue,
                      onTap: () async {
                        Navigator.pop(context);
                        final file = await _pickFile();
                        if (file != null) _upload(file);
                      },
                    ),
                    _actionTile(
                      icon: Icons.camera_alt_outlined,
                      label: "Use Camera",
                      color: primaryBlue,
                      onTap: () async {
                        Navigator.pop(context);
                        final file = await _captureImage();
                        if (file != null) _upload(file);
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openImagePreview(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: InteractiveViewer(child: Image.network(url)),
          ),
        ),
      ),
    );
  }

  void _snack(String msg, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: success ? primaryBlue : Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _sheetHandle() {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFDDE3F0),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Center(child: Text("User not logged in"));
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              // ── HEADER ──────────────────────────────
              Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: primaryBlue,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: primaryBlue.withOpacity(0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: 43,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(Icons.folder_copy_rounded,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Medical Reports',
                                style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white)),
                            Text('Your documents & prescriptions',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.white70)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── SEARCH ──────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => searchQuery = v),
                    decoration: InputDecoration(
                      hintText: "Search reports...",
                      hintStyle: GoogleFonts.poppins(
                          color: const Color(0xFF8A97B8)),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFF8A97B8)),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),

              // ── FOLDERS ─────────────────────────────
              StreamBuilder(
                stream: foldersRef.snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  final folders = snapshot.data!.docs;
                  if (folders.isEmpty) return const SizedBox();

                  if (selectedFolderId != null) {
                    return SizedBox(
                      height: 52,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        itemCount: folders.length,
                        itemBuilder: (context, index) {
                          final f = folders[index];
                          return StreamBuilder(
                            stream: foldersRef
                                .doc(f.id)
                                .collection('reports')
                                .snapshots(),
                            builder: (context, snap) {
                              final count =
                                  snap.data?.docs.length ?? 0;
                              final isSelected =
                                  f.id == selectedFolderId;
                              return GestureDetector(
                                onTap: () => setState(() {
                                  selectedFolderId =
                                      isSelected ? null : f.id;
                                }),
                                onLongPress: () => _showFolderActions(
                                    f.id,
                                    f['name'],
                                    snap.data?.docs ?? []),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  margin:
                                      const EdgeInsets.only(right: 10),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    gradient: isSelected
                                        ? cardGradient
                                        : null,
                                    color: isSelected
                                        ? null
                                        : Colors.white
                                            .withOpacity(0.85),
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: primaryBlue
                                                  .withOpacity(0.3),
                                              blurRadius: 10,
                                              offset:
                                                  const Offset(0, 4),
                                            )
                                          ]
                                        : [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.05),
                                              blurRadius: 6,
                                              offset:
                                                  const Offset(0, 2),
                                            )
                                          ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.folder_rounded,
                                          size: 18,
                                          color: isSelected
                                              ? Colors.white
                                              : primaryBlue),
                                      const SizedBox(width: 6),
                                      Text(f['name'],
                                          style: GoogleFonts.poppins(
                                              color: isSelected
                                                  ? Colors.white
                                                  : const Color(
                                                      0xFF1A2236),
                                              fontSize: 12,
                                              fontWeight:
                                                  FontWeight.w500)),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.white
                                                  .withOpacity(0.2)
                                              : const Color(0xFFF0F4FF),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text("$count",
                                            style: GoogleFonts.poppins(
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color: isSelected
                                                    ? Colors.white
                                                    : primaryBlue)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: folders.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.8,
                      ),
                      itemBuilder: (context, index) {
                        final f = folders[index];
                        return StreamBuilder(
                          stream: foldersRef
                              .doc(f.id)
                              .collection('reports')
                              .snapshots(),
                          builder: (context, snap) {
                            final count = snap.data?.docs.length ?? 0;
                            final isSelected = f.id == selectedFolderId;
                            return GestureDetector(
                              onTap: () => setState(() {
                                selectedFolderId =
                                    isSelected ? null : f.id;
                              }),
                              onLongPress: () => _showFolderActions(
                                  f.id,
                                  f['name'],
                                  snap.data?.docs ?? []),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient:
                                      isSelected ? cardGradient : null,
                                  color: isSelected
                                      ? null
                                      : Colors.white.withOpacity(0.85),
                                  borderRadius:
                                      BorderRadius.circular(16),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: primaryBlue
                                                .withOpacity(0.3),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          )
                                        ]
                                      : [
                                          BoxShadow(
                                            color: Colors.black
                                                .withOpacity(0.05),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          )
                                        ],
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.folder_rounded,
                                        size: 18,
                                        color: isSelected
                                            ? Colors.white
                                            : primaryBlue),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(f['name'],
                                          style: GoogleFonts.poppins(
                                              color: isSelected
                                                  ? Colors.white
                                                  : const Color(
                                                      0xFF1A2236),
                                              fontSize: 12,
                                              fontWeight:
                                                  FontWeight.w500),
                                          overflow:
                                              TextOverflow.ellipsis),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white
                                                .withOpacity(0.2)
                                            : const Color(0xFFF0F4FF),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Text("$count",
                                          style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? Colors.white
                                                  : primaryBlue)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),

              // ── REPORTS LIST ────────────────────────
              Expanded(
                child: StreamBuilder(
                  stream: foldersRef.snapshots(),
                  builder: (context, folderSnap) {
                    final folders = folderSnap.data?.docs ?? [];
                    final query = searchQuery.trim().toLowerCase();

                    if (folders.isEmpty) {
                      return _emptyState(
                        icon: Icons.folder_open_rounded,
                        title: "No folders yet",
                        subtitle:
                            "Tap + to create your first folder and start uploading reports",
                      );
                    }

                    if (query.isNotEmpty) {
                      return StreamBuilder(
                        stream: Stream.fromFuture(
                          Future.wait(
                            folders.map((folder) async {
                              final snap = await foldersRef
                                  .doc(folder.id)
                                  .collection('reports')
                                  .orderBy('timestamp', descending: true)
                                  .get();
                              return snap.docs
                                  .map((doc) =>
                                      (folder: folder, doc: doc))
                                  .toList();
                            }),
                          ).then((lists) =>
                              lists.expand((e) => e).toList()),
                        ),
                        builder: (context, AsyncSnapshot snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator(
                                    color: primaryBlue));
                          }

                          final allResults =
                              (snapshot.data as List).where((item) {
                            final data = item.doc.data()
                                as Map<String, dynamic>;
                            final text = (data['data'] ?? "")
                                .toString()
                                .toLowerCase();
                            final label = (data['label'] ?? "")
                                .toString()
                                .toLowerCase();
                            return text.contains(query) ||
                                label.contains(query);
                          }).toList();

                          if (allResults.isEmpty) {
                            return _emptyState(
                              icon: Icons.search_off_rounded,
                              title: "No results found",
                              subtitle:
                                  'No reports matched "$searchQuery" across any folder',
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                                16, 4, 16, 100),
                            itemCount: allResults.length,
                            itemBuilder: (context, i) {
                              final item = allResults[i];
                              final data = item.doc.data()
                                  as Map<String, dynamic>;
                              final folderName =
                                  item.folder['name'] as String;
                              final label = data['label'] as String? ??
                                  "Report #${i + 1}";

                              return Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: 6, left: 4),
                                    child: Row(
                                      children: [
                                        const Icon(
                                            Icons.folder_rounded,
                                            size: 13,
                                            color: primaryBlue),
                                        const SizedBox(width: 5),
                                        Text(folderName,
                                            style: GoogleFonts.poppins(
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color: primaryBlue)),
                                      ],
                                    ),
                                  ),
                                  _ReportCard(
                                    imageUrl: data['imageUrl'],
                                    rawText: data['data'] ?? "",
                                    label: label,
                                    index: i + 1,
                                    reportId: item.doc.id,
                                    onTap: () => _openImagePreview(
                                        data['imageUrl']),
                                    onReadMore: (text) =>
                                        _showFullReport(context, text),
                                    onLongPress: () =>
                                        _showReportActions(
                                      context,
                                      reportId: item.doc.id,
                                      folderId: item.folder.id,
                                      reportLabel: label,
                                      imageUrl: data['imageUrl'],
                                      rawText: data['data'] ?? "",
                                    ),
                                    onShare: () => _shareReportAsPdf(
                                      label,
                                      data['imageUrl'],
                                      data['data'] ?? "",
                                    ),
                                    onSetReminder: () =>
                                        _showMedReminderSheet(
                                      context,
                                      reportId: item.doc.id,
                                      rawText: data['data'] ?? "",
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    }

                    if (selectedFolderId == null) {
                      return _emptyState(
                        icon: Icons.touch_app_rounded,
                        title: "Select a folder",
                        subtitle:
                            "Tap a folder above to view its reports",
                      );
                    }

                    return StreamBuilder(
                      stream: foldersRef
                          .doc(selectedFolderId)
                          .collection('reports')
                          .orderBy('timestamp', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: primaryBlue));
                        }

                        final docs = snapshot.data!.docs;

                        if (docs.isEmpty) {
                          return _emptyState(
                            icon: Icons.description_outlined,
                            title: "No reports yet",
                            subtitle:
                                "Upload your first report to this folder",
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              16, 4, 16, 100),
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final doc = docs[i];
                            final data =
                                doc.data() as Map<String, dynamic>;
                            final label = data['label'] as String? ??
                                "Report #${i + 1}";

                            return _ReportCard(
                              imageUrl: data['imageUrl'],
                              rawText: data['data'] ?? "",
                              label: label,
                              index: i + 1,
                              reportId: doc.id,
                              onTap: () =>
                                  _openImagePreview(data['imageUrl']),
                              onReadMore: (text) =>
                                  _showFullReport(context, text),
                              onLongPress: () => _showReportActions(
                                context,
                                reportId: doc.id,
                                folderId: selectedFolderId!,
                                reportLabel: label,
                                imageUrl: data['imageUrl'],
                                rawText: data['data'] ?? "",
                              ),
                              onShare: () => _shareReportAsPdf(
                                label,
                                data['imageUrl'],
                                data['data'] ?? "",
                              ),
                              onSetReminder: () =>
                                  _showMedReminderSheet(
                                context,
                                reportId: doc.id,
                                rawText: data['data'] ?? "",
                              ),
                            );
                          },
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

      // ── FAB ─────────────────────────────────────
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: cardGradient,
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: FloatingActionButton(
            onPressed: _showUploadOptions,
            backgroundColor: Colors.transparent,
            elevation: 0,
            shape: const CircleBorder(),
            child:
                const Icon(Icons.add_rounded, size: 28, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentBlue, size: 34),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: const Color(0xFF1A2236))),
            const SizedBox(height: 6),
            Text(subtitle,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: const Color(0xFF8A97B8)),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// =========================
// MED REMINDER BOTTOM SHEET
// =========================
class _MedReminderSheet extends StatefulWidget {
  final List<Map<String, String>> meds;
  final String reportId;
  final String userId;
  final CollectionReference foldersRef;

  const _MedReminderSheet({
    required this.meds,
    required this.reportId,
    required this.userId,
    required this.foldersRef,
  });

  @override
  State<_MedReminderSheet> createState() => _MedReminderSheetState();
}

class _MedReminderSheetState extends State<_MedReminderSheet> {
  static const Color primaryBlue = Color(0xFF2533AE);
  static const Color accentBlue = Color(0xFF6EA8FF);

  final Map<String, Map<String, dynamic>> _state = {};
  final Map<String, TextEditingController> _freqControllers = {};

  bool _saving = false;

  DocumentReference get _prefsDoc => FirebaseFirestore.instance
      .collection('users')
      .doc(widget.userId)
      .collection('med_reminders')
      .doc(widget.reportId);

  /// Reads the master "Medication Reminders" toggle from
  /// patients/{uid}/settings/preferences. Defaults to true when the doc
  /// doesn't exist yet so first-time users aren't silently blocked.
  Future<bool> _masterReminderEnabled() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.userId)
          .collection('settings')
          .doc('preferences')
          .get();
      if (!doc.exists) return true;
      return (doc.data() as Map<String, dynamic>)['medicationReminder']
              as bool? ??
          true;
    } catch (_) {
      return true; // fail open — don't silently block reminders
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFromFirestore();
  }

  Future<void> _loadFromFirestore() async {
    final doc = await _prefsDoc.get();
    final saved =
        doc.exists ? (doc.data() as Map<String, dynamic>) : <String, dynamic>{};

    final allMeds = List<Map<String, String>>.from(widget.meds);

    saved.forEach((name, val) {
      final alreadyListed = allMeds.any((m) => m['name'] == name);
      if (!alreadyListed) {
        allMeds.add({'name': name, 'frequency': val['frequency'] ?? ''});
      }
    });

    if (!mounted) return;
    setState(() {
      for (final med in allMeds) {
        final name = med['name']!;
        final savedEntry = saved[name] as Map<String, dynamic>?;
        final parsedFreq = med['frequency'] ?? '';
        final savedFreq = savedEntry?['frequency'] as String? ?? parsedFreq;

        final savedTimesRaw = savedEntry?['times'] as List<dynamic>?;
        final times = savedTimesRaw != null
            ? savedTimesRaw
                .map((t) => TimeOfDay(
                    hour: (t as Map<String, dynamic>)['hour'] as int,
                    minute: t['minute'] as int))
                .toList()
            : NotificationService.parseFrequency(savedFreq);

        _state[name] = {
          'enabled': savedEntry?['enabled'] as bool? ?? false,
          'frequency': savedFreq,
          'times': times,
        };
        _freqControllers[name] = TextEditingController(text: savedFreq);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      // Read the master toggle BEFORE scheduling anything.
      // If the user has turned off "Medication Reminders" in Settings,
      // we still save their per-med preferences (so they're restored when
      // they turn it back on) but we don't actually register any OS
      // notifications while the master switch is off.
      final masterEnabled = await _masterReminderEnabled();

      final batch = <String, dynamic>{};

      for (final entry in _state.entries) {
        final name = entry.key;
        final enabledByUser = entry.value['enabled'] as bool;
        final freq = _freqControllers[name]?.text.trim() ?? '';
        final times = (entry.value['times'] as List<TimeOfDay>?) ?? [];

        // Save the user's per-med choice as-is — don't let the master
        // toggle overwrite what they've set per medication.
        batch[name] = {
          'enabled': enabledByUser,
          'frequency': freq,
          'times': times
              .map((t) => {'hour': t.hour, 'minute': t.minute})
              .toList(),
        };

        final baseId =
            NotificationService.makeBaseId(widget.reportId, name);

        // Only schedule an OS notification when BOTH the master toggle
        // (Settings page) AND this specific medication are enabled.
        final shouldSchedule = enabledByUser && masterEnabled;

        if (shouldSchedule && times.isNotEmpty) {
          await NotificationService().scheduleMedReminders(
            notificationBaseId: baseId,
            medName: name,
            times: times,
          );
        } else {
          // Cancel any previously scheduled notifications for this med —
          // covers the case where the user had it on before and is now
          // toggling it off (or the master switch is off).
          await NotificationService().cancelMedReminders(baseId, 6);
        }
      }

      await _prefsDoc.set(batch);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              masterEnabled
                  ? "Reminders saved!"
                  : "Preferences saved. Enable Medication Reminders in Settings to activate them.",
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: primaryBlue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving: $e",
                style: GoogleFonts.poppins(color: Colors.white)),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addCustomMed() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.medication_rounded,
                  color: primaryBlue, size: 18),
            ),
            const SizedBox(width: 10),
            Text("Add Medication",
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: const Color(0xFF1A2236))),
          ],
        ),
        content: TextField(
          controller: nameCtrl,
          style: GoogleFonts.poppins(fontSize: 14),
          decoration: InputDecoration(
            hintText: "Medication name",
            hintStyle:
                GoogleFonts.poppins(color: const Color(0xFF8A97B8)),
            filled: true,
            fillColor: const Color(0xFFF0F4FF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel",
                style: GoogleFonts.poppins(
                    color: const Color(0xFF8A97B8))),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [accentBlue, primaryBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(context);
                setState(() {
                  _state[name] = {
                    'enabled': true,
                    'frequency': '',
                    'times': <TimeOfDay>[],
                  };
                  _freqControllers[name] = TextEditingController();
                });
              },
              child: Text("Add",
                  style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addTime(String name) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      final times =
          List<TimeOfDay>.from(_state[name]!['times'] as List<TimeOfDay>);
      times.add(picked);
      times.sort(
          (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
      _state[name]!['times'] = times;
    });
  }

  Future<void> _editTime(String name, int index) async {
    final times = _state[name]!['times'] as List<TimeOfDay>;
    final picked = await showTimePicker(
      context: context,
      initialTime: times[index],
    );
    if (picked == null) return;
    setState(() {
      final updated = List<TimeOfDay>.from(times);
      updated[index] = picked;
      updated.sort(
          (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
      _state[name]!['times'] = updated;
    });
  }

  void _removeTime(String name, int index) {
    setState(() {
      final updated =
          List<TimeOfDay>.from(_state[name]!['times'] as List<TimeOfDay>)
            ..removeAt(index);
      _state[name]!['times'] = updated;
    });
  }

  void _autoFillFromFrequency(String name) {
    final freq = _freqControllers[name]?.text.trim() ?? '';
    if (freq.isEmpty) return;
    setState(() {
      _state[name]!['times'] = NotificationService.parseFrequency(freq);
    });
  }

  @override
  void dispose() {
    for (final c in _freqControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keys = _state.keys.toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.45,
      expand: false,
      builder: (_, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE3F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [accentBlue, primaryBlue],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.medication_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Medication Reminders",
                              style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1A2236))),
                          Text("Set daily reminders for your medications",
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: const Color(0xFF8A97B8))),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _addCustomMed,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.add_rounded,
                            color: primaryBlue, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(color: Colors.grey.withOpacity(0.1), height: 1),

              Expanded(
                child: keys.isEmpty
                    ? _emptyMeds()
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: keys.length,
                        itemBuilder: (_, i) {
                          final name = keys[i];
                          return _MedTile(
                            medName: name,
                            enabled: _state[name]!['enabled'] as bool,
                            freqController: _freqControllers[name]!,
                            times: _state[name]!['times']
                                as List<TimeOfDay>,
                            onToggle: (val) => setState(
                                () => _state[name]!['enabled'] = val),
                            onFreqChanged: (_) => setState(() {}),
                            onAutoFillTimes: () =>
                                _autoFillFromFrequency(name),
                            onAddTime: () => _addTime(name),
                            onEditTime: (idx) => _editTime(name, idx),
                            onRemoveTime: (idx) =>
                                _removeTime(name, idx),
                          );
                        },
                      ),
              ),

              Padding(
                padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    MediaQuery.of(context).padding.bottom + 16),
                child: GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [accentBlue, primaryBlue],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: primaryBlue.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text("Save Reminders",
                                    style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15)),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyMeds() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFF0F4FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.medication_outlined,
                color: accentBlue, size: 30),
          ),
          const SizedBox(height: 14),
          Text("No medications detected",
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: const Color(0xFF1A2236))),
          const SizedBox(height: 6),
          Text("Tap + to add a medication manually",
              style: GoogleFonts.poppins(
                  fontSize: 12, color: const Color(0xFF8A97B8))),
        ],
      ),
    );
  }
}

// =========================
// MED TILE
// =========================
class _MedTile extends StatelessWidget {
  static const Color primaryBlue = Color(0xFF2533AE);
  static const Color accentBlue = Color(0xFF6EA8FF);

  final String medName;
  final bool enabled;
  final TextEditingController freqController;
  final List<TimeOfDay> times;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onFreqChanged;
  final VoidCallback onAutoFillTimes;
  final VoidCallback onAddTime;
  final ValueChanged<int> onEditTime;
  final ValueChanged<int> onRemoveTime;

  const _MedTile({
    required this.medName,
    required this.enabled,
    required this.freqController,
    required this.times,
    required this.onToggle,
    required this.onFreqChanged,
    required this.onAutoFillTimes,
    required this.onAddTime,
    required this.onEditTime,
    required this.onRemoveTime,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFF0F4FF) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: enabled
              ? primaryBlue.withOpacity(0.25)
              : const Color(0xFFE8EDF5),
          width: 1.2,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: primaryBlue.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: enabled
                        ? primaryBlue.withOpacity(0.1)
                        : const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.medication_rounded,
                    color:
                        enabled ? primaryBlue : const Color(0xFFB0BAD0),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    medName,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? const Color(0xFF1A2236)
                          : const Color(0xFF8A97B8),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: enabled,
                    onChanged: onToggle,
                    activeColor: primaryBlue,
                    activeTrackColor: accentBlue.withOpacity(0.4),
                    inactiveThumbColor: const Color(0xFFB0BAD0),
                    inactiveTrackColor: const Color(0xFFE8EDF5),
                  ),
                ),
              ],
            ),

            if (enabled) ...[
              const SizedBox(height: 12),
              Text("Frequency  (e.g. 1-1-1, twice, 3)",
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: const Color(0xFF8A97B8),
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: freqController,
                      onChanged: onFreqChanged,
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: const Color(0xFF1A2236)),
                      decoration: InputDecoration(
                        hintText: "e.g. 1-0-1  or  twice  or  2",
                        hintStyle: GoogleFonts.poppins(
                            color: const Color(0xFFB0BAD0), fontSize: 12),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: primaryBlue.withOpacity(0.15)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: primaryBlue, width: 1.5),
                        ),
                        prefixIcon: const Icon(Icons.schedule_rounded,
                            color: accentBlue, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onAutoFillTimes,
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: primaryBlue.withOpacity(0.15)),
                        ),
                        child: const Icon(Icons.auto_fix_high_rounded,
                            color: primaryBlue, size: 18),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Text("Reminder Times — tap to edit",
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: const Color(0xFF8A97B8),
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < times.length; i++)
                    _TimeChip(
                      time: times[i],
                      onTap: () => onEditTime(i),
                      onRemove: () => onRemoveTime(i),
                    ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onAddTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: primaryBlue.withOpacity(0.3),
                              style: BorderStyle.solid),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_rounded,
                                size: 14, color: primaryBlue),
                            const SizedBox(width: 4),
                            Text("Add time",
                                style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    color: primaryBlue,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              if (times.isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  "No reminder times set yet — tap \"Add time\" or use the wand to fill from frequency.",
                  style: GoogleFonts.poppins(
                      fontSize: 10.5, color: const Color(0xFFB0BAD0)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// =========================
// TIME CHIP
// =========================
class _TimeChip extends StatelessWidget {
  static const Color primaryBlue = Color(0xFF2533AE);

  final TimeOfDay time;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _TimeChip({
    required this.time,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primaryBlue.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.only(left: 12, right: 6, top: 7, bottom: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications_active_rounded,
                  size: 13, color: primaryBlue),
              const SizedBox(width: 6),
              Text(
                time.format(context),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded,
                      size: 14, color: primaryBlue.withOpacity(0.6)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================
// REPORT CARD
// =========================
class _ReportCard extends StatelessWidget {
  final String? imageUrl;
  final String rawText;
  final String label;
  final int index;
  final String reportId;
  final VoidCallback onTap;
  final Function(String) onReadMore;
  final VoidCallback onLongPress;
  final VoidCallback onShare;
  final VoidCallback onSetReminder;

  const _ReportCard({
    this.imageUrl,
    required this.rawText,
    required this.label,
    required this.index,
    required this.reportId,
    required this.onTap,
    required this.onReadMore,
    required this.onLongPress,
    required this.onShare,
    required this.onSetReminder,
  });

  @override
  Widget build(BuildContext context) {
    final cleanText = _ReportsScreenState.cleanExtractedText(rawText);

    final lines = cleanText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(5)
        .toList();

    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2533AE).withOpacity(0.07),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null)
              GestureDetector(
                onTap: onTap,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(22)),
                      child: Image.network(
                        imageUrl!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, prog) {
                          if (prog == null) return child;
                          return Container(
                            height: 180,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF0F4FF),
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(22)),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF2533AE),
                                  strokeWidth: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text("Expand",
                                style: TextStyle(
                                    color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.description_rounded,
                                size: 13, color: Color(0xFF2533AE)),
                            const SizedBox(width: 5),
                            Text(label,
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF2533AE))),
                          ],
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onShare,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.share_rounded,
                                  size: 13, color: Color(0xFF2533AE)),
                              const SizedBox(width: 5),
                              Text("Share PDF",
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF2533AE))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  ...lines.map((line) {
                    final colonIdx = line.indexOf(':');
                    if (colonIdx > 0 && colonIdx < line.length - 1) {
                      final key = line.substring(0, colonIdx).trim();
                      final val = line.substring(colonIdx + 1).trim();
                      return _CardKvRow(label: key, value: val);
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(line,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: const Color(0xFF4A5568),
                              height: 1.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    );
                  }),

                  const SizedBox(height: 10),
                  Divider(color: Colors.grey.withOpacity(0.1), height: 1),
                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => onReadMore(rawText),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6EA8FF), Color(0xFF2533AE)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.article_rounded,
                                  color: Colors.white, size: 13),
                              const SizedBox(width: 5),
                              Text("Full Report",
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),

                      GestureDetector(
                        onTap: onSetReminder,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: const Color(0xFF2533AE)
                                    .withOpacity(0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                  Icons.notifications_active_rounded,
                                  color: Color(0xFF2533AE),
                                  size: 13),
                              const SizedBox(width: 5),
                              Text("Reminders",
                                  style: GoogleFonts.poppins(
                                      color: const Color(0xFF2533AE),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Align(
                    alignment: Alignment.centerRight,
                    child: Text("Hold to manage",
                        style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: const Color(0xFFB0BAD0))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================
// KEY-VALUE ROW (card preview)
// =========================
class _CardKvRow extends StatelessWidget {
  final String label;
  final String value;
  const _CardKvRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 5, right: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF6EA8FF),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2533AE))),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: const Color(0xFF4A5568)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// =========================
// STYLED DIALOGS
// =========================
class _StyledDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;

  const _StyledDialog({
    required this.title,
    required this.icon,
    required this.child,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF2533AE), size: 20),
          ),
          const SizedBox(width: 12),
          Text(title,
              style: GoogleFonts.poppins(
                  color: const Color(0xFF1A2236),
                  fontWeight: FontWeight.w700,
                  fontSize: 17)),
        ],
      ),
      content: child,
      actions: actions,
    );
  }
}

class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _StyledTextField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: const Color(0xFF8A97B8)),
        filled: true,
        fillColor: const Color(0xFFF0F4FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _DialogCancelButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DialogCancelButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text("Cancel",
          style: GoogleFonts.poppins(color: const Color(0xFF8A97B8))),
    );
  }
}

class _DialogConfirmButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DialogConfirmButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6EA8FF), Color(0xFF2533AE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
        child:
            Text(label, style: GoogleFonts.poppins(color: Colors.white)),
      ),
    );
  }
}

// =========================
// EXTRACTED ROW WIDGET
// =========================
class _ExtractedRow extends StatelessWidget {
  final String label;
  final String value;
  const _ExtractedRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8FF), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2533AE))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: const Color(0xFF4A5568))),
          ),
        ],
      ),
    );
  }
}