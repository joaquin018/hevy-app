import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/auth_controller.dart';
import 'package:hevy_hello/routine_sharing_page.dart';
import 'package:hevy_hello/workout_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const routine = RoutinePayload(
  id: 'routine-a',
  name: 'Empuje',
  exercises: ['Press'],
);
const folder = RoutineFolderPayload(
  id: 'folder-a',
  name: 'Plan',
  routines: [routine],
);
const library = RoutineLibraryPayload(version: 7, folders: [folder]);
const shareId = 'f08b13ab-b7f8-46cd-92b2-d5a5a0cc7801';
const share = {
  'id': shareId,
  'name': 'Empuje',
  'exerciseCount': 1,
  'senderEmail': 'alice@gmail.com',
  'recipientEmail': 'bob@gmail.com',
  'status': 'pending',
  'createdAt': '2026-10-14T15:00:00Z',
};
Widget app(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: child),
);
http.Response json(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  setUp(
    () => AuthController.instance.session = const UserSession(
      token: '',
      id: 'alice',
      email: 'alice@gmail.com',
    ),
  );
  tearDown(() => AuthController.instance.session = null);

  test('rename sends only the changed routine and preserves exercise rows', () {
    final patch = library.changesTo([
      const RoutineFolderPayload(
        id: 'folder-a',
        name: 'Plan',
        routines: [
          RoutinePayload(
            id: 'routine-a',
            name: 'Mi plan',
            exercises: ['Press'],
          ),
        ],
      ),
    ]);
    expect(patch['version'], 7);
    expect(patch['folders'], isEmpty);
    expect(patch['routines'], [
      {
        'id': 'routine-a',
        'folderId': 'folder-a',
        'name': 'Mi plan',
        'position': 0,
      },
    ]);
    expect(patch['deletedRoutines'], isEmpty);
  });
  test('deleting a folder relies on cascade, while moving its routine preserves identity', () {
    final patch = library.changesTo([
      const RoutineFolderPayload(
        id: 'folder-b',
        name: 'Nueva',
        routines: [routine],
      ),
    ]);
    expect(patch['deletedFolders'], ['folder-a']);
    expect(patch['deletedRoutines'], isEmpty);
    expect((patch['routines'] as List).single['id'], 'routine-a');
    expect(
      (patch['routines'] as List).single.containsKey('exercises'),
      isFalse,
    );
  });
  test('unchanged library makes no HTTP write', () async {
    var calls = 0;
    final api = WorkoutApi(
      client: MockClient((_) async {
        calls++;
        return json({});
      }),
    );
    expect(await api.saveRoutineChanges(library, [folder]), 7);
    expect(calls, 0);
    api.close();
  });
  test(
    'library conflicts propagate instead of appearing as a successful save',
    () async {
      final api = WorkoutApi(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(jsonDecode(request.body)['version'], 7);
          return json({
            'code': 'LIBRARY_CHANGED',
            'message': 'Actualiza la lista',
          }, 409);
        }),
      );
      await expectLater(
        api.saveRoutineChanges(library, []),
        throwsA(
          isA<RoutineApiFailure>().having(
            (e) => e.code,
            'code',
            'LIBRARY_CHANGED',
          ),
        ),
      );
      api.close();
    },
  );
  testWidgets(
    'search waits for three characters, debounces and ignores stale results',
    (tester) async {
      final old = Completer<http.Response>();
      final queries = <String>[];
      final api = WorkoutApi(
        client: MockClient((request) async {
          final q = request.url.queryParameters['q']!;
          queries.add(q);
          if (q == 'ali') return old.future;
          return json([
            {'id': 'bob', 'email': 'bob@gmail.com'},
          ]);
        }),
      );
      await tester.pumpWidget(
        app(
          ShareRoutineDialog(
            api: api,
            routineId: 'r',
            routineName: 'Empuje',
            version: 7,
          ),
        ),
      );
      final field = find.byKey(const ValueKey('correo-destinatario'));
      await tester.enterText(field, 'al');
      await tester.pump(const Duration(milliseconds: 400));
      expect(queries, isEmpty);
      await tester.enterText(field, 'ali');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.enterText(field, 'bob');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('bob@gmail.com'), findsOneWidget);
      old.complete(
        json([
          {'id': 'alice', 'email': 'alice@gmail.com'},
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('alice@gmail.com'), findsNothing);
      expect(queries, ['ali', 'bob']);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );
  testWidgets(
    'sharing requires selection; retries retain the request ID and concurrent clicks cannot resend',
    (tester) async {
      final ids = <String>[];
      final pending = Completer<http.Response>();
      final api = WorkoutApi(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return json([
              {'id': 'bob', 'email': 'bob@gmail.com'},
            ]);
          }
          final body = jsonDecode(request.body);
          ids.add(body['id'] as String);
          expect(body['recipientId'], 'bob');
          expect(body['version'], 7);
          return ids.length == 1
              ? json({'message': 'Intenta otra vez'}, 503)
              : pending.future;
        }),
      );
      await tester.pumpWidget(
        app(
          ShareRoutineDialog(
            api: api,
            routineId: 'r',
            routineName: 'Empuje',
            version: 7,
          ),
        ),
      );
      final sendButton = find.byKey(const ValueKey('enviar-rutina'));
      expect(tester.widget<FilledButton>(sendButton).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('correo-destinatario')),
        'bob',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('destinatario-bob')));
      await tester.pumpAndSettle();
      await tester.tap(sendButton);
      await tester.pumpAndSettle();
      expect(find.text('Intenta otra vez'), findsOneWidget);
      await tester.tap(sendButton);
      await tester.pump();
      expect(tester.widget<FilledButton>(sendButton).onPressed, isNull);
      expect(ids, hasLength(2));
      expect(ids[0], ids[1]);
      pending.complete(json({'id': ids.last, 'status': 'pending'}));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );
  testWidgets(
    'received routine can be previewed and accepted into a selected folder',
    (tester) async {
      bool accepted = false;
      final api = WorkoutApi(
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/routine-shares':
              return json({
                'items': accepted ? [] : [share],
                'nextCursor': null,
              });
            case '/routine-shares/$shareId':
              return json({
                'snapshot': {
                  'name': 'Empuje',
                  'exercises': [
                    {'name': 'Press'},
                  ],
                },
              });
            case '/routine-library':
              return json({
                'version': 0,
                'folders': [
                  {'id': 'mine', 'name': 'Mi carpeta', 'routines': []},
                ],
              });
            case '/routine-shares/$shareId/accept':
              expect(jsonDecode(request.body), {'folderId': 'mine'});
              accepted = true;
              return json({'status': 'accepted'});
            default:
              throw StateError('Unexpected request ${request.url}');
          }
        }),
      );
      await tester.pumpWidget(app(RoutineSharingPage(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver rutina'));
      await tester.pumpAndSettle();
      expect(find.text('Press'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mi carpeta').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('aceptar-rutina')));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
      expect(find.text('No tienes compartidos pendientes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );
}
