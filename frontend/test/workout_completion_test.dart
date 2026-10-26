import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/app.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _WorkoutFixture {
  _WorkoutFixture({this.hasHistory = true});

  final bool hasHistory;
  Map<String, dynamic>? draft;
  Map<String, dynamic>? session;

  http.Client client() => MockClient((request) async {
    Object response = {};
    switch (request.url.path) {
      case '/exercises/previous':
        response = {
          'sets': hasHistory
              ? [
                  {'type': 'normal', 'kg': 42.5, 'reps': 8},
                ]
              : [],
        };
      case '/exercises/rest-timer':
        response = {'restSeconds': 60};
      case '/workout-draft':
        if (request.method == 'PUT') {
          draft = jsonDecode(request.body) as Map<String, dynamic>;
        }
      case '/workout-sessions':
        session = jsonDecode(request.body) as Map<String, dynamic>;
      default:
        throw StateError('Unexpected request ${request.url}');
    }
    return http.Response(
      jsonEncode(response),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

Finder _field(String name) => find.descendant(
  of: find.byKey(ValueKey(name)),
  matching: find.byType(TextField),
);

Future<void> _openWorkout(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WorkoutPage(initialExercises: ['Press']),
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
    'checking empty fields fills previous results and saves them once',
    (tester) async {
      final fixture = _WorkoutFixture();
      await http.runWithClient(() async {
        await _openWorkout(tester);
        final weight = tester.widget<TextField>(_field('kg-1'));
        final reps = tester.widget<TextField>(_field('repeticiones-1'));
        expect(weight.controller!.text, isEmpty);
        expect(reps.controller!.text, isEmpty);
        expect(weight.decoration!.hintText, '42.5');
        expect(reps.decoration!.hintText, '8');

        final check = find.byKey(const ValueKey('checkbox-1'));
        await tester.tap(check);
        await tester.pump();
        expect(weight.controller!.text, '42.5');
        expect(reps.controller!.text, '8');
        expect(find.text('340 kg'), findsOneWidget);

        await tester.tap(check);
        await tester.pump();
        expect(find.text('0 kg'), findsOneWidget);
        expect(weight.controller!.text, '42.5');
        expect(reps.controller!.text, '8');
        await tester.tap(check);
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('340 kg'), findsOneWidget);
        expect(fixture.draft!['exercises'][0]['sets'][0], {
          'type': 'normal',
          'kg': 42.5,
          'reps': 8,
          'completed': true,
          'kgInput': '42.5',
          'repsInput': '8',
        });

        await tester.tap(find.byKey(const ValueKey('finalizar-entrenamiento')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('confirmar-guardar-entrenamiento')),
        );
        await tester.pumpAndSettle();
        expect(fixture.session!['exercises'][0]['sets'][0], {
          'type': 'normal',
          'kg': 42.5,
          'reps': 8,
          'completed': true,
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }, fixture.client);
    },
  );

  for (final (
        name,
        weightInput,
        repsInput,
        expectedWeight,
        expectedReps,
        volume,
      )
      in [
        ('typed decimal weight', '45,5', '', '45,5', '8', '364 kg'),
        ('typed reps', '', '10', '42.5', '10', '425 kg'),
        ('explicit zero weight', '0', '', '0', '8', '0 kg'),
      ]) {
    testWidgets('checking preserves $name and fills only missing values', (
      tester,
    ) async {
      final fixture = _WorkoutFixture();
      await http.runWithClient(() async {
        await _openWorkout(tester);
        if (weightInput.isNotEmpty) {
          await tester.enterText(_field('kg-1'), weightInput);
        }
        if (repsInput.isNotEmpty) {
          await tester.enterText(_field('repeticiones-1'), repsInput);
        }
        await tester.tap(find.byKey(const ValueKey('checkbox-1')));
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          tester.widget<TextField>(_field('kg-1')).controller!.text,
          expectedWeight,
        );
        expect(
          tester.widget<TextField>(_field('repeticiones-1')).controller!.text,
          expectedReps,
        );
        expect(find.text(volume), findsOneWidget);
        final saved = fixture.draft!['exercises'][0]['sets'][0];
        expect(saved['kgInput'], expectedWeight);
        expect(saved['repsInput'], expectedReps);
        expect(saved['completed'], isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      }, fixture.client);
    });
  }

  testWidgets('without previous results the default zero hint is not copied', (
    tester,
  ) async {
    final fixture = _WorkoutFixture(hasHistory: false);
    await http.runWithClient(() async {
      await _openWorkout(tester);
      await tester.tap(find.byKey(const ValueKey('checkbox-1')));
      await tester.pump();
      expect(
        tester.widget<TextField>(_field('kg-1')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(_field('repeticiones-1')).controller!.text,
        isEmpty,
      );
      expect(find.text('0 kg'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, fixture.client);
  });
}
