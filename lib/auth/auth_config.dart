import 'package:firebase_core/firebase_core.dart';

/// Where this build expects its Firebase project to be configured.
///
/// Supplying the values at build time keeps the credentials out of the source
/// tree and keeps a build without them working: Strand still opens, still reads
/// sleep, and the account screens say plainly that sign-in is not configured
/// yet instead of pretending it is.
///
/// ```text
/// flutter build apk --debug \
///   --dart-define=FIREBASE_API_KEY=... \
///   --dart-define=FIREBASE_APP_ID=... \
///   --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
///   --dart-define=FIREBASE_PROJECT_ID=... \
///   --dart-define=FIREBASE_STORAGE_BUCKET=...
/// ```
abstract final class AuthConfig {
  static const String apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  /// Whether a Firebase app can be created from the values in this build.
  static bool get hasFirebaseOptions =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  /// The dart-define keys that are empty in this build.
  static List<String> get missingValues {
    final List<String> out = <String>[];
    if (apiKey.isEmpty) out.add('FIREBASE_API_KEY');
    if (appId.isEmpty) out.add('FIREBASE_APP_ID');
    if (messagingSenderId.isEmpty) {
      out.add('FIREBASE_MESSAGING_SENDER_ID');
    }
    if (projectId.isEmpty) out.add('FIREBASE_PROJECT_ID');
    if (storageBucket.isEmpty) out.add('FIREBASE_STORAGE_BUCKET');
    return out;
  }

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        storageBucket: storageBucket.isEmpty ? null : storageBucket,
      );
}
