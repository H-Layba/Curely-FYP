import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;

  final Color primaryBlue = const Color(0xFF2533AE);

  static const String _apiKey =
      'YOUR_GROQ_API_KEY_HERE';

  static const String _apiUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  final List<_Message> _messages = [
    _Message(
      text: 'Hello! I\'m your Medical AI assistant. How can I help you today?',
      isBot: true,
    ),
  ];

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isTyping) return;

    setState(() {
      _messages.add(_Message(text: text, isBot: false));
      _controller.clear();
      _isTyping = true;
    });

    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.3-70b-versatile',
          'messages': [
            {
              'role': 'system',
              'content': '''
You are a medical and nutrition assistant chatbot.

Only answer questions related to:
health, symptoms, diseases, diet, nutrition, and wellness.

If unrelated, reply:
I can only help with medical-related questions.
'''
            },
            {
              'role': 'user',
              'content': text,
            }
          ],
          'max_tokens': 1024,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply =
            data['choices'][0]['message']['content'] as String;

        setState(() {
          _isTyping = false;
          _messages.add(_Message(text: reply, isBot: true));
        });
      } else {
        _showError('API error: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Connection error');
    }

    _scrollToBottom();
  }

  void _showError(String msg) {
    setState(() {
      _isTyping = false;
      _messages.add(
        _Message(text: '⚠️ $msg', isBot: true, isError: true),
      );
    });

    _scrollToBottom();
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

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        ///  SAME APP GRADIENT
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

              ///  HEADER (INVERTED COLORS)
Padding(
  padding: const EdgeInsets.all(10),
  child: Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: primaryBlue, //  was white → now blue
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: primaryBlue.withOpacity(0.25), // slightly stronger for depth
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: SizedBox(
  height: 43, //  locks header height
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        height: 60,
        child: Center(
          child: Image.asset(
            'assets/logo/logo.png',
            height: 40, //  bigger logo WITHOUT stretching header
            fit: BoxFit.contain,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Column(
        mainAxisAlignment: MainAxisAlignment.center, //  vertical center
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Curely AI Assistant',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Text(
            _isTyping ? 'Typing...' : 'Online',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ],
      ),
    ],
  ),
),
  ),
),

              ///  CHAT LIST
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (_isTyping && i == _messages.length) {
                      return const _TypingBubble();
                    }
                    return _ChatBubble(message: _messages[i]);
                  },
                ),
              ),

             
              ///  FIXED INPUT BAR (MAIN FIX HERE)
              SafeArea(
                top: false,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 10,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                  ),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22),
                        bottom: Radius.circular(22),
                      ),
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
                              controller: _controller,
                              enabled: !_isTyping,
                              decoration: const InputDecoration(
                                hintText: 'Type your message...',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _isTyping ? null : _sendMessage,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
          colors: [
            Color(0xFF6EA8FF), // refined highlight
            Color(0xFF2533AE), // your primary blue (stronger match)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _Message {
  final String text;
  final bool isBot;
  final bool isError;

  _Message({
    required this.text,
    required this.isBot,
    this.isError = false,
  });
}

///  IMPROVED CHAT BUBBLE
class _ChatBubble extends StatelessWidget {
  final _Message message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isBot = message.isBot;

    return Align(
      alignment:
          isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: message.isError
              ? Colors.red.shade100
              : isBot
                  ? Colors.white
                  : const Color(0xFF2533AE),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isBot ? 4 : 16),
            bottomRight: Radius.circular(isBot ? 16 : 4),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 14,
            color: isBot
                ? Colors.black87
                : Colors.white,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

///  TYPING BUBBLE 
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();

    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..repeat(reverse: true),
    );

    _animations = List.generate(3, (i) {
      return Tween<double>(begin: 0, end: -6).animate(
        CurvedAnimation(
          parent: _controllers[i],
          curve: Curves.easeInOut,
        ),
      );
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _animations[i],
              builder: (_, __) => Transform.translate(
                offset: Offset(0, _animations[i].value),
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}