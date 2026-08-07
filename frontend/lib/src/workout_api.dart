import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class WorkoutSetPayload {
  const WorkoutSetPayload({
    required this.type,
    required this.kg,
    required this.reps,
    required this.completed,
  });

  final String type;
  final double kg;
  final int reps;
  final bool completed;

  Map<String, Object> toJson() => {
    'type': type,
    'kg': kg,
    'reps': reps,
    'completed': completed,
  };
}

class WorkoutExercisePayload {
  const WorkoutExercisePayload({required this.name, required this.sets});

  final String name;
  final List<WorkoutSetPayload> sets;

  Map<String, Object> toJson() => {
    'name': name,
    'sets': sets.map((set) => set.toJson()).toList(),
  };
}

class PreviousSet {
  const PreviousSet({required this.type, required this.kg, required this.reps});

  final String type;
  final double kg;
  final int reps;
}

class ExerciseCatalogItem {
  const ExerciseCatalogItem({required this.name, required this.muscleGroup});

  final String name;
  final String muscleGroup;
}

class RoutinePayload {
  const RoutinePayload({required this.name, required this.exercises});
  final String name;
  final List<String> exercises;
}

class RoutineFolderPayload {
  const RoutineFolderPayload({required this.name, required this.routines});
  final String name;
  final List<RoutinePayload> routines;
}

class WorkoutApi {
  WorkoutApi({http.Client? client}) : _client = client ?? http.Client();

  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
  final http.Client _client;

  String get _baseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    return Platform.isAndroid
        ? 'http://10.0.2.2:3000'
        : 'http://localhost:3000';
  }

  Future<void> saveSession({
    required String routineName,
    required DateTime startedAt,
    required DateTime completedAt,
    required int durationSeconds,
    required List<WorkoutExercisePayload> exercises,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/workout-sessions'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'routineName': routineName,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'completedAt': completedAt.toUtc().toIso8601String(),
        'durationSeconds': durationSeconds,
        'exercises': exercises.map((exercise) => exercise.toJson()).toList(),
      }),
    );
    if (response.statusCode != 201) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  Future<List<PreviousSet>> getPreviousSets(String exerciseName) async {
    final uri = Uri.parse(
      '$_baseUrl/exercises/previous',
    ).replace(queryParameters: {'name': exerciseName});
    final response = await _client.get(uri);
    if (response.statusCode == 404) return const [];
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final sets = body['sets'] as List<dynamic>;
    return [
      for (final value in sets)
        PreviousSet(
          type: (value as Map<String, dynamic>)['type'] as String,
          kg: (value['kg'] as num).toDouble(),
          reps: value['reps'] as int,
        ),
    ];
  }

  Future<List<ExerciseCatalogItem>> getExercises() async {
    final response = await _client.get(Uri.parse('$_baseUrl/exercises'));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final exercises = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final value in exercises)
        ExerciseCatalogItem(
          name: (value as Map<String, dynamic>)['name'] as String,
          muscleGroup: value['muscleGroup'] as String? ?? 'Otro',
        ),
    ];
  }

  Future<ExerciseCatalogItem> createExercise({
    required String name,
    required String muscleGroup,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/exercises'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'name': name, 'muscleGroup': muscleGroup}),
    );
    if (response.statusCode != 201) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final value = jsonDecode(response.body) as Map<String, dynamic>;
    return ExerciseCatalogItem(
      name: value['name'] as String,
      muscleGroup: value['muscleGroup'] as String? ?? 'Otro',
    );
  }

  Future<int> getRestTimerSeconds(String exerciseName) async {
    final uri = Uri.parse(
      '$_baseUrl/exercises/rest-timer',
    ).replace(queryParameters: {'name': exerciseName});
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final value = jsonDecode(response.body) as Map<String, dynamic>;
    return value['restSeconds'] as int;
  }

  Future<void> saveRestTimerSeconds({
    required String exerciseName,
    required int restSeconds,
  }) async {
    final response = await _client.put(
      Uri.parse('$_baseUrl/exercises/rest-timer'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'name': exerciseName, 'restSeconds': restSeconds}),
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  Future<List<RoutineFolderPayload>> getRoutineFolders() async {
    final response = await _client.get(Uri.parse('$_baseUrl/routine-folders'));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final folders = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final value in folders)
        RoutineFolderPayload(
          name: (value as Map<String, dynamic>)['name'] as String,
          routines: [
            for (final routine in value['routines'] as List<dynamic>)
              RoutinePayload(
                name: (routine as Map<String, dynamic>)['name'] as String,
                exercises: List<String>.from(
                  routine['exercises'] as List<dynamic>,
                ),
              ),
          ],
        ),
    ];
  }

  Future<void> saveRoutineFolders(List<RoutineFolderPayload> folders) async {
    final response = await _client.put(
      Uri.parse('$_baseUrl/routine-folders'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'folders': [
          for (final folder in folders)
            {
              'name': folder.name,
              'routines': [
                for (final routine in folder.routines)
                  {'name': routine.name, 'exercises': routine.exercises},
              ],
            },
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }
}
