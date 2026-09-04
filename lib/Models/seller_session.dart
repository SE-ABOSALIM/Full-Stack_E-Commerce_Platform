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
    try {
      final prefs = await SharedPreferences.getInstance();
      final sellerDataString = prefs.getString('seller_data');
      
      if (sellerDataString != null && sellerDataString.isNotEmpty) {
        final sellerData = jsonDecode(sellerDataString) as Map<String, dynamic>;
        // Backfill defaults for older stored sessions missing new fields
        sellerData.putIfAbsent('followers_count', () => 0);
        sellerData.putIfAbsent('phone_verified', () => 'pending');
        sellerData.putIfAbsent('email_verified', () => 'pending');
        
        // Ensure followers_count is properly typed as int
        if (sellerData['followers_count'] is String) {
          sellerData['followers_count'] = int.tryParse(sellerData['followers_count']) ?? 0;
        }
        final seller = Seller.fromMap(sellerData);
        currentSeller = seller;
        print('Seller session loaded: ${seller.storeName}');
        return seller;
      }
    } catch (e) {
      print('Error loading seller session: ${e.runtimeType}');
      await clearSellerSession();
    }
    return null;
  }
  
  // Clear seller session from SharedPreferences
  static Future<void> clearSellerSession() async {
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