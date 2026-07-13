import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../utils/cloudinary_cleanup.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final user = FirebaseAuth.instance.currentUser;

  final Color primaryBlue = const Color(0xFF2533AE);

  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  bool isEditing = false;
  bool isLoaded = false;

  Map<String, dynamic> data = {};

  // Fetched once and cached here instead of being called inline inside
  // FutureBuilder's `future:` parameter — previously every setState() in
  // this screen (toggling edit mode, saving) created a *new* Future each
  // build, which FutureBuilder treated as a fresh request and re-read
  // from Firestore every time.
  late Future<DocumentSnapshot<Map<String, dynamic>>> _userDataFuture;

  @override
  void initState() {
    super.initState();
    _userDataFuture = _getUserData();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getUserData() {
    return FirebaseFirestore.instance
        .collection('patients')
        .doc(user!.uid)
        .get();
  }

  /// Pull-to-refresh handler. Unlike the initial load, this deliberately
  /// re-reads from Firestore and overwrites the local `data` map, so it's
  /// the one place a stale screen (e.g. left open while something else
  /// updated this profile) can be brought back up to date without
  /// navigating away and back.
  ///
  /// Refused while isEditing — overwriting `data` mid-edit would silently
  /// discard whatever the user has typed but not yet saved.
  Future<void> _refreshProfile() async {
    if (isEditing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Finish or cancel editing before refreshing"),
        ),
      );
      return;
    }
    try {
      final snapshot = await _getUserData();
      if (!mounted) return;
      if (snapshot.exists) {
        setState(() => data = snapshot.data()!);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't refresh. Check your connection."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _updateProfile() async {
    await FirebaseFirestore.instance
        .collection('patients')
        .doc(user!.uid)
        .update(data);
  }


  Future<String?> uploadToCloudinary(File file) async {
  const cloudName = "dp1ciw5d9";
  const uploadPreset = "profile_upload"; // 👈 your new preset

  final url = Uri.parse(
    "https://api.cloudinary.com/v1_1/$cloudName/image/upload",
  );

  final request = http.MultipartRequest("POST", url);
  request.fields['upload_preset'] = uploadPreset;

  request.files.add(
    await http.MultipartFile.fromPath("file", file.path),
  );

  final response = await request.send();
  final res = await response.stream.bytesToString();

  final jsonData = json.decode(res);
  return jsonData["secure_url"];
}


  Future<void> pickProfileImage() async {
  final XFile? image =
      await _picker.pickImage(source: ImageSource.gallery);

  if (image != null) {
    final oldImageUrl = data['profileImage'] as String?;

    final url = await uploadToCloudinary(File(image.path));

    if (url == null) return;

    await FirebaseFirestore.instance
        .collection('patients')
        .doc(user!.uid)
        .update({
      'profileImage': url,
    });

    setState(() {
      data['profileImage'] = url;
    });

    // Clean up the old photo now that the new one is safely saved —
    // otherwise every replacement leaves the previous image orphaned
    // in Cloudinary forever.
    if (oldImageUrl != null) {
      await deleteCloudinaryImages([oldImageUrl]);
    }
  }
}



  Future<void> removeProfileImage() async {
  final oldImageUrl = data['profileImage'] as String?;

  await FirebaseFirestore.instance
      .collection('patients')
      .doc(user!.uid)
      .update({
    'profileImage': FieldValue.delete(),
  });

  setState(() {
    data['profileImage'] = null;
  });

  if (oldImageUrl != null) {
    await deleteCloudinaryImages([oldImageUrl]);
  }
}



  void _showProfileOptions() {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            /// PICK IMAGE
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text("Choose from Gallery"),
              onTap: () {
                Navigator.pop(context);
                pickProfileImage();
              },
            ),

            /// REMOVE IMAGE (only if exists)
            if (data['profileImage'] != null &&
                data['profileImage'].toString().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  "Remove Profile Picture",
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  removeProfileImage();
                },
              ),
          ],
        ),
      );
    },
  );
}

  /// 🔵 CARD DESIGN (aligned with info page aesthetics)
  Widget _card(String title, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryBlue.withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: primaryBlue.withOpacity(0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  /// Recomputes BMI from whatever height/weight are currently in `data`
  /// and stores it back into `data['bmi']`. Without this, editing height
  /// or weight here updated those two fields but left the stored `bmi`
  /// frozen at whatever it was when patient_info_page.dart first
  /// calculated it — so the BMI gauge on the dashboard would keep
  /// showing a stale number that no longer matched the patient's actual
  /// current height/weight after a profile edit.
  void _recalculateBmi() {
    final height = double.tryParse((data['height'] ?? '').toString());
    final weight = double.tryParse((data['weight'] ?? '').toString());
    if (height != null && weight != null && height > 0 && weight > 0) {
      final heightInMeters = height / 100;
      setState(() {
        data['bmi'] = weight / (heightInMeters * heightInMeters);
      });
    }
  }

  /// Required + numeric + range check for the editable age/height/weight
  /// fields — previously these had no validation at all, so any text
  /// (including empty strings) saved straight to Firestore.
  String? Function(String?) _rangeValidator(num min, num max) {
    return (value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return "Required";
      final n = num.tryParse(trimmed);
      if (n == null) return "Enter a valid number";
      if (n < min || n > max) return "Should be $min–$max";
      return null;
    };
  }

  /// 🔵 INPUT STYLE (aligned with info page)
  InputDecoration _inputStyle() {
    final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(
      color: primaryBlue.withOpacity(0.25),
      width: 1.2,
    ),
  );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      enabledBorder: border,
    disabledBorder: border,
      
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: primaryBlue,
          width: 1.5,
        ),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  /// A read-only value box styled to exactly match the bordered
  /// TextFormField boxes above it (same border, radius, fill, and
  /// padding as _inputStyle()) — used for BMI, which is computed, not
  /// typed, but should still look like it belongs on the same page
  /// instead of floating as a bare, narrower line of text.
  Widget _readOnlyValueBox(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryBlue.withOpacity(0.25),
          width: 1.2,
        ),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: Colors.black.withOpacity(0.6),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF4FF),

      /// 🔵 CLEAN APP BAR (NO ICON CLUTTER)
      appBar: AppBar(
        iconTheme: const IconThemeData(
          color: Colors.white,),
  title: Text(
    "Medical Profile",
    style: TextStyle(
      color: Colors.white.withOpacity(0.95),
      fontWeight: FontWeight.w600,
    ),
  ),
  backgroundColor: primaryBlue,
  elevation: 0,
  centerTitle: false,

  actions: [
    IconButton(
      icon: Icon(
        isEditing ? Icons.close_rounded : Icons.edit_rounded,
        color: Colors.white,
      ),
      onPressed: () {
        setState(() {
          isEditing = !isEditing;
        });
      },
    ),
  ],
),

      body: FutureBuilder(
        future: _userDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("No profile data"));
          }

          if (!isLoaded) {
            data = snapshot.data!.data()!;
            isLoaded = true;
          }

          return RefreshIndicator(
            color: primaryBlue,
            onRefresh: _refreshProfile,
            child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
              children: [

                /// 🔵 HEADER (SOFTER + MORE MODERN)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryBlue,
                        const Color(0xFF4A6CF7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    children: [
                    GestureDetector(
  onTap: isEditing ? _showProfileOptions : null,
  child: CircleAvatar(
    radius: 35,
    backgroundColor: Colors.white,
    backgroundImage: (data['profileImage'] != null &&
            data['profileImage'].toString().isNotEmpty)
        ? NetworkImage(data['profileImage'])
        : null,
    child: (data['profileImage'] == null ||
            data['profileImage'].toString().isEmpty)
        ? Text(
            (data['name'] ?? "U")[0].toUpperCase(),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: primaryBlue,
            ),
          )
        : null,
  ),
),
                      const SizedBox(height: 10),
                      Text(
                        data['name'] ?? "",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        data['email'] ?? "",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                /// 🔵 SECTION TITLE (FIXED COLOR HIERARCHY)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Health Information",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                _card(
                  "Age",
                  TextFormField(
                    initialValue: data['age']?.toString() ?? "",
                    enabled: isEditing,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
    color: Colors.black.withOpacity(0.6),
    fontWeight: FontWeight.w500,
  ),
                    // Parsed to an int before storing — previously this
                    // saved the raw string, which meant `age` flipped
                    // between int (from patient_info_page) and String
                    // (from here) depending on which screen last edited
                    // it. Firestore queries/sorts on a mixed-type field
                    // behave unpredictably, so keep the type consistent.
                    onChanged: (v) => data['age'] = int.tryParse(v.trim()),
                    validator: _rangeValidator(1, 120),
                    decoration: _inputStyle(),
                  ),
                ),

                _card(
                  "Height (cm)",
                  TextFormField(
                    initialValue: data['height'] ?? "",
                    enabled: isEditing,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
    color: Colors.black.withOpacity(0.6),
    fontWeight: FontWeight.w500,
  ),
                    onChanged: (v) {
                      data['height'] = v;
                      _recalculateBmi();
                    },
                    validator: _rangeValidator(30, 250),
                    decoration: _inputStyle(),
                  ),
                ),

                _card(
                  "Weight (kg)",
                  TextFormField(
                    initialValue: data['weight'] ?? "",
                    enabled: isEditing,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
    color: Colors.black.withOpacity(0.6),
    fontWeight: FontWeight.w500,
  ),
                    onChanged: (v) {
                      data['weight'] = v;
                      _recalculateBmi();
                    },
                    validator: _rangeValidator(2, 300),
                    decoration: _inputStyle(),
                  ),
                ),

                if (data['bmi'] != null)
                  _card(
                    "BMI",
                    _readOnlyValueBox((data['bmi'] as num).toStringAsFixed(1)),
                  ),

                _card(
                  "Gender",
                  DropdownButtonFormField(
                    value: data['gender'],
                    decoration: _inputStyle(),
                    dropdownColor: Colors.white,
                    items: ["Male", "Female", "Other"]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e, style: TextStyle(color: Colors.black.withOpacity(0.7)))))
                        .toList(),
                    onChanged: isEditing
                        ? (v) => setState(() => data['gender'] = v)
                        : null,
                  ),
                ),

                _card(
                  "Blood Type",
                  DropdownButtonFormField(
                    value: data['bloodType'],
                    decoration: _inputStyle(),
                    dropdownColor: Colors.white,
                    items: ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e, style: TextStyle(color: Colors.black.withOpacity(0.7)))))
                        .toList(),
                    onChanged: isEditing
                        ? (v) => setState(() => data['bloodType'] = v)
                        : null,
                  ),
                ),

                /// 🔵 CHRONIC DISEASE (RESTORED + IMPROVED UI)
                _card(
                  "Chronic Conditions",
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var item in [
                        "Diabetes",
                        "Hypertension",
                        "Heart Disease",
                        "Obesity",
                        "None"
                      ])
                        ChoiceChip(
                          label: Text(item),
                          selected:
                              (data['chronicDisease'] ?? []).contains(item),
                          selectedColor: primaryBlue,
                          backgroundColor: Colors.white,
                          disabledColor: Colors.white,
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                              color: primaryBlue.withOpacity(0.25),
                          ),
                          ),
                          labelStyle: TextStyle(
                            color: (data['chronicDisease'] ?? [])
                                    .contains(item)
                                ? Colors.white
                                : Colors.black.withOpacity(0.6),
                          ),
                          onSelected: (val) {
  if (!isEditing) return;

  setState(() {
    List list = List.from(data['chronicDisease'] ?? []);
    val ? list.add(item) : list.remove(item);
    data['chronicDisease'] = list;
  });
},
                               
                             
                        )
                    ],
                  ),
                ),

                /// 🔵 ALLERGIES (RESTORED + IMPROVED UI)
                _card(
                  "Allergies",
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var item in [
                        "Gluten",
                        "Lactose",
                        "Nut Allergy",
                        "None"
                      ])
                        ChoiceChip(
                          label: Text(item),
                          selected: (data['allergies'] ?? []).contains(item),
                          selectedColor: primaryBlue,
                          backgroundColor: Colors.white,
                          disabledColor: Colors.white,
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: primaryBlue.withOpacity(0.25),
                            ),
                          ),
                          labelStyle: TextStyle(
                            color: (data['allergies'] ?? []).contains(item)
                                ? Colors.white
                                : Colors.black.withOpacity(0.6),
                          ),
                          onSelected: (val) {
  if (!isEditing) return;

  setState(() {
    List list = List.from(data['allergies'] ?? []);
    val ? list.add(item) : list.remove(item);
    data['allergies'] = list;
  });
},
                             
                        )
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                /// 🔵 SAVE BUTTON ONLY (NO LOGOUT HERE)
                if (isEditing)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;
                        try {
                          await _updateProfile();
                          if (!mounted) return;
                          setState(() => isEditing = false);
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                  "Couldn't save changes. Check your connection and try again."),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      },
                      child: const Text(
                        "Save Changes",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
              ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }
}