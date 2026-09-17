import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


EXPECTED_REQUIREMENT = "pymobiledevice3==11.13.0"
PRIMARY_WHEEL = "pymobiledevice3-11.13.0-py3-none-any.whl"
SCRIPT_SOURCE = (
    Path(__file__).resolve().parents[1] / "generate_tunnel_trust_anchor.py"
)


class GeneratorFixture:
    def __init__(self, lock_contents=None, wheels=None, extra_files=None):
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary_directory.name)
        self.project_root = self.root / "project"
        self.helper_root = self.project_root / "iPhoneLocationMoveTunnelHelper"
        self.script_path = self.helper_root / "Scripts" / "generate_tunnel_trust_anchor.py"
        self.wheelhouse = self.helper_root / "Resources" / "tunnel-wheelhouse"
        self.lockfile = (
            self.project_root
            / "iPhoneLocationMove"
            / "Device"
            / "Resources"
            / "pymobiledevice3.lock"
        )
        self.manifest = self.wheelhouse / "runtime-manifest.json"
        self.swift = self.helper_root / "GeneratedTunnelTrustAnchor.swift"

        self.script_path.parent.mkdir(parents=True)
        self.wheelhouse.mkdir(parents=True)
        shutil.copy2(SCRIPT_SOURCE, self.script_path)
        if lock_contents is not None:
            self.lockfile.parent.mkdir(parents=True)
            self.lockfile.write_text(lock_contents, encoding="utf-8")
        for filename, payload in (wheels or {}).items():
            (self.wheelhouse / filename).write_bytes(payload)
        for filename, payload in (extra_files or {}).items():
            (self.wheelhouse / filename).write_bytes(payload)

    def close(self):
        self._temporary_directory.cleanup()

    def run(self):
        return subprocess.run(
            [sys.executable, str(self.script_path)],
            cwd=self.project_root,
            capture_output=True,
            text=True,
            check=False,
        )


