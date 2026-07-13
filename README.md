# Curely

Curely is a Flutter app for chronic disease patients to manage their condition day to day — daily vitals tracking, medication reminders, AI-assisted diet guidance, a chatbot for quick questions, and automatic extraction of data from scanned medical reports.

## What it does

- **Daily vitals tracking** — log blood pressure, glucose, temperature, water intake, and sleep once a day, with duplicate-entry checks so the same day can't be logged twice
- **Dashboard** — vitals and trends charted over time at a glance
- **Report scanning (OCR)** — upload a photo of a lab report or prescription; Gemini-powered OCR on the backend extracts the data into structured text instead of the patient re-typing it
- **AI chatbot** — Groq-powered assistant for quick patient questions
- **AI diet assistant** — Groq-powered, personalized diet guidance
- **Medication reminders** — local notifications for scheduled doses
- **Daily entry reminders** — a nudge if today's vitals haven't been logged yet
- **PDF reports** — generate and share a clean health summary
- **Emergency info** — critical patient details reachable in one tap
- **Profile & onboarding** — guided first-time setup and profile management
- **Auth** — email/Google sign-in via Firebase Auth

## Built with

- **Flutter** — Android, iOS, Web, Windows, macOS, Linux from one codebase
- **Firebase** — Auth, Firestore, Storage
- **Node.js/Express backend** — Gemini-based OCR extraction and signed Cloudinary deletes
- **Groq API** — powers the chatbot and diet assistant
- **Cloudinary** — image hosting for uploaded reports
- **Provider** for state management
- flutter_local_notifications, pdf/printing, image_picker, file_picker round out the rest

## Running it yourself

### You'll need

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (^3.10.7)
- A Firebase project (Auth, Firestore, and Storage enabled)
- A [Groq API key](https://console.groq.com)

### Setup

1. Clone it
   ```bash
   git clone https://github.com/H-Layba/Curely.git
   cd Curely
   ```

2. Install dependencies
   ```bash
   flutter pub get
   ```

3. Add your own Firebase config
   - Add `android/app/google-services.json` (Android) and/or `ios/Runner/GoogleService-Info.plist` (iOS) from your Firebase console
   - Update `lib/firebase_options.dart` if you're using FlutterFire CLI (`flutterfire configure`)

4. Add your Groq API key
   - In `lib/chatbot_model/chatbot.dart`, replace `YOUR_GROQ_API_KEY_HERE` with your own key
   - In `lib/diet_model/diet.dart`, replace `YOUR_GROQ_API_KEY_HERE` with your own key
   - **Do not commit real keys** — these files are meant to hold placeholders only

5. Run the app
   ```bash
   flutter run
   ```

> Report scanning and Cloudinary deletes depend on the companion backend service — the app expects it at the `BASE_URL` set in `lib/reports/report.dart`. Point that at your own deployment if you're standing the backend up yourself.

## Project Structure

```
lib/
├── auth/            # Login, signup, authentication logic
├── onboarding/       # First-time user setup flow
├── dashboard/        # Main patient dashboard
├── chatbot_model/    # AI chatbot (Groq)
├── diet_model/       # AI diet assistant (Groq)
├── patient/          # Daily vitals entry, patient data models and screens
├── reports/          # Report upload, OCR extraction, PDF generation
├── emergency/        # Emergency info screen
├── notifications/    # Medication and daily-entry reminders
├── profile/          # User profile management
├── settings/         # App settings
└── utils/            # Shared utilities (incl. Cloudinary cleanup helper)
```

## License

Built as a university Final Year Project.
