import '../Models/User.dart';
import 'auth_http.dart';
import 'auth_session.dart';
import 'dart:convert';
import '../Models/session.dart';
import '../Utils/app_config.dart';

class ApiService {
  static Future<User> loginUser(String email, String password) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/users/login'),
      body: {'email': email, 'password': password},
    );
    if (response.statusCode != 200) throw Exception('E-posta veya şifre hatalı');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await AuthSession.save('user', data['access_token'] as String);
    final user = User.fromMap(data);
    Session.currentUser = user;
    return user;
  }

  static Future<Map<String, dynamic>> fetchMyProfile() async {
    final response = await AuthHttp.get(Uri.parse('$baseUrl/users/me'));
    if (response.statusCode != 200) throw Exception('Lütfen yeniden giriş yapın');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> changePassword(String currentPassword, String newPassword, String newPasswordAgain) async {
    final response = await AuthHttp.put(
      Uri.parse('$baseUrl/users/me/password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'current_password': currentPassword, 'new_password': newPassword, 'new_password_again': newPasswordAgain}),
    );
    if (response.statusCode != 200) throw Exception('Şifre değiştirilemedi; mevcut şifrenizi kontrol edin');
    await AuthSession.clear('user');
    Session.currentUser = null;
  }

  static Future<void> requestPasswordReset(String phoneNumber) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/auth/forgot-password/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone_number': phoneNumber}),
    );
    if (response.statusCode != 200) throw Exception('Doğrulama kodu gönderilemedi');
  }

  static Future<void> resetPassword(String phoneNumber, String code, String newPassword) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/auth/forgot-password/reset'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone_number': phoneNumber, 'verification_code': code, 'new_password': newPassword}),
    );
    if (response.statusCode != 200) throw Exception('Kod geçersiz veya süresi dolmuş. Yeni kod isteyin.');
    await AuthSession.clear('user');
    Session.currentUser = null;
  }

  static String get baseUrl => AppConfig.baseUrl;

  // --- PRODUCT CRUD ---
  static Future<List<dynamic>> fetchProducts() async {
    final response = await AuthHttp.get(Uri.parse('$baseUrl/products'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Ürünler alınamadı');
    }
  }

  static Future<void> addProduct(Map<String, dynamic> data) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/products'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Ürün eklenemedi');
    }
  }

  static Future<void> updateProduct(int id, Map<String, dynamic> data) async {
    final response = await AuthHttp.put(
      Uri.parse('$baseUrl/products/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Ürün güncellenemedi');
    }
  }

  static Future<void> deleteProduct(int id) async {
    final response = await AuthHttp.delete(Uri.parse('$baseUrl/products/$id'));
    if (response.statusCode != 200) {
      throw Exception('Ürün silinemedi');
    }
  }

  // Satıcının ürünlerini getir
  static Future<List<dynamic>> fetchSellerProducts(int sellerId) async {
    final response = await AuthHttp.get(Uri.parse('$baseUrl/sellers/$sellerId/products'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Satıcı ürünleri alınamadı');
    }
  }

  // --- PHONE VERIFICATION ---
  static Future<Map<String, dynamic>> sendVerificationCode(String phoneNumber) async {
    // Telefon numarasını backend formatına çevir
    String formattedPhone = phoneNumber;
    if (phoneNumber.startsWith('0')) {
      formattedPhone = '+90 ' + phoneNumber.substring(1, 4) + ' ' + 
                      phoneNumber.substring(4, 7) + ' ' + 
                      phoneNumber.substring(7, 9) + ' ' + 
                      phoneNumber.substring(9, 11);
    }
    
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/send-verification-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone_number': formattedPhone}),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['detail'] ?? 'Doğrulama kodu gönderilemedi');
    }
  }

  static Future<Map<String, dynamic>> verifyPhone(String phoneNumber, String verificationCode) async {
    // Telefon numarasını backend formatına çevir
    String formattedPhone = phoneNumber;
    if (phoneNumber.startsWith('0')) {
      formattedPhone = '+90 ' + phoneNumber.substring(1, 4) + ' ' + 
                      phoneNumber.substring(4, 7) + ' ' + 
                      phoneNumber.substring(7, 9) + ' ' + 
                      phoneNumber.substring(9, 11);
    }
    
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/verify-phone'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone_number': formattedPhone,
        'verification_code': verificationCode,
      }),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['detail'] ?? 'Telefon doğrulanamadı');
    }
  }

  // --- USER PHONE VERIFICATION (by user id) ---
  static Future<Map<String, dynamic>> sendUserPhoneVerificationByUserId(int userId) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/users/$userId/send-phone-verification'),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['detail'] ?? 'Doğrulama kodu gönderilemedi');
    }
  }

  // --- EMAIL VERIFICATION ---
  static Future<Map<String, dynamic>> sendEmailVerificationCode(String email, {String? language}) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/send-email-verification-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'language': language ?? 'tr',
      }),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['detail'] ?? 'Email doğrulama kodu gönderilemedi');
    }
  }

  static Future<Map<String, dynamic>> verifyEmail(String email, String verificationCode) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/verify-email'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'verification_code': verificationCode,
      }),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['detail'] ?? 'Email doğrulanamadı');
    }
  }

  // --- SELLER EMAIL VERIFICATION ---
  static Future<Map<String, dynamic>> sendSellerEmailVerificationCode(String email, {String? language}) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/send-seller-email-verification-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'language': language ?? 'tr',
      }),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['detail'] ?? 'Email doğrulama kodu gönderilemedi');
    }
  }

  static Future<Map<String, dynamic>> verifySellerEmail(String email, String verificationCode) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/verify-seller-email'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'verification_code': verificationCode,
      }),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['detail'] ?? 'Email doğrulanamadı');
    }
  }

  // --- SELLER PHONE VERIFICATION (by seller id) ---
  static Future<Map<String, dynamic>> sendSellerPhoneVerificationBySellerId(int sellerId) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/sellers/$sellerId/send-phone-verification'),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['detail'] ?? 'Doğrulama kodu gönderilemedi');
    }
  }

  // --- USER CRUD ---
  static Future<List<dynamic>> fetchUsers() async {
    final response = await AuthHttp.get(Uri.parse('$baseUrl/users'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Kullanıcılar alınamadı');
    }
  }

  static Future<Map<String, dynamic>> registerUser(Map<String, dynamic> data) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['detail'] ?? 'Kullanıcı eklenemedi');
    }
  }

  static Future<Map<String, dynamic>> registerSeller(Map<String, dynamic> data) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/sellers/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['detail'] ?? 'Satıcı eklenemedi');
    }
  }

  static Future<void> addUser(Map<String, dynamic> data) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Kullanıcı eklenemedi');
    }
  }

  static Future<void> updateUser(int id, Map<String, dynamic> data) async {
    final response = await AuthHttp.put(
      Uri.parse('$baseUrl/users/me'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Kullanıcı güncellenemedi');
    }
  }

  static Future<void> deleteUser(int id) async {
    final response = await AuthHttp.delete(Uri.parse('$baseUrl/users/$id'));
    if (response.statusCode != 200) {
      throw Exception('Kullanıcı silinemedi');
    }
  }

  // --- ADDRESS CRUD ---
  static Future<List<dynamic>> fetchAddresses() async {
    if (Session.currentUser == null) {
      return [];
    }

    try {
      // Önce users_address tablosundan kullanıcının adres ID'lerini al
      final userAddressesResponse = await AuthHttp.get(Uri.parse('$baseUrl/users_address'));
      if (userAddressesResponse.statusCode == 200) {
        final userAddresses = jsonDecode(userAddressesResponse.body) as List;
        final userAddressIds = <int>[];
        
        // Kullanıcının adres ID'lerini topla
        for (final ua in userAddresses) {
          if (ua['user_id'] == Session.currentUser!.id) {
            userAddressIds.add(ua['address_id'] as int);
          }
        }

        if (userAddressIds.isEmpty) {
          return [];
        }

        // Şimdi bu ID'lere sahip adresleri getir
        final addressesResponse = await AuthHttp.get(Uri.parse('$baseUrl/address'));
        if (addressesResponse.statusCode == 200) {
          final allAddresses = jsonDecode(addressesResponse.body) as List;
          final userSpecificAddresses = <dynamic>[];
          
          // Kullanıcının adreslerini filtrele
          for (final address in allAddresses) {
            if (userAddressIds.contains(address['id'] as int)) {
              userSpecificAddresses.add(address);
            }
          }
          
          return userSpecificAddresses;
        } else {
          print('Failed to fetch addresses: ${addressesResponse.statusCode}');
          return [];
        }
      } else {
        print('Failed to fetch user addresses: ${userAddressesResponse.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error in fetchAddresses: ${e.runtimeType}');
      return [];
    }
  }

  static Future<void> addAddress(Map<String, dynamic> data) async {
    // Önce address tablosuna ekle
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/address'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      print('Address creation error: ${response.statusCode}');
      throw Exception('Adres eklenemedi: ${response.body}');
    }

    // Eklenen adresin ID'sini response'dan al
    final createdAddress = jsonDecode(response.body);
    final addressId = createdAddress['id'];
    print('Created address ID: $addressId');

    // Şimdi users_address tablosuna ekle
    if (Session.currentUser != null && Session.currentUser!.id != null) {
      print('Current user ID: ${Session.currentUser!.id}');
      final userAddressData = {
        'user_id': Session.currentUser!.id,
        'address_id': addressId,
      };
      print('Adding to users_address: $userAddressData');
      print('User ID type: ${Session.currentUser!.id.runtimeType}, value: ${Session.currentUser!.id}');
      print('Address ID type: ${addressId.runtimeType}, value: $addressId');

      final userAddressResponse = await AuthHttp.post(
        Uri.parse('$baseUrl/users_address'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(userAddressData),
      );
      print('Response status: ${userAddressResponse.statusCode}');
      if (userAddressResponse.statusCode != 200 && userAddressResponse.statusCode != 201) {
        print('Users address creation error: ${userAddressResponse.statusCode}');
        throw Exception('Kullanıcı adresi eklenemedi: ${userAddressResponse.body}');
      }
      print('Users address created successfully');
    } else {
      print('Session.currentUser is null or user ID is null!');
      print('User session present: ${Session.currentUser != null}');
      if (Session.currentUser != null) {
        print('User ID: ${Session.currentUser!.id}');
      }
      throw Exception('Kullanıcı oturumu bulunamadı veya kullanıcı ID\'si geçersiz');
    }
  }

  static Future<void> updateAddress(int id, Map<String, dynamic> data) async {
    final response = await AuthHttp.put(
      Uri.parse('$baseUrl/address/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Adres güncellenemedi');
    }
  }

  static Future<void> deleteAddress(int id) async {
    final response = await AuthHttp.delete(Uri.parse('$baseUrl/address/$id'));
    if (response.statusCode != 200) {
      throw Exception('Adres silinemedi');
    }
  }

  // --- CREDIT CARD CRUD ---
  static Future<List<dynamic>> fetchCreditCards() async {
    if (Session.currentUser == null) {
      print('Session.currentUser is null');
      return [];
    }

    try {
      print('Fetching credit cards for user: ${Session.currentUser!.id}');
      final cardsResponse = await AuthHttp.get(Uri.parse('$baseUrl/credit_card'));
      if (cardsResponse.statusCode == 200) {
        final allCards = jsonDecode(cardsResponse.body) as List;
        final filtered = allCards.where((c) => c['user_id'] == Session.currentUser!.id).toList();
        return filtered;
      } else {
        print('Failed to fetch credit cards: ${cardsResponse.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error in fetchCreditCards: ${e.runtimeType}');
      return [];
    }
  }

  static Future<void> addCreditCard(Map<String, dynamic> data) async {
    // Güvenlik: client tarafında hassas PAN göndermiyoruz; token gönderiyoruz
    // Backend user_id bekliyor; eklenmediyse mevcut oturumdan set edelim
    if (data['user_id'] == null && Session.currentUser?.id != null) {
      data = Map<String, dynamic>.from(data);
      data['user_id'] = Session.currentUser!.id;
    }
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/credit_card'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Kredi kartı eklenemedi: ${response.body}');
    }

    // Yeni şemada kart user_id ile birlikte saklandığından ek işlem gerekmez
  }

  // --- PAYMENT TOKENIZATION ---
  static Future<Map<String, dynamic>> tokenizeCard({
    required int userId,
    required String cardHolderName,
    required String cardNumber,
    required int expireMonth,
    required int expireYear,
    required String cvc,
  }) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/tokenize'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'card_holder_name': cardHolderName,
        'card_number': cardNumber,
        'expire_month': expireMonth,
        'expire_year': expireYear,
        'cvc': cvc,
      }),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw Exception(body['detail'] ?? 'Kart tokenleştirme başarısız');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> chargePayment({
    required int userId,
    required double price,
    required double paidPrice,
    required String currency,
    required String cardToken,
    int? installment,
    String? basketId,
  }) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/charge'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'price': price,
        'paid_price': paidPrice,
        'currency': currency,
        'card_token': cardToken,
        'installment': installment,
        'basket_id': basketId,
      }),
    );
    final body = jsonDecode(response.body);
    if (response.statusCode != 200 || body['status'] != 'success') {
      throw Exception(body['error_message'] ?? 'Ödeme başarısız');
    }
    return body as Map<String, dynamic>;
  }

  static Future<void> updateCreditCard(int id, Map<String, dynamic> data) async {
    final response = await AuthHttp.put(
      Uri.parse('$baseUrl/credit_card/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Kredi kartı güncellenemedi');
    }
  }

  static Future<void> deleteCreditCard(int id) async {
    final response = await AuthHttp.delete(Uri.parse('$baseUrl/credit_card/$id'));
    if (response.statusCode != 200) {
      throw Exception('Kredi kartı silinemedi');
    }
  }

  // --- ORDER CRUD ---
  static Future<List<dynamic>> fetchOrders() async {
    try {
      print('=== FETCH ORDERS START ===');
      final currentUser = Session.currentUser;
      
      if (currentUser == null) {
        print('Session.currentUser is null!');
        return [];
      }
      
      print('Fetching orders for user ID: ${currentUser.id}');
      
      // Önce kullanıcının sipariş ID'lerini al
      final userOrdersResponse = await AuthHttp.get(Uri.parse('$baseUrl/users_order'));
      print('Users order response status: ${userOrdersResponse.statusCode}');
      
      if (userOrdersResponse.statusCode != 200) {
        throw Exception('Kullanıcı siparişleri alınamadı');
      }
      
      final userOrders = jsonDecode(userOrdersResponse.body) as List;
      print('Users-order records received: ${userOrders.length}');
      
      // Sadece mevcut kullanıcıya ait sipariş ID'lerini filtrele
      final userOrderIds = <int>[];
      for (var userOrder in userOrders) {
        if (userOrder['user_id'] == currentUser.id) {
          userOrderIds.add(userOrder['order_id'] as int);
        }
      }
      
      print('User order IDs: $userOrderIds');
      
      if (userOrderIds.isEmpty) {
        print('No user order IDs found');
        return [];
      }
      
      // Tüm siparişleri al
      final allOrdersResponse = await AuthHttp.get(Uri.parse('$baseUrl/order'));
      print('All orders response status: ${allOrdersResponse.statusCode}');
      
      if (allOrdersResponse.statusCode != 200) {
        throw Exception('Siparişler alınamadı');
      }
      
      final allOrders = jsonDecode(allOrdersResponse.body) as List;
      print('Orders received: ${allOrders.length}');
      
      // Sadece kullanıcıya ait siparişleri filtrele
      final userSpecificOrders = <dynamic>[];
      for (var order in allOrders) {
        if (userOrderIds.contains(order['id'])) {
          userSpecificOrders.add(order);
        }
      }
      
      print('User orders received: ${userSpecificOrders.length}');
      print('=== FETCH ORDERS SUCCESS ===');
      return userSpecificOrders;
    } catch (e) {
      print('=== FETCH ORDERS ERROR ===');
      print('Error fetching orders: ${e.runtimeType}');
      throw Exception('Siparişler alınamadı: $e');
    }
  }

  static Future<void> addOrder(Map<String, dynamic> data, {int? cardId, double? amount, List<dynamic>? cartItems}) async {
    try {
      print('=== ADD ORDER START ===');
      print('Order request received');
      print('Card ID: $cardId, Amount: $amount');
      
      // Order data'ya kart bilgilerini ekle
      final orderData = Map<String, dynamic>.from(data);
      if (cardId != null && amount != null) {
        orderData['card_id'] = cardId;
        orderData['amount'] = amount;
        print('Added card info to order data');
      }
      
      print('Order request prepared');
      
      // Backend'e gönder (transaction içinde para çekme ile birlikte)
      final response = await AuthHttp.post(
        Uri.parse('$baseUrl/order'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(orderData),
      );
      
      print('Response status: ${response.statusCode}');
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Sipariş eklenemedi');
      }

      // Eklenen siparişin ID'sini response'dan al
      final createdOrder = jsonDecode(response.body);
      final orderId = createdOrder['id'];
      print('Created order ID: $orderId');

      // Şimdi users_order tablosuna ekle (her ürün için ayrı kayıt)
      if (Session.currentUser != null && cartItems != null) {
        for (var cartItem in cartItems) {
          final userOrderData = {
            'user_id': Session.currentUser!.id,
            'product_id': cartItem['product']['id'],
            'order_id': orderId,
          };
          print('Adding to users_order: $userOrderData');
          print('JSON being sent: ${jsonEncode(userOrderData)}');

          final userOrderResponse = await AuthHttp.post(
            Uri.parse('$baseUrl/users_order'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(userOrderData),
          );
          print('Users order response status: ${userOrderResponse.statusCode}');
          
          if (userOrderResponse.statusCode != 200 && userOrderResponse.statusCode != 201) {
            throw Exception('Kullanıcı siparişi eklenemedi: ${userOrderResponse.statusCode} - ${userOrderResponse.body}');
          }
          print('Users order created successfully for product ${cartItem['product']['id']}');
        }
      } else {
        print('Session.currentUser is null or cartItems is null!');
        throw Exception('Kullanıcı oturumu bulunamadı');
      }
      
      print('=== ADD ORDER SUCCESS ===');
    } catch (e) {
      print('=== ADD ORDER ERROR ===');
      print('Error adding order: ${e.runtimeType}');
      throw Exception('Sipariş eklenemedi: $e');
    }
  }

  static Future<void> updateOrder(int id, Map<String, dynamic> data) async {
    final response = await AuthHttp.put(
      Uri.parse('$baseUrl/order/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Sipariş güncellenemedi');
    }
  }

  static Future<void> deleteOrder(int id) async {
    final response = await AuthHttp.delete(Uri.parse('$baseUrl/order/$id'));
    if (response.statusCode != 200) {
      throw Exception('Sipariş silinemedi');
    }
  }

  // --- USERS_ADDRESS CRUD ---
  static Future<List<dynamic>> fetchUsersAddresses() async {
    final response = await AuthHttp.get(Uri.parse('$baseUrl/users_address'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Kullanıcı-adres ilişkileri alınamadı');
    }
  }

  static Future<void> addUsersAddress(Map<String, dynamic> data) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/users_address'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Kullanıcı-adres ilişkisi eklenemedi');
    }
  }

  static Future<void> updateUsersAddress(int id, Map<String, dynamic> data) async {
    final response = await AuthHttp.put(
      Uri.parse('$baseUrl/users_address/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Kullanıcı-adres ilişkisi güncellenemedi');
    }
  }

  static Future<void> deleteUsersAddress(int id) async {
    final response = await AuthHttp.delete(Uri.parse('$baseUrl/users_address/$id'));
    if (response.statusCode != 200) {
      throw Exception('Kullanıcı-adres ilişkisi silinemedi');
    }
  }

  // --- USERS_CREDIT_CARD CRUD ---
  static Future<List<dynamic>> fetchUsersCreditCards() async {
    final response = await AuthHttp.get(Uri.parse('$baseUrl/users_credit_card'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Kullanıcı-kredi kartı ilişkileri alınamadı');
    }
  }

  static Future<void> addUsersCreditCard(Map<String, dynamic> data) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/users_credit_card'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Kullanıcı-kredi kartı ilişkisi eklenemedi');
    }
  }

  static Future<void> updateUsersCreditCard(int id, Map<String, dynamic> data) async {
    final response = await AuthHttp.put(
      Uri.parse('$baseUrl/users_credit_card/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Kullanıcı-kredi kartı ilişkisi güncellenemedi');
    }
  }

  static Future<void> deleteUsersCreditCard(int id) async {
    final response = await AuthHttp.delete(Uri.parse('$baseUrl/users_credit_card/$id'));
    if (response.statusCode != 200) {
      throw Exception('Kullanıcı-kredi kartı ilişkisi silinemedi');
    }
  }

  // --- USERS_ORDER CRUD ---
  static Future<List<dynamic>> fetchUsersOrders() async {
    final response = await AuthHttp.get(Uri.parse('$baseUrl/users_order'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Kullanıcı-sipariş ilişkileri alınamadı');
    }
  }

  static Future<void> addUsersOrder(Map<String, dynamic> data) async {
    final response = await AuthHttp.post(
      Uri.parse('$baseUrl/users_order'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Kullanıcı-sipariş ilişkisi eklenemedi');
    }
  }

  static Future<void> updateUsersOrder(int id, Map<String, dynamic> data) async {
    final response = await AuthHttp.put(
      Uri.parse('$baseUrl/users_order/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Kullanıcı-sipariş ilişkisi güncellenemedi');
    }
  }

  static Future<void> deleteUsersOrder(int id) async {
    final response = await AuthHttp.delete(Uri.parse('$baseUrl/users_order/$id'));
    if (response.statusCode != 200) {
      throw Exception('Kullanıcı-sipariş ilişkisi silinemedi');
    }
  }

  static Future<List<int>> fetchUserOrderProductIds(int? orderId, int? userId) async {
    if (orderId == null || userId == null) return [];
    final usersOrders = await fetchUsersOrders();
    return usersOrders
      .where((uo) => uo['order_id'] == orderId && uo['user_id'] == userId)
      .map<int>((uo) => uo['product_id'] as int)
      .toList();
  }

  // --- SELLER ORDERS ---
  static Future<List<dynamic>> fetchSellerOrders(int sellerId) async {
    try {
      print('=== FETCH SELLER ORDERS START ===');
      print('Fetching orders for seller ID: $sellerId');
      
      final response = await AuthHttp.get(Uri.parse('$baseUrl/seller_orders/$sellerId'));
      print('Response status: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        throw Exception('Satıcı siparişleri alınamadı');
      }
      
      final orders = jsonDecode(response.body) as List;
      print('Seller orders received: ${orders.length}');
      print('=== FETCH SELLER ORDERS SUCCESS ===');
      return orders;
    } catch (e) {
      print('=== FETCH SELLER ORDERS ERROR ===');
      print('Error fetching seller orders: ${e.runtimeType}');
      throw Exception('Satıcı siparişleri alınamadı: $e');
    }
  }

  static Future<void> updateSellerOrderStatus(int orderId, String status) async {
    try {
      print('=== UPDATE SELLER ORDER STATUS START ===');
      print('Updating order $orderId to status: $status');
      
      final response = await AuthHttp.put(
        Uri.parse('$baseUrl/seller_orders/$orderId/status?status=$status'),
        headers: {'Content-Type': 'application/json'},
      );
      
      print('Response status: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        throw Exception('Sipariş durumu güncellenemedi');
      }
      
      print('=== UPDATE SELLER ORDER STATUS SUCCESS ===');
    } catch (e) {
      print('=== UPDATE SELLER ORDER STATUS ERROR ===');
      print('Error updating seller order status: ${e.runtimeType}');
      throw Exception('Sipariş durumu güncellenemedi: $e');
    }
  }

  // --- SELLER STATISTICS ---
  static Future<Map<String, dynamic>> fetchSellerStatistics(int sellerId) async {
    try {
      print('=== FETCH SELLER STATISTICS START ===');
      print('Fetching statistics for seller ID: $sellerId');
      
      final response = await AuthHttp.get(Uri.parse('$baseUrl/seller_statistics/$sellerId'));
      print('Response status: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        throw Exception('Satıcı istatistikleri alınamadı');
      }
      
      final statistics = jsonDecode(response.body) as Map<String, dynamic>;
      print('Seller statistics received');
      print('=== FETCH SELLER STATISTICS SUCCESS ===');
      return statistics;
    } catch (e) {
      print('=== FETCH SELLER STATISTICS ERROR ===');
      print('Error fetching seller statistics: ${e.runtimeType}');
      throw Exception('Satıcı istatistikleri alınamadı: $e');
    }
  }

  // --- SELLER ACTIVE ORDERS ---
  static Future<List<dynamic>> fetchSellerActiveOrders(int sellerId) async {
    try {
      print('=== FETCH SELLER ACTIVE ORDERS START ===');
      print('Fetching active orders for seller ID: $sellerId');
      
      final response = await AuthHttp.get(Uri.parse('$baseUrl/seller_active_orders/$sellerId'));
      print('Response status: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        throw Exception('Satıcı aktif siparişleri alınamadı');
      }
      
      final orders = jsonDecode(response.body) as List;
      print('Active seller orders received: ${orders.length}');
      print('=== FETCH SELLER ACTIVE ORDERS SUCCESS ===');
      return orders;
    } catch (e) {
      print('=== FETCH SELLER ACTIVE ORDERS ERROR ===');
      print('Error fetching seller active orders: ${e.runtimeType}');
      throw Exception('Satıcı aktif siparişleri alınamadı: $e');
    }
  }

  // --- PRODUCT REVIEWS ---
  static Future<void> submitProductReview({
    required String productId,
    required int sellerId,
    required int rating,
    required String comment,
  }) async {
    try {
      print('=== SUBMIT PRODUCT REVIEW START ===');
      print('Submitting review for product ID: $productId, seller ID: $sellerId, rating: $rating');
      print('User session present: ${Session.currentUser != null}');
      print('Current user ID: ${Session.currentUser?.id}');
      
      if (Session.currentUser?.id == null) {
        throw Exception('Kullanıcı oturumu bulunamadı');
      }
      
      final requestBody = {
        'product_id': int.parse(productId),
        'seller_id': sellerId,
        'user_id': Session.currentUser!.id,
        'rating': rating,
        'comment': comment,
      };
      
      print('Review request prepared');
      
      final response = await AuthHttp.post(
        Uri.parse('$baseUrl/seller_reviews'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      
      print('Response status: ${response.statusCode}');
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Ürün değerlendirmesi gönderilemedi: ${response.body}');
      }
      
      print('=== SUBMIT PRODUCT REVIEW SUCCESS ===');
    } catch (e) {
      print('=== SUBMIT PRODUCT REVIEW ERROR ===');
      print('Error submitting product review: ${e.runtimeType}');
      throw Exception('Ürün değerlendirmesi gönderilemedi: $e');
    }
  }

  // Get seller reviews
  static Future<List<dynamic>> getSellerReviews({
    int? sellerId,
    int? productId,
  }) async {
    try {
      print('=== GET SELLER REVIEWS START ===');
      
      final queryParams = <String, String>{};
      if (sellerId != null) queryParams['seller_id'] = sellerId.toString();
      if (productId != null) queryParams['product_id'] = productId.toString();
      
      final uri = Uri.parse('$baseUrl/seller_reviews').replace(queryParameters: queryParams);
      final response = await AuthHttp.get(uri);
      
      print('Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final reviews = jsonDecode(response.body) as List;
        print('=== GET SELLER REVIEWS SUCCESS ===');
        return reviews;
      } else {
        throw Exception('Değerlendirmeler alınamadı');
      }
    } catch (e) {
      print('=== GET SELLER REVIEWS ERROR ===');
      print('Error getting seller reviews: ${e.runtimeType}');
      throw Exception('Değerlendirmeler alınamadı: $e');
    }
  }

  // Get user's reviewed product IDs
  static Future<List<int>> fetchUserReviewedProductIds(int userId) async {
    try {
      print('=== FETCH USER REVIEWED PRODUCT IDS START ===');
      print('Fetching reviewed products for user ID: $userId');
      
      final reviews = await getSellerReviews();
      final userReviews = reviews.where((review) => review['user_id'] == userId).toList();
      final productIds = userReviews.map((review) => review['product_id'] as int).toList();
      
      print('User reviewed product IDs: $productIds');
      print('=== FETCH USER REVIEWED PRODUCT IDS SUCCESS ===');
      return productIds;
    } catch (e) {
      print('=== FETCH USER REVIEWED PRODUCT IDS ERROR ===');
      print('Error fetching user reviewed product IDs: ${e.runtimeType}');
      return [];
    }
  }

  // Get product reviews
  static Future<List<dynamic>> getProductReviews(int productId) async {
    try {
      print('=== GET PRODUCT REVIEWS START ===');
      print('Fetching reviews for product ID: $productId');
      
      final reviews = await getSellerReviews(productId: productId);
      
      // Her yorum için kullanıcı bilgilerini al
      final reviewsWithUserInfo = <dynamic>[];
      for (final review in reviews) {
        try {
          final users = await fetchUsers();
          final user = users.firstWhere(
            (user) => user['id'] == review['user_id'],
            orElse: () => {'name_surname': 'Anonim'},
          );
          
          reviewsWithUserInfo.add({
            ...review,
            'user_name': user['name_surname'] ?? 'Anonim',
          });
        } catch (e) {
          reviewsWithUserInfo.add({
            ...review,
            'user_name': 'Anonim',
          });
        }
      }
      
      print('Product reviews received: ${reviewsWithUserInfo.length}');
      print('=== GET PRODUCT REVIEWS SUCCESS ===');
      return reviewsWithUserInfo;
    } catch (e) {
      print('=== GET PRODUCT REVIEWS ERROR ===');
      print('Error getting product reviews: ${e.runtimeType}');
      return [];
    }
  }

  // --- SELLER FOLLOW SYSTEM ---
  
  // Satıcıyı takip et
  static Future<Map<String, dynamic>> followSeller(int userId, int sellerId) async {
    try {
      final response = await AuthHttp.post(
        Uri.parse('$baseUrl/users/$userId/follow-seller/$sellerId'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Satıcı takip edilemedi');
      }
    } catch (e) {
      throw Exception('Takip işlemi başarısız: $e');
    }
  }

  // Satıcıyı takipten çıkar
  static Future<Map<String, dynamic>> unfollowSeller(int userId, int sellerId) async {
    try {
      final response = await AuthHttp.delete(
        Uri.parse('$baseUrl/users/$userId/unfollow-seller/$sellerId'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Takipten çıkarılamadı');
      }
    } catch (e) {
      throw Exception('Takipten çıkarma işlemi başarısız: $e');
    }
  }

  // Kullanıcının takip ettiği satıcıları getir
  static Future<Map<String, dynamic>> getFollowedSellers(int userId) async {
    try {
      final response = await AuthHttp.get(
        Uri.parse('$baseUrl/users/$userId/followed-sellers'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Takip edilen satıcılar getirilemedi');
      }
    } catch (e) {
      throw Exception('Takip edilen satıcılar alınamadı: $e');
    }
  }

  // Satıcının takipçi sayısını getir
  static Future<Map<String, dynamic>> getSellerFollowersCount(int sellerId) async {
    try {
      final response = await AuthHttp.get(
        Uri.parse('$baseUrl/sellers/$sellerId/followers-count'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Takipçi sayısı getirilemedi');
      }
    } catch (e) {
      throw Exception('Takipçi sayısı alınamadı: $e');
    }
  }

  // Kullanıcının satıcıyı takip edip etmediğini kontrol et
  static Future<Map<String, dynamic>> checkIfFollowing(int userId, int sellerId) async {
    try {
      final response = await AuthHttp.get(
        Uri.parse('$baseUrl/users/$userId/is-following/$sellerId'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Takip durumu kontrol edilemedi');
      }
    } catch (e) {
      throw Exception('Takip durumu kontrol edilemedi: $e');
    }
  }
}
