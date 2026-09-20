# DormMate — Cloud Functions

This folder contains Firebase Cloud Functions (TypeScript) that:
- schedule monthly reminders (27th)
- send SMS via Twilio for documents in `sms_queue`
- receive Twilio delivery webhooks and update `sms_queue` statuses
- helper to set custom claims for RBAC

Setup
1. cd functions
2. npm ci
3. copy ../.env.example -> .env (or set environment in Firebase Console)
4. firebase deploy --only functions

Local emulation: `firebase emulators:start --only functions,firestore,auth`
