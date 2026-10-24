import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/app.dart';
import 'package:hevy_hello/auth_controller.dart';
import 'package:hevy_hello/rest_timer_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _response(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

http.Client _client({int restSeconds = 60, ValueChanged<int>? onRestSaved}) =>
    MockClient((request) async {
      if (request.url.path == '/exercises/rest-timer' &&
          request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'Press');
        restSeconds = body['restSeconds'] as int;
        onRestSaved?.call(restSeconds);
        return _response({'restSeconds': restSeconds});
      }
      if (request.method != 'GET') return _response({});
      return switch (request.url.path) {
        '/routine-library' => _response({
          'version': 1,
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
        }),
        '/routine-shares/pending' => _response({'pending': false}),
        '/workout-draft' => _response({}, 404),
        '/exercises/previous' => _response({'sets': []}),
        '/exercises/rest-timer' => _response({'restSeconds': restSeconds}),
        _ => throw StateError('Unexpected request: ${request.url}'),
      };
    });

Future<void> _startWorkout(WidgetTester tester) async {
  await tester.pumpWidget(const HelloApp());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('carpeta-folder-a')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('iniciar-rutina-Empuje')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('checkbox-1')));
  await tester.pump();
}

Future<void> _goBack(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back));
  await tester.pumpAndSettle();
}

void main() {
  final start = DateTime.utc(2026, 10, 20, 12);
  final timer = RestTimerState(
    endsAt: start.add(const Duration(seconds: 60)),
    totalSeconds: 60,
  );

  test('rest accounts for time spent away without timer callbacks', () {
    expect(timer.remainingSecondsAt(start), 60);
    expect(
      timer.remainingSecondsAt(start.add(const Duration(seconds: 37))),
      23,
    );
    expect(
      timer.remainingSecondsAt(start.add(const Duration(milliseconds: 59500))),
      1,
    );
    expect(timer.remainingSecondsAt(start.add(const Duration(seconds: 60))), 0);
    expect(timer.remainingSecondsAt(start.add(const Duration(minutes: 2))), 0);
  });

  test('adjustments preserve the deadline and partial elapsed second', () {
    final now = start.add(const Duration(milliseconds: 10250));
    final increased = timer.adjustedBy(15, now)!;
    expect(increased.endsAt, start.add(const Duration(seconds: 75)));
    expect(increased.remainingSecondsAt(now), 65);
    expect(increased.totalSeconds, 65);
    expect(increased.adjustedBy(-15, now)!.endsAt, timer.endsAt);
  });

  test('reducing to zero stops the rest and expired rests cannot restart', () {
    expect(
      timer.adjustedBy(-15, start.add(const Duration(seconds: 50))),
      isNull,
    );
    expect(timer.adjustedBy(15, start.add(const Duration(minutes: 1))), isNull);
    final maximum = timer.adjustedBy(4000, start)!;
    expect(maximum.remainingSecondsAt(start), 3599);
    expect(maximum.totalSeconds, 3599);
  });

  setUp(() {
    clearActiveWorkout();
    AuthController.instance.session = const UserSession(
      token: '',
      id: 'alice',
      email: 'alice@example.com',
    );
  });
  tearDown(() {
    clearActiveWorkout();
    AuthController.instance.session = null;
  });

  testWidgets(
    'rest picker saves and starts every half-minute option up to five minutes',
    (tester) async {
      final savedDurations = <int>[];
      await http.runWithClient(() async {
        await _startWorkout(tester);
        await tester.tap(find.byKey(const ValueKey('checkbox-1')));
        await tester.pump();
        const options = [
          ('1 min', 60, '01:00'),
          ('1 min 30s', 90, '01:30'),
          ('2 min', 120, '02:00'),
          ('2 min 30s', 150, '02:30'),
          ('3 min', 180, '03:00'),
          ('3 min 30s', 210, '03:30'),
          ('4 min', 240, '04:00'),
          ('4 min 30s', 270, '04:30'),
          ('5 min', 300, '05:00'),
        ];
        for (var index = 0; index < options.length; index++) {
          final (label, seconds, countdown) = options[index];
          await tester.tap(find.byKey(const ValueKey('temporizador-Press')));
          await tester.pumpAndSettle();
          final wheel = tester.widget<ListWheelScrollView>(
            find.byType(ListWheelScrollView),
          );
          (wheel.controller! as FixedExtentScrollController).jumpToItem(index);
          await tester.pumpAndSettle();
          expect(tester.widget<Text>(find.text(label)).style!.fontSize, 20);
          expect(find.text('5 min 30s'), findsNothing);
          await tester.tap(find.text('Listo'));
          await tester.pumpAndSettle();
          expect(savedDurations.last, seconds);
          await tester.tap(find.byKey(const ValueKey('checkbox-1')));
          await tester.pump();
          expect(find.text(countdown), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('checkbox-1')));
          await tester.pump();
        }
        expect(savedDurations, [60, 90, 120, 150, 180, 210, 240, 270, 300]);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => _client(onRestSaved: savedDurations.add));
    },
  );

  testWidgets(
    'a saved half-minute rest stays selected and survives leaving the workout',
    (tester) async {
      final savedDurations = <int>[];
      await http.runWithClient(() async {
        await _startWorkout(tester);
        expect(find.text('01:30'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('temporizador-Press')));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(find.text('1 min 30s')).style!.fontSize, 20);
        await tester.tap(find.text('Listo'));
        await tester.pumpAndSettle();
        expect(savedDurations, [90]);
        await _goBack(tester);
        await tester.tap(find.byKey(const ValueKey('entrenamiento-activo')));
        await tester.pumpAndSettle();
        expect(find.text('01:30'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => _client(restSeconds: 90, onRestSaved: savedDurations.add));
    },
  );

  testWidgets(
    'rest and its adjustments survive leaving and resuming a workout',
    (tester) async {
      await http.runWithClient(() async {
        await _startWorkout(tester);
        expect(find.text('+15'), findsOneWidget);
        await tester.tap(find.text('+15'));
        await tester.pump();
        await _goBack(tester);
        expect(find.byType(WorkoutPage), findsNothing);
        await tester.tap(find.byKey(const ValueKey('entrenamiento-activo')));
        await tester.pumpAndSettle();
        expect(find.text('+15'), findsOneWidget);
        expect(find.text('01:15'), findsOneWidget);

        for (var i = 0; i < 5; i++) {
          await tester.tap(find.text('-15'));
          await tester.pump();
        }
        expect(find.text('+15'), findsNothing);
        await _goBack(tester);
        await tester.tap(find.byKey(const ValueKey('entrenamiento-activo')));
        await tester.pumpAndSettle();
        expect(find.text('+15'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }, _client);
    },
  );

  testWidgets('starting another workout does not inherit the previous rest', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await _startWorkout(tester);
      expect(find.text('+15'), findsOneWidget);
      await _goBack(tester);
      await tester.tap(find.byKey(const ValueKey('iniciar-rutina-Empuje')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('iniciar-nuevo-entrenamiento')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutPage), findsOneWidget);
      expect(find.text('+15'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, _client);
  });
}
