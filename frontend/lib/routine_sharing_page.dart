import 'dart:async';

import 'package:flutter/material.dart';

import 'workout_api.dart';

const _muted = Color(0xFF9399A6);
String _errorMessage(Object error) => error is RoutineApiFailure
    ? error.message
    : 'No se pudo completar la acción. Revisa tu conexión e inténtalo de nuevo.';

// Returns true when the caller must reload a stale library.
Future<bool> showRoutineShareDialog(
  BuildContext context, {
  required WorkoutApi api,
  required String routineId,
  required String routineName,
  required int version,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShareRoutineDialog(
          api: api,
          routineId: routineId,
          routineName: routineName,
          version: version,
        ),
      ) ??
      false;
}

Future<bool> showFolderShareDialog(
  BuildContext context, {
  required WorkoutApi api,
  required String folderId,
  required String folderName,
  required int version,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ShareRoutineDialog.folder(
        api: api,
        folderId: folderId,
        folderName: folderName,
        version: version,
      ),
    ) ??
    false;

class ShareRoutineDialog extends StatefulWidget {
  const ShareRoutineDialog({
    super.key,
    required this.api,
    required this.routineId,
    required this.routineName,
    required this.version,
  }) : folderId = null;
  const ShareRoutineDialog.folder({
    super.key,
    required this.api,
    required this.folderId,
    required String folderName,
    required this.version,
  }) : routineId = null,
       routineName = folderName;
  final WorkoutApi api;
  final String? routineId, folderId;
  final String routineName;
  final int version;
  @override
  State<ShareRoutineDialog> createState() => _ShareRoutineDialogState();
}

class _ShareRoutineDialogState extends State<ShareRoutineDialog> {
  final _email = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  List<RoutineRecipient> _results = [];
  RoutineRecipient? _selected;
  String? _error;
  String _requestId = newRoutineId();
  bool _searching = false, _sending = false, _searched = false;
  bool get _sharingFolder => widget.folderId != null;
  @override
  void dispose() {
    _debounce?.cancel();
    _email.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _selected = null;
      _results = [];
      _error = null;
      _searched = false;
      _searching = value.trim().length >= 3;
    });
    if (!_searching) return;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await widget.api.findRoutineRecipients(value.trim());
        if (mounted && generation == _generation) {
          setState(() {
            _results = results;
            _searched = true;
          });
        }
      } catch (error) {
        if (mounted && generation == _generation) {
          setState(() => _error = _errorMessage(error));
        }
      } finally {
        if (mounted && generation == _generation) {
          setState(() => _searching = false);
        }
      }
    });
  }

  Future<void> _send() async {
    if (_sending || _selected == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (_sharingFolder) {
        await widget.api.shareFolder(
          id: _requestId,
          folderId: widget.folderId!,
          recipientId: _selected!.id,
          version: widget.version,
        );
      } else {
        await widget.api.shareRoutine(
          id: _requestId,
          routineId: widget.routineId!,
          recipientId: _selected!.id,
          version: widget.version,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_sharingFolder ? 'Carpeta' : 'Rutina'} enviada a ${_selected!.email}',
          ),
        ),
      );
      Navigator.of(context).pop(false);
    } catch (error) {
      if (!mounted) return;
      if (error is RoutineApiFailure && error.code == 'LIBRARY_CHANGED') {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: AlertDialog(
      backgroundColor: const Color(0xFF171A22),
      surfaceTintColor: Colors.transparent,
      title: Text(_sharingFolder ? 'Compartir carpeta' : 'Compartir rutina'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.routineName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _sharingFolder
                    ? 'Busca el correo de una cuenta registrada. La persona recibirá una copia de la carpeta con todas sus rutinas.'
                    : 'Busca el correo de una cuenta registrada. La persona recibirá una copia en su bandeja.',
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 18),
              TextField(
                key: const ValueKey('correo-destinatario'),
                controller: _email,
                autofocus: true,
                enabled: !_sending,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Correo de Google',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: 'Ej.: persona@gmail.com',
                  hintStyle: TextStyle(
                    color: _muted,
                    fontStyle: FontStyle.italic,
                  ),
                  helperText: 'Escribe al menos 3 caracteres',
                ),
                onChanged: _changed,
              ),
              if (_searching)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_searched && _results.isEmpty && _selected == null)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'No encontramos esa cuenta. La persona debe registrarse primero.',
                    style: TextStyle(color: _muted),
                  ),
                ),
              for (final recipient in _results)
                ListTile(
                  key: ValueKey('destinatario-${recipient.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(recipient.email),
                  onTap: _sending
                      ? null
                      : () {
                          _debounce?.cancel();
                          _generation++;
                          setState(() {
                            _selected = recipient;
                            _email.text = recipient.email;
                            _results = [];
                            _searching = false;
                            _error = null;
                            _requestId = newRoutineId();
                          });
                        },
                ),
              if (_selected != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 20,
                        color: Color(0xFF7C8CFF),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Enviar a ${_selected!.email}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFF7B85)),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(foregroundColor: Colors.white),
          key: const ValueKey('enviar-rutina'),
          onPressed: _selected == null || _sending ? null : _send,
          child: Text(
            _sending
                ? 'Enviando…'
                : _sharingFolder
                ? 'Enviar carpeta'
                : 'Enviar rutina',
          ),
        ),
      ],
    ),
  );
}

