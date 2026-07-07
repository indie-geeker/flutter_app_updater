class UpdateActionCancelToken {
  bool _isCanceled = false;

  bool get isCanceled => _isCanceled;

  void cancel() {
    _isCanceled = true;
  }
}
