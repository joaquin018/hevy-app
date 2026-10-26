import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/app.dart';
import 'package:hevy_hello/auth_controller.dart';
import 'package:hevy_hello/workout_api.dart';
import 'package:hevy_hello/workout_history_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const firstId = '3c537989-1663-4580-824b-8f6f20ab5024';
const secondId = '7f707f68-4c39-4df4-9d3c-d1cd03ab174b';
http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
Map<String, Object> session(String id, String name) => {
  'id': id,
  'routineName': name,
  'startedAt': '2026-10-26T10:00:00Z',
  'durationSeconds': 3600,
  'volumeKg': 500,
  'records': 0,
  'exercises': [],
};

class HistoryFixture {
  final sessions = [session(firstId, 'Empuje'), session(secondId, 'Piernas')];
  final deletedIds = <String>[];
  final offsets = <int>[];
  int pageSize = 1;
  int deleteStatus = 200;
  bool failReloadAfterDelete = false;
  bool failNextLoad = false;
  Completer<void>? deleteGate;

  http.Client client() => MockClient((request) async {
    if (request.url.path == '/workout-sessions') {
      expect(request.method, 'GET');
      final offset = int.parse(request.url.queryParameters['offset']!);
      offsets.add(offset);
      if (failNextLoad) {
        failNextLoad = false;
        return json({}, 503);
      }
      return json({
        'sessions': sessions.skip(offset).take(pageSize).toList(),
        'total': sessions.length,
        'hasMore': offset + pageSize < sessions.length,
      });
    }
    if (request.url.path.startsWith('/workout-sessions/')) {
      expect(request.method, 'DELETE');
      final id = request.url.pathSegments.last;
      deletedIds.add(id);
      await deleteGate?.future;
      if (deleteStatus == 200 || deleteStatus == 404) {
        sessions.removeWhere((item) => item['id'] == id);
        for (final item in sessions) {
          item['records'] = 1;
        }
        failNextLoad = failReloadAfterDelete;
      }
      return json({'deleted': deleteStatus == 200}, deleteStatus);
    }
    return switch (request.url.path) {
      '/routine-library' => json({'version': 0, 'folders': []}),
      '/routine-shares/pending' => json({'pending': false}),
      '/workout-draft' => json({}, 404),
      _ => throw StateError(
        'Unexpected request: ${request.method} ${request.url}',
      ),
    };
  });
}

