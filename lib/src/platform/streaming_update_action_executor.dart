import '../actions/update_action.dart';
import 'update_action_event.dart';
import 'update_action_executor.dart';

abstract interface class StreamingUpdateActionExecutor
    implements UpdateActionExecutor {
  Stream<UpdateActionEvent> performStream(UpdateAction action);
}

Stream<UpdateActionEvent> futureBackedActionEvents({
  required UpdateAction action,
  required Future<UpdateActionResult> Function() perform,
}) async* {
  yield UpdateActionStarted(action);
  final result = await perform();
  if (result.isSuccess) {
    yield UpdateActionCompleted(result);
  } else {
    yield UpdateActionFailed(result);
  }
}
