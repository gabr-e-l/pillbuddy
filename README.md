# PillBuddy

A medication reminder app for individuals and families.

## Firebase Setup (Required)

This project uses Firebase. The config files are excluded from this 
repository for security. To run this project locally:

### 1. Install FlutterFire CLI

dart pub global activate flutterfire_cli

### 2. Run inside the project folder

flutterfire configure --project=pillbuddy-82cc0

This will auto-generate:
- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `macos/Runner/GoogleService-Info.plist`

### 3. Install dependencies

flutter pub get

### 4. Run the app

flutter run