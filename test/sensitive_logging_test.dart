import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

import 'package:ceptevar/Models/User.dart';
import 'package:ceptevar/Models/session.dart';
import 'package:ceptevar/Services/api_service.dart';
import 'package:ceptevar/Services/seller_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const password = 'Private-password-789!';
const phone = '+90 532 765 43 21';
const canonicalPhone = '+905327654321';
const email = 'private-buyer@example.com';
const code = '918273';
const token = 'private-payment-token';
const cardNumber = '4111111111111111';
const secretError = '$password $phone $email $code $token private-api-secret';

Future<List<String>> captureLogs(Future<void> Function() action) async {
  final logs = <String>[];
  await runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => logs.add(line),
    ),
  );
  return logs;
}

void expectSafeLogs(List<String> logs) {
  for (final secret in [
    password,
    phone,
    canonicalPhone,
    email,
    code,
    token,
    cardNumber,
    'private-api-secret',
  ]) {
    expect(logs.join('\n'), isNot(contains(secret)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => Session.currentUser = null);

  test(
    'seller login sends credentials without logging request or error data',
    () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode({'detail': secretError}), 401);
      });
      addTearDown(client.close);
      final logs = await captureLogs(
        () => http.runWithClient(() async {
          await expectLater(
            SellerApiService.login(email, password),
            throwsException,
          );
        }, () => client),
      );
      expect(Uri.splitQueryString(sent.body), {
        'email': email,
        'password': password,
      });
      expect(sent.url.path, '/sellers/login');
      expectSafeLogs(logs);
      expect(logs.join('\n'), contains('401'));
      expect(logs.join('\n'), contains('Exception'));
    },
  );

  test(
    'seller verification retains phone and code only in HTTP payloads',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'success': true, 'message': secretError}),
          200,
        );
      });
      addTearDown(client.close);
      final logs = await captureLogs(
        () => http.runWithClient(() async {
          final sent = await SellerApiService.sendSellerVerificationCode(
            phone,
            language: 'tr',
          );
          final verified = await SellerApiService.verifySellerPhone(
            phone,
            code,
          );
          expect(sent['success'], isTrue);
          expect(verified['success'], isTrue);
          expect(verified['message'], secretError);
        }, () => client),
      );
      expect(requests.map((request) => request.url.path), [
        '/send-seller-verification-code',
        '/verify-seller-phone',
      ]);
      expect(jsonDecode(requests[0].body), {
        'phone_number': canonicalPhone,
        'language': 'tr',
      });
      expect(jsonDecode(requests[1].body), {
        'phone_number': canonicalPhone,
        'verification_code': code,
      });
      expectSafeLogs(logs);
      expect(logs.join('\n'), contains('200'));
    },
  );

  test('card response parsing errors do not log payment credentials', () async {
    Session.currentUser = const User(
      id: 1,
      nameSurname: 'Buyer',
      password: '',
      email: email,
      phoneNumber: phone,
    );
    final client = MockClient(
      (request) async => http.Response('$secretError $cardNumber', 200),
    );
    addTearDown(client.close);
    final logs = await captureLogs(
      () => http.runWithClient(() async {
        expect(await ApiService.fetchCreditCards(), isEmpty);
      }, () => client),
    );
    expectSafeLogs(logs);
    expect(logs.join('\n'), contains('FormatException'));
  });

  test(
    'tokenization and payment requests still carry required credentials',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(
            request.url.path == '/tokenize'
                ? {
                  'card_token': token,
                  'card_brand': 'visa',
                  'last4': '1111',
                  'expiry_month': 12,
                  'expiry_year': 2030,
                }
                : {'status': 'success', 'payment_id': 'payment-test'},
          ),
          200,
        );
      });
      addTearDown(client.close);
      final logs = await captureLogs(
        () => http.runWithClient(() async {
          final card = await ApiService.tokenizeCard(
            userId: 1,
            cardHolderName: 'Buyer',
            cardNumber: cardNumber,
            expireMonth: 12,
            expireYear: 2030,
            cvc: '735',
          );
          expect(card['card_token'], token);
          final charge = await ApiService.chargePayment(
            userId: 1,
            price: 20,
            paidPrice: 20,
            currency: 'TRY',
            cardToken: card['card_token'],
          );
          expect(charge['status'], 'success');
        }, () => client),
      );
      expect(requests.map((request) => request.url.path), [
        '/tokenize',
        '/charge',
      ]);
      final cardPayload = jsonDecode(requests[0].body) as Map<String, dynamic>;
      expect(cardPayload['card_number'], cardNumber);
      expect(cardPayload['cvc'], '735');
      final chargePayload =
          jsonDecode(requests[1].body) as Map<String, dynamic>;
      expect(chargePayload['card_token'], token);
      expect(chargePayload['paid_price'], 20);
      expectSafeLogs(logs);
      expect(logs.join('\n'), isNot(contains('735')));
    },
  );
}
