import 'package:flutter/foundation.dart';

import '../social/cloud_store.dart' show Friendship;

/// Shared selection so the shell can intercept the system back button and close
/// an open friend detail view instead of leaving the app.
final ValueNotifier<Friendship?> selectedFriendInsights = ValueNotifier<Friendship?>(null);
