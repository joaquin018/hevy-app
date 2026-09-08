import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'workout_api.dart';
import 'workout_history_page.dart';

const _accent = Color(0xFF7C8CFF);
const _page = Color(0xFF090B0F);
const _card = Color(0xFF11141A);
const _surface = Color(0xB31C2028);
const _muted = Color(0xFF9399A6);
const _border = Color(0x24FFFFFF);

class _ActiveWorkout {
  const _ActiveWorkout({
    required this.routineName,
    required this.startedAt,
    required this.exercises,
    required this.originalExercises,
    required this.firstExercise,
    required this.results,
  });

  final String routineName;
  final DateTime startedAt;
  final List<String> exercises;
  final List<String> originalExercises;
  final String firstExercise;
  final Map<String, List<WorkoutSetPayload>> results;
}

final _activeWorkout = ValueNotifier<_ActiveWorkout?>(null);

class _AtmosphericBackground extends StatelessWidget {
  const _AtmosphericBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _page,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -90,
                  right: -80,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 65, sigmaY: 65),
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF24445A).withValues(alpha: 0.14),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 300,
                  left: -120,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 85, sigmaY: 85),
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF25304A).withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -130,
                  bottom: -70,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 95, sigmaY: 95),
                    child: Container(
                      width: 320,
                      height: 320,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1A3548).withValues(alpha: 0.14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class HelloApp extends StatelessWidget {
  const HelloApp({super.key, this.enableCloudPersistence = true});

  final bool enableCloudPersistence;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'i7l',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _page,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          surface: _surface,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: WorkoutHomePage(enableCloudPersistence: enableCloudPersistence),
    );
  }
}

class WorkoutHomePage extends StatefulWidget {
  const WorkoutHomePage({super.key, this.enableCloudPersistence = true});

  final bool enableCloudPersistence;

  @override
  State<WorkoutHomePage> createState() => _WorkoutHomePageState();
}

class _RoutineData {
  const _RoutineData(this.name, this.exercises);

  final String name;
  final List<String> exercises;
}

class _WorkoutHomePageState extends State<WorkoutHomePage> {
  final WorkoutApi _workoutApi = WorkoutApi();
  final List<String> _folders = [];
  final Map<String, List<_RoutineData>> _folderRoutines = {};

  @override
  void initState() {
    super.initState();
    if (widget.enableCloudPersistence) {
      _loadRoutineFolders();
      _loadActiveWorkoutDraft();
    }
  }

  Future<void> _loadActiveWorkoutDraft() async {
    try {
      final draft = await _workoutApi.getWorkoutDraft();
      if (!mounted || draft == null) return;
      final results = {
        for (final exercise in draft.exercises)
          exercise.name: List<WorkoutSetPayload>.of(exercise.sets),
      };
      _activeWorkout.value = _ActiveWorkout(
        routineName: draft.routineName,
        startedAt: draft.startedAt,
        exercises: draft.exercises.map((exercise) => exercise.name).toList(),
        originalExercises: draft.originalExercises,
        firstExercise: draft.exercises.isEmpty
            ? 'Sin ejercicios'
            : draft.exercises.first.name,
        results: results,
      );
    } catch (_) {
      // La pantalla principal puede continuar aunque el borrador no cargue.
    }
  }

  Future<void> _loadRoutineFolders() async {
    try {
      final savedFolders = await _workoutApi.getRoutineFolders();
      if (!mounted) return;
      setState(() {
        _folders
          ..clear()
          ..addAll(savedFolders.map((folder) => folder.name));
        _folderRoutines
          ..clear()
          ..addEntries(
            savedFolders.map(
              (folder) => MapEntry(folder.name, [
                for (final routine in folder.routines)
                  _RoutineData(routine.name, routine.exercises),
              ]),
            ),
          );
      });
    } catch (_) {
      if (mounted) _showPersistenceError();
    }
  }

  Future<void> _persistRoutineFolders() async {
    if (!widget.enableCloudPersistence) return;
    try {
      await _workoutApi.saveRoutineFolders([
        for (final folder in _folders)
          RoutineFolderPayload(
            name: folder,
            routines: [
              for (final routine in _folderRoutines[folder]!)
                RoutinePayload(
                  name: routine.name,
                  exercises: routine.exercises,
                ),
            ],
          ),
      ]);
    } catch (_) {
      if (mounted) _showPersistenceError();
    }
  }

