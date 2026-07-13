<div align="center">

<img src="assets/logo/logo.png" alt="Curely logo" width="120"/>

# Curely

Daily vitals tracking, medication reminders, and AI-assisted health management — built in Flutter.

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![Node.js](https://img.shields.io/badge/Node.js-339933?style=for-the-badge&logo=node.js&logoColor=white)
![Express](https://img.shields.io/badge/Express-000000?style=for-the-badge&logo=express&logoColor=white)
![Google Gemini](https://img.shields.io/badge/Gemini-8E75B2?style=for-the-badge&logo=googlegemini&logoColor=white)
![Groq](https://img.shields.io/badge/Groq-F55036?style=for-the-badge&logo=groq&logoColor=white)
![Cloudinary](https://img.shields.io/badge/Cloudinary-3448C5?style=for-the-badge&logo=cloudinary&logoColor=white)

[**Download APK**](#) &nbsp;•&nbsp; [**Try the web build**](#)

</div>

---

Curely is a Flutter app for chronic disease patients to manage their condition day to day — daily vitals tracking, medication reminders, AI-assisted diet guidance, a chatbot for quick questions, and automatic extraction of data from scanned medical reports.

---

## Demo

<div align="center">

https://github.com/user-attachments/assets/dc84dc96-c0f5-46a4-bf32-17b28e16fea3

</div>

---

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

---

## Screenshots

<div align="center">

<table>
  <tr>
    <td align="center" width="25%"><b>Dashboard</b></td>
    <td align="center" width="25%"><b>Vitals Trend</b></td>
    <td align="center" width="25%"><b>Daily Vitals Entry</b></td>
    <td align="center" width="25%"><b>AI Chatbot</b></td>
  </tr>
  <tr>
    <td><img src="https://github.com/user-attachments/assets/4896bdcf-d8e4-4251-938c-0763bb0c51fc" width="200"/></td>
    <td><img src="https://github.com/user-attachments/assets/a0152c09-57e7-433c-a71d-e1f833e7fa3c" width="200"/></td>
    <td><img src="https://github.com/user-attachments/assets/35dc2f7a-bebb-4eed-b1dc-5a08b732e431" width="200"/></td>
    <td><img src="https://github.com/user-attachments/assets/8c8d5ce8-cfa3-48e9-b3f0-04954082afbe" width="200"/></td>
  </tr>
  <tr>
    <td align="center" width="25%"><b>Report Scan (OCR)</b></td>
    <td align="center" width="25%"><b>Medication Reminder</b></td>
    <td align="center" width="25%"><b>Emergency Info</b></td>
    <td align="center" width="25%"><b>Settings</b></td>
  </tr>
  <tr>
    <td><img src="https://github.com/user-attachments/assets/53c114a7-56e2-4613-a5bd-c929ca499c87" width="200"/></td>
    <td><img src="https://github.com/user-attachments/assets/a1a87d84-4ef5-4854-adf6-eafc4bfaa311" width="200"/></td>
    <td><img src="https://github.com/user-attachments/assets/e306ab9f-e177-4c5a-8ab5-33fa31b85599" width="200"/></td>
    <td><img src="https://github.com/user-attachments/assets/ab54f9fe-c764-4da3-9ed3-234072551bb6" width="200"/></td>
  </tr>
</table>

</div>

---

## Built with

Flutter targets Android, iOS, Web, Windows, macOS, and Linux from one codebase. State management runs on Provider, with flutter_local_notifications, pdf/printing, image_picker, and file_picker handling the rest of the app-side work.

---

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

---

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

---

## License

Built as a university Final Year Project.
