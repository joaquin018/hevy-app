import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/app.dart';
import 'package:hevy_hello/auth_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

class Fixture {
  bool isolated = false;
  String name = 'Sábado brazos';
  int version = 1;
  final patches = <Map<String, dynamic>>[];
  final previousIds = <String?>[];
  Map<String, dynamic>? savedDraft, savedSession, restoredDraft;
  late final client = MockClient((request) async {
    switch (request.url.path) {
      case '/routine-library':
        if (request.method == 'PATCH') {
          final patch = jsonDecode(request.body) as Map<String, dynamic>;
          patches.add(patch);
          final routine = (patch['routines'] as List).single;
          isolated = routine['isolateResults'] as bool? ?? isolated;
          name = routine['name'] as String;
          return json({'version': ++version});
        }
        return json({
          'version': version,
          'folders': [
            {
              'id': 'folder-a',
              'name': 'Plan',
              'routines': [
                {
                  'id': 'routine-a',
                  'name': name,
                  'exercises': ['Press'],
                  'isolateResults': isolated,
                },
                {
                  'id': 'routine-b',
                  'name': 'Lunes',
                  'exercises': ['Press'],
                },
              ],
            },
          ],
        });
      case '/routine-shares/pending':
        return json({'pending': false});
      case '/workout-draft':
        if (request.method == 'PUT') {
          savedDraft = jsonDecode(request.body) as Map<String, dynamic>;
          return json({'saved': true});
        }
        if (request.method == 'DELETE') return json({'deleted': true});
        return restoredDraft == null ? json({}, 404) : json(restoredDraft!);
      case '/exercises/previous':
        final id = request.url.queryParameters['routineId'];
        previousIds.add(id);
        return json({
          'sets': [
            {
              'position': 0,
              'type': 'warmup',
              'kg': id == 'routine-a' ? 22 : 80,
              'reps': 12,
            },
          ],
        });
      case '/exercises/rest-timer':
        return json({'restSeconds': 60});
      case '/workout-settings':
        return json({'betweenExercisesSeconds': 180});
      case '/workout-sessions':
        savedSession = jsonDecode(request.body) as Map<String, dynamic>;
        return json({'id': 'session-a'}, 201);
      default:
        throw StateError('Unexpected request ${request.url}');
    }
  });
}

Future<void> openFolder(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(650, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const HelloApp());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('carpeta-folder-a')));
  await tester.pumpAndSettle();
}

Future<void> options(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey('opciones-rutina-$name')));
  await tester.pumpAndSettle();
}

