import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/app.dart';
import 'package:hevy_hello/workout_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

Future<void> _openWorkout(
  WidgetTester tester, {
  Map<String, List<WorkoutSetPayload>> results = const {},
  bool resuming = false,
  bool editing = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WorkoutPage(
                  initialExercises: const ['Press'],
                  isEditing: editing,
                  routineName: 'Empuje',
                  resumeStartedAt: resuming ? DateTime.now() : null,
                  initialResults: results,
                ),
              ),
            ),
            child: const Text('Iniciar'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Iniciar'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(clearActiveWorkout);
  tearDown(clearActiveWorkout);

  testWidgets(
    'editing a routine loads previous results without starting a workout',
    (tester) async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/exercises/previous') {
          expect(request.url.queryParameters['name'], 'Press');
          return _json({
            'sets': [
              {'type': 'warmup', 'kg': 22, 'reps': 12},
              {'type': 'warmup', 'kg': 34, 'reps': 6},
              {'type': 'normal', 'kg': 58, 'reps': 9},
              {'type': 'normal', 'kg': 58, 'reps': 5},
            ],
          });
        }
        return _json({'restSeconds': 60});
      });
      await http.runWithClient(() async {
        await _openWorkout(tester, editing: true);
        expect(find.text('Editar Empuje'), findsOneWidget);
        expect(find.text('W'), findsNWidgets(2));
        expect(find.text('3'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
        for (final result in [
          '22kg x 12',
          '34kg x 6',
          '58kg x 9',
          '58kg x 5',
        ]) {
          expect(find.text(result), findsOneWidget);
        }
        final fields = tester.widgetList<TextField>(find.byType(TextField));
        expect(
          fields.map((field) => field.controller!.text),
          everyElement(isEmpty),
        );
        expect(fields.map((field) => field.decoration!.hintText), [
          '22',
          '12',
          '34',
          '6',
          '58',
          '9',
          '58',
          '5',
        ]);
        await tester.tap(find.byKey(const ValueKey('checkbox-W')).first);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('guardar-rutina')));
        await tester.pumpAndSettle();
        expect(find.text('Iniciar'), findsOneWidget);
        expect(
          requests.where(
            (request) => request.url.path == '/exercises/previous',
          ),
          hasLength(1),
        );
        expect(requests.map((request) => request.method), everyElement('GET'));
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => client);
    },
  );

  testWidgets(
    'a routine without previous results keeps an empty editable set',
    (tester) async {
      final client = MockClient((request) async {
        if (request.url.path == '/exercises/previous') {
          return http.Response('{}', 404);
        }
        return _json({'restSeconds': 60});
      });
      await http.runWithClient(() async {
        await _openWorkout(tester, editing: true);
        expect(find.byKey(const ValueKey('checkbox-1')), findsOneWidget);
        expect(find.text('—'), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('kg-1')), '20');
        await tester.enterText(
          find.byKey(const ValueKey('repeticiones-1')),
          '10',
        );
        await tester.tap(find.byKey(const ValueKey('guardar-rutina')));
        await tester.pumpAndSettle();
        expect(find.text('Iniciar'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => client);
    },
  );

  testWidgets('previous set types keep their labels when loaded and saved', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    final client = MockClient((request) async {
      if (request.url.path == '/exercises/previous') {
        return _json({
          'sets': [
            {'type': 'warmup', 'kg': 10, 'reps': 10},
            {'type': 'normal', 'kg': 40, 'reps': 10},
            {'type': 'failure', 'kg': 30, 'reps': 10},
            {'type': 'drop', 'kg': 20, 'reps': 10},
          ],
        });
      }
      if (request.url.path == '/workout-sessions') {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
      }
      return _json({'restSeconds': 60});
    });
    await http.runWithClient(() async {
      await _openWorkout(tester);
      for (final label in ['W', '2', 'F', 'D']) {
        expect(find.text(label), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('checkbox-$label')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('finalizar-entrenamiento')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirmar-guardar-entrenamiento')),
      );
      await tester.pumpAndSettle();
      final sets = saved!['exercises'][0]['sets'] as List;
      expect(sets.map((set) => set['type']), [
        'warmup',
        'normal',
        'failure',
        'drop',
      ]);
      expect(sets.first['kg'], 10);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });

  testWidgets('resuming keeps the draft type over the previous workout type', (
    tester,
  ) async {
    final client = MockClient((request) async {
      return _json(
        request.url.path == '/exercises/previous'
            ? {
                'sets': [
                  {'type': 'normal', 'kg': 40, 'reps': 10},
                ],
              }
            : {'restSeconds': 60},
      );
    });
    await http.runWithClient(() async {
      await _openWorkout(
        tester,
        resuming: true,
        results: const {
          'Press': [
            WorkoutSetPayload(
              type: 'warmup',
              kg: 10,
              reps: 10,
              completed: false,
              kgInput: '10',
              repsInput: '10',
            ),
          ],
        },
      );
      expect(find.text('W'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });

  testWidgets('late previous sets do not replace a type selected by the user', (
    tester,
  ) async {
    final previous = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.path == '/exercises/previous') return previous.future;
      return _json({'restSeconds': 60});
    });
    await http.runWithClient(() async {
      await _openWorkout(tester);
      await tester.tap(find.text('1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Serie normal'));
      await tester.pumpAndSettle();
      previous.complete(
        _json({
          'sets': [
            {'type': 'warmup', 'kg': 10, 'reps': 10},
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('W'), findsNothing);
      expect(find.byKey(const ValueKey('checkbox-1')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });

  testWidgets('restored special sets can be changed back to normal sets', (
    tester,
  ) async {
    final client = MockClient(
      (request) async => _json(
        request.url.path == '/exercises/previous'
            ? {'sets': []}
            : {'restSeconds': 60},
      ),
    );
    await http.runWithClient(() async {
      await _openWorkout(
        tester,
        resuming: true,
        results: {
          'Press': [
            for (final type in ['warmup', 'failure', 'drop'])
              WorkoutSetPayload(type: type, kg: 10, reps: 10, completed: false),
          ],
        },
      );
      final labels = ['W', 'F', 'D'];
      for (var index = 0; index < labels.length; index++) {
        await tester.tap(find.text(labels[index]));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Serie normal'));
        await tester.pumpAndSettle();
        expect(find.text(labels[index]), findsNothing);
        expect(find.text('${index + 1}'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });

  testWidgets('a personal record does not hide the warmup label', (
    tester,
  ) async {
    final client = MockClient((request) async {
      return _json(
        request.url.path == '/exercises/previous'
            ? {
                'sets': [
                  {'type': 'warmup', 'kg': 10, 'reps': 10},
                ],
              }
            : {'restSeconds': 60},
      );
    });
    await http.runWithClient(() async {
      await _openWorkout(
        tester,
        resuming: true,
        results: const {
          'Press': [
            WorkoutSetPayload(
              type: 'warmup',
              kg: 20,
              reps: 10,
              completed: true,
              kgInput: '20',
              repsInput: '10',
            ),
          ],
        },
      );
      expect(
        find.byKey(const ValueKey('medalla-record-personal')),
        findsOneWidget,
      );
      expect(find.text('W'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });
}
