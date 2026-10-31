// File cấu hình Firebase Options dự phòng theo chuẩn FlutterFire
// Khi nhóm tạo Project thật trên Firebase Console và tải google-services.json,
// file này có thể được sinh tự động bằng lệnh: flutterfire configure

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
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDemoBlockchainVerifierKey123456Web',
    appId: '1:100000000000:web:abcdef1234567890',
    messagingSenderId: '100000000000',
    projectId: 'nhom4-blockchain-verifier',
    authDomain: 'nhom4-blockchain-verifier.firebaseapp.com',
    databaseURL: 'https://nhom4-blockchain-verifier-default-rtdb.firebaseio.com',
    storageBucket: 'nhom4-blockchain-verifier.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDemoBlockchainVerifierKey123456Android',
    appId: '1:100000000000:android:abcdef1234567890',
    messagingSenderId: '100000000000',
    projectId: 'nhom4-blockchain-verifier',
    databaseURL: 'https://nhom4-blockchain-verifier-default-rtdb.firebaseio.com',
    storageBucket: 'nhom4-blockchain-verifier.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDemoBlockchainVerifierKey123456iOS',
    appId: '1:100000000000:ios:abcdef1234567890',
    messagingSenderId: '100000000000',
    projectId: 'nhom4-blockchain-verifier',
    databaseURL: 'https://nhom4-blockchain-verifier-default-rtdb.firebaseio.com',
    storageBucket: 'nhom4-blockchain-verifier.appspot.com',
    iosBundleId: 'com.example.nhom4LapTrinhMobile',
  );
}
