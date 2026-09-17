import 'package:flutter/material.dart';
import 'workout_history_models.dart';

const _muted = Color(0xFF9399A6);
const _accent = Color(0xFF7C8CFF);
const _gold = Color(0xFFFFCD62);

String _number(double value) {
  final parts = value
      .toStringAsFixed(value == value.roundToDouble() ? 0 : 1)
      .split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return parts.length == 1 ? whole : '$whole,${parts.last}';
}

String _duration(int seconds) {
  if (seconds < 60) return '$seconds s';
  final minutes = seconds ~/ 60;
  return minutes < 60
      ? '$minutes min'
      : '${minutes ~/ 60} h ${minutes % 60} min';
}

String _date(DateTime date) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _relative(DateTime date) {
  final now = DateTime.now();
  final days = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
  if (days <= 0) return 'Hoy';
  if (days == 1) return 'Ayer';
  return 'Hace $days días';
}

class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key, this.loadHistory});
  final Future<WorkoutHistoryPage> Function(int offset)? loadHistory;

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  final List<WorkoutHistorySession> _sessions = [];
  bool _loading = false;
  bool _failed = false;
  bool _hasMore = false;
  bool _retryRefresh = true;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    _retryRefresh = refresh;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page =
          await widget.loadHistory?.call(refresh ? 0 : _sessions.length) ??
          const WorkoutHistoryPage(sessions: [], total: 0, hasMore: false);
      if (!mounted) return;
      setState(() {
        if (refresh) _sessions.clear();
        _sessions.addAll(page.sessions);
        _total = page.total;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        actions: [
          IconButton(
            tooltip: 'Actualizar historial',
            onPressed: _loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            const Text(
              'TU PROGRESO',
              style: TextStyle(
                color: _accent,
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cada entrenamiento cuenta.',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '$_total ${_total == 1 ? 'entrenamiento guardado' : 'entrenamientos guardados'}',
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 24),
            if (!_loading && !_failed && _sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Column(
                  children: [
                    Icon(Icons.history_rounded, size: 52, color: _accent),
                    SizedBox(height: 18),
                    Text(
                      'Tu historia empieza aquí',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Finaliza y guarda un entrenamiento para ver aquí tus ejercicios y logros.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, height: 1.5),
                    ),
                  ],
                ),
              ),
            for (final session in _sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _HistoryCard(
                  key: ValueKey(session.id),
                  session: session,
                ),
              ),
            if (_failed) ...[
              const Text(
                'No se pudo cargar el historial. Revisa tu conexión e inténtalo de nuevo.',
                textAlign: TextAlign.center,
              ),
              TextButton.icon(
                onPressed: () => _load(refresh: _retryRefresh),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_hasMore && !_loading && !_failed)
              OutlinedButton(
                onPressed: _load,
                child: const Text('Ver entrenamientos anteriores'),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatefulWidget {
  const _HistoryCard({super.key, required this.session});
  final WorkoutHistorySession session;
  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _expanded = false;
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final visible = _expanded || _details
        ? session.exercises
        : session.exercises.take(3);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11141A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calendar_today_outlined,
                  color: _accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _relative(session.startedAt),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _date(session.startedAt),
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            session.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 21),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _Metric(
                label: 'Tiempo',
                value: _duration(session.durationSeconds),
                icon: Icons.schedule_rounded,
              ),
              _Metric(
                label: 'Volumen',
                value: '${_number(session.volumeKg)} kg',
                icon: Icons.fitness_center_rounded,
              ),
              _Metric(
                label: 'Récords',
                value: '${session.records}',
                icon: Icons.emoji_events_rounded,
                gold: true,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: Color(0xFF252932)),
          ),
          if (session.exercises.isEmpty)
            const Text(
              'Sin series completadas',
              style: TextStyle(color: _muted),
            ),
          for (final exercise in visible) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF252932),
                    foregroundColor: _muted,
                    radius: 23,
                    child: Text(
                      exercise.name
                          .trim()
                          .split(RegExp(r'\s+'))
                          .where((w) => w.isNotEmpty)
                          .take(2)
                          .map((w) => w[0])
                          .join()
                          .toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exercise.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${exercise.sets.length} ${exercise.sets.length == 1 ? 'serie' : 'series'}',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_details)
              for (final (index, set) in exercise.sets.indexed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${index + 1}. ${_setType(set.type)}',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                      Text(
                        '${_number(set.kg)} kg × ${set.reps}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 20,
                        child: set.isRecord
                            ? const Tooltip(
                                message: 'Récord en esta sesión',
                                child: Icon(
                                  Icons.emoji_events_rounded,
                                  color: _gold,
                                  size: 18,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
          ],
          if (!_expanded && !_details && session.exercises.length > 3)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _expanded = true),
                child: Text(
                  'Ver ${session.exercises.length - 3} ejercicios más',
                ),
              ),
            ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => setState(() => _details = !_details),
              icon: Icon(
                _details ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
              label: Text(
                _details ? 'Ocultar detalle' : 'Ver series y repeticiones',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _setType(String type) => switch (type) {
  'warmup' => 'Calentamiento',
  'failure' => 'Al fallo',
  'drop' => 'Descendente',
  _ => 'Normal',
};

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    this.gold = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final bool gold;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      const SizedBox(height: 7),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: gold ? _gold : _muted),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: gold ? _gold : Colors.white,
            ),
          ),
        ],
      ),
    ],
  );
}
