"""CLI contract tests for the read-only RR driver planner (no kernel modules needed)."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
RRCTL = REPO / "files/initrd/opt/rr/rrctl"
TARGET = "fixture-7.4"
REAL_TARGET = "epyc7002-7.4-5.10.55"


def entries(**depends):
    return {name: {"depends": deps} for name, deps in depends.items()}


class DriverPlanTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)
        self.catalog = self.work / "catalog.json"

    def fixture(self, entries):
        self.catalog.write_text(json.dumps({TARGET: entries}), encoding="utf-8")

    def command(self, *options, catalog=None, platform=TARGET):
        return subprocess.run(
            [sys.executable, str(RRCTL), "plan", "--catalog", str(catalog or self.catalog),
             "--platform", platform, *options],
            cwd=self.work, capture_output=True, text=True, timeout=15,
        )

    def plan(self, *options, catalog=None, platform=TARGET, valid=True):
        result = self.command(*options, "--json", catalog=catalog, platform=platform)
        self.assertEqual(result.returncode == 0, valid, result.stdout + result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(bool(data["problems"]), not valid, data)
        if not valid:
            # A partially resolved invalid plan may not propose changing the current set.
            self.assertIsNone(data["diff"], data)
        return data

    def test_diamond_reasons_determinism_and_no_writes(self):
        graph = entries(storage="bus,clock", network="bus", bus="clock", clock="")
        self.fixture(graph)
        before = self.catalog.read_bytes()
        options = ("--root", "storage", "--root", "network", "--explain")
        plan = self.plan(*options)
        self.assertIsNone(plan["diff"])
        self.assertEqual(plan["modules"], ["bus", "clock", "network", "storage"])
        self.assertEqual(plan["reasons"]["clock"]["roots"], ["network", "storage"])
        self.assertEqual(plan["reasons"]["clock"]["required_by"], ["bus", "storage"])
        self.assertEqual(plan["reasons"]["bus"]["required_by"], ["network", "storage"])
        self.assertEqual(self.catalog.read_bytes(), before)
        self.assertEqual(list(self.work.iterdir()), [self.catalog])
        # Permuting dependency lists, module records and requested roots is immaterial.
        graph["storage"]["depends"] = "clock,bus"
        self.fixture(dict(reversed(list(graph.items()))))
        permuted = self.plan("--root", "network", "--root", "storage", "--explain")
        self.assertEqual(permuted, plan)

    def test_deselect_preserves_shared_dependency_and_shows_diff(self):
        self.fixture(entries(camera="usb", disk="usb", usb="bus", bus=""))
        # Both roots needed usb+bus. Remove camera, and compare against an old
        # selection also missing one dependency. No device state is consulted.
        plan = self.plan("--root", "disk", "--selected", "disk",
                         "--selected", "camera", "--selected", "usb")
        self.assertEqual(plan["modules"], ["bus", "disk", "usb"])
        self.assertEqual(plan["diff"], {"add": ["bus"], "remove": ["camera"]})

    def test_selected_file_can_compare_against_empty_and_combine_names(self):
        self.fixture(entries(bus="", disk="bus"))
        previous = self.work / "selected.txt"
        previous.write_text("", encoding="utf-8")
        empty = self.plan("--root", "disk", "--selected-file", str(previous))
        self.assertEqual(empty["diff"], {"add": ["bus", "disk"], "remove": []})
        content = "disk\n\nold-driver\n"
        previous.write_text(content, encoding="utf-8")
        diff = self.plan("--root", "disk", "--selected-file", str(previous),
                         "--selected", "bus")
        self.assertEqual(diff["diff"], {"add": [], "remove": ["old-driver"]})
        self.assertEqual(previous.read_text(encoding="utf-8"), content)

    def test_cycle_rejected_with_names(self):
        self.fixture(entries(disk="bus", bus="disk"))
        failed = self.plan("--root", "disk", "--selected", "old", valid=False)
        message = " ".join(failed["problems"]).lower()
        for name in ("disk", "bus", "cycl"):
            self.assertIn(name, message)

    def test_long_chain_is_not_limited_by_python_call_stack(self):
        # Iterative resolution should cover long acyclic chains; no timing assertion.
        keys = ["m%04d" % n for n in range(1200)]
        self.fixture({key: {"depends": keys[i+1] if i+1 < len(keys) else ""}
                      for i, key in enumerate(keys)})
        self.assertEqual(self.plan("--root", keys[0])["modules"], keys)

    def test_unlisted_is_not_silently_counted_as_builtin(self):
        self.fixture(entries(disk="transport"))
        failed = self.plan("--root", "disk", valid=False)
        self.assertIn("transport", " ".join(failed["problems"]))
        approved = self.plan("--root", "disk", "--builtin", "transport", "--explain")
        self.assertEqual(approved["modules"], ["disk"])
        self.assertEqual(approved["builtins"], ["transport"])
        self.assertEqual(approved["reasons"]["transport"]["required_by"], ["disk"])

    def test_scoped_root_has_no_fallback_and_sole_update_provider_is_used(self):
        graph = entries(disk="bus", clock="")
        graph["update/bus"] = {"depends": "clock"}
        self.fixture(graph)
        plan = self.plan("--root", "disk")
        self.assertEqual(plan["modules"], ["clock", "disk", "update/bus"])
        self.plan("--root", "update/clock", valid=False)

    def test_base_and_update_are_distinct_selectable_providers(self):
        self.fixture({"disk": {"depends": "bus"}, "bus": {"depends": "legacy"},
                      "update/bus": {"depends": "new"}, **entries(legacy="", new="")})
        # --selected reflects old state only; it must never break provider ties.
        failed = self.plan("--root", "disk", "--selected", "update/bus", valid=False)
        self.assertIn("bus", " ".join(failed["problems"]))
        base = self.plan("--root", "bus", "--root", "disk")
        self.assertEqual(base["modules"], ["bus", "disk", "legacy"])
        updated = self.plan("--root", "update/bus", "--root", "disk",
                            "--selected", "disk", "--selected", "bus", "--selected", "legacy")
        self.assertEqual(updated["modules"], ["disk", "new", "update/bus"])
        self.assertEqual(updated["diff"], {"add": ["new", "update/bus"],
                                            "remove": ["bus", "legacy"]})
        self.plan("--root", "bus", "--root", "update/bus", valid=False)

    def test_unscoped_kernel_module_hyphen_underscore_alias(self):
        self.fixture({"disk": {"depends": "disk_bus"}, "disk-bus": {"depends": ""}})
        self.assertEqual(self.plan("--root", "disk")["modules"], ["disk", "disk-bus"])

    def test_unknown_root_and_platform_have_actionable_errors(self):
        self.fixture(entries(disk=""))
        failed = self.plan("--root", "not-a-driver", valid=False)
        self.assertIn("not-a-driver", " ".join(failed["problems"]))
        failed = self.plan("--root", "disk", platform="absent-target", valid=False)
        self.assertIn("absent-target", " ".join(failed["problems"]))

    def test_bad_catalog_rejected_without_traceback_or_changes(self):
        self.catalog.write_text("{ truncated", encoding="utf-8")
        bad = self.command("--root", "disk", "--json")
        self.assertNotEqual(bad.returncode, 0)
        self.assertNotIn("Traceback", bad.stdout + bad.stderr)
        self.assertEqual(self.catalog.read_text(encoding="utf-8"), "{ truncated")
        self.fixture({"disk": {"depends": {"incorrect": "shape"}}})
        self.assertNotEqual(self.command("--root", "disk", "--json").returncode, 0)

    def test_human_preview_explains_instead_of_writing(self):
        self.fixture(entries(bus="", disk="bus"))
        plain = self.command("--root", "disk", "--explain", "--selected", "disk")
        self.assertEqual(plain.returncode, 0, plain.stdout + plain.stderr)
        self.assertIn("disk", plain.stdout)
        self.assertIn("bus", plain.stdout)
        self.assertEqual(list(self.work.iterdir()), [self.catalog])

    def test_supplied_catalogs_match_reference_for_example_target(self):
        # Public catalog parity, not an assertion about installed hardware or a custom bundle.
        catalogs = [REPO / "docs/modules.json", REPO / "docs/modules_detailed.json"]
        roots = ["virtio_scsi", "virtio_net", "i915"]
        modules = json.loads(catalogs[0].read_text(encoding="utf-8"))[REAL_TARGET]
        expected = set(roots)
        while True:
            dependencies = {dep for module in expected
                            for dep in modules[module]["depends"].split(",") if dep}
            if dependencies <= expected:
                break
            expected.update(dependencies)
        self.assertIn("virtio", expected)
        args = [item for root in roots for item in ("--root", root)]
        for catalog in catalogs:
            with self.subTest(catalog=catalog.name):
                data = self.plan(*args, catalog=catalog, platform=REAL_TARGET)
                self.assertEqual(data["modules"], sorted(expected))


if __name__ == "__main__":
    unittest.main()
