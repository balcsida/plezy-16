#!/usr/bin/env bash
# Log analysis script for flutter-tizen plugin regression tests.
# Companion to ../SKILL.md.

set -eu

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
	echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
	echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Analyze example app logs
analyze_example_logs() {
	local log_file="$1"

	if [[ ! -f "$log_file" ]]; then
		log_error "Log file not found: $log_file"
		return 1
	fi

	log_section "Example App Log Analysis: $log_file"

	# Check for Dart / Flutter framework errors. dlog/logcat-style prefixes
	# (F/, E/FlutterEngine, E/FlutterJNI) never appear in the run console —
	# grepping for them silently matches nothing and reports a false PASS.
	# Case-insensitive: the engine logs "Unhandled Exception:", the bare VM
	# "Unhandled exception:".
	log_info "Checking for Dart/framework errors..."
	local dart_error_count=$(grep -ci "Unhandled Exception\|EXCEPTION CAUGHT BY\|PlatformException" "$log_file" 2>/dev/null || echo "0")
	if [[ $dart_error_count -gt 0 ]]; then
		log_error "Found $dart_error_count Dart/framework error(s):"
		grep -i "Unhandled Exception\|EXCEPTION CAUGHT BY\|PlatformException" "$log_file" | head -10
	else
		log_info "No Dart/framework errors found"
	fi

	# Check for crashes (SIGSEGV, SIGABRT)
	log_info "Checking for crash indicators..."
	local crash_count=$(grep -ci "SIGSEGV\|SIGABRT\|crash\|fatal signal" "$log_file" 2>/dev/null || echo "0")
	if [[ $crash_count -gt 0 ]]; then
		log_error "Found $crash_count crash indicator(s):"
		grep -i "SIGSEGV\|SIGABRT\|crash\|fatal signal" "$log_file" | head -10
	else
		log_info "No crash indicators found"
	fi

	# Check for exceptions
	log_info "Checking for exceptions..."
	local exception_count=$(grep -ci "exception\|unhandled" "$log_file" 2>/dev/null || echo "0")
	if [[ $exception_count -gt 0 ]]; then
		log_warn "Found $exception_count exception(s):"
		grep -i "exception\|unhandled" "$log_file" | head -10
	else
		log_info "No exceptions found"
	fi

	# Check for "Failed to" patterns
	log_info "Checking for 'Failed to' patterns..."
	local failed_count=$(grep -ci "failed to" "$log_file" 2>/dev/null || echo "0")
	if [[ $failed_count -gt 0 ]]; then
		log_warn "Found $failed_count 'Failed to' pattern(s):"
		grep -i "failed to" "$log_file" | head -10
	else
		log_info "No 'Failed to' patterns found"
	fi

}

# Analyze integration test logs
analyze_test_logs() {
	local log_file="$1"

	if [[ ! -f "$log_file" ]]; then
		log_error "Log file not found: $log_file"
		return 1
	fi

	log_section "Integration Test Log Analysis: $log_file"

	# Count passed tests
	local pass_count=$(grep -c "✓\|PASS\|passed" "$log_file" 2>/dev/null || echo "0")
	log_info "Passed test indicators: $pass_count"

	# Count failed tests
	local fail_count=$(grep -c "✗\|FAIL\|failed" "$log_file" 2>/dev/null || echo "0")
	if [[ $fail_count -gt 0 ]]; then
		log_error "Found $fail_count failure indicator(s):"
		grep "✗\|FAIL\|failed" "$log_file" | head -10
	else
		log_info "No test failure indicators found"
	fi

	# Check for "All tests passed!" message
	if grep -q "All tests passed!" "$log_file" 2>/dev/null; then
		log_info "✓ All tests passed message found!"
	fi

	# Check for "Some tests failed" message
	if grep -q "Some tests failed" "$log_file" 2>/dev/null; then
		log_error "✗ 'Some tests failed' message found"
	fi

	# Check for stack traces
	local stack_count=$(grep -c "stack trace\|at .*\.dart" "$log_file" 2>/dev/null || echo "0")
	if [[ $stack_count -gt 0 ]]; then
		log_warn "Found $stack_count stack trace line(s):"
		grep "stack trace\|at .*\.dart" "$log_file" | head -5
	fi

	# Check for timeout errors
	local timeout_count=$(grep -ci "timeout\|timed out" "$log_file" 2>/dev/null || echo "0")
	if [[ $timeout_count -gt 0 ]]; then
		log_warn "Found $timeout_count timeout indicator(s):"
		grep -i "timeout\|timed out" "$log_file" | head -5
	fi
}

# Generate summary
generate_summary() {
	local log_dir="$1"

	log_section "Summary Report"

	# Count log files
	local example_logs=$(find "$log_dir" -name "*_example_run.log" 2>/dev/null | wc -l)
	local test_logs=$(find "$log_dir" -name "*_test_output.log" 2>/dev/null | wc -l)
	local issue_files=$(find "$log_dir" -name "*_issues.txt" 2>/dev/null | wc -l)

	echo "Log files found:"
	echo "  - Example run logs: $example_logs"
	echo "  - Test outputs: $test_logs"
	echo "  - Issue reports: $issue_files"

	if [[ $issue_files -gt 0 ]]; then
		log_warn "\nPlugins with issues:"
		find "$log_dir" -name "*_issues.txt" -exec basename {} _issues.txt \; 2>/dev/null | sort -u
	fi
}

# Main function
main() {
	if [[ $# -lt 1 ]]; then
		echo "Usage: $0 <log_file | log_dir>"
		echo ""
		echo "Examples:"
		echo "  $0 example_run.log          # Analyze single example log"
		echo "  $0 test_output.log          # Analyze single test log"
		echo "  $0 ./logs/                  # Analyze all logs in directory"
		exit 1
	fi

	local target="$1"

	if [[ -d "$target" ]]; then
		# Directory mode: analyze all logs
		log_info "Analyzing all logs in: $target"

		# Analyze example logs (captured from the foreground `flutter-tizen run`
		# session — `sdb dlog` is unavailable on the TV emulator)
		for log_file in "$target"/*_example_run.log; do
			if [[ -f "$log_file" ]]; then
				analyze_example_logs "$log_file"
			fi
		done

		# Analyze test logs
		for log_file in "$target"/*_test_output.log; do
			if [[ -f "$log_file" ]]; then
				analyze_test_logs "$log_file"
			fi
		done

		# Generate summary
		generate_summary "$target"
	elif [[ -f "$target" ]]; then
		# Single file mode
		if [[ "$target" == *test* ]]; then
			analyze_test_logs "$target"
		else
			analyze_example_logs "$target"
		fi
	else
		log_error "Target not found: $target"
		exit 1
	fi
}

main "$@"