class GenerateTunnelTrustAnchorTests(unittest.TestCase):
    def fixture(self, **kwargs):
        return GeneratorFixture(**kwargs)

    def test_generates_manifest_and_trust_anchor_from_lock_and_wheel_bytes(self):
        fixture = self.fixture(
            lock_contents=f"{EXPECTED_REQUIREMENT}\n",
            wheels={PRIMARY_WHEEL: b"primary wheel bytes"},
        )
        self.addCleanup(fixture.close)

        result = fixture.run()

        self.assertEqual(result.returncode, 0, result.stderr)
        manifest_data = fixture.manifest.read_bytes()
        manifest = json.loads(manifest_data)
        expected_wheel_digest = hashlib.sha256(b"primary wheel bytes").hexdigest()
        self.assertEqual(
            manifest,
            {
                "files": [
                    {
                        "mode": 0o600,
                        "relativePath": PRIMARY_WHEEL,
                        "sha256": expected_wheel_digest,
                    }
                ]
            },
        )

        swift_source = fixture.swift.read_text(encoding="utf-8")
        manifest_digest = hashlib.sha256(manifest_data).hexdigest()
        self.assertIn(f'manifestSHA256: "{manifest_digest}"', swift_source)
        self.assertIn("requirement: TunnelRuntimePin.requirement", swift_source)
        self.assertNotIn(f'requirement: "{EXPECTED_REQUIREMENT}"', swift_source)
        self.assertIn(f'sha256: "{expected_wheel_digest}"', swift_source)
        self.assertNotIn("9.36.3", swift_source)

    def test_rejects_missing_lockfile_without_writing_outputs(self):
        fixture = self.fixture(wheels={PRIMARY_WHEEL: b"primary wheel bytes"})
        self.addCleanup(fixture.close)
        sentinel = "sentinel trust anchor"
        fixture.swift.write_text(sentinel, encoding="utf-8")

        result = fixture.run()

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(fixture.manifest.exists())
        self.assertEqual(fixture.swift.read_text(encoding="utf-8"), sentinel)

    def test_rejects_multiple_lock_requirements_without_writing_outputs(self):
        fixture = self.fixture(
            lock_contents=f"{EXPECTED_REQUIREMENT}\nrequests==2.32.5\n",
            wheels={PRIMARY_WHEEL: b"primary wheel bytes"},
        )
        self.addCleanup(fixture.close)

        result = fixture.run()

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(fixture.manifest.exists())
        self.assertFalse(fixture.swift.exists())

    def test_rejects_missing_primary_wheel_without_writing_outputs(self):
        fixture = self.fixture(
            lock_contents=f"{EXPECTED_REQUIREMENT}\n",
            wheels={"requests-2.32.5-py3-none-any.whl": b"dependency wheel"},
        )
        self.addCleanup(fixture.close)

        result = fixture.run()

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(fixture.manifest.exists())
        self.assertFalse(fixture.swift.exists())

    def test_rejects_primary_wheel_version_mismatch_without_writing_outputs(self):
        fixture = self.fixture(
            lock_contents=f"{EXPECTED_REQUIREMENT}\n",
            wheels={
                "pymobiledevice3-9.36.3-py3-none-any.whl": b"old primary wheel"
            },
        )
        self.addCleanup(fixture.close)

        result = fixture.run()

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(fixture.manifest.exists())
        self.assertFalse(fixture.swift.exists())

    def test_rejects_non_wheel_payload_without_writing_outputs(self):
        fixture = self.fixture(
            lock_contents=f"{EXPECTED_REQUIREMENT}\n",
            wheels={PRIMARY_WHEEL: b"primary wheel bytes"},
            extra_files={"README.txt": b"not a wheel"},
        )
        self.addCleanup(fixture.close)

        result = fixture.run()

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(fixture.manifest.exists())
        self.assertFalse(fixture.swift.exists())

    def test_rejects_stale_manifest_without_replacing_trust_anchor(self):
        fixture = self.fixture(
            lock_contents=f"{EXPECTED_REQUIREMENT}\n",
            wheels={PRIMARY_WHEEL: b"primary wheel bytes"},
        )
        self.addCleanup(fixture.close)
        stale_manifest = b'{"files":[]}'
        fixture.manifest.write_bytes(stale_manifest)
        sentinel = "sentinel trust anchor"
        fixture.swift.write_text(sentinel, encoding="utf-8")

        result = fixture.run()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(fixture.manifest.read_bytes(), stale_manifest)
        self.assertEqual(fixture.swift.read_text(encoding="utf-8"), sentinel)

    def test_generated_manifest_digest_is_byte_exact(self):
        fixture = self.fixture(
            lock_contents=f"{EXPECTED_REQUIREMENT}\n",
            wheels={
                "dependency-1.0-py3-none-any.whl": b"dependency bytes",
                PRIMARY_WHEEL: b"primary wheel bytes",
            },
        )
        self.addCleanup(fixture.close)

        result = fixture.run()

        self.assertEqual(result.returncode, 0, result.stderr)
        manifest_data = fixture.manifest.read_bytes()
        swift_source = fixture.swift.read_text(encoding="utf-8")
        manifest_digest = re.search(
            r'manifestSHA256: "([0-9a-f]{64})"', swift_source
        )
        self.assertIsNotNone(manifest_digest)
        self.assertEqual(
            manifest_digest.group(1), hashlib.sha256(manifest_data).hexdigest()
        )
        manifest = json.loads(manifest_data)
        self.assertEqual(
            [entry["relativePath"] for entry in manifest["files"]],
            sorted(entry["relativePath"] for entry in manifest["files"]),
        )
        for entry in manifest["files"]:
            self.assertIn(
                f'sha256: "{entry["sha256"]}"',
                swift_source,
            )


if __name__ == "__main__":
    unittest.main()