  void _showPersistenceError() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF292C34),
          content: Text(
            'No se pudieron sincronizar las rutinas con la nube.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
  }

  Future<void> _createFolder() async {
    var folderName = '';
    final name = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171A22),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _border),
        ),
        title: const Text('Nueva carpeta'),
        content: TextField(
          key: const ValueKey('nombre-carpeta'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [_CapitalizedCaseFormatter()],
          decoration: const InputDecoration(
            hintText: 'Nombre de la carpeta',
            hintStyle: TextStyle(color: _muted, fontSize: 16),
          ),
          onChanged: (value) => folderName = value,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final name = folderName.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (!mounted || name == null) return;
    setState(() {
      _folders.add(name);
      _folderRoutines[name] = [];
    });
    await _persistRoutineFolders();
  }

  Future<void> _renameFolder(int index) async {
    final currentName = _folders[index];
    var updatedName = currentName;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171A22),
        surfaceTintColor: Colors.transparent,
        title: const Text('Cambiar nombre de carpeta'),
        content: TextFormField(
          key: const ValueKey('editar-nombre-carpeta'),
          initialValue: currentName,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [_CapitalizedCaseFormatter()],
          onChanged: (value) => updatedName = value,
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('guardar-nombre-carpeta'),
            onPressed: () {
              final value = updatedName.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (!mounted || name == null || name == currentName) return;
    setState(() {
      final routines = _folderRoutines.remove(currentName)!;
      _folders[index] = name;
      _folderRoutines[name] = routines;
    });
    await _persistRoutineFolders();
  }

  Future<void> _deleteFolder(int index) async {
    final folder = _folders[index];
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171A22),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _border),
        ),
        title: const Text('Eliminar carpeta'),
        content: Text(
          '¿Quieres eliminar “$folder” y todas las rutinas que contiene?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const ValueKey('confirmar-eliminar-carpeta'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF5C68),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _folders.removeAt(index);
      _folderRoutines.remove(folder);
    });
    await _persistRoutineFolders();
  }

  Future<void> _openFolderOptions(int index) async {
    final action = await showModalBottomSheet<_ItemManagementAction>(
      context: context,
      backgroundColor: _card,
      barrierColor: Colors.black.withValues(alpha: 0.76),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) =>
          const _ItemManagementSheet(itemType: 'carpeta', canReorder: true),
    );
    if (!mounted || action == null) return;
    if (action == _ItemManagementAction.reorder) {
      await _reorderFolders();
    } else if (action == _ItemManagementAction.rename) {
      await _renameFolder(index);
    } else {
      await _deleteFolder(index);
    }
  }

  Future<void> _reorderFolders() async {
    final folders = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => _ReorderFoldersPage(
          folders: _folders,
          routineCounts: {
            for (final folder in _folders)
              folder: _folderRoutines[folder]!.length,
          },
        ),
      ),
    );
    if (!mounted || folders == null) return;
    setState(() {
      final removedFolders = _folders.where(
        (folder) => !folders.contains(folder),
      );
      for (final folder in removedFolders) {
        _folderRoutines.remove(folder);
      }
      _folders
        ..clear()
        ..addAll(folders);
    });
    await _persistRoutineFolders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _AtmosphericBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _RoutinesHeader(
                onCreateFolder: _createFolder,
                onHistory: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WorkoutHistoryScreen(
                        loadHistory: widget.enableCloudPersistence
                            ? (offset) => _workoutApi.getHistory(offset: offset)
                            : null,
                      ),
                    ),
                  );
                },
              ),
              Expanded(
                child: _folders.isEmpty
                    ? _EmptyFolders(onCreateFolder: _createFolder)
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          18,
                          18,
                          18,
                          MediaQuery.paddingOf(context).bottom + 36,
                        ),
                        itemCount: _folders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final folder = _folders[index];
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              key: ValueKey('carpeta-$folder'),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => _RoutineFolderPage(
                                      name: folder,
                                      routines: _folderRoutines[folder]!,
                                      onChanged: _persistRoutineFolders,
                                    ),
                                  ),
                                );
                                if (mounted) setState(() {});
                              },
                              tileColor: _surface,
                              shape: RoundedRectangleBorder(
                                side: const BorderSide(color: _border),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              leading: const Icon(
                                Icons.folder_outlined,
                                color: _accent,
                                size: 30,
                              ),
                              title: Text(
                                folder,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                _folderRoutines[folder]!.isEmpty
                                    ? 'Sin rutinas'
                                    : '${_folderRoutines[folder]!.length} rutinas',
                                style: const TextStyle(color: _muted),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey('opciones-carpeta-$folder'),
                                    onPressed: () => _openFolderOptions(index),
                                    tooltip: 'Opciones de carpeta',
                                    icon: const Icon(
                                      Icons.more_vert,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutineFolderPage extends StatefulWidget {
  const _RoutineFolderPage({
    required this.name,
    required this.routines,
    required this.onChanged,
  });

  final String name;
  final List<_RoutineData> routines;
  final Future<void> Function() onChanged;

  @override
  State<_RoutineFolderPage> createState() => _RoutineFolderPageState();
}

class _RoutineFolderPageState extends State<_RoutineFolderPage> {
  Future<void> _openWorkout({
    required List<String> exercises,
    required String routineName,
    DateTime? resumeStartedAt,
    List<String>? originalExercises,
    Map<String, List<WorkoutSetPayload>> initialResults = const {},
  }) {
    return Navigator.of(context)
        .push<List<String>>(
          MaterialPageRoute<List<String>>(
            builder: (_) => WorkoutPage(
              initialExercises: exercises,
              routineName: routineName,
              resumeStartedAt: resumeStartedAt,
              originalExercises: originalExercises,
              initialResults: initialResults,
            ),
          ),
        )
        .then((updatedExercises) async {
          if (!mounted || updatedExercises == null) return;
          final index = widget.routines.indexWhere(
            (routine) => routine.name == routineName,
          );
          if (index < 0) return;
          setState(() {
            widget.routines[index] = _RoutineData(
              routineName,
              updatedExercises,
            );
          });
          await widget.onChanged();
        });
  }

  Future<void> _startRoutine(_RoutineData routine) async {
    final active = _activeWorkout.value;
    if (active == null) {
      _openWorkout(exercises: routine.exercises, routineName: routine.name);
      return;
    }

    final action = await showDialog<_WorkoutConflictAction>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.84),
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF171A22),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Hay un entrenamiento en curso',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text(
                'Si inicias uno nuevo, el entrenamiento actual se eliminará permanentemente.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.45),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('retomar-entrenamiento-activo'),
                  onPressed: () =>
                      Navigator.of(context).pop(_WorkoutConflictAction.resume),
                  style: FilledButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Retomar entrenamiento en curso'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('iniciar-nuevo-entrenamiento'),
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(_WorkoutConflictAction.startNew),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF292C34),
                    foregroundColor: const Color(0xFFFF5C68),
                  ),
                  child: const Text('Iniciar nuevo entrenamiento'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF292C34),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == _WorkoutConflictAction.resume) {
      _openWorkout(
        exercises: active.exercises,
        originalExercises: active.originalExercises,
        routineName: active.routineName,
        resumeStartedAt: active.startedAt,
        initialResults: active.results,
      );
      return;
    }
    _activeWorkout.value = null;
    _openWorkout(exercises: routine.exercises, routineName: routine.name);
  }

  Future<void> _createRoutine() async {
    var routineName = '';
    final name = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171A22),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _border),
        ),
        title: const Text('Nueva rutina'),
        content: TextField(
          key: const ValueKey('nombre-rutina'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [_CapitalizedCaseFormatter()],
          decoration: const InputDecoration(
            hintText: 'Nombre de la rutina',
            hintStyle: TextStyle(color: _muted, fontSize: 16),
          ),
          onChanged: (value) => routineName = value,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final name = routineName.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (!mounted || name == null) return;
    setState(() => widget.routines.insert(0, _RoutineData(name, const [])));
    await widget.onChanged();
  }

  Future<void> _renameRoutine(int index) async {
    final routine = widget.routines[index];
    var updatedName = routine.name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171A22),
        surfaceTintColor: Colors.transparent,
        title: const Text('Cambiar nombre de rutina'),
        content: TextFormField(
          key: const ValueKey('editar-nombre-rutina'),
          initialValue: routine.name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const [_CapitalizedCaseFormatter()],
          onChanged: (value) => updatedName = value,
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('guardar-nombre-rutina'),
            onPressed: () {
              final value = updatedName.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (!mounted || name == null || name == routine.name) return;
    setState(() {
      widget.routines[index] = _RoutineData(name, routine.exercises);
    });
    await widget.onChanged();
  }

  Future<void> _editRoutine(int index) async {
    final active = _activeWorkout.value;
    if (active != null) {
      await _openWorkout(
        exercises: active.exercises,
        originalExercises: active.originalExercises,
        routineName: active.routineName,
        resumeStartedAt: active.startedAt,
        initialResults: active.results,
      );
      return;
    }
    final routine = widget.routines[index];
    final exercises = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => WorkoutPage(
          initialExercises: routine.exercises,
          isEditing: true,
          routineName: routine.name,
        ),
      ),
    );
    if (!mounted || exercises == null) return;
    setState(() {
      widget.routines[index] = _RoutineData(routine.name, exercises);
    });
    await widget.onChanged();
  }

  Future<void> _deleteRoutine(int index) async {
    final routine = widget.routines[index];
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171A22),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _border),
        ),
        title: const Text('Eliminar rutina'),
        content: Text(
          '¿Quieres eliminar “${routine.name}” y todos sus ejercicios?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const ValueKey('confirmar-eliminar-rutina'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF5C68),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => widget.routines.removeAt(index));
    await widget.onChanged();
  }

  Future<void> _openRoutineOptions(int index) async {
    final action = await showModalBottomSheet<_ItemManagementAction>(
      context: context,
      backgroundColor: _card,
      barrierColor: Colors.black.withValues(alpha: 0.76),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) =>
          const _ItemManagementSheet(itemType: 'rutina', canReorder: true),
    );
    if (!mounted || action == null) return;
    if (action == _ItemManagementAction.reorder) {
      await _reorderRoutines();
    } else if (action == _ItemManagementAction.rename) {
      await _renameRoutine(index);
    } else {
      await _deleteRoutine(index);
    }
  }

  Future<void> _reorderRoutines() async {
    final routines = await Navigator.of(context).push<List<_RoutineData>>(
      MaterialPageRoute<List<_RoutineData>>(
        builder: (_) => _ReorderRoutinesPage(routines: widget.routines),
      ),
    );
    if (!mounted || routines == null) return;
    setState(() {
      widget.routines
        ..clear()
        ..addAll(routines);
    });
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: _AtmosphericBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _FolderHeader(name: widget.name, onCreateRoutine: _createRoutine),
              Expanded(
                child: widget.routines.isEmpty
                    ? _EmptyRoutines(onCreateRoutine: _createRoutine)
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          18,
                          18,
                          18,
                          MediaQuery.paddingOf(context).bottom + 36,
                        ),
                        itemCount: widget.routines.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final routine = widget.routines[index];
                          return _RoutineCard(
                            day: routine.name,
                            exercises: routine.exercises,
                            onOptions: () => _openRoutineOptions(index),
                            onEdit: () => _editRoutine(index),
                            onStart: () => _startRoutine(routine),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: ValueListenableBuilder<_ActiveWorkout?>(
        valueListenable: _activeWorkout,
        builder: (context, activeWorkout, _) {
          if (activeWorkout == null) return const SizedBox.shrink();
          return _ActiveWorkoutBanner(
            workout: activeWorkout,
            onResume: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WorkoutPage(
                  initialExercises: activeWorkout.exercises,
                  originalExercises: activeWorkout.originalExercises,
                  routineName: activeWorkout.routineName,
                  resumeStartedAt: activeWorkout.startedAt,
                  initialResults: activeWorkout.results,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _WorkoutConflictAction { resume, startNew }

class _RoutinesHeader extends StatelessWidget {
  const _RoutinesHeader({
    required this.onCreateFolder,
    required this.onHistory,
  });

  final VoidCallback onCreateFolder;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      color: _card,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Rutinas',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('abrir-historial'),
            tooltip: 'Historial',
            onPressed: onHistory,
            icon: const Icon(Icons.history_rounded, color: _accent),
          ),
          IconButton(
            key: const ValueKey('crear-carpeta'),
            onPressed: onCreateFolder,
            icon: const Icon(
              Icons.create_new_folder_outlined,
              size: 25,
              color: _accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFolders extends StatelessWidget {
  const _EmptyFolders({required this.onCreateFolder});

  final VoidCallback onCreateFolder;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_outlined, color: _accent, size: 52),
            const SizedBox(height: 18),
            const Text(
              'Aún no hay carpetas',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crea una carpeta para organizar tus rutinas de entrenamiento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              key: const ValueKey('crear-primera-carpeta'),
              onPressed: onCreateFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Crear carpeta'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ItemManagementAction { reorder, rename, delete }

class _ItemManagementSheet extends StatelessWidget {
  const _ItemManagementSheet({required this.itemType, this.canReorder = false});

  final String itemType;
  final bool canReorder;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canReorder)
                _ExerciseOption(
                  icon: Icons.swap_vert,
                  label: itemType == 'carpeta'
                      ? 'Reordenar carpetas'
                      : 'Reordenar rutinas',
                  onTap: () =>
                      Navigator.of(context).pop(_ItemManagementAction.reorder),
                ),
              _ExerciseOption(
                icon: Icons.edit_outlined,
                label: 'Cambiar nombre',
                onTap: () =>
                    Navigator.of(context).pop(_ItemManagementAction.rename),
              ),
              _ExerciseOption(
                icon: Icons.delete_outline,
                label: 'Eliminar $itemType',
                destructive: true,
                last: true,
                onTap: () =>
                    Navigator.of(context).pop(_ItemManagementAction.delete),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderHeader extends StatelessWidget {
  const _FolderHeader({required this.name, required this.onCreateRoutine});

  final String name;
  final VoidCallback onCreateRoutine;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      color: _card,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            key: const ValueKey('crear-rutina'),
            onPressed: onCreateRoutine,
            tooltip: 'Crear rutina',
            icon: const Icon(Icons.add, color: _accent, size: 27),
          ),
        ],
      ),
    );
  }
}

class _EmptyRoutines extends StatelessWidget {
  const _EmptyRoutines({required this.onCreateRoutine});

  final VoidCallback onCreateRoutine;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fitness_center, color: _accent, size: 50),
            const SizedBox(height: 18),
            const Text(
              'Aún no hay rutinas',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crea una rutina para organizar los ejercicios de tu entrenamiento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              key: const ValueKey('crear-primera-rutina'),
              onPressed: onCreateRoutine,
              icon: const Icon(Icons.add),
              label: const Text('Crear rutina'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.day,
    required this.exercises,
    required this.onOptions,
    required this.onEdit,
    required this.onStart,
  });

  final String day;
  final List<String> exercises;
  final VoidCallback onOptions;
  final VoidCallback onEdit;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: _surface,
          child: InkWell(
            key: ValueKey('editar-rutina-$day'),
            onTap: onEdit,
            child: Container(
              height: 172,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              decoration: BoxDecoration(
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          day,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        key: ValueKey('opciones-rutina-$day'),
                        onPressed: onOptions,
                        tooltip: 'Opciones de rutina',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    exercises.isEmpty ? 'Sin ejercicios' : exercises.join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 15.5,
                      height: 1.45,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: FilledButton(
                        key: ValueKey('iniciar-rutina-$day'),
                        onPressed: onStart,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: const Text(
                          'Iniciar rutina',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveWorkoutBanner extends StatefulWidget {
  const _ActiveWorkoutBanner({required this.workout, required this.onResume});

  final _ActiveWorkout workout;
  final VoidCallback onResume;

  @override
  State<_ActiveWorkoutBanner> createState() => _ActiveWorkoutBannerState();
}

class _ActiveWorkoutBannerState extends State<_ActiveWorkoutBanner> {
  Timer? _ticker;

  int get _elapsed =>
      DateTime.now().difference(widget.workout.startedAt).inSeconds;

  String get _formattedElapsed {
    final elapsed = _elapsed;
    final hours = elapsed ~/ 3600;
    final minutes = (elapsed % 3600) ~/ 60;
    final seconds = elapsed % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171A22),
        surfaceTintColor: Colors.transparent,
        title: const Text('Descartar entrenamiento'),
        content: const Text('¿Quieres descartar el entrenamiento en curso?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const ValueKey('confirmar-descartar-entrenamiento'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF5C68),
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await WorkoutApi().deleteWorkoutDraft();
      } catch (_) {
        // El estado local se descarta aunque la API no esté disponible.
      }
      _activeWorkout.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Material(
          color: const Color(0xFF1A1D24),
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            key: const ValueKey('entrenamiento-activo'),
            onTap: widget.onResume,
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(
              height: 66,
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFF292C34),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.keyboard_arrow_up, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                color: Color(0xFF62D84E),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${widget.workout.routineName} $_formattedElapsed',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.workout.firstExercise,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('descartar-entrenamiento-activo'),
                    onPressed: _discard,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFFF5C68),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkoutPage extends StatefulWidget {
  const WorkoutPage({
    super.key,
    this.initialExercises = const ['Press Banca Inclinado Con Barra', 'Fondos'],
    this.isEditing = false,
    this.routineName,
    this.resumeStartedAt,
    this.originalExercises,
    this.initialResults = const {},
  });

  final List<String> initialExercises;
  final bool isEditing;
  final String? routineName;
  final DateTime? resumeStartedAt;
  final List<String>? originalExercises;
  final Map<String, List<WorkoutSetPayload>> initialResults;

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  Timer? _restTicker;
  Timer? _workoutTicker;
  Timer? _draftSaveDebounce;
  int? _remainingSeconds;
  int _totalSeconds = 1;
  int _elapsedSeconds = 0;
  double _totalVolume = 0;
  bool _workoutClosed = false;
  late List<String> _exerciseOrder;
  late final List<String> _initialExerciseOrder;
  late final DateTime _startedAt;
  final Map<String, List<_SetData>> _exerciseSets = {};
  final Map<String, List<WorkoutSetPayload>> _workoutResults = {};
  final WorkoutApi _workoutApi = WorkoutApi();

  @override
  void initState() {
    super.initState();
    _exerciseOrder = List.of(widget.initialExercises);
    _initialExerciseOrder = List.of(
      widget.originalExercises ?? widget.initialExercises,
    );
    _workoutResults.addAll({
      for (final entry in widget.initialResults.entries)
        entry.key: List<WorkoutSetPayload>.of(entry.value),
    });
    for (final exercise in _exerciseOrder) {
      final savedSets = _workoutResults[exercise];
      _exerciseSets.putIfAbsent(
        exercise,
        () => savedSets == null || savedSets.isEmpty
            ? const [_SetData('1', '—', '', '')]
            : [
                for (var index = 0; index < savedSets.length; index++)
                  _SetData(
                    _setLabelFor(savedSets[index].type, index),
                    '—',
                    savedSets[index].kgInput ??
                        (savedSets[index].completed
                            ? _formatDraftKg(savedSets[index].kg)
                            : ''),
                    savedSets[index].repsInput ??
                        (savedSets[index].completed
                            ? savedSets[index].reps.toString()
                            : ''),
                    completed: savedSets[index].completed,
                  ),
              ],
      );
    }
    _totalVolume = _workoutResults.values
        .expand((sets) => sets)
        .where((set) => set.completed)
        .fold(0, (total, set) => total + (set.kg * set.reps));
    if (widget.isEditing) return;
    final startedAt = widget.resumeStartedAt ?? DateTime.now();
    _startedAt = startedAt;
    _elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
    final activeWorkout = _ActiveWorkout(
      routineName: widget.routineName ?? 'Rutina',
      startedAt: startedAt,
      exercises: List.of(_exerciseOrder),
      originalExercises: List.of(_initialExerciseOrder),
      firstExercise: _exerciseOrder.isEmpty
          ? 'Sin ejercicios'
          : _exerciseOrder.first,
      results: _copyWorkoutResults(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeWorkout.value = activeWorkout;
      _persistActiveWorkout();
    });
    _loadPreviousHistory();
    _workoutTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  static String _setLabelFor(String type, int index) => switch (type) {
    'warmup' => 'W',
    'failure' => 'F',
    'drop' => 'D',
    _ => '${index + 1}',
  };

  static String _formatDraftKg(double kg) => kg == kg.roundToDouble()
      ? kg.round().toString()
      : kg.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  Map<String, List<WorkoutSetPayload>> _copyWorkoutResults() => {
    for (final exercise in _exerciseOrder)
      exercise: List<WorkoutSetPayload>.of(
        _workoutResults[exercise] ?? const [],
      ),
  };

  Future<void> _persistActiveWorkout() async {
    if (widget.isEditing) return;
    try {
      await _workoutApi.saveWorkoutDraft(
        WorkoutDraftPayload(
          routineName: widget.routineName ?? 'Rutina',
          startedAt: _startedAt,
          originalExercises: List.of(_initialExerciseOrder),
          exercises: [
            for (final exercise in _exerciseOrder)
              WorkoutExercisePayload(
                name: exercise,
                sets: List<WorkoutSetPayload>.of(
                  _workoutResults[exercise] ?? const [],
                ),
              ),
          ],
        ),
      );
    } catch (_) {
      // Se reintentará con el próximo cambio del entrenamiento.
    }
  }

  void _scheduleDraftSave() {
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(
      const Duration(milliseconds: 200),
      _persistActiveWorkout,
    );
  }

  String get _formattedElapsedTime {
    final hours = _elapsedSeconds ~/ 3600;
    final minutes = (_elapsedSeconds % 3600) ~/ 60;
    final seconds = _elapsedSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _loadPreviousHistory() async {
    await Future.wait(
      _exerciseOrder.map((exercise) async {
        try {
          final previousSets = await _workoutApi.getPreviousSets(exercise);
          if (!mounted || previousSets.isEmpty) return;
          final currentSets = List<_SetData>.of(
            _exerciseSets[exercise] ?? const [],
          );
          while (widget.resumeStartedAt == null &&
              currentSets.length < previousSets.length) {
            currentSets.add(_SetData('${currentSets.length + 1}', '—', '', ''));
          }
          final comparableSetCount = currentSets.length < previousSets.length
              ? currentSets.length
              : previousSets.length;
          for (var index = 0; index < comparableSetCount; index++) {
            final previous = previousSets[index];
            final current = currentSets[index];
            final kg = previous.kg == previous.kg.roundToDouble()
                ? previous.kg.round().toString()
                : previous.kg
                      .toStringAsFixed(2)
                      .replaceFirst(RegExp(r'\.?0+$'), '');
            currentSets[index] = _SetData(
              current.set,
              '${kg}kg x ${previous.reps}',
              current.kg,
              current.reps,
              placeholderKg: kg,
              placeholderReps: previous.reps.toString(),
              completed: current.completed,
            );
          }
          _exerciseSets[exercise] = currentSets;
        } catch (_) {
          // La sesión puede continuar aunque el historial no esté disponible.
        }
      }),
    );
    if (mounted) setState(() {});
  }

  String get _formattedVolume {
    final value = _totalVolume.round().toString();
    final grouped = value.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '$grouped kg';
  }

  void _updateVolume(double difference) {
    setState(() {
      _totalVolume = (_totalVolume + difference).clamp(0, double.infinity);
    });
  }

  Future<void> _openExercisePicker() async {
    final exercise = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const AddExercisePage()),
    );
    if (!mounted || exercise == null) return;
    if (_exerciseOrder.contains(exercise)) {
      _showDuplicateExerciseMessage(exercise);
      return;
    }
    setState(() {
      _exerciseOrder.add(exercise);
      _exerciseSets[exercise] = const [_SetData('1', '—', '', '')];
    });
    _syncActiveWorkout();
    _loadPreviousHistory();
  }

  void _showDuplicateExerciseMessage(String exercise) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF252936),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _border),
          ),
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: _accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '“$exercise” ya está en esta rutina.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _syncActiveWorkout() {
    if (widget.isEditing) return;
    final active = _activeWorkout.value;
    if (active == null) return;
    _activeWorkout.value = _ActiveWorkout(
      routineName: active.routineName,
      startedAt: active.startedAt,
      exercises: List.of(_exerciseOrder),
      originalExercises: List.of(_initialExerciseOrder),
      firstExercise: _exerciseOrder.isEmpty
          ? 'Sin ejercicios'
          : _exerciseOrder.first,
      results: _copyWorkoutResults(),
    );
    _scheduleDraftSave();
  }

  void _removeExercise(String exercise) {
    setState(() {
      _exerciseOrder.remove(exercise);
      _exerciseSets.remove(exercise);
      _workoutResults.remove(exercise);
    });
    _syncActiveWorkout();
  }

  void _replaceExercise(String current, String replacement) {
    if (replacement != current && _exerciseOrder.contains(replacement)) {
      _showDuplicateExerciseMessage(replacement);
      return;
    }
    setState(() {
      final index = _exerciseOrder.indexOf(current);
      if (index < 0) return;
      _exerciseOrder[index] = replacement;
      _exerciseSets[replacement] =
          _exerciseSets.remove(current) ?? const [_SetData('1', '—', '', '')];
      final results = _workoutResults.remove(current);
      if (results != null) _workoutResults[replacement] = results;
    });
    _syncActiveWorkout();
    _loadPreviousHistory();
  }

  Future<void> _reorderExercises() async {
    final order = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => _ReorderExercisesPage(exercises: _exerciseOrder),
      ),
    );
    if (!mounted || order == null) return;
    setState(() {
      _exerciseOrder = order;
      _exerciseSets.removeWhere((name, _) => !order.contains(name));
    });
    _syncActiveWorkout();
  }

  void _startRestTimer(int seconds) {
    _restTicker?.cancel();
    setState(() {
      _totalSeconds = seconds;
      _remainingSeconds = seconds;
    });
    _restTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _remainingSeconds == null) return;
      if (_remainingSeconds! <= 1) {
        _skipRestTimer();
      } else {
        setState(() => _remainingSeconds = _remainingSeconds! - 1);
      }
    });
  }

  void _adjustTimer(int seconds) {
    if (_remainingSeconds == null) return;
    setState(() {
      _remainingSeconds = (_remainingSeconds! + seconds).clamp(0, 3599);
      _totalSeconds = _totalSeconds.clamp(_remainingSeconds!, 3599);
    });
    if (_remainingSeconds == 0) _skipRestTimer();
  }

  void _skipRestTimer() {
    _restTicker?.cancel();
    if (mounted) setState(() => _remainingSeconds = null);
  }

  Future<void> _showFinishSheet() {
    return _finishWorkout();
  }

  Future<void> _finishWorkout() async {
    var updateRoutine = false;
    final routineChanged = !listEquals(_initialExerciseOrder, _exerciseOrder);
    if (routineChanged) {
      final decision = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: _card,
        barrierColor: Colors.black.withValues(alpha: 0.76),
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _FinishWorkoutSheet(
          routineName: widget.routineName ?? 'Rutina',
          changeDescription: _routineChangeDescription,
        ),
      );
      if (!mounted || decision == null) return;
      updateRoutine = decision;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _card,
      barrierColor: Colors.black.withValues(alpha: 0.76),
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _SaveWorkoutSheet(),
    );
    if (!mounted || confirmed != true) return;

    try {
      _draftSaveDebounce?.cancel();
      await _workoutApi.saveSession(
        routineName: widget.routineName ?? 'Rutina',
        startedAt: _startedAt,
        completedAt: DateTime.now(),
        durationSeconds: _elapsedSeconds,
        exercises: [
          for (final exercise in _exerciseOrder)
            WorkoutExercisePayload(
              name: exercise,
              sets: _workoutResults[exercise] ?? const [],
            ),
        ],
      );
      _workoutClosed = true;
      try {
        await _workoutApi.deleteWorkoutDraft();
      } catch (_) {
        // La sesión ya se guardó; no se vuelve a crear el borrador al salir.
      }
      _activeWorkout.value = null;
      if (mounted) {
        Navigator.of(
          context,
        ).pop(updateRoutine ? List<String>.of(_exerciseOrder) : null);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF292C34),
          content: Text(
            'No se pudo guardar el entrenamiento. Inténtalo nuevamente.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  String get _routineChangeDescription {
    final added = _exerciseOrder
        .where((exercise) => !_initialExerciseOrder.contains(exercise))
        .length;
    final removed = _initialExerciseOrder
        .where((exercise) => !_exerciseOrder.contains(exercise))
        .length;
    if (added > 0 && removed > 0) {
      return 'Cambiaste $removed ejercicio${removed == 1 ? '' : 's'} por $added nuevo${added == 1 ? '' : 's'}.';
    }
    if (added > 0) {
      return 'Añadiste $added ejercicio${added == 1 ? '' : 's'}.';
    }
    if (removed > 0) {
      return 'Eliminaste $removed ejercicio${removed == 1 ? '' : 's'}.';
    }
    return 'Cambiaste el orden de los ejercicios.';
  }

  @override
  void dispose() {
    _restTicker?.cancel();
    _workoutTicker?.cancel();
    _draftSaveDebounce?.cancel();
    if (!widget.isEditing && !_workoutClosed) {
      unawaited(_persistActiveWorkout());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _AtmosphericBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _WorkoutHeader(
                onFinish: widget.isEditing
                    ? () => Navigator.of(context).pop(List.of(_exerciseOrder))
                    : _showFinishSheet,
                elapsedTime: _formattedElapsedTime,
                volume: _formattedVolume,
                isEditing: widget.isEditing,
                routineName: widget.routineName,
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 14),
                      for (
                        var index = 0;
                        index < _exerciseOrder.length;
                        index++
                      ) ...[
                        if (index > 0) const SizedBox(height: 12),
                        _ExerciseCard(
                          key: ValueKey(
                            'ejercicio-activo-$index-${_exerciseOrder[index]}',
                          ),
                          name: _exerciseOrder[index],
                          onDelete: () =>
                              _removeExercise(_exerciseOrder[index]),
                          onReplace: (replacement) => _replaceExercise(
                            _exerciseOrder[index],
                            replacement,
                          ),
                          onReorder: _reorderExercises,
                          onSetsChanged: (sets) {
                            _workoutResults[_exerciseOrder[index]] = sets;
                            _syncActiveWorkout();
                          },
                          onSetCompleted: _startRestTimer,
                          onVolumeChanged: _updateVolume,
                          sets: _exerciseSets[_exerciseOrder[index]]!,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.icon(
                            key: const ValueKey('agregar-ejercicio'),
                            onPressed: _openExercisePicker,
                            style: FilledButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.add, size: 23),
                            label: const Text(
                              'Agregar ejercicio',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: MediaQuery.paddingOf(context).bottom + 76,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _remainingSeconds == null
          ? null
          : _ActiveRestTimer(
              remainingSeconds: _remainingSeconds!,
              totalSeconds: _totalSeconds,
              onDecrease: () => _adjustTimer(-15),
              onIncrease: () => _adjustTimer(15),
            ),
    );
  }
}

class AddExercisePage extends StatefulWidget {
  const AddExercisePage({super.key, this.replacing = false});

  final bool replacing;

  @override
  State<AddExercisePage> createState() => _AddExercisePageState();
}

class _AddExercisePageState extends State<AddExercisePage> {
  static const List<(String, String)> _defaultExercises = [
    ('Press Banca Inclinado Con Barra', 'Pecho'),
    ('Aperturas En Polea Alta', 'Pecho'),
    ('Dominadas', 'Dorsales'),
    ('Remo En Polea Baja Agarre Amplio', 'Espalda superior'),
    ('Elevaciones Laterales En Polea', 'Hombros'),
    ('Jalón Al Pecho Agarre Cerrado', 'Dorsales'),
    ('Remo En Polea Baja Agarre Neutro', 'Dorsales'),
    ('Pullover', 'Dorsales'),
  ];
  final WorkoutApi _workoutApi = WorkoutApi();
  final List<(String, String)> _exercises = List.of(_defaultExercises);
  String _query = '';

  List<(String, String)> get _filteredExercises {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _exercises;
    return _exercises
        .where(
          (exercise) =>
              exercise.$1.toLowerCase().contains(query) ||
              exercise.$2.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    try {
      final savedExercises = await _workoutApi.getExercises();
      if (!mounted) return;
      setState(() {
        for (final saved in savedExercises.reversed) {
          _exercises.removeWhere(
            (exercise) => exercise.$1.toLowerCase() == saved.name.toLowerCase(),
          );
          _exercises.insert(0, (saved.name, saved.muscleGroup));
        }
      });
    } catch (_) {
      // Los ejercicios incluidos siguen disponibles si no hay conexión.
    }
  }

  Future<void> _createExercise() async {
    final exercise = await Navigator.of(context).push<(String, String)>(
      MaterialPageRoute<(String, String)>(
        builder: (_) => const CreateExercisePage(),
      ),
    );
    if (!mounted || exercise == null) return;
    try {
      final saved = await _workoutApi.createExercise(
        name: exercise.$1,
        muscleGroup: exercise.$2,
      );
      if (!mounted) return;
      setState(() {
        _exercises.removeWhere(
          (item) => item.$1.toLowerCase() == saved.name.toLowerCase(),
        );
        _exercises.insert(0, (saved.name, saved.muscleGroup));
        _query = '';
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF292C34),
          content: Text(
            'No se pudo guardar el ejercicio. Revisa la conexión.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _AtmosphericBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _AddExerciseHeader(
                title: widget.replacing
                    ? 'Reemplazar ejercicio'
                    : 'Agregar ejercicio',
                onCancel: () => Navigator.of(context).pop(),
                onCreate: _createExercise,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Buscar ejercicio',
                    hintStyle: const TextStyle(color: _muted),
                    prefixIcon: const Icon(Icons.search, color: _muted),
                    filled: true,
                    fillColor: _surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(17, 24, 17, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ejercicios recientes',
                    style: TextStyle(color: _muted, fontSize: 16),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    MediaQuery.paddingOf(context).bottom + 28,
                  ),
                  itemCount: _filteredExercises.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 68, color: _border),
                  itemBuilder: (context, index) {
                    final exercise = _filteredExercises[index];
                    return _ExercisePickerRow(
                      name: exercise.$1,
                      muscle: exercise.$2,
                      onTap: () => Navigator.of(context).pop(exercise.$1),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddExerciseHeader extends StatelessWidget {
  const _AddExerciseHeader({
    required this.title,
    required this.onCancel,
    required this.onCreate,
  });

  final String title;
  final VoidCallback onCancel;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      color: _card,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.arrow_back, size: 25),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: onCreate, child: const Text('Crear')),
        ],
      ),
    );
  }
}

class _ExercisePickerRow extends StatelessWidget {
  const _ExercisePickerRow({
    required this.name,
    required this.muscle,
    required this.onTap,
  });

  final String name;
  final String muscle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('seleccionar-$name'),
      onTap: onTap,
      child: SizedBox(
        height: 82,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _surface,
                shape: BoxShape.circle,
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.fitness_center, size: 25),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        muscle,
                        style: const TextStyle(color: _muted, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.trending_up, color: Colors.white, size: 25),
          ],
        ),
      ),
    );
  }
}

class CreateExercisePage extends StatefulWidget {
  const CreateExercisePage({super.key});

  @override
  State<CreateExercisePage> createState() => _CreateExercisePageState();
}

class _CreateExercisePageState extends State<CreateExercisePage> {
  final _nameController = TextEditingController();
  String? _muscleGroup;

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _muscleGroup == null) return;
    Navigator.of(context).pop((name, _muscleGroup!));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _AtmosphericBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                height: 66,
                color: _card,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, size: 25),
                    ),
                    const Expanded(
                      child: Text(
                        'Crear ejercicio',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('guardar-ejercicio'),
                      onPressed: _save,
                      tooltip: 'Guardar',
                      icon: const Icon(
                        LucideIcons.saveCheck,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    28,
                    24,
                    MediaQuery.paddingOf(context).bottom + 36,
                  ),
                  child: Column(
                    children: [
                      TextField(
                        key: const ValueKey('nombre-ejercicio'),
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: const [_CapitalizedCaseFormatter()],
                        style: const TextStyle(fontSize: 17),
                        decoration: const InputDecoration(
                          hintText: 'Nombre del ejercicio',
                          hintStyle: TextStyle(color: _muted, fontSize: 17),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: _border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: _accent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _MuscleGroupField(
                        onChanged: (group) => _muscleGroup = group,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapitalizedCaseFormatter extends TextInputFormatter {
  const _CapitalizedCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var capitalizeNext = true;
    final buffer = StringBuffer();
    for (final rune in newValue.text.toLowerCase().runes) {
      final character = String.fromCharCode(rune);
      if (capitalizeNext && RegExp(r'[a-záéíóúüñ]').hasMatch(character)) {
        buffer.write(character.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(character);
      }
      if (RegExp(r'\s').hasMatch(character)) capitalizeNext = true;
    }

    return newValue.copyWith(text: buffer.toString());
  }
}

class _MuscleGroupField extends StatefulWidget {
  const _MuscleGroupField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<_MuscleGroupField> createState() => _MuscleGroupFieldState();
}

class _MuscleGroupFieldState extends State<_MuscleGroupField> {
  String? _selectedGroup;

  Future<void> _openSelector() async {
    final group = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _card,
      barrierColor: Colors.black.withValues(alpha: 0.76),
      showDragHandle: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _MuscleGroupSheet(),
    );
    if (group != null && mounted) {
      setState(() => _selectedGroup = group);
      widget.onChanged(group);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('grupo-muscular-principal'),
      onTap: _openSelector,
      child: Container(
        height: 82,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Grupo Muscular Principal',
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedGroup ?? 'Seleccionar',
                    style: const TextStyle(color: _accent, fontSize: 16),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _muted),
          ],
        ),
      ),
    );
  }
}

class _MuscleGroupSheet extends StatefulWidget {
  const _MuscleGroupSheet();

  @override
  State<_MuscleGroupSheet> createState() => _MuscleGroupSheetState();
}

class _MuscleGroupSheetState extends State<_MuscleGroupSheet> {
  static const _groups = [
    'Abdominales',
    'Abductores',
    'Aductores',
    'Bíceps',
    'Pantorrillas',
    'Pecho',
    'Antebrazos',
    'Glúteos',
    'Isquiotibiales',
    'Dorsales',
    'Zona Lumbar',
    'Cuello',
    'Cuádriceps',
    'Hombros',
    'Trapecios',
    'Tríceps',
    'Espalda Superior',
  ];

  final _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 10),
            const ColoredBox(
              color: _card,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: Center(
                  child: Text(
                    'Grupo Muscular Principal',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ClipRect(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final group in _groups)
                      ListTile(
                        title: Text(group),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: _muted,
                        ),
                        onTap: () => Navigator.of(context).pop(group),
                      ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Otro',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('otro-grupo-muscular'),
                      controller: _otherController,
                      decoration: InputDecoration(
                        hintText: 'Escribe Otro Grupo Muscular',
                        hintStyle: const TextStyle(color: _muted),
                        filled: true,
                        fillColor: _surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: const [_CapitalizedCaseFormatter()],
                      onSubmitted: _submitOther,
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => _submitOther(_otherController.text),
                      child: const Text('Usar Este Grupo'),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitOther(String value) {
    final group = value.trim();
    if (group.isNotEmpty) Navigator.of(context).pop(group);
  }
}

class _WorkoutHeader extends StatelessWidget {
  const _WorkoutHeader({
    required this.onFinish,
    required this.elapsedTime,
    required this.volume,
    required this.isEditing,
    this.routineName,
  });

  final VoidCallback onFinish;
  final String elapsedTime;
  final String volume;
  final bool isEditing;
  final String? routineName;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: _card,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 40),
            icon: const Icon(Icons.arrow_back, size: 25),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isEditing
                ? Text(
                    'Editar ${routineName ?? 'rutina'}',
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          label: 'Duración',
                          value: elapsedTime,
                          blue: true,
                        ),
                      ),
                      Expanded(
                        child: _Metric(label: 'Volumen', value: volume),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: ValueKey(
              isEditing ? 'guardar-rutina' : 'finalizar-entrenamiento',
            ),
            onPressed: onFinish,
            tooltip: isEditing ? 'Guardar rutina' : 'Finalizar',
            icon: Icon(
              isEditing ? LucideIcons.saveCheck : LucideIcons.checkCheck,
              color: Colors.white,
              size: 27,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinishWorkoutSheet extends StatelessWidget {
  const _FinishWorkoutSheet({
    required this.routineName,
    required this.changeDescription,
  });

  final String routineName;
  final String changeDescription;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.assignment_outlined, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              'Actualizar «$routineName»',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              changeDescription,
              style: TextStyle(color: _muted, fontSize: 16),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text(
                  'Actualizar rutina',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: FilledButton.styleFrom(
                  backgroundColor: _surface,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text(
                  'Mantener rutina original',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveWorkoutSheet extends StatelessWidget {
  const _SaveWorkoutSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.saveCheck, size: 42, color: _accent),
            const SizedBox(height: 16),
            const Text(
              'Guardar entrenamiento',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Se guardarán los pesos y repeticiones completados para usarlos como referencia en tu próxima sesión.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                key: const ValueKey('confirmar-guardar-entrenamiento'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Guardar entrenamiento'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: FilledButton.styleFrom(backgroundColor: _surface),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.blue = false});

  final String label;
  final String value;
  final bool blue;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: blue ? _accent : Colors.white, fontSize: 16),
        ),
      ],
    );
  }
}

class _SetData {
  const _SetData(
    this.set,
    this.previous,
    this.kg,
    this.reps, {
    this.placeholderKg,
    this.placeholderReps,
    this.completed = false,
  });

  final String set;
  final String previous;
  final String kg;
  final String reps;
  final String? placeholderKg;
  final String? placeholderReps;
  final bool completed;
}

class _ExerciseCard extends StatefulWidget {
  const _ExerciseCard({
    super.key,
    required this.name,
    required this.sets,
    required this.onDelete,
    required this.onReplace,
    required this.onReorder,
    required this.onSetsChanged,
    required this.onSetCompleted,
    required this.onVolumeChanged,
  });

  final String name;
  final List<_SetData> sets;
  final VoidCallback onDelete;
  final ValueChanged<String> onReplace;
  final VoidCallback onReorder;
  final ValueChanged<List<WorkoutSetPayload>> onSetsChanged;
  final ValueChanged<int> onSetCompleted;
  final ValueChanged<double> onVolumeChanged;

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  final WorkoutApi _workoutApi = WorkoutApi();
  int _restMinutes = 3;
  int? _personalRecordSetIndex;
  final Map<int, bool> _personalRecordCandidates = {};
  late final List<_SetData> _sets = List.of(widget.sets);
  late final List<WorkoutSetPayload> _results = [
    for (final set in widget.sets)
      WorkoutSetPayload(
        type: switch (set.set) {
          'W' => 'warmup',
          'F' => 'failure',
          'D' => 'drop',
          _ => 'normal',
        },
        kg: double.tryParse(set.kg) ?? 0,
        reps: int.tryParse(set.reps) ?? 0,
        completed: set.completed,
        kgInput: set.kg,
        repsInput: set.reps,
      ),
  ];

  double? get _previousBestKg {
    final values = _sets
        .map((set) => double.tryParse(set.placeholderKg ?? ''))
        .whereType<double>();
    if (values.isEmpty) return null;
    return values.reduce((best, value) => value > best ? value : best);
  }

  int? get _previousBestReps {
    final values = _sets
        .map((set) => int.tryParse(set.placeholderReps ?? ''))
        .whereType<int>();
    if (values.isEmpty) return null;
    return values.reduce((best, value) => value > best ? value : best);
  }

  @override
  void initState() {
    super.initState();
    _loadRestTimer();
  }

  Future<void> _loadRestTimer() async {
    try {
      final seconds = await _workoutApi.getRestTimerSeconds(widget.name);
      if (!mounted) return;
      setState(() => _restMinutes = (seconds / 60).round().clamp(1, 5));
    } catch (_) {
      // Se conserva el valor predeterminado si no hay conexión.
    }
  }

  @override
  void didUpdateWidget(covariant _ExerciseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) _loadRestTimer();
    for (var index = 0; index < widget.sets.length; index++) {
      if (index >= _sets.length) {
        _sets.add(widget.sets[index]);
        _results.add(
          const WorkoutSetPayload(
            type: 'normal',
            kg: 0,
            reps: 0,
            completed: false,
          ),
        );
      } else {
        final current = _sets[index];
        _sets[index] = _SetData(
          current.set,
          widget.sets[index].previous,
          current.kg,
          current.reps,
          placeholderKg: widget.sets[index].placeholderKg,
          placeholderReps: widget.sets[index].placeholderReps,
          completed: current.completed,
        );
      }
    }
  }

  void _addSet() {
    final numbers = _sets.map((set) => int.tryParse(set.set)).whereType<int>();
    final nextNumber = numbers.isEmpty
        ? 1
        : numbers.reduce(
                (current, value) => value > current ? value : current,
              ) +
              1;
    setState(() {
      _sets.add(_SetData('$nextNumber', '—', '', ''));
      _results.add(
        const WorkoutSetPayload(
          type: 'normal',
          kg: 0,
          reps: 0,
          completed: false,
        ),
      );
    });
    widget.onSetsChanged(List.of(_results));
  }

  void _removeSet(int index) {
    if (index < 0 || index >= _sets.length) return;
    setState(() {
      _sets.removeAt(index);
      _results.removeAt(index);
      _personalRecordCandidates
        ..clear()
        ..addEntries([
          for (
            var resultIndex = 0;
            resultIndex < _results.length;
            resultIndex++
          )
            MapEntry(
              resultIndex,
              _results[resultIndex].completed &&
                  _previousBestKg != null &&
                  _previousBestReps != null &&
                  (_results[resultIndex].kg > _previousBestKg! ||
                      _results[resultIndex].reps > _previousBestReps!),
            ),
        ]);
      _personalRecordSetIndex = _findBestPersonalRecordIndex();
    });
    widget.onSetsChanged(List.of(_results));
  }

  int? _findBestPersonalRecordIndex() {
    final candidates = _personalRecordCandidates.entries
        .where(
          (entry) =>
              entry.value &&
              entry.key < _results.length &&
              _results[entry.key].completed,
        )
        .map((entry) => entry.key);
    if (candidates.isEmpty) return null;
    return candidates.reduce((bestIndex, candidateIndex) {
      final best = _results[bestIndex];
      final candidate = _results[candidateIndex];
      if (candidate.kg != best.kg) {
        return candidate.kg > best.kg ? candidateIndex : bestIndex;
      }
      return candidate.reps > best.reps ? candidateIndex : bestIndex;
    });
  }

  void _updatePersonalRecordCandidate(int index, bool isRecord) {
    _personalRecordCandidates[index] = isRecord;
    final nextIndex = _findBestPersonalRecordIndex();
    if (nextIndex != _personalRecordSetIndex && mounted) {
      setState(() => _personalRecordSetIndex = nextIndex);
    }
  }

  Future<void> _openExerciseOptions() async {
    final action = await showModalBottomSheet<_ExerciseOptionAction>(
      context: context,
      backgroundColor: _card,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const _ExerciseOptionsSheet(),
    );
    if (!mounted || action == null) return;
    if (action == _ExerciseOptionAction.reorder) {
      widget.onReorder();
      return;
    }
    if (action == _ExerciseOptionAction.replace) {
      final replacement = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => const AddExercisePage(replacing: true),
        ),
      );
      if (replacement != null && mounted) widget.onReplace(replacement);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171A22),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _border),
        ),
        title: const Text('Eliminar ejercicio'),
        content: Text('¿Quieres eliminar “${widget.name}” de esta rutina?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const ValueKey('confirmar-eliminar-ejercicio'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF5C68),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) widget.onDelete();
  }

  Future<void> _openRestTimer() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: _card,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _RestTimerSheet(
        exerciseName: widget.name,
        initialMinutes: _restMinutes,
      ),
    );
    if (minutes != null && mounted) {
      setState(() => _restMinutes = minutes);
      try {
        await _workoutApi.saveRestTimerSeconds(
          exerciseName: widget.name,
          restSeconds: minutes * 60,
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF292C34),
            content: Text(
              'No se pudo guardar el tiempo de descanso.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.only(top: 18, bottom: 16),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.name,
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('temporizador-${widget.name}'),
                  onPressed: _openRestTimer,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 38,
                  ),
                  icon: const Icon(
                    Icons.timer_outlined,
                    color: _accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 7),
                IconButton(
                  key: ValueKey('opciones-${widget.name}'),
                  onPressed: _openExerciseOptions,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 38,
                  ),
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          const _SetHeader(),
          const SizedBox(height: 3),
          for (var index = 0; index < _sets.length; index++)
            _SetRow(
              data: _sets[index],
              previousBestKg: _previousBestKg,
              previousBestReps: _previousBestReps,
              showPersonalRecord: _personalRecordSetIndex == index,
              onChanged: (result) {
                _results[index] = result;
                widget.onSetsChanged(List.of(_results));
              },
              onPersonalRecordChanged: (isRecord) =>
                  _updatePersonalRecordCandidate(index, isRecord),
              onRemoved: () => _removeSet(index),
              onCompleted: () => widget.onSetCompleted(_restMinutes * 60),
              onVolumeChanged: widget.onVolumeChanged,
            ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              key: ValueKey('añadir-serie-${widget.name}'),
              onTap: _addSet,
              borderRadius: BorderRadius.circular(11),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 22),
                    SizedBox(width: 7),
                    Text('Añadir serie', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseOptionsSheet extends StatelessWidget {
  const _ExerciseOptionsSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ExerciseOption(
                icon: Icons.swap_vert,
                label: 'Reordenar ejercicios',
                onTap: () =>
                    Navigator.of(context).pop(_ExerciseOptionAction.reorder),
              ),
              _ExerciseOption(
                icon: Icons.sync,
                label: 'Reemplazar ejercicio',
                onTap: () =>
                    Navigator.of(context).pop(_ExerciseOptionAction.replace),
              ),
              _ExerciseOption(
                icon: Icons.close,
                label: 'Eliminar ejercicio',
                destructive: true,
                last: true,
                onTap: () =>
                    Navigator.of(context).pop(_ExerciseOptionAction.delete),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReorderExercisesPage extends StatefulWidget {
  const _ReorderExercisesPage({required this.exercises});

  final List<String> exercises;

  @override
  State<_ReorderExercisesPage> createState() => _ReorderExercisesPageState();
}

class _ReorderRoutinesPage extends StatefulWidget {
  const _ReorderRoutinesPage({required this.routines});

  final List<_RoutineData> routines;

  @override
  State<_ReorderRoutinesPage> createState() => _ReorderRoutinesPageState();
}

class _ReorderFoldersPage extends StatefulWidget {
  const _ReorderFoldersPage({
    required this.folders,
    required this.routineCounts,
  });

  final List<String> folders;
  final Map<String, int> routineCounts;

  @override
  State<_ReorderFoldersPage> createState() => _ReorderFoldersPageState();
}

class _ReorderFoldersPageState extends State<_ReorderFoldersPage> {
  late final List<String> _folders = List.of(widget.folders);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              height: 66,
              color: _card,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      'Reordenar carpetas',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.only(top: 10),
                buildDefaultDragHandles: false,
                itemCount: _folders.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final folder = _folders.removeAt(oldIndex);
                    _folders.insert(newIndex, folder);
                  });
                },
                itemBuilder: (context, index) {
                  final folder = _folders[index];
                  final routineCount = widget.routineCounts[folder] ?? 0;
                  return ListTile(
                    key: ValueKey('reordenar-carpeta-$folder'),
                    leading: IconButton(
                      key: ValueKey('quitar-carpeta-$folder'),
                      onPressed: () => setState(() => _folders.removeAt(index)),
                      icon: const Icon(
                        Icons.remove_circle,
                        color: Color(0xFFFF5C4D),
                      ),
                    ),
                    title: Text(folder),
                    subtitle: Text(
                      routineCount == 0
                          ? 'Sin rutinas'
                          : '$routineCount rutinas',
                      style: const TextStyle(color: _muted),
                    ),
                    trailing: ReorderableDragStartListener(
                      key: ValueKey('arrastrar-carpeta-$folder'),
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle, color: _muted),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  key: const ValueKey('guardar-orden-carpetas'),
                  onPressed: () => Navigator.of(context).pop(_folders),
                  child: const Text('Listo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderRoutinesPageState extends State<_ReorderRoutinesPage> {
  late final List<_RoutineData> _routines = List.of(widget.routines);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              height: 66,
              color: _card,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      'Reordenar rutinas',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.only(top: 10),
                buildDefaultDragHandles: false,
                itemCount: _routines.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final routine = _routines.removeAt(oldIndex);
                    _routines.insert(newIndex, routine);
                  });
                },
                itemBuilder: (context, index) {
                  final routine = _routines[index];
                  return ListTile(
                    key: ValueKey('reordenar-rutina-${routine.name}'),
                    leading: IconButton(
                      key: ValueKey('quitar-rutina-${routine.name}'),
                      onPressed: () =>
                          setState(() => _routines.removeAt(index)),
                      icon: const Icon(
                        Icons.remove_circle,
                        color: Color(0xFFFF5C4D),
                      ),
                    ),
                    title: Text(routine.name),
                    subtitle: Text(
                      routine.exercises.isEmpty
                          ? 'Sin ejercicios'
                          : '${routine.exercises.length} ejercicios',
                      style: const TextStyle(color: _muted),
                    ),
                    trailing: ReorderableDragStartListener(
                      key: ValueKey('arrastrar-rutina-${routine.name}'),
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle, color: _muted),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  key: const ValueKey('guardar-orden-rutinas'),
                  onPressed: () => Navigator.of(context).pop(_routines),
                  child: const Text('Listo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderExercisesPageState extends State<_ReorderExercisesPage> {
  late final List<String> _exercises = List.of(widget.exercises);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              height: 66,
              color: _card,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      'Reordenar ejercicios',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.only(top: 10),
                buildDefaultDragHandles: false,
                itemCount: _exercises.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final exercise = _exercises.removeAt(oldIndex);
                    _exercises.insert(newIndex, exercise);
                  });
                },
                itemBuilder: (context, index) {
                  final exercise = _exercises[index];
                  return ListTile(
                    key: ValueKey('reordenar-$exercise'),
                    leading: IconButton(
                      key: ValueKey('quitar-$exercise'),
                      onPressed: () =>
                          setState(() => _exercises.removeAt(index)),
                      icon: const Icon(
                        Icons.remove_circle,
                        color: Color(0xFFFF5C4D),
                      ),
                    ),
                    title: Text(exercise),
                    trailing: ReorderableDragStartListener(
                      key: ValueKey('arrastrar-$exercise'),
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle, color: _muted),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  key: const ValueKey('guardar-orden-ejercicios'),
                  onPressed: () => Navigator.of(context).pop(_exercises),
                  child: const Text('Listo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ExerciseOptionAction { reorder, replace, delete }

class _ExerciseOption extends StatelessWidget {
  const _ExerciseOption({
    required this.icon,
    required this.label,
    this.destructive = false,
    this.last = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool destructive;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFFF5C68) : Colors.white;
    return Material(
      color: _surface,
      child: InkWell(
        onTap: onTap ?? () => Navigator.of(context).pop(),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(width: 18),
              Text(label, style: TextStyle(color: color, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestTimerSheet extends StatefulWidget {
  const _RestTimerSheet({
    required this.exerciseName,
    required this.initialMinutes,
  });

  final String exerciseName;
  final int initialMinutes;

  @override
  State<_RestTimerSheet> createState() => _RestTimerSheetState();
}

class _RestTimerSheetState extends State<_RestTimerSheet> {
  late final _scrollController = FixedExtentScrollController(
    initialItem: widget.initialMinutes - 1,
  );
  late int _selectedMinutes = widget.initialMinutes;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Temporizador de descanso',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            Text(
              widget.exerciseName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 15),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 210,
              child: ListWheelScrollView.useDelegate(
                controller: _scrollController,
                itemExtent: 48,
                diameterRatio: 1.6,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (index) {
                  setState(() => _selectedMinutes = index + 1);
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: 5,
                  builder: (context, index) {
                    final minutes = index + 1;
                    final selected = minutes == _selectedMinutes;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      alignment: Alignment.center,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: selected ? _surface : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        '$minutes min',
                        style: TextStyle(
                          color: selected ? Colors.white : _muted,
                          fontSize: selected ? 20 : 17,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 43,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_selectedMinutes),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Listo', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetHeader extends StatelessWidget {
  const _SetHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: _muted, fontSize: 13);
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          SizedBox(width: 58, child: Text('SET', style: style)),
          Expanded(flex: 3, child: Text('ANTERIOR', style: style)),
          Expanded(flex: 2, child: Text('KG', style: style)),
          Expanded(child: Text('REP', style: style)),
          SizedBox(
            width: 33,
            child: Icon(Icons.check, color: _muted, size: 21),
          ),
        ],
      ),
    );
  }
}

enum _SetType { warmup, normal, failure, drop, remove }

class _SetRow extends StatefulWidget {
  const _SetRow({
    required this.data,
    required this.previousBestKg,
    required this.previousBestReps,
    required this.showPersonalRecord,
    required this.onChanged,
    required this.onPersonalRecordChanged,
    required this.onRemoved,
    required this.onCompleted,
    required this.onVolumeChanged,
  });

  final _SetData data;
  final double? previousBestKg;
  final int? previousBestReps;
  final bool showPersonalRecord;
  final ValueChanged<WorkoutSetPayload> onChanged;
  final ValueChanged<bool> onPersonalRecordChanged;
  final VoidCallback onRemoved;
  final VoidCallback onCompleted;
  final ValueChanged<double> onVolumeChanged;

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late String _setLabel = widget.data.set;
  late Color _setColor = widget.data.set == 'W' ? _accent : Colors.white;
  late final TextEditingController _kgController = TextEditingController(
    text: widget.data.kg,
  );
  late final TextEditingController _repsController = TextEditingController(
    text: widget.data.reps,
  );
  bool _removed = false;
  late bool _completed = widget.data.completed;
  double _reportedVolume = 0;

  double get _effectiveKg =>
      double.tryParse(_kgController.text.replaceAll(',', '.')) ??
      double.tryParse(widget.data.placeholderKg ?? '') ??
      0;

  int get _effectiveReps =>
      int.tryParse(_repsController.text) ??
      int.tryParse(widget.data.placeholderReps ?? '') ??
      0;

  double get _currentVolume => _effectiveKg * _effectiveReps;

  bool get _isPersonalRecord {
    if (_removed ||
        !_completed ||
        widget.previousBestKg == null ||
        widget.previousBestReps == null) {
      return false;
    }
    return _effectiveKg > widget.previousBestKg! ||
        _effectiveReps > widget.previousBestReps!;
  }

  String get _type => switch (_setLabel) {
    'W' => 'warmup',
    'F' => 'failure',
    'D' => 'drop',
    _ => 'normal',
  };

  void _notifyChanged() {
    widget.onChanged(
      WorkoutSetPayload(
        type: _type,
        kg: _effectiveKg,
        reps: _effectiveReps,
        completed: _completed && !_removed,
        kgInput: _kgController.text,
        repsInput: _repsController.text,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (_completed) _reportedVolume = _currentVolume;
    _kgController.addListener(_refreshReportedVolume);
    _repsController.addListener(_refreshReportedVolume);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPersonalRecordChanged(_isPersonalRecord);
    });
  }

  @override
  void didUpdateWidget(covariant _SetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.placeholderKg == null &&
        widget.data.placeholderKg != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _notifyChanged();
        widget.onPersonalRecordChanged(_isPersonalRecord);
      });
    }
  }

  @override
  void dispose() {
    _kgController.removeListener(_refreshReportedVolume);
    _repsController.removeListener(_refreshReportedVolume);
    _kgController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  void _toggleCompleted() {
    setState(() => _completed = !_completed);
    if (_completed) {
      _reportedVolume = _currentVolume;
      widget.onVolumeChanged(_reportedVolume);
      widget.onCompleted();
    } else {
      widget.onVolumeChanged(-_reportedVolume);
      _reportedVolume = 0;
    }
    _notifyChanged();
    widget.onPersonalRecordChanged(_isPersonalRecord);
  }

  void _refreshReportedVolume() {
    if (_completed) {
      final updatedVolume = _currentVolume;
      widget.onVolumeChanged(updatedVolume - _reportedVolume);
      _reportedVolume = updatedVolume;
      if (mounted) setState(() {});
      widget.onPersonalRecordChanged(_isPersonalRecord);
    }
    _notifyChanged();
  }

  Future<void> _selectSetType() async {
    final type = await showModalBottomSheet<_SetType>(
      context: context,
      backgroundColor: _card,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const _SetTypeSheet(),
    );

    if (type == null || !mounted) return;
    setState(() {
      switch (type) {
        case _SetType.warmup:
          _setLabel = 'W';
          _setColor = _accent;
        case _SetType.normal:
          _setLabel = widget.data.set == 'W' ? '1' : widget.data.set;
          _setColor = Colors.white;
        case _SetType.failure:
          _setLabel = 'F';
          _setColor = const Color(0xFFFF453A);
        case _SetType.drop:
          _setLabel = 'D';
          _setColor = const Color(0xFF35C8FF);
        case _SetType.remove:
          if (_completed) widget.onVolumeChanged(-_reportedVolume);
          _reportedVolume = 0;
          _removed = true;
      }
    });
    if (type == _SetType.remove) {
      widget.onRemoved();
      return;
    }
    _notifyChanged();
    widget.onPersonalRecordChanged(_isPersonalRecord);
  }

  @override
  Widget build(BuildContext context) {
    if (_removed) return const SizedBox.shrink();
    return Container(
      height: 50,
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: InkWell(
              onTap: _selectSetType,
              child: Align(
                alignment: Alignment.centerLeft,
                child: widget.showPersonalRecord
                    ? const Tooltip(
                        message: 'Nuevo récord personal',
                        child: Icon(
                          Icons.workspace_premium,
                          key: ValueKey('medalla-record-personal'),
                          color: Color(0xFFFFD600),
                          size: 25,
                        ),
                      )
                    : Text(
                        _setLabel,
                        style: TextStyle(
                          color: _setColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                        ),
                      ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              widget.data.previous,
              style: const TextStyle(color: _muted, fontSize: 16),
            ),
          ),
          Expanded(
            flex: 2,
            child: _InlineNumberField(
              key: ValueKey('kg-${widget.data.set}'),
              controller: _kgController,
              placeholder: widget.data.placeholderKg ?? '0',
              decimal: true,
            ),
          ),
          Expanded(
            child: _InlineNumberField(
              key: ValueKey('repeticiones-${widget.data.set}'),
              controller: _repsController,
              placeholder: widget.data.placeholderReps ?? '0',
            ),
          ),
          SizedBox(
            width: 33,
            child: InkWell(
              key: ValueKey('checkbox-${widget.data.set}'),
              onTap: _toggleCompleted,
              borderRadius: BorderRadius.circular(11),
              child: Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  color: _completed ? _accent : _surface,
                  border: _completed ? null : Border.all(color: _border),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: _completed
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNumberField extends StatelessWidget {
  const _InlineNumberField({
    super.key,
    required this.controller,
    this.placeholder,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String? placeholder;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      textInputAction: TextInputAction.next,
      selectAllOnFocus: true,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      cursorColor: _accent,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: const TextStyle(color: _muted, fontSize: 16),
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}

class _ActiveRestTimer extends StatelessWidget {
  const _ActiveRestTimer({
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int remainingSeconds;
  final int totalSeconds;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  String get _formattedTime {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = (remainingSeconds / totalSeconds).clamp(0.0, 1.0);
    return SafeArea(
      top: false,
      child: Container(
        height: 88,
        decoration: const BoxDecoration(color: _card),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              color: _accent,
              backgroundColor: _surface,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _TimerAdjustButton(label: '-15', onTap: onDecrease),
                    Expanded(
                      child: Text(
                        _formattedTime,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 29,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    _TimerAdjustButton(label: '+15', onTap: onIncrease),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerAdjustButton extends StatelessWidget {
  const _TimerAdjustButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 40,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: _surface,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

class _SetTypeSheet extends StatelessWidget {
  const _SetTypeSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Text(
                'Seleccionar tipo de serie',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Column(
                children: [
                  _SetTypeOption(
                    type: _SetType.warmup,
                    symbol: 'W',
                    label: 'Serie de calentamiento',
                    color: _accent,
                  ),
                  _SetTypeOption(
                    type: _SetType.normal,
                    symbol: '1',
                    label: 'Serie normal',
                  ),
                  _SetTypeOption(
                    type: _SetType.failure,
                    symbol: 'F',
                    label: 'Serie al fallo',
                    color: Color(0xFFFF453A),
                  ),
                  _SetTypeOption(
                    type: _SetType.drop,
                    symbol: 'D',
                    label: 'Drop Set',
                    color: Color(0xFF35C8FF),
                  ),
                  _SetTypeOption(
                    type: _SetType.remove,
                    symbol: '×',
                    label: 'Eliminar serie',
                    color: Color(0xFFFF453A),
                    last: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetTypeOption extends StatelessWidget {
  const _SetTypeOption({
    required this.type,
    required this.symbol,
    required this.label,
    this.color = Colors.white,
    this.last = false,
  });

  final _SetType type;
  final String symbol;
  final String label;
  final Color color;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(type),
      child: Container(
        height: 65,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: _border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 37,
              child: Text(
                symbol,
                style: TextStyle(
                  color: color,
                  fontSize: symbol == '×' ? 27 : 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          ],
        ),
      ),
    );
  }
}
