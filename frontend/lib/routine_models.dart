import 'dart:math';

import 'package:flutter/foundation.dart';

String newRoutineId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class RoutinePayload {
  const RoutinePayload({
    required this.id,
    required this.name,
    required this.exercises,
  });
  final String id;
  final String name;
  final List<String> exercises;
  factory RoutinePayload.fromJson(Map<String, dynamic> json) => RoutinePayload(
    id: json['id'] as String,
    name: json['name'] as String,
    exercises: List<String>.from(json['exercises'] as List),
  );
}

class RoutineFolderPayload {
  const RoutineFolderPayload({
    required this.id,
    required this.name,
    required this.routines,
  });
  final String id;
  final String name;
  final List<RoutinePayload> routines;
  factory RoutineFolderPayload.fromJson(Map<String, dynamic> json) =>
      RoutineFolderPayload(
        id: json['id'] as String,
        name: json['name'] as String,
        routines: (json['routines'] as List)
            .map((r) => RoutinePayload.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}

class RoutineLibraryPayload {
  const RoutineLibraryPayload({required this.version, required this.folders});
  final int version;
  final List<RoutineFolderPayload> folders;
  factory RoutineLibraryPayload.fromJson(Map<String, dynamic> json) =>
      RoutineLibraryPayload(
        version: json['version'] as int,
        folders: (json['folders'] as List)
            .map(
              (f) => RoutineFolderPayload.fromJson(f as Map<String, dynamic>),
            )
            .toList(),
      );

  Map<String, dynamic> changesTo(List<RoutineFolderPayload> next) {
    final oldFolders = {for (final f in folders) f.id: f};
    final oldRoutines = <String, Map<String, dynamic>>{};
    for (final f in folders) {
      for (var i = 0; i < f.routines.length; i++) {
        oldRoutines[f.routines[i].id] = {
          'routine': f.routines[i],
          'folderId': f.id,
          'position': i,
        };
      }
    }
    final folderChanges = <Map<String, dynamic>>[];
    final routineChanges = <Map<String, dynamic>>[];
    final nextRoutineIds = <String>{};
    for (var fi = 0; fi < next.length; fi++) {
      final f = next[fi], old = oldFolders[f.id];
      if (old == null || old.name != f.name || folders.indexOf(old) != fi) {
        folderChanges.add({'id': f.id, 'name': f.name, 'position': fi});
      }
      for (var ri = 0; ri < f.routines.length; ri++) {
        final r = f.routines[ri], previous = oldRoutines[r.id];
        final oldRoutine = previous?['routine'] as RoutinePayload?;
        nextRoutineIds.add(r.id);
        final exercisesChanged =
            oldRoutine == null ||
            !listEquals(oldRoutine.exercises, r.exercises);
        if (previous == null ||
            oldRoutine!.name != r.name ||
            previous['folderId'] != f.id ||
            previous['position'] != ri ||
            exercisesChanged) {
          routineChanges.add({
            'id': r.id,
            'folderId': f.id,
            'name': r.name,
            'position': ri,
            if (exercisesChanged) 'exercises': r.exercises,
          });
        }
      }
    }
    final nextFolderIds = next.map((f) => f.id).toSet();
    final removedFolderIds = oldFolders.keys
        .where((id) => !nextFolderIds.contains(id))
        .toList();
    return {
      'version': version,
      'folders': folderChanges,
      'routines': routineChanges,
      'deletedFolders': removedFolderIds,
      'deletedRoutines': oldRoutines.entries
          .where(
            (entry) =>
                !nextRoutineIds.contains(entry.key) &&
                !removedFolderIds.contains(entry.value['folderId']),
          )
          .map((entry) => entry.key)
          .toList(),
    };
  }
}

class RoutineRecipient {
  const RoutineRecipient({required this.id, required this.email});
  final String id;
  final String email;
  factory RoutineRecipient.fromJson(Map<String, dynamic> json) =>
      RoutineRecipient(
        id: json['id'] as String,
        email: json['email'] as String,
      );
}

class RoutineShare {
  const RoutineShare({
    required this.id,
    required this.name,
    required this.exerciseCount,
    required this.senderEmail,
    required this.recipientEmail,
    required this.status,
    required this.createdAt,
  });
  final String id, name, senderEmail, recipientEmail, status;
  final int exerciseCount;
  final DateTime createdAt;
  factory RoutineShare.fromJson(Map<String, dynamic> json) => RoutineShare(
    id: json['id'] as String,
    name: json['name'] as String,
    exerciseCount: json['exerciseCount'] as int,
    senderEmail: json['senderEmail'] as String,
    recipientEmail: json['recipientEmail'] as String,
    status: json['status'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class RoutineSharePage {
  const RoutineSharePage({required this.items, this.nextCursor});
  final List<RoutineShare> items;
  final String? nextCursor;
}

class RoutinePreview {
  const RoutinePreview({required this.name, required this.exercises});
  final String name;
  final List<String> exercises;
}
