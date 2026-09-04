import '../Services/auth_session.dart';
import '../Services/seller_api_service.dart';
import 'seller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SellerSession {
  static Seller? currentSeller;
  
  // Save seller session to SharedPreferences
  static Future<void> saveSellerSession(Seller seller) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sellerData = {
        'id': seller.id,
        'name': seller.name,
        'email': seller.email,
        'phone': seller.phone,
        // Persist verification statuses so UI remains consistent across restarts
        'phone_verified': seller.phoneVerified,
        'email_verified': seller.emailVerified,
        'store_name': seller.storeName,
        'store_description': seller.storeDescription,
        'store_logo_url': seller.storeLogo,
        'cargo_company': seller.cargoCompany,
        'is_verified': seller.isVerified ? 'verified' : 'pending',
        // CRITICAL: Persist followers count; otherwise it loads as 0 on next app start
        'followers_count': seller.followersCount,
        'created_at': seller.createdAt.toIso8601String(),
        'updated_at': seller.updatedAt.toIso8601String(),
      };
      await prefs.setString('seller_data', jsonEncode(sellerData));
      currentSeller = seller;
      print('Seller session saved: ${seller.storeName}');
    } catch (e) {
      print('Error saving seller session: ${e.runtimeType}');
    }
  }
  
  // Load seller session from SharedPreferences
  static Future<Seller?> loadSellerSession() async {
    await AuthSession.load();
    currentSeller = null;
    if (AuthSession.sellerToken == null) return null;
    try {
      final seller = await SellerApiService.getProfile();
      currentSeller = seller;
      return seller;
    } catch (_) {
      return null;
    }
  }

  // Clear seller session from SharedPreferences
  static Future<void> clearSellerSession() async {
    await AuthSession.clear('seller');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('seller_data');
      currentSeller = null;
      print('Seller session cleared');
    } catch (e) {
      print('Error clearing seller session: ${e.runtimeType}');
    }
  }
} 