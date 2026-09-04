import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../Models/seller.dart';
import '../Utils/app_config.dart';

class SellerApiService {
  static String get baseUrl => AppConfig.baseUrl;
  
  // Backend durumunu kontrol et
  static Future<bool> checkBackendStatus() async {
    try {
      print('Checking backend status at: $baseUrl/');
      final response = await http.get(
        Uri.parse('$baseUrl/'),
      ).timeout(const Duration(seconds: 10));
      
      print('Backend status response: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('Backend status check failed: ${e.runtimeType}');
      return false;
    }
  }

  // Satıcı Girişi
  static Future<Seller> login(String email, String password) async {
    try {
      print('Seller login attempt started');
      
      final response = await http.post(
        Uri.parse('$baseUrl/sellers/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: Uri(queryParameters: {
          'email': email,
          'password': password,
        }).query,
      ).timeout(const Duration(seconds: 10));

      print('Response status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Seller.fromMap(data);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Giriş başarısız');
      }
    } catch (e) {
      print('Login error: ${e.runtimeType}');
      if (e.toString().contains('SocketException') || e.toString().contains('Connection refused')) {
        throw Exception('Sunucuya bağlanılamıyor. Backend çalışıyor mu?');
      }
      throw Exception('Giriş başarısız: $e');
    }
  }

  // Satıcı Kaydı
  static Future<Seller> signup({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String storeName,
    String? storeDescription,
    String? cargoCompany,
    File? logoFile,
  }) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/sellers/signup'),
    );

    // Text fields
    request.fields['name'] = name;
    request.fields['email'] = email;
    request.fields['password'] = password;
    request.fields['phone'] = phone;
    request.fields['store_name'] = storeName;
    if (storeDescription != null) {
      request.fields['store_description'] = storeDescription;
    }
    if (cargoCompany != null) {
      request.fields['cargo_company'] = cargoCompany;
    }

    // Logo file
    if (logoFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'logo',
          logoFile.path,
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return Seller.fromMap(data);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Kayıt başarısız');
    }
  }

  // Satıcı Profili Getir
  static Future<Seller> getProfile(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/sellers/profile'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Seller.fromMap(data);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Profil getirilemedi');
    }
  }

  // Satıcı Profili Güncelle
  static Future<Seller> updateProfile({
    required int sellerId,
    String? name,
    String? email,
    String? phone,
    String? storeName,
    String? storeDescription,
    String? cargoCompany,
    File? logoFile,
  }) async {
    var request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/sellers/profile?seller_id=$sellerId'),
    );

    // Text fields - sadece null olmayan değerleri gönder
    if (name != null && name.isNotEmpty) request.fields['name'] = name;
    if (email != null && email.isNotEmpty) request.fields['email'] = email;
    if (phone != null && phone.isNotEmpty) request.fields['phone'] = phone;
    if (storeName != null && storeName.isNotEmpty) request.fields['store_name'] = storeName;
    if (storeDescription != null && storeDescription.isNotEmpty) request.fields['store_description'] = storeDescription;
    if (cargoCompany != null && cargoCompany.isNotEmpty) request.fields['cargo_company'] = cargoCompany;

    // Logo file - sadece yeni logo seçilmişse gönder
    if (logoFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'logo',
          logoFile.path,
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    print('Update profile response status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Seller.fromMap(data);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Profil güncellenemedi');
    }
  }

  // Satıcı Çıkışı
  static Future<void> logout(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/sellers/logout'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Çıkış başarısız');
    }
  }

  // Satıcı Bilgilerini Getir (ID ile)
  static Future<Seller> getSellerById(int sellerId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/sellers/$sellerId'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Seller.fromMap(data);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Satıcı bilgileri getirilemedi');
    }
  }

  // Satıcılar için telefon doğrulama kodu gönder
  static Future<Map<String, dynamic>> sendSellerVerificationCode(String phoneNumber, {String? language}) async {
    try {
      print('Seller verification code request started');
      
      final response = await http.post(
        Uri.parse('$baseUrl/send-seller-verification-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone_number': phoneNumber,
          'language': language ?? 'tr'
        }),
      ).timeout(const Duration(seconds: 10));

      print('Seller verification response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Doğrulama kodu gönderilemedi');
      }
    } catch (e) {
      print('Seller verification error: ${e.runtimeType}');
      if (e.toString().contains('SocketException') || e.toString().contains('Connection refused')) {
        throw Exception('Sunucuya bağlanılamıyor. Backend çalışıyor mu?');
      }
      throw Exception('Doğrulama kodu gönderilemedi: $e');
    }
  }

  // Satıcılar için telefon doğrulama kodunu doğrula
  static Future<Map<String, dynamic>> verifySellerPhone(String phoneNumber, String verificationCode) async {
    try {
      print('Seller phone verification submission started');
      
      final response = await http.post(
        Uri.parse('$baseUrl/verify-seller-phone'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone_number': phoneNumber,
          'verification_code': verificationCode
        }),
      ).timeout(const Duration(seconds: 10));

      print('Seller phone verification response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Telefon doğrulanamadı');
      }
    } catch (e) {
      print('Seller phone verification error: ${e.runtimeType}');
      if (e.toString().contains('SocketException') || e.toString().contains('Connection refused')) {
        throw Exception('Sunucuya bağlanılamıyor. Backend çalışıyor mu?');
      }
      throw Exception('Telefon doğrulanamadı: $e');
    }
  }
} 