import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevy_hello/app.dart';
import 'package:hevy_hello/auth_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> openCatalog(
  WidgetTester tester, {
  ValueChanged<String?>? onSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final name = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const AddExercisePage()),
              );
              onSelected?.call(name);
            },
            child: const Text('Abrir catálogo'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir catálogo'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(
    () => AuthController.instance.session = const UserSession(
      token: 'bob-token',
      id: 'bob',
      email: 'bob@gmail.com',
    ),
  );
  tearDown(() => AuthController.instance.session = null);

  testWidgets(
    'a shared exercise can be searched without accents and selected',
    (tester) async {
      final requests = <http.Request>[];
      String? selected;
      await http.runWithClient(
        () async {
          await openCatalog(tester, onSelected: (name) => selected = name);
          await tester.enterText(find.byType(TextField), 'extension');
          await tester.pump();
          expect(find.text('Extensión en máquina'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('seleccionar-Extensión en máquina')),
          );
          await tester.pumpAndSettle();
          expect(selected, 'Extensión en máquina');
          expect(requests.map((r) => r.method), ['GET']);
          expect(requests.single.url.path, '/exercises');
        },
        () => MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode([
              {'name': 'Extensión en máquina', 'muscleGroup': 'Cuádriceps'},
            ]),
            200,
          );
        }),
      );
    },
  );

  testWidgets(
    'pulling to refresh loads newly shared exercises without duplicates',
    (tester) async {
      var loads = 0;
      await http.runWithClient(
        () async {
          await openCatalog(tester);
          await tester.enterText(find.byType(TextField), 'comunitario');
          await tester.pump();
          expect(find.text('Press comunitario'), findsOneWidget);
          expect(find.text('Remo comunitario'), findsNothing);

          await tester.drag(find.byType(ListView), const Offset(0, 400));
          await tester.pumpAndSettle();
          expect(loads, 2);
          expect(find.text('Press comunitario'), findsOneWidget);
          expect(find.text('Remo comunitario'), findsOneWidget);
        },
        () => MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/exercises');
          loads++;
          return http.Response(
            jsonEncode([
              {'name': 'Press comunitario', 'muscleGroup': 'Pecho'},
              if (loads > 1)
                {'name': 'Remo comunitario', 'muscleGroup': 'Espalda'},
            ]),
            200,
          );
        }),
      );
    },
  );
}
