import '../actions/update_action.dart';
import 'update_action_cancel_token.dart';
import 'update_action_event.dart';
import 'update_action_executor.dart';

abstract interface class StreamingUpdateActionExecutor
    implements UpdateActionExecutor {
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  });
}
