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
    apiKey: 'AIzaSyAt3zWwjAFuYJZtbYSLeng7QzwCE_o97Bo',
    appId: '1:460606007905:web:nhom4blockchainverifier',
    messagingSenderId: '460606007905',
    projectId: 'nhom4-blockchain-verifier',
    authDomain: 'nhom4-blockchain-verifier.firebaseapp.com',
    databaseURL: 'https://nhom4-blockchain-verifier-default-rtdb.firebaseio.com',
    storageBucket: 'nhom4-blockchain-verifier.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAt3zWwjAFuYJZtbYSLeng7QzwCE_o97Bo',
    appId: '1:460606007905:android:b60e0c7eab14b1b3585820',
    messagingSenderId: '460606007905',
    projectId: 'nhom4-blockchain-verifier',
    databaseURL: 'https://nhom4-blockchain-verifier-default-rtdb.firebaseio.com',
    storageBucket: 'nhom4-blockchain-verifier.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAt3zWwjAFuYJZtbYSLeng7QzwCE_o97Bo',
    appId: '1:460606007905:ios:b60e0c7eab14b1b3585820',
    messagingSenderId: '460606007905',
    projectId: 'nhom4-blockchain-verifier',
    databaseURL: 'https://nhom4-blockchain-verifier-default-rtdb.firebaseio.com',
    storageBucket: 'nhom4-blockchain-verifier.firebasestorage.app',
    iosBundleId: 'com.example.nhom4LapTrinhMobile',
  );
}
