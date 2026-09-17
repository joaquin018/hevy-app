class WorkoutHistoryPage {
  const WorkoutHistoryPage({
    required this.sessions,
    required this.total,
    required this.hasMore,
  });
  final List<WorkoutHistorySession> sessions;
  final int total;
  final bool hasMore;
}

class WorkoutHistorySession {
  WorkoutHistorySession.fromJson(Map<String, dynamic> value)
    : id = value['id'] as String,
      name = value['routineName'] as String? ?? 'Entrenamiento',
      startedAt = DateTime.parse(value['startedAt'] as String).toLocal(),
      durationSeconds = value['durationSeconds'] as int,
      volumeKg = (value['volumeKg'] as num).toDouble(),
      records = value['records'] as int,
      exercises = (value['exercises'] as List)
          .map((v) => HistoryExercise.fromJson(v as Map<String, dynamic>))
          .toList();
  final String id;
  final String name;
  final DateTime startedAt;
  final int durationSeconds;
  final double volumeKg;
  final int records;
  final List<HistoryExercise> exercises;
}

class HistoryExercise {
  HistoryExercise.fromJson(Map<String, dynamic> value)
    : name = value['name'] as String,
      sets = (value['sets'] as List)
          .map((v) => HistorySet.fromJson(v as Map<String, dynamic>))
          .toList();
  final String name;
  final List<HistorySet> sets;
}

class HistorySet {
  HistorySet.fromJson(Map<String, dynamic> value)
    : type = value['type'] as String,
      kg = (value['kg'] as num).toDouble(),
      reps = value['reps'] as int,
      isRecord = value['isRecord'] as bool;
  final String type;
  final double kg;
  final int reps;
  final bool isRecord;
}
