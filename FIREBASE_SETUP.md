# Firebase Setup for Android

## CRITICAL: App crashes because google-services.json is missing!

### How to fix Android crash:

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: `x5-marketing-app`
3. Click the gear icon -> Project Settings
4. Scroll down to "Your apps" section
5. Click on Android app (package: `com.x5marketing.mobile`)
6. Click "Download google-services.json"
7. Place the file in: `android/app/google-services.json`

### For iOS (GoogleService-Info.plist):

1. Same Firebase Console
2. Click on iOS app
3. Download `GoogleService-Info.plist`
4. Place in: `ios/Runner/GoogleService-Info.plist`

### If you don't have an Android app registered:

1. In Firebase Console, click "Add app"
2. Select Android
3. Package name: `com.x5marketing.mobile`
4. App nickname: X5 Marketing (optional)
5. Debug signing certificate SHA-1: (get from `./gradlew signingReport`)
6. Register the app
7. Download google-services.json

### To get SHA-1 for Google Sign-In:

```bash
cd android
./gradlew signingReport
```

Copy the SHA-1 fingerprint and add it to Firebase Console -> Project Settings -> Android app -> Add fingerprint

---

After adding google-services.json, rebuild the app:
```bash
flutter clean
flutter pub get
flutter run
```
