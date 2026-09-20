# DormMate (mobile)

Run locally:
1. cd mobile
2. flutter pub get
3. flutter run -d chrome  # or run on an emulator/device

Notes:
- App uses Firebase Auth + Firestore for sync; configure `google-services.json` / `GoogleService-Info.plist` for Android/iOS when ready.
- Local DB uses `sqflite` and stores `sms_queue` for offline-first behavior.
- Background sync uses `workmanager` (Android) and `background_fetch` (iOS) — implementation scaffolded in `sync_service.dart`.
flut