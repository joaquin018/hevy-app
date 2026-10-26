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
  final betweenSeconds = {'Press': 180, 'Remo': 180};
  bool failRead = false, failSave = false;
  final savedTransitions = <int>[];
  final setSeconds = {'Press': 60, 'Remo': 120};
  late final client = MockClient((request) async {
    switch (request.url.path) {
      case '/exercises/rest-timer':
        final name = request.url.queryParameters['name'];
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body);
          if (body['kind'] == 'exercises') {
            if (failSave) return json({}, 503);
            betweenSeconds[body['name'] as String] = body['restSeconds'] as int;
            savedTransitions.add(body['restSeconds'] as int);
          } else {
            setSeconds[body['name'] as String] = body['restSeconds'] as int;
          }
          return json({'restSeconds': body['restSeconds']});
        }
        if (request.url.queryParameters['kind'] == 'exercises') {
          if (failRead) return json({}, 503);
          return json({'restSeconds': betweenSeconds[name]});
        }
        return json({'restSeconds': setSeconds[name]});
      case '/exercises/previous':
        return json({
          'sets': [
            {'type': 'warmup', 'kg': 1, 'reps': 12},
            {'type': 'normal', 'kg': 2, 'reps': 10},
            {'type': 'normal', 'kg': 2, 'reps': 8},
          ],
        });
      case '/routine-library':
        return json({
          'version': 1,
          'folders': [
            {
              'id': 'folder-a',
              'name': 'Plan',
              'routines': [
                {
                  'id': 'routine-a',
                  'name': 'Empuje',
                  'exercises': ['Press', 'Remo'],
                },
                {
                  'id': 'routine-b',
                  'name': 'Piernas',
                  'exercises': ['Press', 'Remo'],
                },
              ],
            },
          ],
        });
      case '/routine-shares/pending':
        return json({'pending': false});
      case '/workout-draft':
        return json({}, request.method == 'GET' ? 404 : 200);
      default:
        throw StateError('Unexpected request ${request.url}');
    }
  });
}

Finder card(String name) =>
    find.byKey(ValueKey('ejercicio-activo-${name == 'Press' ? 0 : 1}-$name'));
Finder check(String name, String set) => find.descendant(
  of: card(name),
  matching: find.byKey(ValueKey('checkbox-$set')),
);
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const HelloApp());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('carpeta-folder-a')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('iniciar-rutina-Empuje')));
  await tester.pumpAndSettle();
}

Future<void> complete(WidgetTester tester, String name) async {
  for (final label in ['W', '2', '3']) {
    await tap(tester, check(name, label));
  }
}

