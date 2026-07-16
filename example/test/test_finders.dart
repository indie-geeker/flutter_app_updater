import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds a widget by assignable type instead of exact runtime type.
///
/// Flutter 3.29 implements icon buttons with private subclasses such as
/// `_FilledButtonWithIcon`, while newer Flutter versions use a different
/// implementation. `find.widgetWithText` relies on an exact type match and is
/// therefore unsuitable for tests that must run across both versions.
Finder widgetSubtypeWithText<T extends Widget>(String text) {
  return find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate((widget) => widget is T),
  );
}
