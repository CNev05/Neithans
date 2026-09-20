# DormMate

DormMate — offline-first rent/SMS notifier for apartment & dormitory owners.

Features
- Flutter mobile app (Android + iOS) + Flutter Web dashboard (superadmin)
- Offline-first local DB with queued SMS syncing to Firestore
- Firebase backend (Auth, Firestore, Cloud Functions) with Twilio integration
- RBAC: `superadmin` (dashboard) and `owner` (end users)
- Scheduler: monthly reminders (27th) implemented as a Cloud Function

## Data and security architecture

- Firestore is the source of truth for `users`, `owners`, `rooms`, `tenants`, `payments`, and `sms_queue`.
- Clients can read only records permitted by Firebase Auth claims. All writes go through the `mutateRecord` callable function.
- `superadmin` and `owner` are boolean custom claims. New Auth users are provisioned as owners by the `provisionOwner` Auth trigger.
- Role changes use `setRole`; Cloud Functions write immutable records to `audit_logs`, which clients cannot write.
- `scheduledFirestoreBackup` starts a daily Firestore export to Cloud Storage. Configure `backup.bucket` and grant the Functions service account Storage Admin access to that bucket.
- The admin panel is served from `build/web` through Firebase Hosting.

Quick start (local)
1. Install Flutter and Firebase CLI.
2. Copy `.env.example` -> `.env.local` and set TWILIO and Firebase project vars.
3. From `/mobile` run:
   - flutter pub get
   - flutter run -d chrome  # for web or use an emulator/device
4. Start Firebase emulator (optional) and deploy functions when ready:
   - firebase emulators:start --only auth,firestore,functions
   - firebase deploy --only functions,firestore,hosting

Dev notes
- Use Firebase custom claims for RBAC (`superadmin: true` or `owner: true`); role changes must go through `setRole`.
- The app keeps an `sms_queue` locally and syncs to Firestore when online; Cloud Functions send SMS via Twilio.

Files of interest
- `/mobile/lib` — Flutter app source (mobile + web)
- `/functions/src` — Firebase Cloud Functions (Twilio + scheduler)
- `/firebase/firestore.rules` — security rules
- `.github/workflows/ci.yml` — CI for tests/build/deploy

Roadmap / TODO
- Add payment gateway integration
- Improve analytics & reporting
- Add push notifications and delivery receipts

License: MIT
