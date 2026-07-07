class UpdateActionCancelToken {
  var _isCanceled = false;
  final _callbacks = <void Function()>[];

  bool get isCanceled => _isCanceled;

  void cancel() {
    if (_isCanceled) {
      return;
    }
    _isCanceled = true;
    final callbacks = List<void Function()>.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  void onCancel(void Function() callback) {
    if (_isCanceled) {
      callback();
      return;
    }
    _callbacks.add(callback);
  }
}
