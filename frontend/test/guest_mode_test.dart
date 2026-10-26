import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/app.dart';
import 'package:hevy_hello/auth_controller.dart';
import 'package:hevy_hello/guest_store.dart';
import 'package:hevy_hello/workout_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const folderId = 'test-folder', routineId = 'test-routine';
const folder = RoutineFolderPayload(
  id: folderId,
  name: 'Mi plan',
  routines: [
    RoutinePayload(id: routineId, name: 'Empuje', exercises: ['Press']),
  ],
);
Future<void> createPlan(WorkoutApi api) async {
  await api.saveRoutineChanges(await api.getRoutineLibrary(), [folder]);
}

int sequence = 0;
Future<void> save(
  WorkoutApi api,
  double kg, {
  String? id = routineId,
  String type = 'normal',
  int reps = 10,
}) async {
  final start = DateTime.utc(2026, 10, 26, 10, sequence++);
  await api.saveSession(
    routineName: 'Empuje',
    routineId: id,
    startedAt: start,
    completedAt: start.add(const Duration(minutes: 1)),
    durationSeconds: 60,
    exercises: [
      WorkoutExercisePayload(
        name: 'Press',
        sets: [
          WorkoutSetPayload(type: type, kg: kg, reps: reps, completed: true),
        ],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = AuthController.instance;
  var networkCalls = 0, storageCalls = 0;
  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  late http.Client network;
  setUp(() {
    auth.session = null;
    auth.busy = false;
    auth.error = null;
    auth.onSessionEnded = clearActiveWorkout;
    clearActiveWorkout();
    sequence = 0;
    networkCalls = storageCalls = 0;
    network = MockClient((request) async {
      networkCalls++;
      throw StateError(
        'Guest mode attempted to send ${request.method} ${request.url}',
      );
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (_) async {
          storageCalls++;
          throw StateError('Guest mode attempted to access persistent storage');
        });
  });
  tearDown(() async {
    if (auth.isGuest) await auth.signOut();
    auth.session = null;
    auth.busy = false;
    auth.error = null;
    auth.onSessionEnded = null;
    clearActiveWorkout();
    network.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
    expect(networkCalls, 0);
    expect(storageCalls, 0);
  });

  testWidgets(
    'guest entry is available without a localhost restriction and exits with empty data',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await http.runWithClient(() async {
        await tester.pumpWidget(const HelloApp());
        await tester.pumpAndSettle();
        expect(find.text('Continuar con Google'), findsOneWidget);
        expect(find.text('Continuar como invitado'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('continuar-como-invitado')));
        await tester.pumpAndSettle();
        expect(auth.isGuest, isTrue);
        expect(find.text('Invitado · datos temporales'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('abrir-rutinas-compartidas')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('crear-carpeta')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('nombre-carpeta')),
          'Temporal',
        );
        await tester.tap(find.text('Crear'));
        await tester.pumpAndSettle();
        expect(find.text('Temporal'), findsOneWidget);
        final oldApi = WorkoutApi(client: network);
        expect(
          (await oldApi.getRoutineLibrary()).folders.single.name,
          'Temporal',
        );
        await tester.tap(find.byTooltip('Cuenta'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Salir del modo invitado'));
        await tester.pumpAndSettle();
        expect(find.text('Continuar como invitado'), findsOneWidget);
        await expectLater(oldApi.getRoutineLibrary(), throwsStateError);
        await tester.tap(find.byKey(const ValueKey('continuar-como-invitado')));
        await tester.pumpAndSettle();
        expect((await WorkoutApi().getRoutineLibrary()).folders, isEmpty);
        expect(find.text('Temporal'), findsNothing);
        oldApi.close();
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => network);
    },
  );

  testWidgets(
    'a guest can train, view history and delete a workout without network access',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      auth.continueAsGuest();
      final api = WorkoutApi(client: network);
      await createPlan(api);
      await save(api, 1, type: 'warmup', reps: 12);
      await api.saveRestTimerSeconds(
        exerciseName: 'Press',
        restSeconds: 90,
        betweenExercises: true,
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(const HelloApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('carpeta-test-folder')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('iniciar-rutina-Empuje')));
        await tester.pumpAndSettle();
        expect(find.text('1kg x 12'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('checkbox-W')));
        await tester.pump();
        expect(find.text('01:30'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('finalizar-entrenamiento')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('confirmar-guardar-entrenamiento')),
        );
        await tester.pumpAndSettle();
        final history = await api.getHistory();
        expect(history.total, 2);
        expect(history.sessions.every((s) => s.volumeKg == 12), isTrue);
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('abrir-historial')));
        await tester.pumpAndSettle();
        expect(find.text('Empuje'), findsNWidgets(2));
        await tester.tap(
          find.byKey(
            ValueKey('eliminar-entrenamiento-${history.sessions.first.id}'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('confirmar-eliminar-entrenamiento')),
        );
        await tester.pumpAndSettle();
        expect((await api.getHistory()).total, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => network);
      api.close();
    },
  );

  test('routines, custom exercises, rests and drafts stay in memory across API instances only', () async {
    auth.continueAsGuest();
    final api = WorkoutApi(client: network),
        other = WorkoutApi(client: network);
    await createPlan(api);
    expect(
      (await other.getRoutineLibrary()).folders.single.routines.single.id,
      routineId,
    );
    await api.createExercise(name: 'Ejercicio temporal', muscleGroup: 'Pecho');
    expect(
      (await other.getExercises()).any((e) => e.name == 'Ejercicio temporal'),
      isTrue,
    );
    await api.saveRestTimerSeconds(exerciseName: 'Press', restSeconds: 60);
    await api.saveRestTimerSeconds(
      exerciseName: 'Press',
      restSeconds: 90,
      betweenExercises: true,
    );
    expect(await other.getRestTimerSeconds('Press'), 60);
    expect(
      await other.getRestTimerSeconds('Press', betweenExercises: true),
      90,
    );
    expect(
      await other.getRestTimerSeconds('Remo', betweenExercises: true),
      180,
    );
    await api.saveWorkoutDraft(
      WorkoutDraftPayload(
        routineName: 'Empuje',
        routineId: routineId,
        startedAt: DateTime.now(),
        originalExercises: ['Press'],
        exercises: [
          WorkoutExercisePayload(
            name: 'Press',
            sets: [
              WorkoutSetPayload(
                type: 'warmup',
                kg: 20,
                reps: 12,
                completed: false,
                kgInput: '20',
                repsInput: '12',
              ),
            ],
          ),
        ],
      ),
    );
    expect(
      (await other.getWorkoutDraft())!.exercises.single.sets.single.kgInput,
      '20',
    );
    await api.deleteWorkoutDraft();
    expect(await other.getWorkoutDraft(), isNull);
    await auth.signOut();
    auth.continueAsGuest();
    final fresh = WorkoutApi(client: network);
    expect((await fresh.getRoutineLibrary()).folders, isEmpty);
    expect(
      (await fresh.getExercises()).any((e) => e.name == 'Ejercicio temporal'),
      isFalse,
    );
    expect(await fresh.getRestTimerSeconds('Press'), 180);
    expect(
      await fresh.getRestTimerSeconds('Press', betweenExercises: true),
      180,
    );
    expect(await fresh.getWorkoutDraft(), isNull);
    api.close();
    other.close();
    fresh.close();
  });

  test('guest history, previous results, warmups and deletion work without a server', () async {
    auth.continueAsGuest();
    final api = WorkoutApi(client: network);
    await createPlan(api);
    await save(api, 20, type: 'warmup', reps: 12);
    await save(api, 30, type: 'warmup', reps: 12);
    expect((await api.getPreviousSets('Press')).single.type, 'warmup');
    expect((await api.getPreviousSets('Press')).single.kg, 30);
    var history = await api.getHistory();
    expect(history.total, 2);
    expect(history.sessions.first.records, 1);
    expect(history.sessions.first.volumeKg, 360);
    await api.deleteSession(history.sessions.first.id);
    expect((await api.getPreviousSets('Press')).single.kg, 20);
    history = await api.getHistory();
    await api.deleteSession(history.sessions.single.id);
    expect((await api.getHistory()).total, 0);
    expect(await api.getPreviousSets('Press'), isEmpty);
    api.close();
  });

  test('guest routine isolation uses only the routine sessions and survives toggling', () async {
    auth.continueAsGuest();
    final api = WorkoutApi(client: network);
    await createPlan(api);
    await save(api, 80, id: null);
    await save(api, 40);
    final library = await api.getRoutineLibrary();
    await api.saveRoutineChanges(library, [
      const RoutineFolderPayload(
        id: folderId,
        name: 'Mi plan',
        routines: [
          RoutinePayload(
            id: routineId,
            name: 'Empuje',
            exercises: ['Press'],
            isolateResults: true,
          ),
        ],
      ),
    ]);
    expect(
      (await api.getPreviousSets('Press', routineId: routineId)).single.kg,
      40,
    );
    expect((await api.getPreviousSets('Press')).single.kg, 80);
    await save(api, 50);
    expect((await api.getHistory()).sessions.first.records, 1);
    await api.saveRoutineChanges(await api.getRoutineLibrary(), [folder]);
    expect(
      (await api.getPreviousSets('Press', routineId: routineId)).single.kg,
      80,
    );
    api.close();
  });

  test('new guest state simulates a reload and stale guest clients cannot access a real account', () async {
    final first = GuestStore(), second = GuestStore();
    final a = first.createClient(), b = second.createClient();
    await a.put(
      Uri.parse('https://app.example/api/exercises/rest-timer'),
      body: '{"name":"Press","restSeconds":60}',
    );
    expect(
      (await b.get(
        Uri.parse('https://app.example/api/exercises/rest-timer?name=Press'),
      )).body,
      '{"restSeconds":180}',
    );
    first.end();
    await expectLater(
      a.get(Uri.parse('https://app.example/api/exercises')),
      throwsStateError,
    );
    a.close();
    b.close();
    second.end();
    auth.continueAsGuest();
    final oldApi = WorkoutApi(client: network);
    await auth.signOut();
    auth.session = const UserSession(
      token: 'real-token',
      id: 'real-user',
      email: 'user@example.com',
    );
    await expectLater(
      oldApi.createExercise(name: 'No escribir', muscleGroup: 'Pecho'),
      throwsStateError,
    );
    oldApi.close();
  });

  test(
    'a response requested before guest entry cannot populate the guest session',
    () async {
      final response = Completer<http.Response>(), sent = Completer<void>();
      final old = AuthenticatedClient(
        MockClient((_) {
          sent.complete();
          return response.future;
        }),
        null,
      );
      final pending = old.get(
        Uri.parse('https://app.example/api/routine-library'),
      );
      final assertion = expectLater(pending, throwsA(isA<AuthFailure>()));
      await sent.future;
      auth.continueAsGuest();
      response.complete(http.Response('{"private":"old account"}', 200));
      await assertion;
      expect((await WorkoutApi().getRoutineLibrary()).folders, isEmpty);
      old.close();
    },
  );

  test('old authenticated clients and auth actions cannot send guest data over the network', () async {
    final old = AuthenticatedClient(network, null);
    auth.continueAsGuest();
    await expectLater(
      old.put(Uri.parse('https://app.example/api/workout-draft')),
      throwsA(isA<AuthFailure>()),
    );
    await http.runWithClient(() async {
      await auth.restore();
      await auth.signIn();
    }, () => network);
    expect(auth.isGuest, isTrue);
    await auth.signOut();
  });
}
