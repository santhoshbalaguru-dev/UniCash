// NOTE: convertBytesToMB() has no dependency on the Drive API itself — it's a
// pure string->double conversion helper, so it's placed in utils/drive_utils.dart
// rather than services/google/google_drive_service.dart.

double convertBytesToMB(String bytesString) {
  try {
    int bytes = int.parse(bytesString);
    double megabytes = bytes / (1024 * 1024);
    return megabytes;
  } catch (e) {
    print("Error parsing bytes string: $e");
    return 0.0;
  }
}