class RoutineSharingPage extends StatefulWidget {
  const RoutineSharingPage({super.key, required this.api});
  final WorkoutApi api;
  @override
  State<RoutineSharingPage> createState() => _RoutineSharingPageState();
}

class _RoutineSharingPageState extends State<RoutineSharingPage> {
  bool _sent = false, _loading = false, _acting = false;
  int _generation = 0;
  final List<RoutineShare> _items = [];
  String? _cursor, _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || _cursor == null)) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _items.clear();
        _cursor = null;
      }
    });
    try {
      final page = await widget.api.getRoutineShares(
        sent: _sent,
        cursor: more ? _cursor : null,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _errorMessage(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _preview(RoutineShare share) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final preview = await widget.api.previewRoutineShare(share.id);
      if (!mounted) return;
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => RoutineSharePreviewPage(
            api: widget.api,
            share: share,
            preview: preview,
            received: !_sent,
          ),
        ),
      );
      if (!mounted) return;
      if (accepted == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${share.isFolder ? 'Carpeta' : 'Rutina'} guardada en tu cuenta.',
            ),
          ),
        );
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _resolve(RoutineShare share) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _sent
              ? 'Cancelar envío'
              : 'Rechazar ${share.isFolder ? 'carpeta' : 'rutina'}',
        ),
        content: Text(
          '¿Quieres ${_sent ? 'cancelar el envío de' : 'rechazar'} “${share.name}”?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _acting = true);
    try {
      await widget.api.resolveRoutineShare(share.id, revoke: _sent);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  String _status(String value) => switch (value) {
    'accepted' => 'Aceptada',
    'rejected' => 'Rechazada',
    'revoked' => 'Envío cancelado',
    _ => 'Pendiente',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Compartidos')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<bool>(
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.22),
              selectedForegroundColor: Colors.white,
            ),
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Recibidas'),
                icon: Icon(Icons.inbox_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('Enviadas'),
                icon: Icon(Icons.send_outlined),
              ),
            ],
            selected: {_sent},
            onSelectionChanged: _acting
                ? null
                : (values) {
                    setState(() => _sent = values.first);
                    _load();
                  },
          ),
        ),
        if (_acting) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (_items.isEmpty && !_loading && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 70),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: _muted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _sent
                              ? 'Aún no has enviado rutinas o carpetas'
                              : 'No tienes compartidos pendientes',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Desliza hacia abajo para actualizar.',
                          style: TextStyle(color: _muted),
                        ),
                      ],
                    ),
                  ),
                for (final share in _items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            share.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_sent ? 'Para' : 'De'}: ${_sent ? share.recipientEmail : share.senderEmail}',
                            style: const TextStyle(color: _muted),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${share.isFolder ? 'Carpeta · ${share.routineCount} rutinas · ' : ''}${share.exerciseCount} ejercicios · ${_status(share.status)}',
                            style: const TextStyle(color: _muted),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.18),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _acting
                                    ? null
                                    : () => _preview(share),
                                child: Text(
                                  share.isFolder ? 'Ver carpeta' : 'Ver rutina',
                                ),
                              ),
                              if (share.status == 'pending')
                                TextButton(
                                  onPressed: _acting
                                      ? null
                                      : () => _resolve(share),
                                  child: Text(
                                    _sent ? 'Cancelar envío' : 'Rechazar',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_error != null)
                  Column(
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      TextButton(
                        onPressed: () => _load(more: _items.isNotEmpty),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_cursor != null && !_loading)
                  TextButton(
                    onPressed: () => _load(more: true),
                    child: const Text('Cargar más'),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class RoutineSharePreviewPage extends StatefulWidget {
  const RoutineSharePreviewPage({
    super.key,
    required this.api,
    required this.share,
    required this.preview,
    required this.received,
  });
  final WorkoutApi api;
  final RoutineShare share;
  final RoutinePreview preview;
  final bool received;
  @override
  State<RoutineSharePreviewPage> createState() =>
      _RoutineSharePreviewPageState();
}

class _RoutineSharePreviewPageState extends State<RoutineSharePreviewPage> {
  List<RoutineFolderPayload> _folders = [];
  String? _folderId, _error;
  bool _loading = true, _accepting = false;
  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    if (!widget.received ||
        widget.share.status != 'pending' ||
        widget.preview.isFolder) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final library = await widget.api.getRoutineLibrary();
      if (mounted) setState(() => _folders = library.folders);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await widget.api.acceptRoutineShare(widget.share.id, folderId: _folderId);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_accepting,
    child: Scaffold(
      appBar: AppBar(title: const Text('Vista previa')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.preview.name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Compartida por ${widget.share.senderEmail}',
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 18),
          if (widget.preview.isFolder)
            for (final routine in widget.preview.routines) ...[
              Text(
                routine.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (routine.exercises.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Sin ejercicios',
                    style: TextStyle(color: _muted),
                  ),
                ),
              for (var i = 0; i < routine.exercises.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  title: Text(routine.exercises[i]),
                ),
              const Divider(height: 24),
            ],
          for (var i = 0; i < widget.preview.exercises.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 16,
                child: Text('${i + 1}', style: const TextStyle(fontSize: 13)),
              ),
              title: Text(widget.preview.exercises[i]),
            ),
          if (widget.received && widget.share.status == 'pending') ...[
            const Divider(height: 32),
            Text(
              widget.preview.isFolder
                  ? 'Al aceptar, se creará una carpeta propia con todas sus rutinas. Puedes editarla sin cambiar la original.'
                  : 'Al aceptar, tendrás una copia propia que puedes editar.',
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (!widget.preview.isFolder)
              DropdownButtonFormField<String>(
                initialValue: _folderId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Guardar en carpeta',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Recibidas (automática)'),
                  ),
                  for (final folder in _folders)
                    DropdownMenuItem(
                      value: folder.id,
                      child: Text(folder.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _accepting
                    ? null
                    : (value) => setState(() => _folderId = value),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(foregroundColor: Colors.white),
              key: ValueKey(
                widget.preview.isFolder ? 'aceptar-carpeta' : 'aceptar-rutina',
              ),
              onPressed:
                  _loading || _accepting || (_error != null && _folders.isEmpty)
                  ? null
                  : _accept,
              icon: const Icon(Icons.add),
              label: Text(_accepting ? 'Guardando…' : 'Aceptar y guardar'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: Color(0xFFFF7B85))),
            TextButton(
              onPressed: _accepting
                  ? null
                  : widget.preview.isFolder
                  ? _accept
                  : _loadFolders,
              child: Text(
                widget.preview.isFolder ? 'Reintentar' : 'Actualizar carpetas',
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
