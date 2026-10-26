import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/app.dart';
import 'package:hevy_hello/auth_controller.dart';
import 'package:hevy_hello/workout_api.dart';

Finder card(String name) => find.byKey(ValueKey('ejercicio-activo-$name'));
Finder handle(String name) => find.byKey(ValueKey('arrastrar-ejercicio-$name'));
List<TextField> fields(WidgetTester tester, String name) => tester
    .widgetList<TextField>(
      find.descendant(of: card(name), matching: find.byType(TextField)),
    )
    .toList();
Future<void> move(
  WidgetTester tester,
  String from,
  String to, {
  bool before = false,
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final start = tester.getCenter(handle(from));
  final target = tester.getRect(card(to));
  final gesture = await tester.startGesture(start, kind: kind);
  await tester.pump(
    kind == PointerDeviceKind.mouse
        ? Duration.zero
        : const Duration(milliseconds: 650),
  );
  final end = Offset(start.dx, before ? target.top + 10 : target.bottom + 50);
  for (var step = 1; step <= 20; step++) {
    await gesture.moveTo(Offset.lerp(start, end, step / 20)!);
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  final auth = AuthController.instance;
  setUp(() {
    auth.session = null;
    auth.onSessionEnded = clearActiveWorkout;
    auth.continueAsGuest();
  });
  tearDown(() async {
    if (auth.isGuest) await auth.signOut();
    auth.onSessionEnded = null;
    clearActiveWorkout();
  });

  testWidgets(
    'mouse drags start immediately and touch drags preserve fields and set types without a visible handle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      List<String>? savedOrder;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  savedOrder = await Navigator.of(context).push<List<String>>(
                    MaterialPageRoute(
                      builder: (_) => const WorkoutPage(
                        isEditing: true,
                        initialExercises: ['Press', 'Remo'],
                        initialResults: {
                          'Press': [
                            WorkoutSetPayload(
                              type: 'warmup',
                              kg: 1,
                              reps: 12,
                              completed: true,
                              kgInput: '1',
                              repsInput: '12',
                            ),
                            WorkoutSetPayload(
                              type: 'normal',
                              kg: 2.5,
                              reps: 8,
                              completed: false,
                              kgInput: '2.5',
                              repsInput: '8',
                            ),
                          ],
                          'Remo': [
                            WorkoutSetPayload(
                              type: 'normal',
                              kg: 3,
                              reps: 10,
                              completed: false,
                              kgInput: '3',
                              repsInput: '10',
                            ),
                          ],
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Editar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      final pressController = fields(tester, 'Press')[2].controller;
      final remoController = fields(tester, 'Remo')[0].controller;
      expect(find.byIcon(Icons.drag_handle), findsNothing);
      await move(tester, 'Press', 'Remo', kind: PointerDeviceKind.mouse);
      expect(
        tester.getTopLeft(card('Remo')).dy,
        lessThan(tester.getTopLeft(card('Press')).dy),
      );
      expect(fields(tester, 'Press')[2].controller, same(pressController));
      expect(fields(tester, 'Remo')[0].controller, same(remoController));
      expect(fields(tester, 'Press').map((f) => f.controller!.text), [
        '1',
        '12',
        '2.5',
        '8',
      ]);
      expect(
        find.descendant(of: card('Press'), matching: find.text('W')),
        findsOneWidget,
      );
      expect(find.text('Reordenar ejercicios'), findsNothing);
      await move(tester, 'Press', 'Remo', before: true);
      expect(
        tester.getTopLeft(card('Press')).dy,
        lessThan(tester.getTopLeft(card('Remo')).dy),
      );
      await move(tester, 'Press', 'Remo', kind: PointerDeviceKind.mouse);
      await tester.tap(find.byKey(const ValueKey('guardar-rutina')));
      await tester.pumpAndSettle();
      expect(savedOrder, ['Remo', 'Press']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'dragged order, entered values, untouched warmups and rest survive resume and routine update',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = WorkoutApi();
      await api.saveRoutineChanges(await api.getRoutineLibrary(), [
        const RoutineFolderPayload(
          id: 'folder',
          name: 'Plan',
          routines: [
            RoutinePayload(
              id: 'routine',
              name: 'Empuje',
              exercises: ['Press', 'Remo'],
            ),
          ],
        ),
      ]);
      final start = DateTime.now().subtract(const Duration(days: 1));
      await api.saveSession(
        routineName: 'Empuje',
        routineId: 'routine',
        startedAt: start,
        completedAt: start.add(const Duration(minutes: 1)),
        durationSeconds: 60,
        exercises: const [
          WorkoutExercisePayload(
            name: 'Press',
            sets: [
              WorkoutSetPayload(
                type: 'warmup',
                kg: 1,
                reps: 12,
                completed: true,
              ),
              WorkoutSetPayload(
                type: 'normal',
                kg: 2,
                reps: 8,
                completed: true,
              ),
            ],
          ),
          WorkoutExercisePayload(
            name: 'Remo',
            sets: [
              WorkoutSetPayload(
                type: 'warmup',
                kg: 0.5,
                reps: 10,
                completed: true,
              ),
              WorkoutSetPayload(
                type: 'normal',
                kg: 1,
                reps: 12,
                completed: true,
              ),
            ],
          ),
        ],
      );
      await api.saveRestTimerSeconds(exerciseName: 'Press', restSeconds: 60);
      await tester.pumpWidget(const HelloApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('carpeta-folder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('iniciar-rutina-Empuje')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: card('Press'),
          matching: find.byKey(const ValueKey('kg-2')),
        ),
        '2.5',
      );
      await tester.enterText(
        find.descendant(
          of: card('Press'),
          matching: find.byKey(const ValueKey('repeticiones-2')),
        ),
        '8',
      );
      await tester.tap(
        find.descendant(
          of: card('Press'),
          matching: find.byKey(const ValueKey('checkbox-W')),
        ),
      );
      await tester.pump();
      await move(tester, 'Press', 'Remo');
      expect(find.text('Entre series'), findsOneWidget);
      expect(
        tester.getTopLeft(card('Remo')).dy,
        lessThan(tester.getTopLeft(card('Press')).dy),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      final draft = (await api.getWorkoutDraft())!;
      expect(draft.exercises.map((e) => e.name), ['Remo', 'Press']);
      expect(draft.exercises.first.sets.length, 2);
      expect(draft.exercises.first.sets.first.type, 'warmup');
      expect(draft.exercises.last.sets.first.completed, isTrue);
      expect(draft.exercises.last.sets[1].kgInput, '2.5');
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('entrenamiento-activo')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(card('Remo')).dy,
        lessThan(tester.getTopLeft(card('Press')).dy),
      );
      expect(fields(tester, 'Press')[2].controller!.text, '2.5');
      expect(fields(tester, 'Remo').length, 4);
      expect(find.text('Entre series'), findsOneWidget);
      for (final label in ['W', '2']) {
        await tester.tap(
          find.descendant(
            of: card('Remo'),
            matching: find.byKey(ValueKey('checkbox-$label')),
          ),
        );
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('finalizar-entrenamiento')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar rutina'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirmar-guardar-entrenamiento')),
      );
      await tester.pumpAndSettle();
      expect(
        (await api.getRoutineLibrary())
            .folders
            .single
            .routines
            .single
            .exercises,
        ['Remo', 'Press'],
      );
      expect(
        (await api.getHistory()).sessions.first.exercises.map((e) => e.name),
        ['Remo', 'Press'],
      );
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets(
    'holding an exercise at the edge scrolls the list and saves its new position',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = WorkoutApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: WorkoutPage(
            initialExercises: List.generate(8, (i) => 'Ejercicio $i'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('lista-ejercicios'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      final start = tester.getCenter(handle('Ejercicio 0'));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 650));
      final edge = Offset(start.dx, tester.getRect(list).bottom - 30);
      for (var step = 1; step <= 20; step++) {
        await gesture.moveTo(Offset.lerp(start, edge, step / 20)!);
        await tester.pump(const Duration(milliseconds: 20));
      }
      for (var step = 0; step < 8; step++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(scrollable.position.pixels, greaterThan(0));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final order = (await api.getWorkoutDraft())!.exercises
          .map((e) => e.name)
          .toList();
      expect(order.indexOf('Ejercicio 0'), greaterThan(0));
      expect(order.toSet().length, 8);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets(
    'scrolling off screen retains unfinished values and controls remain editable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: WorkoutPage(
            isEditing: true,
            initialExercises: List.generate(10, (index) => 'Ejercicio $index'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: card('Ejercicio 0'),
          matching: find.byKey(const ValueKey('kg-1')),
        ),
        '17.5',
      );
      final controller = fields(tester, 'Ejercicio 0')[0].controller;
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('lista-ejercicios')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      scrollable.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(fields(tester, 'Ejercicio 0')[0].controller, same(controller));
      expect(controller!.text, '17.5');
      await tester.enterText(
        find.descendant(
          of: card('Ejercicio 0'),
          matching: find.byKey(const ValueKey('kg-1')),
        ),
        '18',
      );
      expect(controller.text, '18');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
