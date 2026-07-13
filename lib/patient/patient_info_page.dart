import 'package:flutter/material.dart';
import 'package:flutter_fyp_application/main_scaffold.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PatientInfoPage extends StatefulWidget {
  const PatientInfoPage({super.key});

  @override
  State<PatientInfoPage> createState() => _PatientInfoPageState();
}

class _PatientInfoPageState extends State<PatientInfoPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController ageController = TextEditingController();
  final TextEditingController heightController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  

  String? gender;
  String? bloodType;
  String? chronicDisease;
  String? allergies;
  String? smoking;

  double? bmi;


  List<String> selectedChronicDisease = [];
  List<String> selectedAllergies = [];

  final Color primaryBlue = const Color(0xFF2533AE);

  @override
  void initState() {
    super.initState();

    heightController.addListener(_calculateBMI);
    weightController.addListener(_calculateBMI);
  }

  void _calculateBMI() {
  final height = double.tryParse(heightController.text);
  final weight = double.tryParse(weightController.text);

  if (height != null && weight != null && height > 0 && weight > 0) {
    final heightInMeters = height / 100;
    final calculatedBMI = weight / (heightInMeters * heightInMeters);

    setState(() {
      bmi = calculatedBMI;
    });
  } else {
    setState(() {
      bmi = null; //  reset if invalid
    });
  }
}

  /// Required + numeric + range check, so values like age 0, a negative
  /// height, or a height of 9999 can no longer pass validation just
  /// because the old check only confirmed the field wasn't empty.
  String? Function(String?) _rangeValidator(num min, num max) {
    return (value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return "Required field";
      final n = num.tryParse(trimmed);
      if (n == null) return "Enter a valid number";
      if (n < min || n > max) return "Should be $min–$max";
      return null;
    };
  }

  Future<void> _savePatientInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('patients')
        .doc(user.uid)
        .set({
      "name": nameController.text.trim(),
      "age": int.tryParse(ageController.text.trim()),
      "height": heightController.text.trim(),
      "weight": weightController.text.trim(),
      "bmi": bmi,
      "gender": gender,
      "bloodType": bloodType,
      "chronicDisease": selectedChronicDisease,
      "allergies": selectedAllergies,
      "smoking": smoking,
      "email": user.email,
      "createdAt": FieldValue.serverTimestamp(),
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainScaffold()),
    );
  }

  InputDecoration _inputStyle(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 13),
    prefixIcon: Icon(icon, color: primaryBlue),

    filled: true,
    fillColor: Colors.white.withOpacity(0.95), // ✅ back to clean white

    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: primaryBlue.withOpacity(0.25),
        width: 1.2,
      ),
    ),

    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: primaryBlue,
        width: 1.6,
      ),
    ),

    contentPadding:
        const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        child: SafeArea(
          child: Column(
            children: [

             

              /// HEADER
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: Column(
                  children: [
                    Text(
                      "Patient Information",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Help us personalize your healthcare experience",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),

              /// FORM
              Expanded(
                child: SingleChildScrollView(
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
                        children: [

                          _buildTextField(nameController, "Full Name", Icons.badge_outlined),

                          _buildTextField(ageController, "Age", Icons.event_outlined, TextInputType.number, _rangeValidator(1, 120)),

                          _buildTextField(heightController, "Height (cm)", Icons.height, TextInputType.number, _rangeValidator(30, 250)),

                          _buildTextField(weightController, "Weight (kg)", Icons.monitor_weight_outlined, TextInputType.number, _rangeValidator(2, 300)),

                          /// BMI DISPLAY
                          Container(
  margin: const EdgeInsets.only(bottom: 18),
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: primaryBlue.withOpacity(0.2)),
  ),
  child: Row(
    children: [
      
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          bmi == null
              ? "Enter height & weight to calculate BMI"
              : "BMI: ${bmi!.toStringAsFixed(1)}",
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.black.withOpacity(0.6),
          ),
        ),
      ),
    ],
  ),
),


                          _buildDropdown(
  "Gender",
  gender,
  ["Male", "Female", "Other"],
  (val) => setState(() => gender = val),
  Icons.wc_outlined,
),

_buildDropdown(
  "Blood Type",
  bloodType,
  ["A+","A-","B+","B-","AB+","AB-","O+","O-"],
  (val) => setState(() => bloodType = val),
  Icons.bloodtype_outlined,
),

_buildMultiSelect(
  "Chronic Disease",
  Icons.health_and_safety_outlined,
  ["Diabetes", "Hypertension", "Heart Disease", "Obesity", "None"],
  selectedChronicDisease,
),

_buildMultiSelect(
  "Allergies",
  Icons.warning_amber_outlined,
  ["Gluten Intolerance", "Lactose Intolerance", "Nut Allergy", "None"],
  selectedAllergies,
),

_buildRadioGroup(
  "Smoking Habit",
  Icons.smoke_free_outlined,
  ["Yes", "No"],
  smoking,
  (val) => setState(() => smoking = val),
),




                          const SizedBox(height: 25),

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
                              onPressed: () {
                                if (_formKey.currentState!.validate()) {
                                  _savePatientInfo();
                                }
                              },
                              child: const Text(
                                "Save & Continue",
                                style: TextStyle(
                                  fontSize: 16,
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

  Widget _buildTextField(TextEditingController controller, String label, IconData icon,
      [TextInputType type = TextInputType.text, String? Function(String?)? validator]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        style: const TextStyle(fontSize: 13),
        controller: controller,
        keyboardType: type,
        validator: validator ??
            (value) =>
                value == null || value.isEmpty ? "Required field" : null,
        decoration: _inputStyle(label, icon),
      ),
    );
  }

  Widget _buildDropdown(
  String label,
  String? value,
  List<String> items,
  ValueChanged<String?> onChanged,
  IconData icon, // ✅ NEW
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: DropdownButtonFormField<String>(
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(16),

      icon: Icon(Icons.expand_more_rounded, color: primaryBlue), // ✅ nicer arrow
      style: const TextStyle(fontSize: 13, color: Colors.black87),
      value: value,
      items: items
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e, style: TextStyle(color: primaryBlue)),
              ))
          .toList(),
      onChanged: onChanged,
      validator: (value) =>
          value == null ? "Required field" : null,

      decoration: _inputStyle(label, icon), // ✅ dynamic icon
    ),
  );
}
Widget _buildMultiSelect(
  String label,
  IconData icon,
  List<String> options,
  List<String> selectedList,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: primaryBlue),

