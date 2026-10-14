import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/auth_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const alice = UserSession(token: '', id: 'alice', email: 'alice@example.com');
  const bob = UserSession(token: '', id: 'bob', email: 'bob@example.com');
  final auth = AuthController.instance;

  setUp(() {
    auth.session = alice;
    auth.error = null;
    auth.onSessionEnded = null;
  });
  tearDown(() {
    auth.session = null;
    auth.error = null;
    auth.onSessionEnded = null;
  });

  test('cookie requests carry the account displayed in the tab', () async {
    final client = AuthenticatedClient(
      MockClient((request) async {
        expect(request.headers['x-i7l-user'], 'alice');
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response('[]', 200);
      }),
      alice,
    );
    expect(
      (await client.get(Uri.parse('https://app.i7l.cl/api/exercises')))
          .statusCode,
      200,
    );
    client.close();
  });

  test('an old client never sends work under a new account', () async {
    var sent = false;
    final client = AuthenticatedClient(
      MockClient((_) async {
        sent = true;
        return http.Response('{}', 200);
      }),
      alice,
    );
    auth.session = bob;
    await expectLater(
      client.put(Uri.parse('https://app.i7l.cl/api/workout-draft')),
      throwsA(isA<AuthFailure>()),
    );
    expect(sent, isFalse);
    expect(auth.session, same(bob));
    client.close();
  });

  test(
    'a pending response from the old account cannot populate the new UI',
    () async {
      final response = Completer<http.Response>();
      final sent = Completer<void>();
      final client = AuthenticatedClient(
        MockClient((_) {
          sent.complete();
          return response.future;
        }),
        alice,
      );
      final pending = client.get(Uri.parse('https://app.i7l.cl/api/exercises'));
      final assertion = expectLater(pending, throwsA(isA<AuthFailure>()));
      await sent.future;
      auth.session = bob;
      response.complete(http.Response('[]', 401));
      await assertion;
      expect(auth.session, same(bob));
      client.close();
    },
  );

  test(
    'server detects a cookie changed in another tab and clears local data',
    () async {
      var cleared = false;
      auth.onSessionEnded = () => cleared = true;
      final client = AuthenticatedClient(
        MockClient(
          (_) async => http.Response('{"code":"SESSION_CHANGED"}', 409),
        ),
        alice,
      );
      await expectLater(
        client.get(Uri.parse('https://app.i7l.cl/api/exercises')),
        throwsA(isA<AuthFailure>()),
      );
      expect(auth.session, isNull);
      expect(cleared, isTrue);
      client.close();
    },
  );
}
