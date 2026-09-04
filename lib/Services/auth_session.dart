import 'package:shared_preferences/shared_preferences.dart';

/// Separate credentials because user and seller numeric IDs may overlap.
class AuthSession {
  static String? userToken;
  static String? sellerToken;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    userToken = prefs.getString('user_access_token');
    sellerToken = prefs.getString('seller_access_token');
    // An email or cached profile alone is no longer an authenticated session.
    await prefs.remove('user_email');
  }

  static Future<void> save(String role, String token) async {
    if (token.isEmpty) throw const FormatException('Missing access credential');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${role}_access_token', token);
    if (role == 'seller') {
      sellerToken = token;
    } else {
      userToken = token;
    }
  }

  static Future<void> clear(String role) async {
    if (role == 'seller') {
      sellerToken = null;
    } else {
      userToken = null;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${role}_access_token');
    await prefs.remove(role == 'seller' ? 'seller_data' : 'user_email');
  }
}
