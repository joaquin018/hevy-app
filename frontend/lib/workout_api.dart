import 'dart:convert';

import 'package:http/http.dart' as http;

import 'workout_history_models.dart';
import 'auth_controller.dart';
import 'routine_models.dart';
export 'routine_models.dart';
part 'routine_api.dart';

class WorkoutSetPayload {
  const WorkoutSetPayload({
    required this.type,
    required this.kg,
    required this.reps,
    required this.completed,
    this.kgInput,
    this.repsInput,
  });

  final String type;
  final double kg;
  final int reps;
  final bool completed;
  final String? kgInput;
  final String? repsInput;

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

class WorkoutDraftPayload {
  const WorkoutDraftPayload({
    required this.routineName,
    required this.startedAt,
    required this.originalExercises,
    required this.exercises,
    this.routineId,
  });

  final String routineName;
  final String? routineId;
  final DateTime startedAt;
  final List<String> originalExercises;
  final List<WorkoutExercisePayload> exercises;
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

class WorkoutApi {
  WorkoutApi({http.Client? client})
    : _client =
          AuthController.instance.guestStore?.createClient() ??
          AuthenticatedClient(
            client ?? http.Client(),
            AuthController.instance.session,
          );

  final http.Client _client;

  Future<WorkoutHistoryPage> getHistory({int offset = 0}) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/workout-sessions')
          .replace(queryParameters: {'offset': '$offset', 'limit': '20'}),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'No se pudo cargar el historial (${response.statusCode})',
      );
    }
    final value =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return WorkoutHistoryPage(
      sessions: (value['sessions'] as List)
          .map((v) => WorkoutHistorySession.fromJson(v as Map<String, dynamic>))
          .toList(),
      total: value['total'] as int,
      hasMore: value['hasMore'] as bool,
    );
  }

  String get _baseUrl => apiBaseUrl;

  Future<void> deleteSession(String id) async {
    final response = await _client.delete(
      Uri.parse('$_baseUrl/workout-sessions/${Uri.encodeComponent(id)}'),
    );
    // Another device may already have removed this session.
    if (response.statusCode != 200 && response.statusCode != 404) {
      throw Exception(
        'No se pudo eliminar el entrenamiento (${response.statusCode})',
      );
    }
  }

  Future<void> saveSession({
    required String routineName,
    String? routineId,
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
        'routineId': ?routineId,
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

  Future<WorkoutDraftPayload?> getWorkoutDraft() async {
    final response = await _client.get(Uri.parse('$_baseUrl/workout-draft'));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final value = jsonDecode(response.body) as Map<String, dynamic>;
    return WorkoutDraftPayload(
      routineName: value['routineName'] as String,
      routineId: value['routineId'] as String?,
      startedAt: DateTime.parse(value['startedAt'] as String),
      originalExercises: List<String>.from(
        value['originalExercises'] as List<dynamic>,
      ),
      exercises: [
        for (final exerciseValue in value['exercises'] as List<dynamic>)
          WorkoutExercisePayload(
            name: (exerciseValue as Map<String, dynamic>)['name'] as String,
            sets: [
              for (final setValue in exerciseValue['sets'] as List<dynamic>)
                WorkoutSetPayload(
                  type: (setValue as Map<String, dynamic>)['type'] as String,
                  kg: (setValue['kg'] as num).toDouble(),
                  reps: setValue['reps'] as int,
                  completed: setValue['completed'] as bool,
                  kgInput: setValue['kgInput'] as String?,
                  repsInput: setValue['repsInput'] as String?,
                ),
            ],
          ),
      ],
    );
  }

  Future<void> saveWorkoutDraft(WorkoutDraftPayload draft) async {
    final response = await _client.put(
      Uri.parse('$_baseUrl/workout-draft'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'routineName': draft.routineName,
        if (draft.routineId != null) 'routineId': draft.routineId,
        'startedAt': draft.startedAt.toUtc().toIso8601String(),
        'originalExercises': draft.originalExercises,
        'exercises': [
          for (final exercise in draft.exercises)
            {
              'name': exercise.name,
              'sets': [
                for (final set in exercise.sets)
                  {
                    ...set.toJson(),
                    'kgInput': set.kgInput ?? '',
                    'repsInput': set.repsInput ?? '',
                  },
              ],
            },
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  Future<void> deleteWorkoutDraft() async {
    final response = await _client.delete(Uri.parse('$_baseUrl/workout-draft'));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  Future<List<PreviousSet>> getPreviousSets(
    String exerciseName, {
    String? routineId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/exercises/previous',
    ).replace(queryParameters: {'name': exerciseName, 'routineId': ?routineId});
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

  Future<int> getRestTimerSeconds(
    String exerciseName, {
    bool betweenExercises = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/exercises/rest-timer').replace(
      queryParameters: {
        'name': exerciseName,
        if (betweenExercises) 'kind': 'exercises',
      },
    );
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
    bool betweenExercises = false,
  }) async {
    final response = await _client.put(
      Uri.parse('$_baseUrl/exercises/rest-timer'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'name': exerciseName,
        'restSeconds': restSeconds,
        if (betweenExercises) 'kind': 'exercises',
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  void close() => _client.close();
}
