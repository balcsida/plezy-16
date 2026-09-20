---
name: flutter-tizen-plugin-regression-test
description: Run regression tests for flutter-tizen plugins after changes to flutter-tizen tool, embedder, or engine. Executes example apps and integration tests on TV emulator, analyzes logs, and generates issue reports. Use when validating plugin compatibility after flutter-tizen updates, or when running CI-style plugin verification.
metadata:
  target: flutter-tizen
  category: testing
  last_modified: Thu, 04 Jun 2026 00:00:00 GMT
---
# Flutter-Tizen Plugin Regression Testing

## Contents
- [Concepts](#concepts)
- [Prerequisites](#prerequisites)
- [Testable Plugins](#testable-plugins)
- [User Input Priority](#user-input-priority)
- [Workflow: Regression Test](#workflow-regression-test)
- [Running Example Apps](#running-example-apps)
- [Running Integration Tests](#running-integration-tests)
- [Log Analysis](#log-analysis)
- [Issue Report Generation](#issue-report-generation)
- [Common Failures](#common-failures)

## Concepts

This skill performs regression testing for flutter-tizen plugins after changes to the flutter-tizen toolchain, embedder, or engine. It validates that existing plugins continue to work correctly by:

1. Running plugin example apps on TV emulator
2. Executing integration tests
3. Analyzing logs for errors and warnings
4. Generating issue reports for any failures

The skill reads `.github/recipe.yaml` to determine which plugins are testable on the TV profile.

## Prerequisites

Before running regression tests, verify the environment:

### Task Progress
- [ ] **Step 1: Verify flutter-tizen toolchain.** `flutter-tizen doctor -v` must pass.
- [ ] **Step 2: Verify Tizen SDK.** `sdb version` and `tizen version` must succeed.
- [ ] **Step 3: Verify certificate profile.** `tizen security-profiles list` must show an active profile.
- [ ] **Step 4: Verify plugins repository.** The plugins git repository must be available locally.

If any prerequisite is missing, ask the user for the location of the missing component and save valid paths to a configuration file accessible by general agents.

### Configuration Storage

On first run, the skill stores paths in `~/.config/flutter-tizen-regression-test/config.json`:

```json
{
  "flutterTizenPath": "/path/to/flutter-tizen",
  "tizenSdkPath": "/path/to/tizen-studio",
  "pluginsPath": "/path/to/plugins",
  "embedderPath": "/path/to/embedder",
  "enginePath": "/path/to/engine"
}
```

## Testable Plugins

Read `.github/recipe.yaml` in the plugins repository **at test time** to identify plugins testable on `tv-9.0`. The list changes as plugins are added or excluded upstream, so never rely on a cached or hardcoded copy:

```sh
grep -E '\[[^]]*"tv-9.0"[^]]*\]' <pluginsPath>/.github/recipe.yaml | tr -d ' ' | cut -d: -f1
```

Plugins mapped to an empty array (`[]`) or special conditions are skipped.

## User Input Priority

**IMPORTANT:** User-provided parameters take precedence over default values. When the user explicitly specifies a device, emulator, or target, use that specification without overriding it.

### User-Configurable Parameters

| Parameter | User Input Example | Default Behavior |
|-----------|-------------------|------------------|
| **Device/Emulator** | `device: emulator-26101`, `emulator: tv-9.0`, `on device T-12345` | Launch TV 9.0 emulator automatically |
| **Plugin** | `plugin: connectivity_plus`, `test battery_plus` | Test all plugins from recipe.yaml |
| **Profile** | `profile: tv-9.0`, `profile: common` | Use `tv-9.0` for TV emulator |
| **Build Mode** | `--debug`, `--release`, `--profile` | Use `--debug` |
| **Skip Steps** | `skip integration tests`, `example only` | Run all steps |

### Parameter Parsing from User Request

When the user provides a request, parse the following patterns:

1. **Device/Emulator ID**: Look for patterns like:
   - `device <device-id>` or `device: <device-id>`
   - `emulator <emulator-id>` or `emulator: <emulator-id>`
   - `-d <device-id>`
   - `on <device-id>`

2. **Device Type**: Look for keywords:
   - `emulator` → Use connected emulator (verify with `sdb devices`)
   - `device` or `real device` → Use connected physical device
   - `TV` or `tv` → Use TV device/emulator
   - `wearable` → Use wearable device/emulator (requires different profile)

3. **Plugin Name**: Look for plugin names matching the testable plugins list

4. **Skip Options**: Look for:
   - `skip integration test` or `no integration test`
   - `example only` or `run example only`
   - `integration test only` or `skip example`

### Decision Flow for Device Selection

```
User Request
    │
    ├─► User specified device/emulator ID?
    │       │
    │       ├─► YES → Use specified device ID directly
    │       │         (Verify device is connected with `sdb devices`)
    │       │
    │       └─► NO → User specified device type?
    │               │
    │               ├─► "emulator" → Check for running emulators
    │               │               If none running, launch TV 9.0 emulator
    │               │
    │               ├─► "device" or "real device" → Check for physical devices
    │               │                               Error if none connected
    │               │
    │               └─► NO (default) → Launch TV 9.0 emulator
    │
    └─► Proceed with selected device
```

### Decision Flow for Plugin Selection

**IMPORTANT:** User-specified plugin name takes precedence over the default plugin list from `recipe.yaml`.

```
User Request
    │
    ├─► User specified plugin name?
    │       │
    │       ├─► YES → Test only the specified plugin
    │       │         (Verify plugin exists in packages/ directory)
    │       │
    │       └─► NO → Read .github/recipe.yaml
    │               │
    │               ├─► Use plugins list with ["tv-9.0"] profile
    │               │   (These are testable on TV emulator)
    │               │
    │               └─► Skip plugins with empty [] or special conditions
    │
    └─► Proceed with selected plugin(s)
```

### Plugin Selection Examples

| User Request | Plugin Selection |
|--------------|------------------|
| `test connectivity_plus` | Only `connectivity_plus` |
| `regression test for battery_plus and url_launcher` | Only `battery_plus` and `url_launcher` |
| `run regression test` (no plugin specified) | All plugins from `recipe.yaml` with `["tv-9.0"]` |
| `test all plugins` | All plugins from `recipe.yaml` with `["tv-9.0"]` |

## Workflow: Regression Test

### Task Progress
- [ ] **Step 1: Parse user input.** Extract device/emulator, plugin, and other parameters from user request.
- [ ] **Step 2: Verify environment.** Check flutter-tizen, Tizen SDK, certificate, and plugins repository.
- [ ] **Step 3: Select/Verify device.** Use user-specified device OR launch TV 9.0 emulator if not running.
- [ ] **Step 4: Identify test target.** Use user-specified plugin or iterate through all testable plugins.
- [ ] **Step 5: Run example app.** Execute `flutter-tizen run` and capture logs.
- [ ] **Step 6: Analyze example logs.** Check for errors, crashes, and warnings.
- [ ] **Step 7: Check integration test structure.** Verify `test_driver/` and `integration_test/` directories exist.
- [ ] **Step 8: Run integration tests.** Execute `flutter-tizen drive` for each test file (unless skipped).
- [ ] **Step 9: Analyze test logs.** Check for test failures and errors.
- [ ] **Step 10: Generate issue report.** Create report if any issues found.
- [ ] **Step 11: Summary.** Present overall test results.

## Running Example Apps

### Single Plugin Test

```sh
cd /path/to/plugins/packages/<plugin_name>/example
flutter-tizen -d <device-id> run --debug
```

Note: `flutter-tizen run` automatically detects the device profile and architecture from the connected device. The `--device-profile` and `--target-arch` options are only available for `flutter-tizen build tpk`.

### Log Capture

> **Do not use `sdb dlog` on the Samsung TV emulator — it does not work.** Verified on `T-samsung-10.0-x86_64`: `sdb capability` reports `secure_protocol:enabled` + `intershell_support:disabled`, so `sdb dlog` (and `dlog -c`) return **no output at all** (silently, with no error). Every grep over the empty result matches nothing, so the test silently reports a false PASS. `sdb dlog` works only on the **common** emulator (`secure_protocol:disabled`). Confirm on any target with:
>
> ```sh
> sdb -s <device-id> capability | grep -E 'secure_protocol|intershell_support'
> ```

Capture logs from the **foreground `flutter-tizen run` session** instead — the only log channel that works on the TV emulator. It streams Dart `print`/`debugPrint` and Flutter engine messages, so redirect that process to a file.

`flutter-tizen run` stays attached until you press `q`, so an unattended or batch run must bound it — either background it and `kill` after a grace period (as `example/regression_test_runner.sh` does), or wrap it in `timeout` with a generous limit for the first build:

```sh
timeout 300 flutter-tizen -d <device-id> run --debug > example_run.log 2>&1
```

### Success Criteria

The example app is considered successful if:
- App launches without crash
- No unhandled exception or native crash in the captured run-console log (see Failure Detection below)
- Interactive sessions only: hot reload works (press `r` in the terminal). Skip this check when output is redirected to a file — the session is not interactive.

### Failure Detection

Watch for these patterns in the `flutter-tizen run` console output:
- `Unhandled Exception:` (uncaught Dart exception — the Flutter engine logs a capital `E`, the bare Dart VM lowercase, so match case-insensitively)
- `EXCEPTION CAUGHT BY` (Flutter framework error banner)
- `PlatformException`
- `SIGSEGV` or `SIGABRT` (native crash)
- `Failed to`
- `Error:`

Do **not** grep for dlog/logcat-style prefixes (`F/`, `E/FlutterEngine`, `E/FlutterJNI`) — those are Android/dlog formats that never appear in the run console, so they silently match nothing and report a false PASS.

## Running Integration Tests

### Directory Structure Check

Before running integration tests, verify the structure:

```sh
# Check for test_driver directory
ls packages/<plugin_name>/example/test_driver/

# Check for integration_test directory
ls packages/<plugin_name>/example/integration_test/
```

Required files:
- `test_driver/integration_test.dart` - Driver file
- `integration_test/<test_name>.dart` - Test file(s)

### Running Tests

For each test file in `integration_test/`:

```sh
cd /path/to/plugins/packages/<plugin_name>/example

flutter-tizen drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/<test_file>.dart \
  -d <device-id> \
  --debug
```

Note: `flutter-tizen drive` automatically detects the device profile and architecture from the connected device. The `--device-profile` and `--target-arch` options are only available for `flutter-tizen build tpk`.

### Test Result Analysis

Capture test output and check for:
- `✓` (pass) vs `✗` (fail)
- `All tests passed!` message
- `Some tests failed.` message
- Stack traces
- Timeout errors

## Log Analysis

### Example App Log Analysis

```sh
# Check for Dart / framework errors
grep -iE "Unhandled Exception|EXCEPTION CAUGHT BY|PlatformException" example_run.log

# Check for generic failures
grep -iE "error:|failed" example_run.log

# Check for crashes
grep -iE "SIGSEGV|SIGABRT|crash" example_run.log
```

### Integration Test Log Analysis

```sh
# Check for test failures
grep -E "✗|failed|FAIL" test_output.log

# Check for exceptions during tests
grep -iE "exception|error" test_output.log

# Check for timeout
grep -iE "timeout|timed out" test_output.log
```

## Issue Report Generation

When issues are detected, generate a report:

### Report Template

```markdown
# Flutter-Tizen Plugin Regression Test Report

**Date:** <timestamp>
**Plugin:** <plugin_name>
**Device:** <device-id> (<profile>)
**flutter-tizen version:** <version>

## Summary

- Example App: ✅ PASS / ❌ FAIL
- Integration Tests: ✅ PASS / ❌ FAIL (X/Y passed)

## Issues Found

### Issue 1: <short_description>

**Type:** Example App Crash / Integration Test Failure / Log Error
**Severity:** Critical / High / Medium / Low

**Details:**
<description_of_issue>

**Log Excerpt:**
```
<relevant_log_lines>
```

**Reproduction Steps:**
1. <step_1>
2. <step_2>

**Suggested Investigation:**
- <suggestion_1>
- <suggestion_2>

---

### Issue 2: ...
```

### Report Storage

Reports are saved to:
```
~/.config/flutter-tizen-regression-test/reports/<date>_<plugin_name>_report.md
```

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| `No connected Tizen devices` | Emulator not running or not detected | Launch TV emulator with `flutter-tizen emulators --launch <id>` |
| `Installing TPK` hangs | Stale package installation | `sdb -s <id> uninstall <appid>` then retry |
| Integration test `timeout` | App not responding | Check for infinite loops or blocking operations |
| `test_driver/integration_test.dart not found` | Plugin has no integration tests | Skip integration test step for this plugin |
| `Failed to find security-profile` | No certificate profile | Run `tizen security-profiles add` or use flutter-tizen-setup skill |
| `SIGSEGV` in native code | Native plugin crash | Check Tizen native implementation |
| `Privilege denied` error | Missing privilege in manifest | Add required privilege to `tizen-manifest.xml` |

## Example

### Testing a Single Plugin (User-Specified Plugin)

```
User: Run regression test for connectivity_plus plugin

1. Parse user input → Plugin: connectivity_plus (user-specified), No device specified
2. Verify environment (flutter-tizen, Tizen SDK, certificate)
3. Check if TV emulator is running, launch if needed
4. cd packages/connectivity_plus/example
5. flutter-tizen -d emulator-26101 run --debug
6. Capture and analyze logs
7. Check test_driver/ and integration_test/ directories
8. flutter-tizen drive --driver=test_driver/integration_test.dart --target=integration_test/connectivity_plus_test.dart -d emulator-26101 --debug
9. Analyze test output
10. Generate report if issues found
```

### Testing All Plugins (No Plugin Specified - Use recipe.yaml)

```
User: Run regression test

1. Parse user input → No plugin specified, will use recipe.yaml default list
2. Read .github/recipe.yaml → Get plugins with ["tv-9.0"] profile
3. Verify environment (flutter-tizen, Tizen SDK, certificate)
4. Check if TV emulator is running, launch if needed
5. For each plugin in recipe.yaml testable list:
   - Run example app
   - Run integration tests
   - Record results
6. Generate summary report
```

### Testing with Skip Options

```
User: Run regression test for connectivity_plus on device T-12345, skip integration tests

1. Parse user input → Device: T-12345, Skip: integration tests
2. Verify device is connected
3. Run example app only
4. Skip integration test step
5. Generate report for example app results
```

## Related Skills

- [flutter-tizen-setup](../flutter-tizen-setup/SKILL.md) - Set up flutter-tizen environment
- [flutter-tizen-device](../flutter-tizen-device/SKILL.md) - Device connection and logging
- [flutter-tizen-build-tpk](../flutter-tizen-build-tpk/SKILL.md) - Build TPK packages
