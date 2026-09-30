import 'dart:io' show Platform;

/// Keys for your own Supabase project (the same as the Owner and Maid apps).
/// Build with: flutter build … --dart-define-from-file=../dart_defines.json
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

  /// Region the Edge Functions run in. Keep it the same as the database's
  /// region (Supabase → Project Settings → General) so every query stays close
  /// to the data instead of crossing the world from the nearest edge.
  static const functionRegion = String.fromEnvironment('FUNCTION_REGION', defaultValue: 'ap-south-1');

  /// Firebase (push notifications): the same project as the Owner and Maid
  /// apps; the Family app has its own App IDs. Empty = no notifications.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '');
  static const firebaseIosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY', defaultValue: firebaseApiKey);
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID_FAMILY', defaultValue: '');
  static const firebaseIosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID_FAMILY', defaultValue: '');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '');

  static bool get firebaseConfigured =>
      firebaseApiKey.isNotEmpty &&
      (Platform.isIOS ? firebaseIosAppId.isNotEmpty : firebaseAppId.isNotEmpty) &&
      firebaseSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  static bool get supabaseConfigured => !supabaseAnonKey.startsWith('PASTE_');
}