Future<void> openHistory(WidgetTester tester) async {
  final api = WorkoutApi();
  addTearDown(api.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: WorkoutHistoryScreen(
        loadHistory: (offset) => api.getHistory(offset: offset),
        deleteSession: api.deleteSession,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> confirmDelete(WidgetTester tester, [String id = firstId]) async {
  await tester.tap(find.byKey(ValueKey('eliminar-entrenamiento-$id')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('confirmar-eliminar-entrenamiento')),
  );
}

void main() {
  setUp(() {
    clearActiveWorkout();
    AuthController.instance.session = const UserSession(
      token: 'alice-token',
      id: 'alice',
      email: 'alice@gmail.com',
    );
  });
  tearDown(() {
    clearActiveWorkout();
    AuthController.instance.session = null;
  });

  testWidgets(
    'cancel identifies the session and does not send a delete request',
    (tester) async {
      final fixture = HistoryFixture();
      await http.runWithClient(() async {
        await openHistory(tester);
        await tester.tap(
          find.byKey(const ValueKey('eliminar-entrenamiento-$firstId')),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('Empuje'),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('no se puede deshacer'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(fixture.deletedIds, isEmpty);
        expect(find.byKey(const ValueKey(firstId)), findsOneWidget);
        expect(find.text('2 entrenamientos guardados'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }, fixture.client);
    },
  );

  testWidgets(
    'deleting from loaded pages resets offsets and refreshes counts and record badges',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = HistoryFixture();
      await http.runWithClient(() async {
        await openHistory(tester);
        await tester.tap(find.text('Ver entrenamientos anteriores'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey(secondId)), findsOneWidget);
        await confirmDelete(tester);
        await tester.pumpAndSettle();
        expect(fixture.deletedIds, [firstId]);
        expect(fixture.offsets, [0, 1, 0]);
        expect(find.byKey(const ValueKey(firstId)), findsNothing);
        expect(find.text('1 entrenamiento guardado'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey(secondId)),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(find.text('Ver entrenamientos anteriores'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }, fixture.client);
    },
  );

  testWidgets('a failed delete keeps the session and allows retrying', (
    tester,
  ) async {
    final fixture = HistoryFixture()..deleteStatus = 503;
    await http.runWithClient(() async {
      await openHistory(tester);
      await confirmDelete(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(firstId)), findsOneWidget);
      expect(find.text('2 entrenamientos guardados'), findsOneWidget);
      expect(
        find.text('No se pudo eliminar el entrenamiento. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      fixture.deleteStatus = 200;
      await confirmDelete(tester);
      await tester.pumpAndSettle();
      expect(fixture.deletedIds, [firstId, firstId]);
      expect(find.byKey(const ValueKey(firstId)), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, fixture.client);
  });

  testWidgets('deleting the last session shows an empty history', (
    tester,
  ) async {
    final fixture = HistoryFixture()..sessions.removeLast();
    await http.runWithClient(() async {
      await openHistory(tester);
      await confirmDelete(tester);
      await tester.pumpAndSettle();
      expect(find.text('0 entrenamientos guardados'), findsOneWidget);
      expect(find.byKey(const ValueKey(firstId)), findsNothing);
      expect(find.text('Tu historia empieza aquí'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, fixture.client);
  });

  testWidgets(
    'a pending delete blocks other deletes and refreshes until it finishes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gate = Completer<void>();
      final fixture = HistoryFixture()
        ..pageSize = 2
        ..deleteGate = gate;
      await http.runWithClient(() async {
        await openHistory(tester);
        await confirmDelete(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byKey(const ValueKey('eliminando-entrenamiento-$firstId')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('eliminar-entrenamiento-$secondId')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.refresh_rounded),
              )
              .onPressed,
          isNull,
        );
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        expect(fixture.offsets, [0]);
        expect(fixture.deletedIds, [firstId]);
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey(firstId)), findsNothing);
        expect(find.byKey(const ValueKey(secondId)), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }, fixture.client);
    },
  );

  testWidgets(
    'a session already removed on another device refreshes successfully',
    (tester) async {
      final fixture = HistoryFixture()..deleteStatus = 404;
      await http.runWithClient(() async {
        await openHistory(tester);
        await confirmDelete(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey(firstId)), findsNothing);
        expect(find.text('Entrenamiento eliminado.'), findsOneWidget);
        expect(find.text('1 entrenamiento guardado'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }, fixture.client);
    },
  );

  testWidgets(
    'a failed refresh after deletion never restores the deleted card and can retry',
    (tester) async {
      final fixture = HistoryFixture()..failReloadAfterDelete = true;
      await http.runWithClient(() async {
        await openHistory(tester);
        await confirmDelete(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey(firstId)), findsNothing);
        expect(find.text('1 entrenamiento guardado'), findsOneWidget);
        expect(
          find.text(
            'No se pudo cargar el historial. Revisa tu conexión e inténtalo de nuevo.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey(firstId)), findsNothing);
        expect(find.byKey(const ValueKey(secondId)), findsOneWidget);
        expect(fixture.deletedIds, [firstId]);
        expect(fixture.offsets, [0, 0, 0]);
        await tester.pumpWidget(const SizedBox.shrink());
      }, fixture.client);
    },
  );

  testWidgets('the history opened from routines is connected to deletion', (
    tester,
  ) async {
    final fixture = HistoryFixture();
    await http.runWithClient(() async {
      await tester.pumpWidget(const HelloApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('abrir-historial')));
      await tester.pumpAndSettle();
      await confirmDelete(tester);
      await tester.pumpAndSettle();
      expect(fixture.deletedIds, [firstId]);
      expect(find.byKey(const ValueKey(firstId)), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, fixture.client);
  });
}
