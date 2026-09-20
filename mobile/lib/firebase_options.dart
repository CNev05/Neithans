import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
            'DefaultFirebaseOptions have not been configured for iOS.');
      case TargetPlatform.macOS:
        throw UnsupportedError(
            'DefaultFirebaseOptions have not been configured for macOS.');
      case TargetPlatform.windows:
        throw UnsupportedError(
            'DefaultFirebaseOptions have not been configured for windows.');
      case TargetPlatform.linux:
        throw UnsupportedError(
            'DefaultFirebaseOptions have not been configured for linux.');
      default:
        throw UnsupportedError(
            'DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAB7ZxDZCrHuowUV1vbTBSg0a7giCf4Ykk',
    appId: '1:676295004395:android:6a1601a88aa681981caeae',
    messagingSenderId: '676295004395',
    projectId: 'dormmate-6dc56',
    storageBucket: 'dormmate-6dc56.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCymn0vf6_JkxIW-ouP6QfuHWrN_XGTRzI',
    appId: '1:676295004395:web:3e3ea8b2af5cb4f01caeae',
    messagingSenderId: '676295004395',
    projectId: 'dormmate-6dc56',
    authDomain: 'dormmate-6dc56.firebaseapp.com',
    storageBucket: 'dormmate-6dc56.firebasestorage.app',
    measurementId: 'G-69LD8JT4TZ',
  );
}
