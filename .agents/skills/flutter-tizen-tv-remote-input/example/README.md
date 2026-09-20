# Example: TV-remote-driven button + grid

Minimal screen that is fully operable from the D-pad, OK, Back, and color keys.

## Files

- `remote_button.dart` — single focusable button wired via `FocusableActionDetector`, `Shortcuts`, and `Actions`. Includes a focus highlight and color-key shortcut.
- `home_grid.dart` — 4×3 grid wrapped in `FocusTraversalGroup(OrderedTraversalPolicy)` with autofocus on the first tile.

## Scenario

User has a Tizen TV app where focus traversal "works" but OK does nothing, Back exits the app, and color keys are silent. The two files together fix focus + activation + system back + power-user shortcut.
