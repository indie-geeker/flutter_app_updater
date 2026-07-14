import '../actions/update_action.dart';
import 'update_action_cancel_token.dart';
import 'update_action_event.dart';
import 'update_action_executor.dart';

/// Executor that exposes progress and cooperative cancellation.
abstract interface class StreamingUpdateActionExecutor
    implements UpdateActionExecutor {
  /// Performs [action] as a started/progress/completed event stream.
  ///
  /// Implementations must produce exactly one terminal completed event.
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  });
}
