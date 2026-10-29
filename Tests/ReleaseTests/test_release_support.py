"""Exercise exact-source packaging, repeatability, and dependency integrity offline."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("release_support", ROOT / "scripts/release-support.py")
SUPPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SUPPORT)


class ReleaseTests(unittest.TestCase):
    def test_exact_source_package_and_rebuild_snapshot(self):
        with tempfile.TemporaryDirectory(prefix="release-source-test-") as temporary:
            folder = Path(temporary)
            source = folder / "source"
            output = folder / "output"
            source.mkdir()
            output.mkdir()
            SUPPORT.snapshot(ROOT, source)
            archive = SUPPORT.source_package(source, output)
            manifest = json.loads((output / "SOURCE-MANIFEST.json").read_text())
            self.assertIn("Sources/NetMDHelper/main.mm", manifest["sha256"])
            self.assertIn("scripts/release.sh", manifest["sha256"])
            for name in SUPPORT.DEPENDENCIES:
                self.assertIn(".build/NetMD/downloads/" + name, manifest["sha256"])
            self.assertTrue((source / "Licenses/GPL-3.0.txt").is_file())
            self.assertTrue((source / "Licenses/LGPL-2.1.txt").is_file())
            notices = (source / "Licenses/Embedded-Source-Notices.txt").read_text()
            self.assertIn("Mark Borgerding", notices)
            self.assertIn("FFmpeg", notices)
            original_hash = SUPPORT.digest(archive)
            self.assertEqual(SUPPORT.digest(SUPPORT.source_package(source, output)), original_hash)
            extracted = folder / "extracted"
            extracted.mkdir()
            # The archive was just produced here, so its members are trusted.
            with tarfile.open(archive) as package:
                package.extractall(extracted)
            exported = extracted / "Bootlegger"
            self.assertFalse((exported / ".git").exists())
            for name, checksum in manifest["sha256"].items():
                self.assertEqual(SUPPORT.digest(exported / name), checksum, name)
            rebuilt_snapshot = folder / "rebuilt"
            rebuilt_snapshot.mkdir()
            SUPPORT.snapshot(exported, rebuilt_snapshot)
            self.assertEqual((rebuilt_snapshot / "scripts/build-netmd.sh").read_bytes(),
                             (source / "scripts/build-netmd.sh").read_bytes())
            bad_archive = source / ".build/NetMD/downloads/libusb.tar.bz2"
            bad_archive.write_bytes(b"corrupt dependency archive")
            with self.assertRaisesRegex(RuntimeError, "incorrect dependency"):
                SUPPORT.source_package(source, output)


if __name__ == "__main__":
    unittest.main()
