import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

// NOTE: checkConnection() did not depend on anything Google-specific in the
// original file — it only used kIsWeb and dart:io's InternetAddress. It is
// placed here in network_service.dart rather than google_auth_service.dart
// since the folder structure provides a dedicated file for it and its logic
// has nothing to do with Google Sign-In.

Future<bool> checkConnection() async {
  late bool isConnected;
  if (!kIsWeb) {
    try {
      final result = await InternetAddress.lookup('example.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        isConnected = true;
      }
    } on SocketException catch (e) {
      print(e.toString());
      isConnected = false;
    }
  } else {
    isConnected = true;
  }
  return isConnected;
}
