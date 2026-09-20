# Example: Plugin Regression Test Runner

End-to-end regression testing for flutter-tizen plugins on TV emulator.

## Files

- `regression_test_runner.sh` — driver script: environment check, emulator launch, example app execution, log capture.
- `log_analysis.sh` — log analysis script: filter unhandled exceptions, Flutter framework errors, and native crashes from the captured run-console log.

## Scenario

User wants to validate that existing plugins continue to work after changes to the flutter-tizen toolchain, embedder, or engine. The scripts handle the full test cycle: verify environment → launch emulator → run example app → capture logs → analyze for issues.

## Usage

```bash
# Run regression test for a specific plugin
bash regression_test_runner.sh --plugin connectivity_plus

# Run regression test for all testable plugins
bash regression_test_runner.sh --all

# Analyze captured logs
bash log_analysis.sh example_run.log
```
