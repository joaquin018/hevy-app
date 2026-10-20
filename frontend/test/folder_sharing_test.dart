import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/app.dart';
import 'package:hevy_hello/auth_controller.dart';
import 'package:hevy_hello/routine_sharing_page.dart';
import 'package:hevy_hello/workout_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
Widget app(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: child),
);
const shareId = 'f08b13ab-b7f8-46cd-92b2-d5a5a0cc7801';

void main() {
  setUp(() {
    clearActiveWorkout();
    AuthController.instance.session = const UserSession(
      token: '',
      id: 'alice',
      email: 'alice@gmail.com',
    );
  });
  tearDown(() {
    clearActiveWorkout();
    AuthController.instance.session = null;
  });

  testWidgets('folder sharing requires selection and preserves retry IDs', (
    tester,
  ) async {
    final ids = <String>[];
    final pending = Completer<http.Response>();
    final api = WorkoutApi(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return json([
            {'id': 'bob', 'email': 'bob@gmail.com'},
          ]);
        }
        expect(request.url.path, '/folder-shares');
        final body = jsonDecode(request.body);
        expect(body['folderId'], 'folder-a');
        expect(body.containsKey('routineId'), isFalse);
        expect(body['recipientId'], 'bob');
        expect(body['version'], 7);
        ids.add(body['id'] as String);
        return ids.length == 1
            ? json({'message': 'Intenta otra vez'}, 503)
            : pending.future;
      }),
    );
    await tester.pumpWidget(
      app(
        ShareRoutineDialog.folder(
          api: api,
          folderId: 'folder-a',
          folderName: 'Semana',
          version: 7,
        ),
      ),
    );
    final send = find.widgetWithText(FilledButton, 'Enviar carpeta');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('correo-destinatario')),
      'bob',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('destinatario-bob')));
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('Intenta otra vez'), findsOneWidget);
    await tester.tap(send);
    await tester.pump();
    expect(ids, hasLength(2));
    expect(ids[0], ids[1]);
    expect(find.text('Enviando…'), findsOneWidget);
    pending.complete(json({'id': ids.last, 'status': 'pending'}));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
  });

  testWidgets('folder options open the folder sharing dialog', (tester) async {
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/routine-library':
          return json({
            'version': 7,
            'folders': [
              {
                'id': 'folder-a',
                'name': 'Plan',
                'routines': [
                  {
                    'id': 'routine-a',
                    'name': 'Empuje',
                    'exercises': ['Press'],
                  },
                ],
              },
            ],
          });
        case '/workout-draft':
          return json({}, 404);
        case '/routine-shares/pending':
          expect(request.url.queryParameters['includeFolders'], 'true');
          return json({'pending': false});
        default:
          throw StateError('Unexpected request ${request.url}');
      }
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const HelloApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('opciones-carpeta-folder-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compartir carpeta'));
      await tester.pumpAndSettle();
      expect(find.text('Compartir carpeta'), findsOneWidget);
      expect(find.text('Enviar carpeta'), findsOneWidget);
      expect(find.text('Plan'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
    client.close();
  });

  testWidgets(
    'received folder previews every routine and imports as a new folder',
    (tester) async {
      var accepted = false;
      var acceptAttempts = 0;
      final api = WorkoutApi(
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/routine-shares':
              expect(request.url.queryParameters['includeFolders'], 'true');
              return json({
                'items': accepted
                    ? []
                    : [
                        {
                          'id': shareId,
                          'name': 'Semana',
                          'kind': 'folder',
                          'routineCount': 3,
                          'exerciseCount': 2,
                          'senderEmail': 'alice@gmail.com',
                          'recipientEmail': 'bob@gmail.com',
                          'status': 'pending',
                          'createdAt': '2026-10-20T15:00:00Z',
                        },
                      ],
                'nextCursor': null,
              });
            case '/routine-shares/$shareId':
              return json({
                'snapshot': {
                  'version': 2,
                  'name': 'Semana',
                  'routines': [
                    {
                      'name': 'Empuje',
                      'exercises': [
                        {'name': 'Press'},
                      ],
                    },
                    {
                      'name': 'Tirón',
                      'exercises': [
                        {'name': 'Remo'},
                      ],
                    },
                    {'name': 'Descanso', 'exercises': []},
                  ],
                },
              });
            case '/routine-shares/$shareId/accept':
              expect(jsonDecode(request.body), isEmpty);
              acceptAttempts++;
              if (acceptAttempts == 1) {
                return json({'message': 'Intenta aceptar otra vez'}, 503);
              }
              accepted = true;
              return json({'status': 'accepted', 'folderId': 'new-folder'});
            default:
              throw StateError('Unexpected request ${request.url}');
          }
        }),
      );
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(RoutineSharingPage(api: api)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Carpeta · 3 rutinas'), findsOneWidget);
      await tester.tap(find.text('Ver carpeta'));
      await tester.pumpAndSettle();
      for (final name in [
        'Empuje',
        'Press',
        'Tirón',
        'Remo',
        'Descanso',
        'Sin ejercicios',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.tap(find.byKey(const ValueKey('aceptar-carpeta')));
      await tester.pumpAndSettle();
      expect(find.text('Intenta aceptar otra vez'), findsOneWidget);
      expect(accepted, isFalse);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
      expect(acceptAttempts, 2);
      expect(find.text('No tienes compartidos pendientes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );
}
