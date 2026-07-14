import 'dart:async';

/// Cooperative, idempotent cancellation signal for streaming executors.
class UpdateActionCancelToken {
  bool _isCanceled = false;
  final Completer<void> _canceled = Completer<void>();

  /// Whether cancellation has been requested.
  bool get isCanceled => _isCanceled;

  /// Completes once when [cancel] is first called.
  Future<void> get whenCanceled => _canceled.future;

  /// Requests cancellation; subsequent calls have no effect.
  void cancel() {
    if (_isCanceled) {
      return;
    }
    _isCanceled = true;
    _canceled.complete();
  }
}
