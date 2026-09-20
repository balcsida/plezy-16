import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/focus/input_mode_tracker.dart';

void main() {
  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.select]) {
    testWidgets('TV ${key.keyLabel}: held OK activates once; Back bubbles once', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var selected = 0;
      var back = 0;
      await tester.pumpWidget(
        InputModeTracker(
          child: MaterialApp(
            home: Scaffold(
              body: Focus(
                onKeyEvent: (_, event) {
                  if (event.logicalKey == LogicalKeyboardKey.goBack && event is KeyDownEvent) {
                    back++;
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: FocusableWrapper(
                  focusNode: node,
                  onSelect: () => selected++,
                  child: const SizedBox(width: 80, height: 40),
                ),
              ),
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.pump();
      expect(selected, 1);
      // Use the binding's KeyMessage path so FocusManager receives the event.
      // Escape is a physical surrogate for logical GoBack, not a TV mapping claim.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.escape);
      await tester.pump();
      expect(back, 1);
      expect(node.hasFocus, isTrue);
    }, skip: !const bool.fromEnvironment('TIZEN_BUILD'));
  }
}