Future<void> configure(WidgetTester tester, String name, int index) async {
  await tap(tester, find.byKey(ValueKey('temporizador-$name')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Entre ejercicios').last);
  await tester.pumpAndSettle();
  final wheel = tester.widget<ListWheelScrollView>(
    find.byType(ListWheelScrollView),
  );
  (wheel.controller! as FixedExtentScrollController).jumpToItem(index);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Listo'));
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
    'only completing every set, including warmups, starts three minutes between exercises',
    (tester) async {
      final fixture = Fixture();
      await http.runWithClient(() async {
        await open(tester);
        await tap(tester, check('Press', '3'));
        expect(find.text('01:00'), findsOneWidget);
        expect(find.text('Entre series'), findsOneWidget);
        await tap(tester, check('Press', '2'));
        expect(find.text('01:00'), findsOneWidget);
        await tap(tester, check('Press', 'W'));
        expect(find.text('03:00'), findsOneWidget);
        expect(find.text('Entre ejercicios'), findsOneWidget);
        await tap(tester, check('Remo', 'W'));
        expect(find.text('02:00'), findsOneWidget);
        expect(find.text('Entre series'), findsOneWidget);
        await tap(tester, check('Remo', '3'));
        expect(find.text('02:00'), findsOneWidget);
        await tap(tester, check('Remo', '2'));
        expect(find.text('03:00'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => fixture.client);
    },
  );

  testWidgets(
    'undoing completion or adding a pending set cancels between-exercise rest',
    (tester) async {
      final fixture = Fixture();
      await http.runWithClient(() async {
        await open(tester);
        await complete(tester, 'Press');
        await tap(tester, check('Press', '2'));
        expect(find.text('+15'), findsNothing);
        await tap(tester, check('Press', '2'));
        expect(find.text('03:00'), findsOneWidget);
        await tap(tester, find.byKey(const ValueKey('añadir-serie-Press')));
        expect(find.text('+15'), findsNothing);
        await tap(tester, check('Press', '4'));
        expect(find.text('03:00'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => fixture.client);
    },
  );

  testWidgets(
    'each exercise has separate set and transition rests without affecting another exercise',
    (tester) async {
      final fixture = Fixture();
      await http.runWithClient(() async {
        await open(tester);
        await configure(tester, 'Press', 1); // 1 min 30s.
        expect(fixture.savedTransitions, [90]);
        expect(fixture.betweenSeconds, {'Press': 90, 'Remo': 180});
        expect(fixture.setSeconds, {'Press': 60, 'Remo': 120});
        await complete(tester, 'Press');
        expect(find.text('01:30'), findsOneWidget);
        await tap(tester, find.byKey(const ValueKey('temporizador-Remo')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Entre ejercicios').last);
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(find.text('3:00 min')).style!.fontSize, 20);
        expect(find.text('Rutina: Empuje'), findsNothing);
        final wheel = tester.widget<ListWheelScrollView>(
          find.byType(ListWheelScrollView),
        );
        (wheel.controller! as FixedExtentScrollController).jumpToItem(8);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Listo'));
        await tester.pumpAndSettle();
        expect(fixture.savedTransitions, [90, 300]);
        expect(fixture.betweenSeconds, {'Press': 90, 'Remo': 300});
        await tap(tester, check('Press', '3'));
        await tap(tester, check('Press', '3'));
        expect(find.text('01:30'), findsOneWidget);
        await complete(tester, 'Remo');
        expect(find.text('05:00'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => fixture.client);
    },
  );

  testWidgets(
    'exercise preferences persist across routines just like set rests',
    (tester) async {
      final fixture = Fixture();
      await http.runWithClient(() async {
        await open(tester);
        await configure(tester, 'Press', 1);
        expect(fixture.betweenSeconds['Press'], 90);
        for (final entry in [('Piernas', '01:30'), ('Empuje', '01:30')]) {
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('iniciar-rutina-${entry.$1}')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('iniciar-nuevo-entrenamiento')),
          );
          await tester.pumpAndSettle();
          await complete(tester, 'Press');
          expect(find.text(entry.$2), findsOneWidget);
        }
        expect(fixture.betweenSeconds['Remo'], 180);
        expect(fixture.setSeconds, {'Press': 60, 'Remo': 120});
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => fixture.client);
    },
  );

  testWidgets(
    'saved exercise rest and its label survive leaving, adjusting and resuming',
    (tester) async {
      final fixture = Fixture();
      fixture.betweenSeconds['Press'] = 90;
      await http.runWithClient(() async {
        await open(tester);
        await complete(tester, 'Press');
        expect(find.text('01:30'), findsOneWidget);
        await tester.tap(find.text('+15'));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('entrenamiento-activo')));
        await tester.pumpAndSettle();
        expect(find.text('01:45'), findsOneWidget);
        expect(find.text('Entre ejercicios'), findsOneWidget);
        await tester.tap(find.text('-15'));
        await tester.pump();
        expect(find.text('01:30'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => fixture.client);
    },
  );

  testWidgets(
    'failed configuration keeps the previous value and failed loading uses three minutes',
    (tester) async {
      final fixture = Fixture()
        ..failSave = true
        ..failRead = true;
      await http.runWithClient(() async {
        await open(tester);
        await configure(tester, 'Press', 0);
        expect(
          find.text('No se pudo guardar el tiempo de descanso.'),
          findsOneWidget,
        );
        expect(fixture.savedTransitions, isEmpty);
        await complete(tester, 'Press');
        expect(find.text('03:00'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => fixture.client);
    },
  );

  testWidgets('editing a routine never starts either timer', (tester) async {
    final fixture = Fixture();
    await http.runWithClient(() async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const WorkoutPage(
            isEditing: true,
            initialExercises: ['Press', 'Remo'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await configure(tester, 'Press', 1);
      expect(fixture.betweenSeconds['Press'], 90);
      await complete(tester, 'Press');
      expect(find.text('+15'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => fixture.client);
  });
}
