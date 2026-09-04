import 'package:ceptevar/Services/auth_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:ceptevar/Models/User.dart';
import 'package:ceptevar/Models/session.dart';
import 'package:ceptevar/Pages/user/profile/account_info.dart';
import 'package:ceptevar/Pages/user/verification/phone_verification_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const userResponse = {
  'id': 1,
  'name_surname': 'Test Buyer',
  'email': 'buyer@example.com',
  'phone_number': '+90 532 123 45 67',
  'phone_verified': 'verified',
  'email_verified': 'verified',
  'created_at': '2026-01-01T12:00:00',
  'updated_at': '2026-01-01T12:00:00',
};

void main() {
  setUp(() { SharedPreferences.setMockInitialValues({}); AuthSession.userToken = "test-user-token"; });
  tearDown(() => Session.currentUser = null);

  test('password-free responses initialize user lists and sessions', () {
    final users = [userResponse].map(User.fromMap).toList();
    Session.currentUser = users.single;
    expect(Session.currentUser!.password, isEmpty);
    expect(Session.currentUser!.id, 1);
    expect(Session.currentUser!.nameSurname, 'Test Buyer');
    expect(Session.currentUser!.email, 'buyer@example.com');
    expect(Session.currentUser!.phoneNumber, '+90 532 123 45 67');
    expect(Session.currentUser!.phoneVerified, 'verified');
    expect(Session.currentUser!.emailVerified, 'verified');
  });

  for (final cachedPassword in ['', 'legacy-server-hash']) {
    testWidgets('profile save omits password ($cachedPassword)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Session.currentUser = User.fromMap(userResponse);
      Map<String, dynamic>? update;
      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/users/me') {
          return http.Response(
            jsonEncode({
              ...userResponse,
              if (cachedPassword.isNotEmpty) 'password': cachedPassword,
            }),
            200,
          );
        }
        if (request.method == 'PUT' && request.url.path == '/users/me') {
          update = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(userResponse), 200);
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      });
      addTearDown(client.close);

      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: AccountInfoPage()));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Updated Buyer');
        final save = find.text('Değişiklikleri Kaydet');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();

        expect(update, {
          'name_surname': 'Updated Buyer',
          'email': userResponse['email'],
          'phone_number': userResponse['phone_number'],
        });
        expect(Session.currentUser!.password, isEmpty);
      }, () => client);
    });
  }

  testWidgets('profile phone verification needs no registration password', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <String>[];
    final bodies = <dynamic>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      bodies.add(jsonDecode(request.body));
      return http.Response(jsonEncode({'success': true}), 200);
    });
    addTearDown(client.close);

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => const PhoneVerificationPage(
                                  phoneNumber: '+90 532 123 45 67',
                                  userType: 'user',
                                  userData: {},
                                  isRegistration: false,
                                ),
                          ),
                        ),
                    child: const Text('Verify phone'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Verify phone'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(6));
      for (var index = 0; index < 6; index++) {
        await tester.enterText(fields.at(index), '${index + 1}');
      }
      await tester.pumpAndSettle();
      expect(requests, ['POST /verify-phone']);
      expect(bodies, [
        {
          'phone_number': userResponse['phone_number'],
          'verification_code': '123456',
        },
      ]);
      expect(
        find.byType(Dialog),
        findsNothing,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join('\n'),
      );
      expect(find.byType(PhoneVerificationPage), findsNothing);
      expect(find.text('Verify phone'), findsOneWidget);
    }, () => client);
  });

  testWidgets('registration still submits the entered password', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const registration = {
      'name_surname': 'Test Buyer',
      'email': 'buyer@example.com',
      'phone_number': '+90 532 123 45 67',
      'password': 'Entered-password-123!',
    };
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(
          request.url.path == '/verify-phone'
              ? {'success': true}
              : userResponse,
        ),
        200,
      );
    });
    addTearDown(client.close);

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          routes: {'/login': (_) => const Scaffold(body: Text('Login screen'))},
          home: const PhoneVerificationPage(
            phoneNumber: '+90 532 123 45 67',
            userType: 'user',
            userData: registration,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 6; index++) {
        await tester.enterText(
          find.byType(TextField).at(index),
          '${index + 1}',
        );
      }
      await tester.pumpAndSettle();
      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        ['POST /verify-phone', 'POST /users'],
      );
      expect(jsonDecode(requests.last.body), registration);
      expect(find.byType(PhoneVerificationPage), findsNothing);
      expect(find.text('Login screen'), findsOneWidget);
    }, () => client);
  });
}
