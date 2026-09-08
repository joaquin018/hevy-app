import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hevy_hello/src/workout_api.dart';
import 'package:hevy_hello/src/workout_history_models.dart';
import 'package:hevy_hello/src/workout_history_page.dart';

Map<String, dynamic> session(String id) => {
  'id': id,
  'routineName': 'Miércoles',
  'startedAt': '2026-09-02T15:00:00Z',
  'durationSeconds': 4260,
  'volumeKg': 2911.5,
  'records': 2,
  'exercises': List.generate(
    4,
    (i) => {
      'name': 'Ejercicio ${i + 1}',
      'sets': [
        {'type': 'normal', 'kg': 40, 'reps': 8, 'isRecord': true},
      ],
    },
  ),
};

void main() {
  test(
    'API parses history and requests the next page with UTF-8 names',
    () async {
      final api = WorkoutApi(
        client: MockClient((request) async {
          expect(request.url.path, '/workout-sessions');
          expect(request.url.queryParameters['offset'], '20');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'sessions': [session('a')],
                'total': 21,
                'hasMore': false,
              }),
            ),
            200,
          );
        }),
      );
      final result = await api.getHistory(offset: 20);
      expect(result.sessions.single.name, 'Miércoles');
      expect(result.sessions.single.volumeKg, 2911.5);
      expect(result.hasMore, false);
    },
  );

  testWidgets(
    'history expands exercises and shows weights, reps and records on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutHistoryScreen(
            loadHistory: (_) async => WorkoutHistoryPage(
              sessions: [WorkoutHistorySession.fromJson(session('a'))],
              total: 1,
              hasMore: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 h 11 min'), findsOneWidget);
      expect(find.text('2.911,5 kg'), findsOneWidget);
      expect(find.text('Ejercicio 4'), findsNothing);
      await tester.tap(find.text('Ver 1 ejercicios más'));
      await tester.pumpAndSettle();
      expect(find.text('Ejercicio 4'), findsOneWidget);
      await tester.ensureVisible(find.text('Ver series y repeticiones'));
      await tester.tap(find.text('Ver series y repeticiones'));
      await tester.pumpAndSettle();
      expect(find.text('40 kg × 8'), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed history can be retried and renders an empty state', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutHistoryScreen(
          loadHistory: (_) async {
            if (attempts++ == 0) throw Exception('offline');
            return const WorkoutHistoryPage(
              sessions: [],
              total: 0,
              hasMore: false,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Tu historia empieza aquí'), findsOneWidget);
  });
}
