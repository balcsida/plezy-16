#!/usr/bin/env python3
"""Behavioral checks for the pinned SDK compatibility patch and cache handling."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SDK = Path(os.environ.get('FLUTTER_TIZEN_ROOT', ROOT / '.toolchains/flutter-tizen'))
SHA = json.loads((ROOT / 'tizen/toolchain.json').read_text())['flutter_tizen_sha']


class ToolchainPatchTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='plezy-sdk-patch-test-')
        self.addCleanup(self.directory.cleanup)
        self.sdk = Path(self.directory.name) / 'sdk'
        # Shares only Git objects, not the caller's working tree or caches.
        subprocess.run(['git', 'clone', '--quiet', '--shared', '--no-checkout',
                        str(SDK), str(self.sdk)], check=True)
        subprocess.run(['git', '-C', str(self.sdk), 'checkout', '--quiet', '--detach', SHA], check=True)
        self.source = self.sdk / 'lib/executable.dart'
        self.snapshot = self.sdk / 'bin/cache/flutter-tizen.snapshot'
        self.snapshot.parent.mkdir(parents=True, exist_ok=True)
        self.snapshot.write_text('old compiled SDK snapshot')

    def command(self, command):
        return subprocess.run(
            ['bash', '-c', 'source "$1/scripts/tizen/common.sh"; TOOLCHAIN="$2"; ' + command,
             'patch-test', str(ROOT), str(self.sdk)], capture_output=True, text=True)

    def test_version_guard_rejects_unpatched_sdk_without_mutation(self):
        before = self.source.read_bytes()
        result = self.command('require_toolchain')
        self.assertNotEqual(result.returncode, 0, 'Revision alone must not accept the broken host test CLI')
        self.assertEqual(self.source.read_bytes(), before)
        self.assertTrue(self.snapshot.exists())

    def test_apply_and_repeat_preserve_fresh_cache(self):
        result = self.command('toolchain_patch apply; require_toolchain')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.snapshot.exists(), 'An old compiled SDK must be invalidated')
        self.snapshot.write_text('rebuilt SDK snapshot')
        source = self.source.read_bytes()
        result = self.command('toolchain_patch apply; require_toolchain')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot.read_text(), 'rebuilt SDK snapshot')
        self.assertEqual(self.source.read_bytes(), source)

    def test_conflicting_source_is_not_overwritten(self):
        self.source.write_text('// local changes must survive\n')
        result = self.command('toolchain_patch apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.source.read_text(), '// local changes must survive\n')
        self.assertTrue(self.snapshot.exists())


if __name__ == '__main__':
    unittest.main()
