import 'dart:convert';
import 'package:ceptevar/Models/session.dart';
import 'package:ceptevar/Models/seller_session.dart';
import 'package:ceptevar/Pages/user/auth/forgot_password.dart';
import 'package:ceptevar/Services/api_service.dart';
import 'package:ceptevar/Services/auth_http.dart';
import 'package:ceptevar/Services/auth_session.dart';
import 'package:ceptevar/Services/seller_api_service.dart';
import 'package:ceptevar/Utils/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const userData = {
  'id': 1,
  'name_surname': 'Buyer',
  'email': 'buyer@example.com',
  'phone_number': '+905320000001',
  'phone_verified': 'verified',
  'email_verified': 'pending',
  'created_at': '2026-01-01T00:00:00',
  'updated_at': '2026-01-01T00:00:00',
};
const sellerData = {
  'id': 1,
  'name': 'Seller',
  'email': 'seller@example.com',
  'phone': '+905330000001',
  'phone_verified': 'verified',
  'email_verified': 'pending',
  'store_name': 'Store',
  'is_verified': 'pending',
  'created_at': '2026-01-01T00:00:00',
  'updated_at': '2026-01-01T00:00:00',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthSession.userToken = null;
    AuthSession.sellerToken = null;
    Session.currentUser = null;
    SellerSession.currentSeller = null;
  });

  test('user login persists credential and self-profile uses bearer', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/users/login') {
        expect(request.bodyFields, {
          'email': 'buyer@example.com',
          'password': 'Private-password-123!',
        });
        return http.Response(
          jsonEncode({
            ...userData,
            'access_token': 'user-credential',
            'token_type': 'bearer',
          }),
          200,
        );
      }
      expect(request.url.path, '/users/me');
      expect(request.headers['Authorization'], 'Bearer user-credential');
      return http.Response(jsonEncode(userData), 200);
    });
    await http.runWithClient(() async {
      final user = await ApiService.loginUser(
        'buyer@example.com',
        'Private-password-123!',
      );
      expect(user.password, isEmpty);
      expect(Session.currentUser?.id, 1);
      expect((await ApiService.fetchMyProfile())['id'], 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_access_token'), 'user-credential');
      expect(prefs.containsKey('user_email'), isFalse);
    }, () => client);
  });

  test(
    'seller login, multipart profile and product mutations select seller credential',
    () async {
      AuthSession.userToken = 'different-user-credential';
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/sellers/login') {
          return http.Response(
            jsonEncode({...sellerData, 'access_token': 'seller-credential'}),
            200,
          );
        }
        expect(request.headers['Authorization'], 'Bearer seller-credential');
        return http.Response(jsonEncode(sellerData), 200);
      });
      await http.runWithClient(() async {
        await SellerApiService.login(
          'seller@example.com',
          'Seller-password-123!',
        );
        await SellerApiService.getProfile();
        await SellerApiService.updateProfile(sellerId: 1, name: 'Updated');
        await ApiService.addProduct({'seller_id': 1});
        await ApiService.updateProduct(1, {'seller_id': 1});
        await ApiService.deleteProduct(1);
        await SellerApiService.verifySellerPhone('+905330000001', '123456');
        await ApiService.updateSellerOrderStatus(1, 'shipped');
      }, () => client);
      expect(
        requests[2].headers['content-type'],
        startsWith('multipart/form-data'),
      );
      expect(requests[2].body, contains('Updated'));
      expect(AuthSession.userToken, 'different-user-credential');
    },
  );

  test(
    'cached email or seller profile alone never restores authentication',
    () async {
      SharedPreferences.setMockInitialValues({
        'user_email': 'buyer@example.com',
        'seller_data': jsonEncode(sellerData),
      });
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{}', 401);
      });
      await http.runWithClient(() async {
        await AuthSession.load();
        expect(AuthSession.userToken, isNull);
        expect(await SellerSession.loadSellerSession(), isNull);
      }, () => client);
      expect(calls, 0);
      expect(Session.currentUser, isNull);
      expect(SellerSession.currentSeller, isNull);
    },
  );

  test('persisted seller identity must pass backend validation', () async {
    SharedPreferences.setMockInitialValues({
      'seller_access_token': 'expired',
      'seller_data': jsonEncode(sellerData),
      'user_access_token': 'user-valid',
    });
    final client = MockClient((request) async {
      expect(request.url.path, '/sellers/profile');
      expect(request.headers['Authorization'], 'Bearer expired');
      return http.Response('{"detail":"expired"}', 401);
    });
    await http.runWithClient(() async {
      expect(await SellerSession.loadSellerSession(), isNull);
    }, () => client);
    expect(AuthSession.sellerToken, isNull);
    expect(AuthSession.userToken, 'user-valid');
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'seller_access_token',
      ),
      isFalse,
    );
  });

  test(
    'password change sends current/new/confirmation and clears session on success',
    () async {
      await AuthSession.save('user', 'user-credential');
      var succeed = false;
      final client = MockClient((request) async {
        expect(request.url.path, '/users/me/password');
        expect(request.headers['Authorization'], 'Bearer user-credential');
        expect(jsonDecode(request.body), {
          'current_password': 'Current-123!',
          'new_password': 'New-password-456!',
          'new_password_again': 'New-password-456!',
        });
        return http.Response('{}', succeed ? 200 : 401);
      });
      await http.runWithClient(() async {
        await expectLater(
          ApiService.changePassword('Current-123!', 'New-password-456!', 'New-password-456!'),
          throwsException,
        );
        expect(AuthSession.userToken, 'user-credential');
        succeed = true;
        await ApiService.changePassword('Current-123!', 'New-password-456!', 'New-password-456!');
      }, () => client);
      expect(AuthSession.userToken, isNull);
      expect(Session.currentUser, isNull);
    },
  );

  testWidgets(
    'forgot-password screen requests phone OTP then submits code and new password',
    (tester) async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('{"success":true}', 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: ForgotPasswordPage()));
        expect(find.byKey(const Key('reset-code')), findsNothing);
        expect(find.text('Ad Soyad'), findsNothing);
        expect(find.text('E-posta'), findsNothing);
        await tester.enterText(
          find.byKey(const Key('reset-phone')),
          '+905320000001',
        );
        await tester.tap(find.text('Kod Gönder'));
        await tester.pumpAndSettle();
        expect(requests.single.url.path, '/auth/forgot-password/request');
        expect(jsonDecode(requests.single.body), {
          'phone_number': '+905320000001',
        });
        await tester.enterText(find.byKey(const Key('reset-code')), '123456');
        await tester.enterText(
          find.byKey(const Key('reset-password')),
          'New-password-456!',
        );
        await tester.ensureVisible(find.text('Şifreyi Sıfırla'));
        await tester.tap(find.text('Şifreyi Sıfırla'));
        await tester.pumpAndSettle();
        expect(requests.last.url.path, '/auth/forgot-password/reset');
        expect(jsonDecode(requests.last.body), {
          'phone_number': '+905320000001',
          'verification_code': '123456',
          'new_password': 'New-password-456!',
        });
        expect(requests.length, 2);
      }, () => client);
    },
  );

  test('authorization is never attached to a different origin', () {
    AuthSession.userToken = 'private-user';
    AuthSession.sellerToken = 'private-seller';
    expect(
      AuthHttp.headers(Uri.parse('https://unrelated.invalid/users/me'), 'GET'),
      isEmpty,
    );
    expect(
      AuthHttp.headers(
        Uri.parse('${AppConfig.baseUrl}/users/me'),
        'GET',
      )['Authorization'],
      'Bearer private-user',
    );
  });
}
