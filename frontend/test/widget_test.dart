import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/src/app.dart';

void main() {
  testWidgets('starts without hardcoded folders', (tester) async {
    await tester.pumpWidget(const HelloApp(enableCloudPersistence: false));

    expect(find.text('Rutinas'), findsOneWidget);
    expect(find.text('Entrenamiento'), findsNothing);
    expect(find.text('Aún no hay carpetas'), findsOneWidget);
    expect(find.text('Crear carpeta'), findsOneWidget);
  });

  testWidgets('allows creating a folder and a routine from an empty state', (
    tester,
  ) async {
    await tester.pumpWidget(const HelloApp(enableCloudPersistence: false));

    await tester.tap(find.byKey(const ValueKey('crear-primera-carpeta')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('nombre-carpeta')),
      'fuerza semanal',
    );
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();

    expect(find.text('Fuerza Semanal'), findsOneWidget);
    expect(find.text('Sin rutinas'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('carpeta-Fuerza Semanal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('crear-primera-rutina')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('nombre-rutina')),
      'tren superior',
    );
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();

    expect(find.text('Tren Superior'), findsOneWidget);
    expect(find.text('Sin ejercicios'), findsOneWidget);
  });
}
