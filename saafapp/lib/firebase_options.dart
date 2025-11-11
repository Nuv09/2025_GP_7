// lib/firebase_options.dart
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError('No linux config.');
      default:
        throw UnsupportedError('Unsupported platform.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAjBqYlrnyK7ISFlQb7ltu-omBglhI1U2k',
    appId: '1:120954850101:web:6fda6a907c11fcfb359a7c',
    messagingSenderId: '120954850101',
    projectId: 'saaf-97251',
    authDomain: 'saaf-97251.firebaseapp.com',
    storageBucket: 'saaf-97251.firebasestorage.app',
    measurementId: 'G-002R1WHSB3',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDvc_HOStJGLdB-jaQVy_F97P6kcyke0ps',
    appId: '1:120954850101:android:ce517604b0b03d9e359a7c',
    messagingSenderId: '120954850101',
    projectId: 'saaf-97251',
    storageBucket: 'saaf-97251.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAUSw3e2hkYznDFkmILzDmXTcwZW1Kzr1A',
    appId: '1:120954850101:ios:41076c6e71bf90b7359a7c',
    messagingSenderId: '120954850101',
    projectId: 'saaf-97251',
    storageBucket: 'saaf-97251.firebasestorage.app',
    iosBundleId: 'com.example.saafapp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAUSw3e2hkYznDFkmILzDmXTcwZW1Kzr1A',
    appId: '1:120954850101:ios:41076c6e71bf90b7359a7c',
    messagingSenderId: '120954850101',
    projectId: 'saaf-97251',
    storageBucket: 'saaf-97251.firebasestorage.app',
    iosBundleId: 'com.example.saafapp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAjBqYlrnyK7ISFlQb7ltu-omBglhI1U2k',
    appId: '1:120954850101:web:d3eda158cf8c5033359a7c',
    messagingSenderId: '120954850101',
    projectId: 'saaf-97251',
    authDomain: 'saaf-97251.firebaseapp.com',
    storageBucket: 'saaf-97251.firebasestorage.app',
    measurementId: 'G-JFR4L9V12T',
  );

}