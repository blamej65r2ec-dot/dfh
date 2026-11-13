import 'package:flutter/foundation.dart';

class AppEvents {
  /// Goes up whenever you post, delete or change your voices.
  static final postsChanged = ValueNotifier<int>(0);

  /// True while a hold-to-record gesture is on screen (stops page swiping).
  static final pagingLocked = ValueNotifier<bool>(false);

  static void notifyPosted() => postsChanged.value++;
}
