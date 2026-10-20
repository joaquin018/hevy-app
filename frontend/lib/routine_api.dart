part of 'workout_api.dart';

class RoutineApiFailure implements Exception {
  const RoutineApiFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

extension RoutineOperations on WorkoutApi {
  dynamic _routineResponse(http.Response response) {
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RoutineApiFailure(
        body is Map ? body['code'] as String? ?? 'HTTP_ERROR' : 'HTTP_ERROR',
        body is Map
            ? body['message'] as String? ?? 'No se pudo completar la acción.'
            : 'No se pudo completar la acción.',
      );
    }
    return body;
  }

  Future<RoutineLibraryPayload> getRoutineLibrary() async =>
      RoutineLibraryPayload.fromJson(
        _routineResponse(
          await _client.get(Uri.parse('$_baseUrl/routine-library')),
        ) as Map<String, dynamic>,
      );

  Future<int> saveRoutineChanges(
    RoutineLibraryPayload before,
    List<RoutineFolderPayload> after,
  ) async {
    final patch = before.changesTo(after);
    if ([
      'folders',
      'routines',
      'deletedFolders',
      'deletedRoutines',
    ].every((key) => (patch[key] as List).isEmpty)) {
      return before.version;
    }
    final response = _routineResponse(
      await _client.patch(
        Uri.parse('$_baseUrl/routine-library'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(patch),
      ),
    );
    return response['version'] as int;
  }

  Future<List<RoutineRecipient>> findRoutineRecipients(String query) async {
    final response = _routineResponse(
      await _client.get(
        Uri.parse('$_baseUrl/routine-recipients')
            .replace(queryParameters: {'q': query}),
      ),
    );
    return (response as List)
        .map((v) => RoutineRecipient.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  Future<void> shareRoutine({
    required String id,
    required String routineId,
    required String recipientId,
    required int version,
  }) async {
    _routineResponse(
      await _client.post(
        Uri.parse('$_baseUrl/routine-shares'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'id': id,
          'routineId': routineId,
          'recipientId': recipientId,
          'version': version,
        }),
      ),
    );
  }

  Future<void> shareFolder({
    required String id,
    required String folderId,
    required String recipientId,
    required int version,
  }) async {
    _routineResponse(
      await _client.post(
        Uri.parse('$_baseUrl/folder-shares'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'id': id,
          'folderId': folderId,
          'recipientId': recipientId,
          'version': version,
        }),
      ),
    );
  }

  Future<bool> hasPendingRoutines() async =>
      _routineResponse(
            await _client.get(
              Uri.parse('$_baseUrl/routine-shares/pending')
                  .replace(queryParameters: {'includeFolders': 'true'}),
            ),
          )['pending']
          as bool;
  Future<RoutineSharePage> getRoutineShares({
    bool sent = false,
    String? cursor,
  }) async {
    final value = _routineResponse(
      await _client.get(
        Uri.parse('$_baseUrl/routine-shares').replace(
          queryParameters: {
            'direction': sent ? 'sent' : 'received',
            'includeFolders': 'true',
            'cursor': ?cursor,
          },
        ),
      ),
    );
    return RoutineSharePage(
      items: (value['items'] as List)
          .map((v) => RoutineShare.fromJson(v as Map<String, dynamic>))
          .toList(),
      nextCursor: value['nextCursor'] as String?,
    );
  }

  Future<RoutinePreview> previewRoutineShare(String id) async {
    final value = _routineResponse(
      await _client.get(Uri.parse('$_baseUrl/routine-shares/$id')),
    )['snapshot'];
    return RoutinePreview(
      name: value['name'] as String,
      isFolder: value['version'] == 2,
      routines: value['version'] == 2
          ? (value['routines'] as List)
                .map(
                  (routine) => RoutinePreview(
                    name: routine['name'] as String,
                    exercises: (routine['exercises'] as List)
                        .map((e) => e['name'] as String)
                        .toList(),
                  ),
                )
                .toList()
          : const [],
      exercises: ((value['exercises'] ?? []) as List)
          .map((v) => v['name'] as String)
          .toList(),
    );
  }

  Future<void> acceptRoutineShare(String id, {String? folderId}) async {
    _routineResponse(
      await _client.post(
        Uri.parse('$_baseUrl/routine-shares/$id/accept'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'folderId': ?folderId}),
      ),
    );
  }

  Future<void> resolveRoutineShare(String id, {required bool revoke}) async {
    _routineResponse(
      await _client.post(
        Uri.parse(
          '$_baseUrl/routine-shares/$id/${revoke ? 'revoke' : 'reject'}',
        ),
      ),
    );
  }
}
