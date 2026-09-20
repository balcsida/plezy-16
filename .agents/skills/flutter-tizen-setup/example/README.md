# Example: First-time flutter-tizen setup

Bootstrap a clean Ubuntu 24.04 host through to a green `flutter-tizen doctor` and a working smoke build.

## Files

- `setup.sh` — driver script: PATH wiring, doctor, certificate profile sanity, smoke-build.

The script is non-destructive; it inspects what is already installed and prints the next action. Adjust the paths near the top to match the host.

## Scenario

User runs `bash setup.sh` on a fresh laptop after manually installing the VS Code Extension for Tizen and cloning flutter-tizen. The script verifies each step from the parent SKILL.md and stops at the first missing piece.
