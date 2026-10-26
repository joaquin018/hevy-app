import 'dart:convert';

import 'package:http/http.dart' as http;

// A disposable transport. It never opens a network connection or uses
// browser/device storage, including for routes not supported in guest mode.
class GuestStore {
  bool _active = true;
  int _sequence = 0, _version = 0;
  final _folders = <String, Map<String, dynamic>>{};
  final _routines = <String, Map<String, dynamic>>{};
  final _sessions = <Map<String, dynamic>>[];
  final _rests = <String, Map<String, int>>{};
  Map<String, dynamic>? _draft;
  final _catalog = <String, Map<String, dynamic>>{
    for (final entry in const [
      ('Press Banca Inclinado Con Barra', 'Pecho'),
      ('Aperturas En Polea Alta', 'Pecho'),
      ('Dominadas', 'Dorsales'),
      ('Remo En Polea Baja Agarre Amplio', 'Espalda superior'),
      ('Elevaciones Laterales En Polea', 'Hombros'),
      ('Jalón Al Pecho Agarre Cerrado', 'Dorsales'),
      ('Remo En Polea Baja Agarre Neutro', 'Dorsales'),
      ('Pullover', 'Dorsales'),
    ])
      entry.$1.toLowerCase(): {'name': entry.$1, 'muscleGroup': entry.$2},
  };

  http.Client createClient() => _GuestClient(this);

  void end() {
    _active = false;
    _folders.clear();
    _routines.clear();
    _sessions.clear();
    _rests.clear();
    _catalog.clear();
    _draft = null;
  }

