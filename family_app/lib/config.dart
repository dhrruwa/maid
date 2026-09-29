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

  static bool get supabaseConfigured => !supabaseAnonKey.startsWith('PASTE_');
}
