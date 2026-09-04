import 'dart:convert';

import 'package:ceptevar/Models/User.dart';
import 'package:ceptevar/Models/session.dart';
import 'package:ceptevar/Pages/user/profile/account_info.dart';
import 'package:ceptevar/Services/api_service.dart';
import 'package:ceptevar/Services/auth_session.dart';
import 'package:ceptevar/Services/seller_api_service.dart';
import 'package:ceptevar/Utils/phone_number.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const canonicalPhone = '+905556667711';
const equivalentTurkishPhones = [
  '+90 555 666 77 11',
  '+905556667711',
  '0555 666 77 11',
  '05556667711',
  '555 666 77 11',
  '5556667711',
  '0555-666-77-11',
  '(0555) 666 77 11',
  '+90 (555) 666 77 11',
];

const profileResponse = {
  'id': 1,
  'name_surname': 'Phone User',
  'email': 'phone@example.com',
  'phone_number': '+90 555 666 77 11',
  'phone_verified': 'verified',
  'email_verified': 'verified',
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
  });

  for (final phone in equivalentTurkishPhones) {
    test('$phone has the canonical account identity', () {
      expect(normalizePhoneNumber(phone), canonicalPhone);
      expect(isValidPhoneNumber(phone), isTrue);
    });
  }

  test(
    'invalid input is rejected and explicit international input is kept',
    () {
      for (final phone in ['555', '055566677110', '+9005556667711', 'phone']) {
        expect(normalizePhoneNumber(phone), isNull);
      }
      expect(normalizePhoneNumber('+1 (415) 555-2671'), '+14155552671');
      expect(samePhoneIdentity('0555 666 77 11', canonicalPhone), isTrue);
    },
  );

  test(
    'verification and password-reset requests send canonical phones',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('{"success":true}', 200);
      });

      await http.runWithClient(() async {
        await ApiService.sendVerificationCode('0555 666 77 11');
        await ApiService.verifyPhone('+90 (555) 666 77 11', '123456');
        await ApiService.requestPasswordReset('555-666-77-11');
        await ApiService.resetPassword(
          '(0555) 666 77 11',
          '123456',
          'password',
        );
        await SellerApiService.sendSellerVerificationCode('05556667711');
        await SellerApiService.verifySellerPhone('555 666 77 11', '654321');
      }, () => client);

      expect(requests.length, 6);
      for (final request in requests) {
        expect(
          (jsonDecode(request.body) as Map<String, dynamic>)['phone_number'],
          canonicalPhone,
        );
      }
    },
  );

  test('user and seller signup services send canonical phones', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/users') {
        return http.Response(jsonEncode(profileResponse), 200);
      }
      return http.Response(
        jsonEncode({
          'id': 1,
          'name': 'Seller',
          'email': 'seller@example.com',
          'phone': canonicalPhone,
          'phone_verified': 'verified',
          'email_verified': 'pending',
          'store_name': 'Store',
          'is_verified': 'pending',
          'created_at': '2026-01-01T00:00:00',
          'updated_at': '2026-01-01T00:00:00',
        }),
        200,
      );
    });

    await http.runWithClient(() async {
      await ApiService.registerUser({
        'name_surname': 'User',
        'email': 'user@example.com',
        'password': 'password',
        'phone_number': '0555 666 77 11',
      });
      await SellerApiService.signup(
        name: 'Seller',
        email: 'seller@example.com',
        password: 'password',
        phone: '+90 (555) 666 77 11',
        storeName: 'Store',
      );
    }, () => client);

    expect(jsonDecode(requests.first.body)['phone_number'], canonicalPhone);
    expect(requests.last.body, contains(canonicalPhone));
    expect(requests.last.body, isNot(contains('+90 (555) 666 77 11')));
  });

  testWidgets(
    'account info treats a formatting-only edit as the same verified phone',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Session.currentUser = User.fromMap(profileResponse);
      Map<String, dynamic>? update;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode(profileResponse), 200);
        }
        update = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({...profileResponse, 'phone_number': canonicalPhone}),
          200,
        );
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: AccountInfoPage()));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(2), '05556667711');
        final save = find.text('Değişiklikleri Kaydet');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
      }, () => client);

      expect(update?['phone_number'], canonicalPhone);
      expect(Session.currentUser?.phoneNumber, canonicalPhone);
      expect(Session.currentUser?.phoneVerified, 'verified');
      expect(find.text('Telefon numarası değiştirilecek'), findsNothing);
    },
  );
}
