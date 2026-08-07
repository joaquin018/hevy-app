import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/src/app.dart';

void main() {
  testWidgets('opens a routine and returns to workout home', (tester) async {
    await tester.pumpWidget(const HelloApp());

    expect(find.text('Rutinas'), findsOneWidget);
    expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);
    expect(find.text('Lunes'), findsOneWidget);
    expect(find.text('Iniciar rutina'), findsWidgets);

    await tester.tap(find.text('Iniciar rutina').first);
    await tester.pumpAndSettle();

    expect(find.text('0s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('2s'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('finalizar-entrenamiento')),
      findsOneWidget,
    );
    expect(find.text('Press Banca Inclinado Con Barra'), findsOneWidget);
    expect(find.text('Fondos'), findsOneWidget);
    expect(find.text('Agregar ejercicio'), findsOneWidget);
    expect(find.text('Añadir serie'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('finalizar-entrenamiento')));
    await tester.pumpAndSettle();
    expect(find.text('Actualizar «Lunes»'), findsOneWidget);
    expect(find.text('Añadiste 1 ejercicio.'), findsOneWidget);
    expect(find.text('Actualizar rutina'), findsOneWidget);
    expect(find.text('Mantener rutina original'), findsOneWidget);
    await tester.tap(find.text('Mantener rutina original'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('opciones-Press Banca Inclinado Con Barra')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reordenar ejercicios'), findsOneWidget);
    expect(find.text('Reemplazar ejercicio'), findsOneWidget);
    expect(find.text('Eliminar ejercicio'), findsOneWidget);
    expect(find.text('Add To Superset'), findsNothing);
    await tester.tap(find.text('Reordenar ejercicios'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('añadir-serie-Press Banca Inclinado Con Barra'),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('checkbox-5')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('kg-5')), '45');
    await tester.enterText(find.byKey(const ValueKey('repeticiones-5')), '8');
    expect(find.text('45'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('temporizador-Press Banca Inclinado Con Barra'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Temporizador de descanso'), findsOneWidget);
    expect(find.text('3 min'), findsOneWidget);
    expect(find.text('1 min'), findsOneWidget);
    await tester.drag(find.byType(ListWheelScrollView), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(find.text('5 min'), findsOneWidget);
    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('checkbox-W')));
    await tester.pump();
    expect(find.text('200 kg'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('-15'), findsOneWidget);
    expect(find.text('+15'), findsOneWidget);
    expect(find.text('Omitir'), findsNothing);

    await tester.tap(find.text('W'));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar tipo de serie'), findsOneWidget);
    expect(find.text('Serie al fallo'), findsOneWidget);

    await tester.tap(find.text('Serie al fallo'));
    await tester.pumpAndSettle();
    expect(find.text('F'), findsOneWidget);

    final addExerciseButton = find.byKey(const ValueKey('agregar-ejercicio'));
    await tester.ensureVisible(addExerciseButton);
    await tester.pumpAndSettle();
    await tester.tap(addExerciseButton);
    await tester.pumpAndSettle();
    expect(find.text('Buscar ejercicio'), findsOneWidget);
    expect(find.text('Ejercicios recientes'), findsOneWidget);
    expect(find.text('Dominadas'), findsOneWidget);
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    expect(find.text('Crear ejercicio'), findsOneWidget);
    expect(find.byKey(const ValueKey('guardar-ejercicio')), findsOneWidget);
    expect(find.text('Nombre del ejercicio'), findsOneWidget);
    expect(find.text('Grupo Muscular Principal'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('nombre-ejercicio')),
      'press BANCA inclinado',
    );
    expect(find.text('Press Banca Inclinado'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('grupo-muscular-principal')));
    await tester.pumpAndSettle();
    expect(find.text('Abdominales'), findsOneWidget);
    expect(find.text('Pecho'), findsOneWidget);
    await tester.tap(find.text('Pecho'));
    await tester.pumpAndSettle();
    expect(find.text('Pecho'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Lunes'), findsOneWidget);
  });
}
