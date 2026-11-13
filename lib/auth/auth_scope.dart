import 'package:flutter/widgets.dart';

import 'auth_service.dart';

/// Makes the one [StrandAuth] available to the tree and rebuilds listeners when
/// the session or cached profile changes.
class AuthScope extends InheritedNotifier<StrandAuth> {
  const AuthScope({
    super.key,
    required StrandAuth auth,
    required super.child,
  }) : super(notifier: auth);

  static StrandAuth of(BuildContext context) {
    final AuthScope? scope =
        context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope was not found above this widget.');
    return scope!.notifier!;
  }

  static StrandAuth? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AuthScope>()
        ?.notifier;
  }
}
