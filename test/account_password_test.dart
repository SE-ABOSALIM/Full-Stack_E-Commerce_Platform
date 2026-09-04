import 'dart:async';
import 'dart:convert';

import 'package:ceptevar/Models/User.dart';
import 'package:ceptevar/Models/session.dart';
import 'package:ceptevar/Pages/user/auth/login.dart';
import 'package:ceptevar/Pages/user/auth/forgot_password.dart';
import 'package:ceptevar/Pages/user/profile/account_info.dart';
import 'package:ceptevar/Pages/user/profile/profile.dart';
import 'package:ceptevar/Services/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const account = {
  'id': 1,
  'name_surname': 'Test Buyer',
  'email': 'buyer@example.com',
  'phone_number': '+905320000001',
  'phone_verified': 'verified',
  'email_verified': 'verified',
  'created_at': '2026-01-01T00:00:00',
  'updated_at': '2026-01-01T00:00:00',
};
const passwordKeys = ['current-password', 'new-password', 'new-password-again'];

Future<void> enterPasswords(
  WidgetTester tester, {
  String confirmation = 'New-password-456!',
}) async {
  final values = ['Current-password-123!', 'New-password-456!', confirmation];
  for (var index = 0; index < passwordKeys.length; index++) {
    final field = find.byKey(Key(passwordKeys[index]));
    await tester.ensureVisible(field);
    await tester.enterText(field, values[index]);
  }
  await tester.ensureVisible(find.byKey(const Key('change-password-submit')));
}

void mobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_access_token': 'user-credential',
    });
    AuthSession.userToken = 'user-credential';
    AuthSession.sellerToken = null;
    Session.currentUser = User.fromMap(account);
  });
  tearDown(() {
    Session.currentUser = null;
    AuthSession.userToken = null;
  });

  testWidgets(
    'profile opens Account Information with integrated password controls only',
    (tester) async {
      mobileViewport(tester);
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/users/me');
        return http.Response(jsonEncode(account), 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ProfileContent())),
        );
        expect(find.text('Şifre Değiştir'), findsNothing);
        await tester.tap(find.text('Hesap Bilgileri'));
        await tester.pumpAndSettle();
        expect(find.byType(AccountInfoPage), findsOneWidget);
        expect(
          find.byKey(const Key('account-password-section')),
          findsOneWidget,
        );
        expect(find.text('Değişiklikleri Kaydet'), findsOneWidget);
        for (final key in passwordKeys) {
          expect(
            tester.widget<TextField>(find.byKey(Key(key))).obscureText,
            isTrue,
          );
        }
        expect(find.text('Yeni Şifre (Tekrar)'), findsWidgets);
        expect(find.text('Şifre Değiştir'), findsOneWidget);
        expect(find.text('Mevcut Şifre'), findsWidgets);
        expect(tester.takeException(), isNull);
      }, () => client);
    },
  );

  testWidgets('confirmation mismatch is rejected before a password request', (
    tester,
  ) async {
    mobileViewport(tester);
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.method, 'GET');
      return http.Response(jsonEncode(account), 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AccountInfoPage()));
      await tester.pumpAndSettle();
      await enterPasswords(tester, confirmation: 'Different-password-789!');
      await tester.tap(find.byKey(const Key('change-password-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Yeni şifreler eşleşmiyor.'), findsOneWidget);
      expect(requests, 1);
      expect(AuthSession.userToken, 'user-credential');
    }, () => client);
  });

  testWidgets(
    'matching confirmation submits three fields, shows success and returns to login',
    (tester) async {
      mobileViewport(tester);
      final response = Completer<http.Response>();
      Map<String, dynamic>? submitted;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode(account), 200);
        }
        expect(request.method, 'PUT');
        expect(request.url.path, '/users/me/password');
        expect(request.headers['Authorization'], 'Bearer user-credential');
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return response.future;
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: AccountInfoPage()));
        await tester.pumpAndSettle();
        await enterPasswords(tester);
        final controllers =
            passwordKeys
                .map(
                  (key) =>
                      tester
                          .widget<TextField>(find.byKey(Key(key)))
                          .controller!,
                )
                .toList();
        await tester.tap(find.byKey(const Key('change-password-submit')));
        await tester.pump();
        expect(submitted, {
          'current_password': 'Current-password-123!',
          'new_password': 'New-password-456!',
          'new_password_again': 'New-password-456!',
        });
        expect(
          tester
              .widget<ElevatedButton>(
                find.byKey(const Key('change-password-submit')),
              )
              .onPressed,
          isNull,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        for (final key in passwordKeys) {
          expect(
            tester.widget<TextField>(find.byKey(Key(key))).enabled,
            isFalse,
          );
        }
        response.complete(http.Response('{"message":"Password changed"}', 200));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Başarılı!'), findsOneWidget);
        expect(
          controllers.every((controller) => controller.text.isEmpty),
          isTrue,
        );
        expect(AuthSession.userToken, isNull);
        expect(Session.currentUser, isNull);
        expect(
          (await SharedPreferences.getInstance()).containsKey(
            'user_access_token',
          ),
          isFalse,
        );
        // The unchanged login footer needs extra width with Flutter's Ahem test font.
        tester.view.physicalSize = const Size(600, 1000);
        await tester.pump();
        await tester.tap(find.text('Giriş Yap'));
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.byType(AccountInfoPage), findsNothing);
        expect(tester.takeException(), isNull);
      }, () => client);
    },
  );

  testWidgets(
    'password fields toggle independently and failed changes use the existing error dialog',
    (tester) async {
      mobileViewport(tester);
      final client = MockClient(
        (request) async =>
            request.method == 'GET'
                ? http.Response(jsonEncode(account), 200)
                : http.Response(
                  '{"detail":"Current password is incorrect"}',
                  401,
                ),
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: AccountInfoPage()));
        await tester.pumpAndSettle();
        await enterPasswords(tester);
        final current = find.byKey(const Key('current-password'));
        await tester.ensureVisible(current);
        await tester.tap(
          find.descendant(of: current, matching: find.byType(IconButton)),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(current).obscureText, isFalse);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('new-password')))
              .obscureText,
          isTrue,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('new-password-again')))
              .obscureText,
          isTrue,
        );
        await tester.ensureVisible(
          find.byKey(const Key('change-password-submit')),
        );
        await tester.tap(find.byKey(const Key('change-password-submit')));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Hata'), findsOneWidget);
        expect(AuthSession.userToken, 'user-credential');
        expect(Session.currentUser?.id, 1);
      }, () => client);
    },
  );

  testWidgets(
    'forgot-password uses the existing loading and error dialog patterns',
    (tester) async {
      mobileViewport(tester);
      final response = Completer<http.Response>();
      final client = MockClient((request) async {
        expect(request.url.path, '/auth/forgot-password/request');
        expect(jsonDecode(request.body), {'phone_number': '+905320000001'});
        return response.future;
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: ForgotPasswordPage()));
        await tester.enterText(
          find.byKey(const Key('reset-phone')),
          '+905320000001',
        );
        await tester.ensureVisible(find.text('Kod Gönder'));
        await tester.tap(find.text('Kod Gönder'));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('reset-phone')))
              .enabled,
          isFalse,
        );
        response.complete(http.Response('{"detail":"Unavailable"}', 503));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Hata'), findsOneWidget);
        expect(find.byKey(const Key('reset-code')), findsNothing);
      }, () => client);
    },
  );
}
