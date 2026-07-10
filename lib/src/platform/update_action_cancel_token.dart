import 'dart:async';

class UpdateActionCancelToken {
  bool _isCanceled = false;
  final Completer<void> _canceled = Completer<void>();

  bool get isCanceled => _isCanceled;

  Future<void> get whenCanceled => _canceled.future;

  void cancel() {
    if (_isCanceled) {
      return;
    }
    _isCanceled = true;
    _canceled.complete();
  }
}