Text(
  label,
  style: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: primaryBlue,
  ),
),
          ],
        ),
        const SizedBox(height: 10),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((item) {
            final isSelected = selectedList.contains(item);

            return GestureDetector(
              onTap: () {
                setState(() {
                  if (item == "None") {
                    selectedList.clear();
                    selectedList.add(item);
                  } else {
                    selectedList.remove("None");

                    if (isSelected) {
                      selectedList.remove(item);
                    } else {
                      selectedList.add(item);
                    }
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF2533AE)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
  color: primaryBlue.withOpacity(0.25),
),
                ),
                child: Text(
                  item,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? Colors.white : Colors.black87,
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

Widget _buildRadioGroup(
  String label,
  IconData icon,
  List<String> options,
  String? groupValue,
  ValueChanged<String?> onChanged,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: primaryBlue),
            const SizedBox(width: 8),
            Text(label,
            
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: primaryBlue,
                )),
          ],
        ),
        const SizedBox(height: 10),

        Row(
          children: options.map((option) {
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(option),
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: groupValue == option
                          ? primaryBlue
                          : primaryBlue.withOpacity(0.25),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: groupValue == option
                        ? primaryBlue.withOpacity(0.1)
                        : Colors.white,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        groupValue == option
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                        color: const Color(0xFF2533AE),
                      ),
                      const SizedBox(width: 6),
                      Text(option),
                    ],
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

}