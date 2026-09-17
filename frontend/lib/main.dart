import 'package:flutter/material.dart';

import 'app.dart';
import 'auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AuthController.instance.onSessionEnded = clearActiveWorkout;
  await AuthController.instance.restore();
  runApp(const HelloApp());
}