Future<void> comparison(WidgetTester tester) async {
  await options(tester, 'Sábado brazos');
  await tester.tap(find.text('Comparación de resultados'));
  await tester.pumpAndSettle();
}

Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back));
  await tester.pumpAndSettle();
}

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

  testWidgets(
    'isolation is opt-in, cancellation makes no write and rename preserves it',
    (tester) async {
      final fixture = Fixture();
      await http.runWithClient(() async {
        await openFolder(tester);
        expect(find.byTooltip('Resultados aislados'), findsNothing);
        await comparison(tester);
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse,
        );
        await tester.tap(
          find.byKey(const ValueKey('aislar-resultados-rutina')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(fixture.patches, isEmpty);
        await comparison(tester);
        await tester.tap(
          find.byKey(const ValueKey('aislar-resultados-rutina')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('guardar-aislamiento-rutina')),
        );
        await tester.pumpAndSettle();
        final changed = (fixture.patches.single['routines'] as List).single;
        expect(changed['id'], 'routine-a');
        expect(changed['isolateResults'], isTrue);
        expect(changed.containsKey('exercises'), isFalse);
        expect(find.byTooltip('Resultados aislados'), findsOneWidget);

        await options(tester, 'Sábado brazos');
        await tester.tap(find.text('Cambiar nombre'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('editar-nombre-rutina')),
          'Brazos',
        );
        await tester.tap(find.byKey(const ValueKey('guardar-nombre-rutina')));
        await tester.pumpAndSettle();
        expect(fixture.isolated, isTrue);
        expect(find.byTooltip('Resultados aislados'), findsOneWidget);
        await options(tester, 'Brazos');
        await tester.tap(find.text('Comparación de resultados'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue,
        );
        await tester.tap(
          find.byKey(const ValueKey('aislar-resultados-rutina')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('guardar-aislamiento-rutina')),
        );
        await tester.pumpAndSettle();
        expect(
          (fixture.patches.last['routines'] as List).single['isolateResults'],
          isFalse,
        );
        expect(find.byTooltip('Resultados aislados'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => fixture.client);
    },
  );

  testWidgets(
    'editing each routine requests its own references and does not start a draft',
    (tester) async {
      final fixture = Fixture()..isolated = true;
      await http.runWithClient(() async {
        await openFolder(tester);
        await tester.tap(
          find.byKey(const ValueKey('editar-rutina-Sábado brazos')),
        );
        await tester.pumpAndSettle();
        expect(find.text('22kg x 12'), findsOneWidget);
        expect(fixture.previousIds, ['routine-a']);
        expect(fixture.savedDraft, isNull);
        await tester.tap(find.byKey(const ValueKey('guardar-rutina')));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Resultados aislados'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('editar-rutina-Lunes')));
        await tester.pumpAndSettle();
        expect(find.text('80kg x 12'), findsOneWidget);
        expect(fixture.previousIds, ['routine-a', 'routine-b']);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => fixture.client);
    },
  );

  testWidgets(
    'starting, leaving, resuming and saving keep routine identity and auto-filled results',
    (tester) async {
      final fixture = Fixture()..isolated = true;
      await http.runWithClient(() async {
        await openFolder(tester);
        await tester.tap(
          find.byKey(const ValueKey('iniciar-rutina-Sábado brazos')),
        );
        await tester.pumpAndSettle();
        expect(fixture.savedDraft!['routineId'], 'routine-a');
        await tester.tap(find.byKey(const ValueKey('checkbox-W')));
        await tester.pump();
        await back(tester);
        await comparison(tester);
        await tester.tap(
          find.byKey(const ValueKey('aislar-resultados-rutina')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('guardar-aislamiento-rutina')),
        );
        await tester.pumpAndSettle();
        expect(fixture.patches, isEmpty);
        expect(find.textContaining('Termina o descarta'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('entrenamiento-activo')));
        await tester.pumpAndSettle();
        expect(fixture.previousIds, ['routine-a', 'routine-a']);
        await tester.tap(find.byKey(const ValueKey('finalizar-entrenamiento')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('confirmar-guardar-entrenamiento')),
        );
        await tester.pumpAndSettle();
        expect(fixture.savedSession!['routineId'], 'routine-a');
        expect(fixture.savedSession!['exercises'][0]['sets'][0], {
          'type': 'warmup',
          'kg': 22.0,
          'reps': 12,
          'completed': true,
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => fixture.client);
    },
  );

  testWidgets(
    'a restored draft retains its ID despite a renamed routine and resume from another card',
    (tester) async {
      final fixture = Fixture()..isolated = true;
      fixture.restoredDraft = {
        'routineId': 'routine-a',
        'routineName': 'Nombre anterior',
        'isolateResults': true,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'originalExercises': ['Press'],
        'exercises': [
          {
            'name': 'Press',
            'sets': [
              {'type': 'normal', 'kg': 20, 'reps': 8, 'completed': false},
            ],
          },
        ],
      };
      await http.runWithClient(() async {
        await openFolder(tester);
        await tester.tap(find.byKey(const ValueKey('iniciar-rutina-Lunes')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('retomar-entrenamiento-activo')),
        );
        await tester.pumpAndSettle();
        expect(fixture.previousIds, ['routine-a']);
        expect(fixture.savedDraft!['routineId'], 'routine-a');
        expect(fixture.savedDraft!['routineName'], 'Nombre anterior');
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => fixture.client);
    },
  );
}
