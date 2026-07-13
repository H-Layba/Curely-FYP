import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String _groqApiKey =
    'YOUR_GROQ_API_KEY_HERE';
const String _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
const String _backendUrl =
    'https://diet-recommendation-x0yg.onrender.com/predict';

const Color _primaryBlue = Color(0xFF2533AE);

class MealNutrition {
  final double calories, protein, fat, carbs;
  final String summary;
  MealNutrition({
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.summary,
  });
}

class RecommendedNutrition {
  final double calories, protein, carbs, fat;
  RecommendedNutrition({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

class DietScreen extends StatefulWidget {
  const DietScreen({super.key});

  @override
  State<DietScreen> createState() => _DietScreenState();
}

class _DietScreenState extends State<DietScreen> {
  int _step = 0;

  final Map<String, MealNutrition?> _meals = {
    'Breakfast': null,
    'Lunch': null,
    'Dinner': null,
  };
  int _currentMealIndex = 0;
  final List<String> _mealOrder = ['Breakfast', 'Lunch', 'Dinner'];

  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMsg> _chatMessages = [];
  bool _isAnalyzing = false;

  final TextEditingController _bpSysCtrl = TextEditingController();
  final TextEditingController _bpDiaCtrl = TextEditingController();
  final TextEditingController _bloodSugarCtrl = TextEditingController();

  // Profile data loaded from Firestore
  Map<String, dynamic> _profile = {};
  bool _profileLoaded = false;
  bool _isDiabetic = false;
  bool _isHighBP = false;

  RecommendedNutrition? _recommended;
  String _foodRecommendations = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfileThenStart();
  }

  // ─── Load profile first, then start chat ─────────────────────────────────

  Future<void> _loadProfileThenStart() async {
    final user = FirebaseAuth.instance.currentUser;
    final doc = await FirebaseFirestore.instance
        .collection('patients')
        .doc(user!.uid)
        .get();

    if (doc.exists) {
      _profile = doc.data()!;
      final chronicList = List<String>.from(_profile['chronicDisease'] ?? []);
      _isDiabetic = chronicList.contains('Diabetes');
      _isHighBP =
          chronicList.contains('Hypertension') ||
          chronicList.contains('Heart Disease');
    }

    setState(() => _profileLoaded = true);

    _chatMessages.add(
      _ChatMsg(
        text:
            "Hi! Let's track your meals from yesterday 🍽️\n\nWhat did you have for Breakfast yesterday? You can type in English, Urdu, or Roman Urdu.",
        isBot: true,
      ),
    );
  }

  // ─── Groq: analyze meal ───────────────────────────────────────────────────

  Future<MealNutrition?> _analyzeMeal(String mealName, String userInput) async {
    final prompt =
        '''You are a Pakistani nutrition assistant. The user will describe what they had for $mealName yesterday in English, Urdu, or Roman Urdu.

Identify each food item and estimate its nutritional values based on typical Pakistani serving sizes.

User said: "$userInput"

Respond in this format exactly (no extra text):
$mealName Summary:
- [Food Item] x[quantity]: Calories: [x]kcal, Protein: [x]g, Fat: [x]g, Carbs: [x]g
Total: Calories: [x]kcal, Protein: [x]g | Fat: [x]g | Carbs: [x]g

Only return the above format. Be concise.''';

    final response = await http.post(
      Uri.parse(_groqUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_groqApiKey',
      },
      body: jsonEncode({
        'model': 'llama-3.3-70b-versatile',
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'max_tokens': 512,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final text = data['choices'][0]['message']['content'] as String;
      return _parseMealNutrition(text);
    }
    return null;
  }

  MealNutrition _parseMealNutrition(String text) {
    final regex = RegExp(
      r'Total:.*?Calories:\s*([\d.]+)\s*kcal.*?Protein:\s*([\d.]+)g.*?Fat:\s*([\d.]+)g.*?Carbs:\s*([\d.]+)g',
      caseSensitive: false,
    );
    final match = regex.firstMatch(text);
    return MealNutrition(
      calories: match != null ? double.tryParse(match.group(1)!) ?? 0 : 0,
      protein: match != null ? double.tryParse(match.group(2)!) ?? 0 : 0,
      fat: match != null ? double.tryParse(match.group(3)!) ?? 0 : 0,
      carbs: match != null ? double.tryParse(match.group(4)!) ?? 0 : 0,
      summary: text,
    );
  }

  // ─── Handle chat send ─────────────────────────────────────────────────────

  Future<void> _handleChatSend() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isAnalyzing) return;

    final currentMeal = _mealOrder[_currentMealIndex];

    setState(() {
      _chatMessages.add(_ChatMsg(text: text, isBot: false));
      _chatController.clear();
      _isAnalyzing = true;
    });
    _scrollToBottom();

    setState(() {
      _chatMessages.add(
        _ChatMsg(
          text: 'Analyzing your $currentMeal...',
          isBot: true,
          isTyping: true,
        ),
      );
    });

    final nutrition = await _analyzeMeal(currentMeal, text);

    setState(() {
      _chatMessages.removeLast();
      if (nutrition != null) {
        _meals[currentMeal] = nutrition;
        _chatMessages.add(_ChatMsg(text: nutrition.summary, isBot: true));
      } else {
        _chatMessages.add(
          _ChatMsg(
            text: 'Sorry, I could not analyze that. Please try again.',
            isBot: true,
          ),
        );
        _isAnalyzing = false;
        return;
      }
    });

    _currentMealIndex++;

    if (_currentMealIndex < _mealOrder.length) {
      final nextMeal = _mealOrder[_currentMealIndex];
      setState(() {
        _chatMessages.add(
          _ChatMsg(
            text: "Got it! Now, what did you have for $nextMeal yesterday?",
            isBot: true,
          ),
        );
        _isAnalyzing = false;
      });
    } else {
      final total = _getDayTotal();
      setState(() {
        _chatMessages.add(
          _ChatMsg(
            text:
                "Great! Here's yesterday's total:\n\nCalories: ${total['calories']!.toStringAsFixed(0)} kcal\nProtein: ${total['protein']!.toStringAsFixed(1)}g\nFat: ${total['fat']!.toStringAsFixed(1)}g\nCarbs: ${total['carbs']!.toStringAsFixed(1)}g\n\nNow let's calculate your recommended nutrition for today. Tap 'Continue' below.",
            isBot: true,
          ),
        );
        _isAnalyzing = false;
      });
    }

    _scrollToBottom();
  }

  Map<String, double> _getDayTotal() {
    double cal = 0, pro = 0, fat = 0, carb = 0;
    for (final m in _meals.values) {
      if (m != null) {
        cal += m.calories;
        pro += m.protein;
        fat += m.fat;
        carb += m.carbs;
      }
    }
    return {'calories': cal, 'protein': pro, 'fat': fat, 'carbs': carb};
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── Run prediction ───────────────────────────────────────────────────────

  Future<void> _runPrediction() async {
    setState(() => _isLoading = true);

    try {
      final total = _getDayTotal();

      final age = int.tryParse(_profile['age']?.toString() ?? '0') ?? 0;
      final height = int.tryParse(_profile['height']?.toString() ?? '0') ?? 0;
      final weight = int.tryParse(_profile['weight']?.toString() ?? '0') ?? 0;
      final bmi = height > 0
          ? double.parse(
              (weight / ((height / 100) * (height / 100))).toStringAsFixed(2),
            )
          : 0.0;

      final allergiesList = List<String>.from(_profile['allergies'] ?? []);
      String allergy = 'None';
      if (allergiesList.contains('Gluten'))
        allergy = 'Gluten Intolerance';
      else if (allergiesList.contains('Lactose'))
        allergy = 'Lactose Intolerance';
      else if (allergiesList.contains('Nut Allergy'))
        allergy = 'Nut Allergy';

      final chronicList = List<String>.from(_profile['chronicDisease'] ?? []);
      final chronic = chronicList.isNotEmpty && chronicList.first != 'None'
          ? chronicList.first
          : null;

      // smoking from firestore
      final smoking = _profile['smokingHabit'] ?? 'No';

      final payload = {
        'Age': age,
        'Gender': _profile['gender'] ?? 'Male',
        'Height_cm': height,
        'Weight_kg': weight,
        'BMI': bmi,
        'Chronic_Disease': chronic,
        'Blood_Pressure_Systolic': int.tryParse(_bpSysCtrl.text) ?? 120,
        'Blood_Pressure_Diastolic': int.tryParse(_bpDiaCtrl.text) ?? 80,
        'Blood_Sugar_Level': int.tryParse(_bloodSugarCtrl.text) ?? 100,
        'Allergies': allergy,
        'Smoking_Habit': smoking,
        'Caloric_Intake': total['calories']!.toInt(),
        'Protein_Intake': total['protein']!.toInt(),
        'Carbohydrate_Intake': total['carbs']!.toInt(),
        'Fat_Intake': total['fat']!.toInt(),
      };

      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        _recommended = RecommendedNutrition(
          calories: (result['Recommended_Calories'] ?? 0).toDouble(),
          protein: (result['Recommended_Protein'] ?? 0).toDouble(),
          carbs: (result['Recommended_Carbs'] ?? 0).toDouble(),
          fat: (result['Recommended_Fat'] ?? 0).toDouble(),
        );

        await _getFoodRecommendations(_recommended!, allergy, chronic, smoking);

        setState(() {
          _step = 2;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        _showSnack('Prediction failed: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Error: $e');
    }
  }

  Future<void> _getFoodRecommendations(
    RecommendedNutrition rec,
    String allergy,
    String? chronic,
    String smoking,
  ) async {
    // Build a detailed health context so Groq gives safe recommendations
    final List<String> restrictions = [];
    if (_isDiabetic) {
      restrictions.add(
        'Patient has Diabetes — avoid high glycemic index foods, refined sugars, white rice in large quantities, sugary drinks, sweets like mithai and halwa. Prefer whole grains, daal, sabzi, boiled eggs.',
      );
    }
    if (_isHighBP) {
      restrictions.add(
        'Patient has Hypertension/Heart Disease — avoid high sodium foods, fried foods, pickles (achar), papad, salty snacks. Prefer low-salt cooking, grilled or boiled proteins, fruits and vegetables.',
      );
    }
    if (chronic != null &&
        !_isDiabetic &&
        chronic != 'Hypertension' &&
        chronic != 'Heart Disease') {
      restrictions.add('Patient has $chronic — recommend accordingly.');
    }
    if (allergy != 'None') {
      restrictions.add('Patient has $allergy — strictly avoid related foods.');
    }
    if (smoking == 'Yes') {
      restrictions.add(
        'Patient smokes — recommend antioxidant-rich foods like fruits, vegetables, green tea.',
      );
    }

    final bpSys = int.tryParse(_bpSysCtrl.text) ?? 0;
    final bpDia = int.tryParse(_bpDiaCtrl.text) ?? 0;
    final sugar = int.tryParse(_bloodSugarCtrl.text) ?? 0;

    if (bpSys >= 140 || bpDia >= 90) {
      restrictions.add(
        'Blood pressure reading is high (${bpSys}/${bpDia} mmHg) — recommend low sodium, heart-healthy Pakistani foods.',
      );
    }
    if (_isDiabetic && sugar > 180) {
      restrictions.add(
        'Blood sugar is elevated ($sugar mg/dL) — be extra strict on low glycemic index foods today.',
      );
    } else if (!_isDiabetic && sugar > 140) {
      restrictions.add(
        'Blood sugar is slightly elevated ($sugar mg/dL) — recommend low-sugar, high-fiber foods.',
      );
    }

    final restrictionText = restrictions.isNotEmpty
        ? restrictions.join('\n- ')
        : 'No specific restrictions.';

    final prompt =
        '''You are a Pakistani diet expert and clinical nutritionist. Based on the following recommended daily nutrition targets and the patient's health conditions, suggest 3 specific meal options (Breakfast, Lunch, Dinner) using common everyday Pakistani foods.

Recommended nutrition for today:
- Calories: ${rec.calories.toStringAsFixed(0)} kcal
- Protein: ${rec.protein.toStringAsFixed(1)}g
- Carbs: ${rec.carbs.toStringAsFixed(1)}g
- Fat: ${rec.fat.toStringAsFixed(1)}g

Patient health conditions and restrictions:
- $restrictionText

Rules:
1. Only suggest foods that are safe for the patient's conditions above.
2. Use realistic, everyday Pakistani meals (roti, daal, sabzi, chicken, eggs, yogurt, fruits etc.)
3. Suggest meals speicific to time for example only food that is used for breakfast should be suggested in breakfast and so on. For example, sabzi and daal or rice are usually not eaten for breakfast in a Pakistani household, so they should not be suggested for breakfast.
3. Keep portions realistic for a Pakistani household.
4. Each meal should roughly fit within the calorie targets.

Format your response as:
Breakfast: [specific meal with portion] (~[cal]kcal)
Lunch: [specific meal with portion] (~[cal]kcal)
Dinner: [specific meal with portion] (~[cal]kcal)
Health Tip: [one personalized tip based on their conditions]

Be concise and practical.''';

    final response = await http.post(
      Uri.parse(_groqUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_groqApiKey',
      },
      body: jsonEncode({
        'model': 'llama-3.3-70b-versatile',
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'max_tokens': 600,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _foodRecommendations = data['choices'][0]['message']['content'] as String;
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_profileLoaded) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF4FF), Color(0xFFBFDDF7)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: _primaryBlue),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
              _buildHeader(),
              _buildStepIndicator(),
              Expanded(
                child: _step == 0
                    ? _buildMealChat()
                    : _step == 1
                    ? _buildRuntimeInputs()
                    : _buildResults(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _primaryBlue,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _primaryBlue.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.restaurant_menu_rounded,
              color: Colors.white,
              size: 26,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Diet Tracker',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "Yesterday's meals → Today's plan",
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            if (_step > 0)
              GestureDetector(
                onTap: _resetAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Text(
                    'Restart',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _resetAll() {
    setState(() {
      _step = 0;
      _currentMealIndex = 0;
      _meals.updateAll((key, value) => null);
      _chatMessages.clear();
      _chatMessages.add(
        _ChatMsg(
          text:
              "Hi! Let's track your meals from yesterday 🍽️\n\nWhat did you have for Breakfast yesterday? You can type in English, Urdu, or Roman Urdu.",
          isBot: true,
        ),
      );
      _recommended = null;
      _foodRecommendations = '';
      _bpSysCtrl.clear();
      _bpDiaCtrl.clear();
      _bloodSugarCtrl.clear();
    });
  }

  // ─── Step Indicator ───────────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    final steps = ['Yesterday\'s Meals', 'Health Info', 'Today\'s Plan'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isActive = _step == i;
          final isDone = _step > i;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDone || isActive
                              ? _primaryBlue
                              : _primaryBlue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        steps[i],
                        style: TextStyle(
                          fontSize: 9,
                          color: isActive
                              ? _primaryBlue
                              : isDone
                              ? _primaryBlue.withOpacity(0.6)
                              : Colors.black38,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < steps.length - 1) const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ─── Step 0: Meal Chat ────────────────────────────────────────────────────

  Widget _buildMealChat() {
    final allDone = _currentMealIndex >= _mealOrder.length;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            itemCount: _chatMessages.length,
            itemBuilder: (_, i) => _buildChatBubble(_chatMessages[i]),
          ),
        ),
        if (allDone)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                onPressed: () => setState(() => _step = 1),
                child: const Text(
                  'Continue →',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          )
        else
          _buildChatInput(),
      ],
    );
  }

  Widget _buildChatBubble(_ChatMsg msg) {
    return Align(
      alignment: msg.isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isBot ? Colors.white : _primaryBlue,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isBot ? 4 : 16),
            bottomRight: Radius.circular(msg.isBot ? 16 : 4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: msg.isTyping
            ? _buildTypingDots()
            : Text(
                msg.text,
                style: TextStyle(
                  fontSize: 13,
                  color: msg.isBot ? Colors.black87 : Colors.white,
                  height: 1.5,
                ),
              ),
      ),
    );
  }

  Widget _buildTypingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildChatInput() {
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: TextField(
                    controller: _chatController,
                    enabled: !_isAnalyzing,
                    decoration: const InputDecoration(
                      hintText: 'Describe yesterday\'s meal...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _handleChatSend(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _isAnalyzing ? null : _handleChatSend,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: _isAnalyzing
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFF6EA8FF), _primaryBlue],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    color: _isAnalyzing ? Colors.grey.shade300 : null,
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Step 1: Runtime Inputs ───────────────────────────────────────────────

  Widget _buildRuntimeInputs() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Health Check-in',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'A few more details to personalize your plan for today.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withOpacity(0.45),
            ),
          ),
          const SizedBox(height: 20),
          _inputCard(
            label: 'Blood Pressure Systolic (mmHg)',
            hint: 'e.g. 120',
            controller: _bpSysCtrl,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _inputCard(
            label: 'Blood Pressure Diastolic (mmHg)',
            hint: 'e.g. 80',
            controller: _bpDiaCtrl,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _buildBloodSugarCard(),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 0,
              ),
              onPressed: _isLoading ? null : _runPrediction,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Calculate Today\'s Nutrition Plan',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Blood sugar card — shows must-check warning for diabetics,
  // or reference note for non-diabetics
  Widget _buildBloodSugarCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDiabetic
              ? Colors.orange.withOpacity(0.5)
              : _primaryBlue.withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Blood Sugar Level (mg/dL)',
                style: TextStyle(
                  fontSize: 12,
                  color: _primaryBlue.withOpacity(0.75),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isDiabetic) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.4)),
                  ),
                  child: Text(
                    'Required',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Warning for diabetics
          if (_isDiabetic) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade600,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'As a diabetic patient, please check your blood sugar before entering. Accurate readings help generate a safer meal plan for you.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ]
          // Reference note for non-diabetics
          else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _primaryBlue.withOpacity(0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: _primaryBlue.withOpacity(0.7),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'For adults without diabetes, a normal fasting blood sugar is typically below 100 mg/dL (5.6 mmol/L). Two hours after meals, healthy levels are generally below 140 mg/dL (7.8 mmol/L). Consistent healthy levels range between 70–99 mg/dL (3.9–5.5 mmol/L) when fasting.',
                      style: TextStyle(
                        fontSize: 11,
                        color: _primaryBlue.withOpacity(0.75),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          TextField(
            controller: _bloodSugarCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(
              color: Colors.black.withOpacity(0.7),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: _isDiabetic
                  ? 'Enter your current reading...'
                  : 'e.g. 95 (optional)',
              hintStyle: TextStyle(color: Colors.black.withOpacity(0.25)),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputCard({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryBlue.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: _primaryBlue.withOpacity(0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: TextStyle(
              color: Colors.black.withOpacity(0.7),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.black.withOpacity(0.25)),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 2: Results ──────────────────────────────────────────────────────

  Widget _buildResults() {
    final total = _getDayTotal();
    final rec = _recommended!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Nutrition Plan",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Based on yesterday's meals",
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 20),

          _sectionLabel("Yesterday's Intake"),
          const SizedBox(height: 10),
          _nutritionGrid(
            calories: total['calories']!,
            protein: total['protein']!,
            carbs: total['carbs']!,
            fat: total['fat']!,
            isRecommended: false,
          ),

          const SizedBox(height: 20),
          _sectionLabel('Recommended for Today (AI Model)'),
          const SizedBox(height: 10),
          _nutritionGrid(
            calories: rec.calories,
            protein: rec.protein,
            carbs: rec.carbs,
            fat: rec.fat,
            isRecommended: true,
          ),

          const SizedBox(height: 20),

          if (_foodRecommendations.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionLabel('Recommended Pakistani Meals for Today'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _primaryBlue.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                _foodRecommendations,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black.withOpacity(0.7),
                  height: 1.7,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          _sectionLabel("Yesterday's Meal Breakdown"),
          const SizedBox(height: 10),
          ..._mealOrder.map((meal) {
            final m = _meals[meal];
            return m == null
                ? const SizedBox.shrink()
                : _mealSummaryCard(meal, m);
          }),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _primaryBlue.withOpacity(0.85),
      ),
    ),
  );

  Widget _nutritionGrid({
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required bool isRecommended,
  }) {
    final accent = isRecommended ? _primaryBlue : const Color(0xFF4A6CF7);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: [
        _miniStatCard(
          'Calories',
          '${calories.toStringAsFixed(0)} kcal',
          accent,
        ),
        _miniStatCard('Protein', '${protein.toStringAsFixed(1)}g', accent),
        _miniStatCard('Carbs', '${carbs.toStringAsFixed(1)}g', accent),
        _miniStatCard('Fat', '${fat.toStringAsFixed(1)}g', accent),
      ],
    );
  }

  Widget _miniStatCard(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.black.withOpacity(0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _comparisonBar(
    String label,
    double actual,
    double recommended,
    String unit,
  ) {
    final pct = recommended > 0 ? (actual / recommended).clamp(0.0, 1.5) : 0.0;
    final over = actual > recommended;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryBlue.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withOpacity(0.65),
                ),
              ),
              Text(
                '${actual.toStringAsFixed(0)} / ${recommended.toStringAsFixed(0)} $unit',
                style: TextStyle(
                  fontSize: 12,
                  color: over ? Colors.orange.shade700 : Colors.black45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: _primaryBlue.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                over ? Colors.orange : _primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mealSummaryCard(String meal, MealNutrition m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryBlue.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            meal,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${m.calories.toStringAsFixed(0)} kcal · P: ${m.protein.toStringAsFixed(1)}g · F: ${m.fat.toStringAsFixed(1)}g · C: ${m.carbs.toStringAsFixed(1)}g',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    _bpSysCtrl.dispose();
    _bpDiaCtrl.dispose();
    _bloodSugarCtrl.dispose();
    super.dispose();
  }
}

class _ChatMsg {
  final String text;
  final bool isBot;
  final bool isTyping;
  _ChatMsg({required this.text, required this.isBot, this.isTyping = false});
}


