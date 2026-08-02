import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      default:
        return ios;
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey:            'AIzaSyCRcqgmPloq4c-I9_mMB86JrRjZU2Akcmg',
    appId:             '1:1013201175960:ios:1a3b652ce16aafde4f17ed',
    messagingSenderId: '1013201175960',
    projectId:         'cnady-ce15b',
    storageBucket:     'cnady-ce15b.firebasestorage.app',
    iosBundleId:       'com.jeeven.candy',
  );
}