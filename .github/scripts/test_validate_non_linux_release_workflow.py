#!/usr/bin/env python3
"""Mutation tests for the non-Linux release workflow semantic contract."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


SCRIPT_DIR = Path(__file__).resolve().parent
WORKFLOW = SCRIPT_DIR.parent / "workflows" / "non-linux-release-validation.yml"
SPEC = importlib.util.spec_from_file_location(
    "workflow_contract", SCRIPT_DIR / "validate_non_linux_release_workflow.py")
assert SPEC and SPEC.loader
CONTRACT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTRACT)


class BuildInvocationMutationTests(unittest.TestCase):
    def assert_rejected(self, mutated: str) -> None:
        path = SCRIPT_DIR / ".workflow-mutation-test.yml"
        try:
            path.write_text(mutated, encoding="utf-8")
            with self.assertRaises(AssertionError):
                CONTRACT.validate(path)
        finally:
            path.unlink(missing_ok=True)

    def test_rejects_pe_target_substituted_for_normal_build(self) -> None:
        original = WORKFLOW.read_text(encoding="utf-8")
        normal = "& $env:CMAKE_EXE --build $odbcBuild --parallel 4 `"
        replacement = (
            "& $env:CMAKE_EXE --build $odbcBuild `\n"
            "            --target verify-windows-dependencies --parallel 4 `"
        )
        self.assertEqual(original.count(normal), 1)
        self.assert_rejected(original.replace(normal, replacement, 1))

    def test_rejects_additional_parallel_value(self) -> None:
        original = WORKFLOW.read_text(encoding="utf-8")
        normal = "& $env:CMAKE_EXE --build $odbcBuild --parallel 4 `"
        replacement = (
            "& $env:CMAKE_EXE --build $odbcBuild --parallel 2 --parallel 4 `"
        )
        self.assertEqual(original.count(normal), 1)
        self.assert_rejected(original.replace(normal, replacement, 1))

    def test_rejects_duplicate_normal_build(self) -> None:
        original = WORKFLOW.read_text(encoding="utf-8")
        normal = "& $env:CMAKE_EXE --build $odbcBuild --parallel 4 `"
        duplicate = f"{normal}\n          {normal}"
        self.assertEqual(original.count(normal), 1)
        self.assert_rejected(original.replace(normal, duplicate, 1))


if __name__ == "__main__":
    unittest.main()