  String _id() => 'guest-${++_sequence}';
  String _name(String name) => name.trim().toLowerCase();
  List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List? ?? []).cast<Map<String, dynamic>>();
  Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  bool _isolated(Map<String, dynamic> session) =>
      session['isolateResults'] == true;

  ({int status, Object body}) _response(Object body, [int status = 200]) =>
      (status: status, body: body);
  ({int status, Object body}) _missing() =>
      _response({'message': 'No se encontró el elemento.'}, 404);

  ({int status, Object body}) _handle(
    String method,
    Uri url,
    Map<String, dynamic> body,
  ) {
    final path = url.path.replaceFirst(RegExp(r'^/api(?=/|$)'), '');
    if (path == '/routine-library') {
      if (method == 'GET') {
        final folders = _folders.values.toList()..sort(_comparePosition);
        return _response({
          'version': _version,
          'folders': [
            for (final folder in folders)
              {
                'id': folder['id'],
                'name': folder['name'],
                'routines':
                    (_routines.values
                            .where((r) => r['folderId'] == folder['id'])
                            .toList()
                          ..sort(_comparePosition))
                        .map(
                          (r) => {
                            'id': r['id'],
                            'name': r['name'],
                            'exercises': r['exercises'],
                            if (r['isolateResults'] == true)
                              'isolateResults': true,
                          },
                        )
                        .toList(),
              },
          ],
        });
      }
      if (method == 'PATCH') return _patchLibrary(body);
    }
    if (path == '/exercises') {
      if (method == 'GET') {
        return _response(
          _catalog.values.toList()..sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          ),
        );
      }
      if (method == 'POST') {
        final name = (body['name'] as String).trim();
        final exercise = _catalog.putIfAbsent(
          _name(name),
          () => {'name': name, 'muscleGroup': body['muscleGroup']},
        );
        return _response(exercise, 201);
      }
    }
    if (path == '/exercises/rest-timer') {
      final name = _name(
        (method == 'GET' ? url.queryParameters['name'] : body['name'])
            as String,
      );
      final kind =
          (method == 'GET' ? url.queryParameters['kind'] : body['kind']) ==
              'exercises'
          ? 'exercises'
          : 'sets';
      if (method == 'PUT') {
        final seconds = body['restSeconds'] as int;
        if (seconds < 60 || seconds > 300) {
          return _response({'message': 'Tiempo de descanso no válido.'}, 422);
        }
        _rests.putIfAbsent(name, () => {})[kind] = seconds;
      }
      return _response({'restSeconds': _rests[name]?[kind] ?? 180});
    }
    if (path == '/workout-draft') {
      if (method == 'GET') {
        return _draft == null ? _missing() : _response(_draft!);
      }
      if (method == 'PUT') {
        _draft = _copy(body);
        _draft!['isolateResults'] =
            _routines[body['routineId']]?['isolateResults'] == true;
        return _response({'saved': true});
      }
      if (method == 'DELETE') {
        _draft = null;
        return _response({'deleted': true});
      }
    }
    if (path == '/workout-sessions') {
      if (method == 'POST') {
        final existing = _sessions
            .where((s) => s['startedAt'] == body['startedAt'])
            .firstOrNull;
        if (existing != null) return _response(existing, 201);
        final session = _copy(body)
          ..addAll({
            'id': _id(),
            'isolateResults':
                _routines[body['routineId']]?['isolateResults'] == true,
          });
        _sessions.add(session);
        for (final exercise in _rows(session['exercises'])) {
          _catalog.putIfAbsent(
            _name(exercise['name'] as String),
            () => {'name': exercise['name'], 'muscleGroup': 'Otro'},
          );
        }
        return _response(session, 201);
      }
      if (method == 'GET') {
        final history = _history();
        final offset = int.tryParse(url.queryParameters['offset'] ?? '') ?? 0;
        final limit = int.tryParse(url.queryParameters['limit'] ?? '') ?? 20;
        return _response({
          'sessions': history.skip(offset).take(limit).toList(),
          'total': history.length,
          'hasMore': offset + limit < history.length,
        });
      }
    }
    if (path.startsWith('/workout-sessions/') && method == 'DELETE') {
      final id = url.pathSegments.last;
      if (!_sessions.any((s) => s['id'] == id)) return _missing();
      _sessions.removeWhere((s) => s['id'] == id);
      return _response({'deleted': true});
    }
    if (path == '/exercises/previous' && method == 'GET') {
      return _previous(
        url.queryParameters['name']!,
        url.queryParameters['routineId'],
      );
    }
    if (path == '/routine-shares/pending') return _response({'pending': false});
    if (path == '/routine-shares') return _response({'items': []});
    if (path == '/routine-recipients') return _response([]);
    return _response({'message': 'Esta acción requiere una cuenta.'}, 400);
  }

  static int _comparePosition(Map<String, dynamic> a, Map<String, dynamic> b) =>
      (a['position'] as int).compareTo(b['position'] as int);

  ({int status, Object body}) _patchLibrary(Map<String, dynamic> body) {
    if (body['version'] != _version) {
      return _response({
        'code': 'LIBRARY_CHANGED',
        'message': 'Actualiza la lista de rutinas.',
      }, 409);
    }
    for (final input in _rows(body['routines'])) {
      final previous = _routines[input['id']];
      if (previous != null &&
          input.containsKey('isolateResults') &&
          input['isolateResults'] != previous['isolateResults'] &&
          _draft?['routineId'] == input['id']) {
        return _response({
          'code': 'WORKOUT_IN_PROGRESS',
          'message': 'Termina o descarta el entrenamiento en curso antes de cambiar el aislamiento.',
        }, 409);
      }
    }
    for (final input in _rows(body['folders'])) {
      _folders[input['id'] as String] = _copy(input);
    }
    for (final input in _rows(body['routines'])) {
      final id = input['id'] as String;
      _routines[id] = {
        ...?_routines[id],
        'exercises': _routines[id]?['exercises'] ?? <String>[],
        'isolateResults': _routines[id]?['isolateResults'] ?? false,
        ..._copy(input),
      };
      for (final session in _sessions.where((s) => s['routineId'] == id)) {
        session['isolateResults'] = _routines[id]!['isolateResults'];
      }
    }
    for (final id in body['deletedRoutines'] as List? ?? []) {
      _routines.remove(id);
    }
    for (final id in body['deletedFolders'] as List? ?? []) {
      _folders.remove(id);
      _routines.removeWhere((_, r) => r['folderId'] == id);
    }
    return _response({'version': ++_version});
  }

  bool _improves(
    Map<String, dynamic> current,
    Map<String, dynamic>? previous,
  ) =>
      previous == null ||
      (current['kg'] as num) > (previous['kg'] as num) ||
      (current['reps'] as int) > (previous['reps'] as int);

  ({int status, Object body}) _previous(
    String exerciseName,
    String? routineId,
  ) {
    final routine = _routines[routineId];
    final retained = _sessions
        .where((s) => s['routineId'] == routineId && routineId != null)
        .firstOrNull;
    if (routineId != null &&
        routine == null &&
        retained == null &&
        _draft?['routineId'] != routineId) {
      return _missing();
    }
    final isolated =
        routine?['isolateResults'] == true ||
        (routineId != null &&
            routine == null &&
            (retained?['isolateResults'] == true ||
                (_draft?['routineId'] == routineId &&
                    _draft?['isolateResults'] == true)));
    final references = <int, Map<String, dynamic>>{};
    for (final session in _sessions) {
      if (isolated ? session['routineId'] != routineId : _isolated(session)) {
        continue;
      }
      for (final exercise in _rows(session['exercises'])) {
        if (_name(exercise['name'] as String) != _name(exerciseName)) continue;
        final sets = _rows(exercise['sets']);
        for (var i = 0; i < sets.length; i++) {
          if (sets[i]['completed'] != true ||
              !_improves(sets[i], references[i])) {
            continue;
          }
          references[i] = {
            ...sets[i],
            'position': i,
            'completedAt': session['completedAt'],
          };
        }
      }
    }
    if (references.isEmpty) return _missing();
    final positions = references.keys.toList()..sort();
    return _response({
      'completedAt': references[positions.first]!['completedAt'],
      'sets': [
        for (final i in positions)
          {
            'position': i,
            'type': references[i]!['type'],
            'kg': references[i]!['kg'],
            'reps': references[i]!['reps'],
          },
      ],
    });
  }

  List<Map<String, dynamic>> _history() {
    final references = <String, Map<String, dynamic>>{};
    final history = <Map<String, dynamic>>[];
    for (final session in _sessions) {
      var volume = 0.0, records = 0;
      final entries = <Map<String, dynamic>>[];
      for (final exercise in _rows(session['exercises'])) {
        final sets = _rows(exercise['sets']);
        final completed = <Map<String, dynamic>>[];
        for (var i = 0; i < sets.length; i++) {
          final set = sets[i];
          if (set['completed'] != true) continue;
          final key =
              '${_isolated(session) ? session['routineId'] : 'shared'}:${_name(exercise['name'] as String)}:$i';
          final previous = references[key];
          final improves = _improves(set, previous);
          final record = previous != null && improves;
          if (improves) references[key] = set;
          if (record) records++;
          volume += (set['kg'] as num) * (set['reps'] as int);
          completed.add({...set, 'position': i, 'isRecord': record});
        }
        if (completed.isNotEmpty) {
          entries.add({'name': exercise['name'], 'sets': completed});
        }
      }
      history.add({
        ...session,
        'exercises': entries,
        'records': records,
        'volumeKg': (volume * 100).round() / 100,
      });
    }
    history.sort(
      (a, b) => (b['startedAt'] as String).compareTo(a['startedAt'] as String),
    );
    return history;
  }
}

class _GuestClient extends http.BaseClient {
  _GuestClient(this.store);
  final GuestStore store;
  bool _closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    if (_closed || !store._active) {
      throw StateError('La sesión de invitado terminó.');
    }
    final body = bytes.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final response = store._handle(request.method, request.url, body);
    final content = utf8.encode(jsonEncode(response.body));
    return http.StreamedResponse(
      Stream.value(content),
      response.status,
      contentLength: content.length,
      request: request,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
      },
    );
  }

  @override
  void close() => _closed = true;
}
