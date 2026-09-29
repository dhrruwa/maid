import 'dart:io' show Platform;

/// Keys for your own Supabase and Firebase projects.
/// See docs/SETUP_GUIDE.md, steps 4 and 6.
class AppConfig {
  /// Supabase → Project Settings → API → Project URL
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://sbyespnawbknbnlbrmht.supabase.co',
  );

  /// Supabase → Project Settings → API Keys → "anon public" (or "publishable") key
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'PASTE_YOUR_SUPABASE_ANON_KEY_HERE',
  );

  /// Region the Edge Functions run in. Keep it the same as the database's region
  /// (Supabase → Project Settings → General) so each query stays in one data centre
  /// instead of crossing the globe. 'any' or empty lets Supabase pick the nearest edge.
  static const functionRegion = String.fromEnvironment('FUNCTION_REGION', defaultValue: 'ap-south-1');

  /// Firebase console → Project settings → General → Your apps → Android app
  /// (values are also inside google-services.json). Leave empty to run
  /// without push notifications.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '');

  /// iPhone only: Firebase → Project settings → Your apps → iOS app → App ID
  /// (iOS push also needs an APNs key uploaded to Firebase).
  static const firebaseIosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID', defaultValue: '');

  static bool get firebaseConfigured =>
      firebaseApiKey.isNotEmpty &&
      (Platform.isIOS ? firebaseIosAppId.isNotEmpty : firebaseAppId.isNotEmpty) &&
      firebaseSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  static bool get supabaseConfigured => !supabaseAnonKey.startsWith('PASTE_');
}
