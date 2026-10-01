import hashlib
import json
import subprocess
import sys
import struct
import tempfile
import unittest
from pathlib import Path

from tools import vfx_workbench as workbench
from tools import vfx_asset_bridge as bridge


class WorkbenchChecks(unittest.TestCase):
    def test_catalog_paths_and_asset_provenance_are_real(self):
        self.assertEqual(workbench.validate_catalog(workbench.catalog()), [])

    def test_imported_media_fingerprint_retains_binary_bytes_and_normalizes_gltf_text(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "project.godot").write_bytes(b"fixture\n")
            assets = root / "assets"
            assets.mkdir()
            for suffix in (".jpg", ".jpeg", ".webp", ".ogg"):
                with self.subTest(suffix=suffix):
                    media = assets / ("mask" + suffix)
                    before = workbench.fingerprint(root)
                    media.write_bytes(b"compressed fixture\r\nbytes")
                    original = workbench.fingerprint(root)
                    self.assertNotEqual(before, original)
                    media.write_bytes(b"compressed fixture\nbytes")
                    self.assertNotEqual(original, workbench.fingerprint(root))
                    media.unlink()
            gltf = assets / "scene.gltf"
            gltf.write_bytes(b'{"asset":{}}\r\n')
            original = workbench.fingerprint(root)
            gltf.write_bytes(b'{"asset":{}}\n')
            self.assertEqual(original, workbench.fingerprint(root))

    def test_runner_rejects_error_and_missing_marker_even_with_zero_exit(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / "run.log"
            failed = workbench.checked_run([sys.executable, "-c", "print('SCRIPT ERROR: invalid')"], log, 5)
            self.assertEqual(failed["status"], "FAIL")
            missing = workbench.checked_run([sys.executable, "-c", "print('ordinary output')"], log, 5, "REQUIRED")
            self.assertEqual(missing["status"], "FAIL")

    def test_timeout_is_finite_and_never_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            result = workbench.checked_run([sys.executable, "-c", "import time; time.sleep(10)"], Path(folder) / "run.log", 0.05)
            self.assertEqual(result["status"], "TIMEOUT")
            self.assertLess(result["seconds"], 3)

    def test_evidence_freshness_integrity_and_pending_art_review(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            evidence = output / "frame.png"
            evidence.write_bytes(b"fixture bytes; not an engine screenshot")
            manifest = {"source": {"content_sha256": "current"}, "expected_cases": ["day"],
                        "cases": [{"case": "day", "status": "PASS", "files": [
                            {"path": "frame.png", "sha256": hashlib.sha256(evidence.read_bytes()).hexdigest()}]}]}
            workbench.write_json(output / "manifest.json", manifest)
            workbench.write_json(output / "review.json", {})
            technical, artistic = workbench.evidence_errors(output, "current")
            self.assertEqual(technical, [])
            self.assertEqual(len(artistic), len(workbench.REVIEW_ITEMS))
            technical, _ = workbench.evidence_errors(output, "changed")
            self.assertIn("STALE", technical[0])
            evidence.write_bytes(b"altered")
            technical, _ = workbench.evidence_errors(output, "current")
            self.assertIn("Altered evidence", technical[0])

    def test_missing_case_or_empty_evidence_is_not_success(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            workbench.write_json(output / "manifest.json", {"source": {"content_sha256": "same"},
                "expected_cases": ["day", "miss"], "cases": [{"case": "day", "status": "PASS", "files": []}]})
            workbench.write_json(output / "review.json", {})
            technical, _ = workbench.evidence_errors(output, "same")
            self.assertEqual(len(technical), 2)

    def test_cli_dispatch_catalog_and_invalid_case(self):
        result = subprocess.run([sys.executable, str(workbench.ROOT / "tools/vfx_workbench.py"), "catalog"],
                                cwd=workbench.ROOT, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertIn("mine:", result.stdout)
        bad = subprocess.run([sys.executable, str(workbench.ROOT / "tools/vfx_workbench.py"), "capture", "cleave", "--case", "invented"],
                             cwd=workbench.ROOT, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(bad.returncode, 0)
        self.assertIn("Choose distinct cases", bad.stderr)


class AssetBridgeChecks(unittest.TestCase):
    def make_package(self, root: Path) -> Path:
        package = root / "assets/vfx/masks"
        (package / "output").mkdir(parents=True)
        (package / "output/mask.txt").write_text("fixture mask data", encoding="utf-8")
        (package / "undeclared.txt").write_text("must not be imported", encoding="utf-8")
        (package / "manifest.json").write_text(json.dumps({"name": "masks", "type": "vfx", "source": "source",
                                                        "outputs": {"mask": "output/mask.txt"}}), encoding="utf-8")
        return package

    def test_discovery_reports_presence_without_approval(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.make_package(root)
            records = bridge.discover(root)
            self.assertEqual(len(records), 1)
            self.assertFalse(records[0]["quality_contract"])
            self.assertIn("not approved", records[0]["status"])

    def test_only_declared_contained_outputs_are_selected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            package = self.make_package(root)
            _, outputs = bridge.exports(root, "assets/vfx/masks")
            self.assertEqual(list(outputs), ["mask.txt"])
            manifest = bridge.read(package / "manifest.json")
            manifest["outputs"] = {"bad": "../../outside.txt"}
            (package / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaises(ValueError):
                bridge.exports(root, "assets/vfx/masks")

    def test_existing_destination_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            factory = root / "factory"
            self.make_package(factory)
            destination = root / "game/assets/vfx/imported/masks"
            destination.mkdir(parents=True)
            existing = destination / "artist_edit.txt"
            existing.write_text("local artist work")
            with self.assertRaisesRegex(ValueError, "Destination exists"):
                bridge.import_package(root / "game", factory, "assets/vfx/masks", False, "Fixture license note")
            self.assertEqual(existing.read_text(), "local artist work")

    def test_gate_failure_copies_nothing(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            factory = root / "factory"
            self.make_package(factory)
            (factory / "tools").mkdir()
            (factory / "tools/quality_gate.py").write_text("raise SystemExit(1)")
            with self.assertRaisesRegex(ValueError, "Upstream quality gate failed"):
                bridge.import_package(root / "game", factory, "assets/vfx/masks", True, "Fixture license note")
            self.assertFalse((root / "game/screenshots_debug/vfx_workbench/assets/masks").exists())

    def test_glb_external_images_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "model.glb"
            metadata = json.dumps({"asset": {"version": "2.0"}, "images": [{"uri": "lost_texture.png"}]}).encode()
            metadata += b" " * ((-len(metadata)) % 4)
            path.write_bytes(struct.pack("<4sIIII", b"glTF", 2, 20 + len(metadata), len(metadata), 0x4E4F534A) + metadata)
            with self.assertRaisesRegex(ValueError, "external"):
                bridge.check_self_contained_glb(path)

    def test_failed_gate_reports_diagnostics_even_after_staging_removal(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            factory = root / "factory"
            self.make_package(factory)
            (factory / "tools").mkdir()
            (factory / "tools/quality_gate.py").write_text("print('STALE BUILD: fixture'); raise SystemExit(1)")
            with self.assertRaisesRegex(ValueError, "STALE BUILD: fixture"):
                bridge.import_package(root / "game", factory, "assets/vfx/masks", True, "Fixture license note")


if __name__ == "__main__":
    unittest.main()
