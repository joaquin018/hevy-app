class RestTimerState {
  const RestTimerState({required this.endsAt, required this.totalSeconds});

  final DateTime endsAt;
  final int totalSeconds;

  int remainingSecondsAt(DateTime now) {
    final remaining = endsAt.difference(now).inMicroseconds;
    if (remaining <= 0) return 0;
    return (remaining + Duration.microsecondsPerSecond - 1) ~/
        Duration.microsecondsPerSecond;
  }

  RestTimerState? adjustedBy(int seconds, DateTime now) {
    final remaining = remainingSecondsAt(now);
    if (remaining == 0) return null;
    final adjustedRemaining = (remaining + seconds).clamp(0, 3599);
    if (adjustedRemaining == 0) return null;
    return RestTimerState(
      endsAt: endsAt.add(Duration(seconds: adjustedRemaining - remaining)),
      totalSeconds: totalSeconds.clamp(adjustedRemaining, 3599),
    );
  }
}
