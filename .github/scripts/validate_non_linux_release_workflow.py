#!/usr/bin/env python3
"""Semantic contract for the pure-odbc Windows release workflow."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

import yaml


REQUIRED_PATHS = {
    ".github/scripts/validate_non_linux_release_workflow.py",
    "pure-odbc/**",
    "pure/todo/TODO-32-windows-pure-odbc.md",
}

STEP_ORDER = [
    "Install and validate the portable runtime",
    "Configure strict pure-odbc audit",
    "Build and verify pure-odbc PE closure",
    "Run pure-odbc tests and source distribution contract",
    "Install and verify the pure-odbc package",
    "Validate non-Linux workflow semantics",
]

STRICT_CONFIGURE_ARGUMENTS = {
    "-DPURE_ODBC_STRICT_WINDOWS_AUDIT=ON",
    "-DPURE_ODBC_CLANG64_PREFIX=C:/msys64/clang64",
    "-DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/ninja.exe",
    "-DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe",
    "-DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu",
    "-DPURE_ODBC_BUILD_FAULT_TESTS=ON",
    "-DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkgconf.exe",
    "-DLLVM_READOBJ_EXECUTABLE=C:/msys64/clang64/bin/llvm-readobj.exe",
    "-DPURE_ODBC_MAKE_EXECUTABLE=C:/msys64/usr/bin/make.exe",
    "-DGMP_RUNTIME_DLL=C:/msys64/clang64/bin/libgmp-10.dll",
    "-DODBC_HEADER=C:/msys64/clang64/include/sql.h",
    "-DODBC_IMPORT_LIBRARY=C:/msys64/clang64/lib/libodbc32.a",
    "-DSYSTEM_ODBC_DLL=C:/Windows/System32/odbc32.dll",
    "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=C:/Windows",
}

VERIFIER_ARGUMENTS = {
    "-DSTAGE_PREFIX=",
    "-DBASELINE_MANIFEST=",
    "-DRUNTIME_COMPONENT_MANIFEST=",
    "-DDOCUMENTATION_COMPONENT_MANIFEST=",
    "-DLLVM_READOBJ=",
    "-DODBC_MODULE_SOURCE=",
    "-DODBC_INTERFACE_SOURCE=",
    "-DREADME_SOURCE=",
    "-DCOPYING_SOURCE=",
    "-DCOPYING_LESSER_SOURCE=",
    "-DWINDOWS_SOURCE=",
    "-DEXAMPLE_SOURCE=",
    "-DSMOKE_SOURCE=",
    "-DPEOPLE_SOURCE=",
    "-DSCHEMA_SOURCE=",
    "-DGMP_DLL_SOURCE=",
    "-DPURE_RUNTIME_DLL_SOURCE=",
    "-DRUN_PURE_TEST_EXECUTABLE=",
    "-DWINDOWS_DEPENDENCY_VERIFIER=",
    "-DWINDOWS_DIRECTORY=",
    "-DSYSTEM_ODBC_DLL=",
    "-DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def mapping(value: Any, label: str) -> dict[str, Any]:
    require(isinstance(value, dict), f"{label} must be a mapping")
    return value


def sequence(value: Any, label: str) -> list[Any]:
    require(isinstance(value, list), f"{label} must be a sequence")
    return value


def step_by_name(steps: list[Any], name: str) -> dict[str, Any]:
    matches = [mapping(step, f"step {name}") for step in steps
               if isinstance(step, dict) and step.get("name") == name]
    require(len(matches) == 1, f"expected exactly one step named {name!r}")
    return matches[0]


def command(step: dict[str, Any], name: str) -> str:
    value = step.get("run")
    require(isinstance(value, str) and value.strip(),
            f"step {name!r} must have a non-empty run command")
    return value


def validate(path: Path) -> None:
    with path.open("r", encoding="utf-8") as stream:
        document = yaml.load(stream, Loader=yaml.BaseLoader)

    root = mapping(document, "workflow")
    triggers = mapping(root.get("on"), "workflow.on")
    for event in ("push", "pull_request"):
        event_mapping = mapping(triggers.get(event), f"workflow.on.{event}")
        paths = sequence(event_mapping.get("paths"),
                         f"workflow.on.{event}.paths")
        missing = REQUIRED_PATHS.difference(paths)
        require(not missing,
                f"{event} paths are missing: {', '.join(sorted(missing))}")

    jobs = mapping(root.get("jobs"), "workflow.jobs")
    core = mapping(jobs.get("windows-pure-core"),
                   "workflow.jobs.windows-pure-core")
    steps = sequence(core.get("steps"), "windows-pure-core.steps")
    indices = []
    selected: dict[str, dict[str, Any]] = {}
    for name in STEP_ORDER:
        selected[name] = step_by_name(steps, name)
        indices.append(steps.index(selected[name]))
    require(indices == sorted(indices) and len(indices) == len(set(indices)),
            "pure-odbc validation steps are not in dependency order")

    install_step = step_by_name(steps, "Install the CLANG64 build prerequisites")
    packages = str(mapping(install_step.get("with"), "prerequisite.with")
                   .get("install", "")).split()
    for package in ("make", "mingw-w64-clang-x86_64-python-yaml"):
        require(package in packages, f"missing CI prerequisite package: {package}")

    configure = command(selected[STEP_ORDER[1]], STEP_ORDER[1])
    require("-DCMAKE_BUILD_TYPE=Release" in configure,
            "strict pure-odbc configure must select Release")
    require("-DBUILD_TESTING=ON" in configure,
            "strict pure-odbc configure must enable tests")
    for argument in STRICT_CONFIGURE_ARGUMENTS:
        require(argument in configure,
                f"strict configure is missing explicit argument: {argument}")
    for staged_argument in ("-DPURE_PREFIX=", "-DPURE_ODBC_PKG_CONFIG_PATH=",
                            "-DPURE_EXECUTABLE=", "-DPURE_RUNTIME_DLL="):
        require(staged_argument in configure,
                f"strict configure is missing staged input: {staged_argument}")

    build = command(selected[STEP_ORDER[2]], STEP_ORDER[2])
    require(build.count("--parallel 4") == 2,
            "build and PE target must each use exactly --parallel 4")
    require("--target verify-windows-dependencies --parallel 4" in build,
            "exact PE dependency target is missing")
    require("--parallel 1" not in build,
            "pure-odbc audit must not reduce the approved worker count")

    tests = command(selected[STEP_ORDER[3]], STEP_ORDER[3])
    require("-L odbc" in tests and "--no-tests=error" in tests,
            "the full non-empty odbc CTest label must run")
    require("Remove-Item Env:PURELIB" in tests,
            "the ODBC test environment must remove PURELIB")
    require("$env:Path =" in tests and "$prefix/bin" in tests
            and "$env:SystemRoot/System32" in tests,
            "the ODBC test environment must replace PATH explicitly")
    installed = command(selected[STEP_ORDER[4]], STEP_ORDER[4])
    require("--component runtime" in installed,
            "runtime component installation is missing")
    require("--component documentation" in installed,
            "documentation component installation is missing")
    require("VerifyInstalledPackage.cmake" in installed,
            "installed package verifier is missing")
    for argument in VERIFIER_ARGUMENTS:
        require(argument in installed,
                f"installed verifier is missing argument: {argument}")

    semantic = command(selected[STEP_ORDER[5]], STEP_ORDER[5])
    require("validate_non_linux_release_workflow.py" in semantic,
            "workflow semantic validation command is missing")
    require("C:/msys64/clang64/bin/python.exe" in semantic,
            "workflow validation must use the packaged PyYAML interpreter")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("workflow", type=Path)
    args = parser.parse_args()
    validate(args.workflow.resolve())
    print(f"validated workflow semantics: {args.workflow}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
