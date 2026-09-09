#!/usr/bin/env python3
"""Structural YAML and native-command contracts for Windows release gates."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import shlex
from typing import Any

import yaml


REQUIRED_PATHS = {
    ".github/scripts/validate_non_linux_release_workflow.py",
    ".github/scripts/test_validate_non_linux_release_workflow.py",
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

# Independent policy for the Task 4-7 public audio interfaces. The workflow is
# data under validation: it never supplies its own required inputs or commands.
AUDIO_STEP_ORDER = (
    'Configure strict pure-audio audit',
    'Build and verify pure-audio PE closure',
    'Run mandatory no-hardware pure-audio tests',
    'Install and verify the pure-audio package',
    'Verify pure-audio source distribution',
)
AUDIO_REQUIRED_PATHS = {
    'pure-audio/**', 'pure/todo/TODO-33-windows-pure-audio.md',
    '.github/workflows/non-linux-release-validation.yml',
    '.github/scripts/validate_non_linux_release_workflow.py',
    '.github/scripts/test_validate_non_linux_release_workflow.py',
}
AUDIO_REQUIRED_PACKAGES = {'tar', 'gzip', 'make'} | {
    'mingw-w64-clang-x86_64-' + package for package in (
        'clang', 'cmake', 'llvm', 'ninja', 'pkgconf', 'make', 'python-yaml',
        'portaudio', 'fftw', 'libsamplerate', 'libsndfile', 'libogg', 'libvorbis',
        'flac', 'opus', 'mpg123', 'lame', 'winpthreads', 'libc++', 'gmp', 'mpfr',
        'libiconv', 'pcre', 'readline', 'termcap', 'zstd', 'zlib')
}
AUDIO_ENVIRONMENT = {
    'CMAKE_EXE': 'C:/msys64/clang64/bin/cmake.exe',
    'CTEST_EXE': 'C:/msys64/clang64/bin/ctest.exe',
    'INSTALL_PREFIX': 'build/windows-clang64-prefix',
    'AUDIO_SOURCE': '${{ github.workspace }}/pure-audio',
    'AUDIO_BUILD': '${{ runner.temp }}/pa8',
    'AUDIO_STAGE': '${{ runner.temp }}/pa8/package',
    'AUDIO_PREFIX': '${{ github.workspace }}/pure/build/windows-clang64-prefix',
    'AUDIO_RUNTIME_PATH': '${{ github.workspace }}/pure/build/windows-clang64-prefix/bin;C:/msys64/clang64/bin;C:/msys64/usr/bin;C:/Windows/System32;C:/Windows',
}
AUDIO_STEP_ENVIRONMENT = {
    'PATH': '${{ env.AUDIO_RUNTIME_PATH }}', 'PURELIB': '',
    'PURE_INCLUDE': '', 'PURE_LIBRARY': '',
}
AUDIO_CONFIGURE_INPUTS = {
    'CMAKE_BUILD_TYPE': 'Release', 'BUILD_TESTING': 'ON',
    'PURE_AUDIO_STRICT_WINDOWS_AUDIT': 'ON',
    'CMAKE_C_COMPILER': 'C:/msys64/clang64/bin/clang.exe',
    'CMAKE_C_COMPILER_TARGET': 'x86_64-w64-windows-gnu',
    'CMAKE_MAKE_PROGRAM': 'C:/msys64/clang64/bin/ninja.exe',
    'PKG_CONFIG_EXECUTABLE': 'C:/msys64/clang64/bin/pkgconf.exe',
    'LLVM_READOBJ': 'C:/msys64/clang64/bin/llvm-readobj.exe',
    'PURE_AUDIO_MAKE_EXECUTABLE': 'C:/msys64/clang64/bin/mingw32-make.exe',
    'PURE_AUDIO_SH_EXECUTABLE': 'C:/msys64/usr/bin/sh.exe',
    'PURE_AUDIO_CLANG64_PREFIX': 'C:/msys64/clang64',
    'PURE_AUDIO_PURE_PREFIX': '$env:AUDIO_PREFIX',
    'PURE_INCLUDE_DIR': '$env:AUDIO_PREFIX/include',
    'PURE_EXECUTABLE': '$env:AUDIO_PREFIX/bin/pure.exe',
    'PURE_HEADER': '$env:AUDIO_PREFIX/include/pure/runtime.h',
    'PURE_IMPORT_LIBRARY': '$env:AUDIO_PREFIX/lib/libpure.dll.a',
    'PURE_RUNTIME_DLL': '$env:AUDIO_PREFIX/bin/libpure.dll',
    'PORTAUDIO_HEADER': 'C:/msys64/clang64/include/portaudio.h',
    'PORTAUDIO_IMPORT_LIBRARY': 'C:/msys64/clang64/lib/libportaudio.dll.a',
    'FFTW_HEADER': 'C:/msys64/clang64/include/fftw3.h',
    'FFTW_IMPORT_LIBRARY': 'C:/msys64/clang64/lib/libfftw3.dll.a',
    'SAMPLERATE_HEADER': 'C:/msys64/clang64/include/samplerate.h',
    'SAMPLERATE_IMPORT_LIBRARY': 'C:/msys64/clang64/lib/libsamplerate.dll.a',
    'SNDFILE_HEADER': 'C:/msys64/clang64/include/sndfile.h',
    'SNDFILE_IMPORT_LIBRARY': 'C:/msys64/clang64/lib/libsndfile.dll.a',
    'PTHREAD_HEADER': 'C:/msys64/clang64/include/pthread.h',
    'PTHREAD_IMPORT_LIBRARY': 'C:/msys64/clang64/lib/libpthread.dll.a',
    'GMP_HEADER': 'C:/msys64/clang64/include/gmp.h',
    'MPFR_HEADER': 'C:/msys64/clang64/include/mpfr.h',
    'PURE_AUDIO_WINDOWS_HEADER': 'C:/msys64/clang64/include/windows.h',
    'PURE_AUDIO_WINDOWS_SYSTEM_DIRECTORY': 'C:/Windows/System32',
}
AUDIO_RUNTIME_POLICY = {
    name: f'$env:AUDIO_PREFIX/bin/{name}' for name in (
        'pure.exe', 'libpure.dll', 'libc++.dll', 'libgmp-10.dll', 'libiconv-2.dll',
        'libmpfr-6.dll', 'libpcre-1.dll', 'libpcreposix-0.dll', 'libreadline8.dll',
        'libtermcap-0.dll', 'libwinpthread-1.dll', 'libzstd.dll', 'zlib1.dll')
} | {
    name: f'C:/msys64/clang64/bin/{name}' for name in (
        'libportaudio.dll', 'libfftw3-3.dll', 'libsamplerate-0.dll', 'libsndfile-1.dll',
        'libogg-0.dll', 'libvorbisenc-2.dll', 'libFLAC.dll', 'libopus-0.dll',
        'libmpg123-0.dll', 'libmp3lame-0.dll', 'libvorbis-0.dll')
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


def cmake_build_invocations(script: str) -> list[list[str]]:
    """Return tokenized CMake --build invocations after PS continuations."""
    logical_script = re.sub(r"`[ \t]*\r?\n[ \t]*", " ", script)
    invocations = []
    prefix = "& $env:CMAKE_EXE --build "
    for line in logical_script.splitlines():
        line = line.strip()
        if not line.startswith(prefix):
            continue
        command_only = line.split("2>&1", 1)[0].strip()
        invocations.append(command_only.split())
    return invocations


def audio_native_calls(script: str) -> tuple[list[list[str]], set[str]]:
    """Parse the deliberately small audited PowerShell command language.

    Quotes/continuations and logging pipelines are normalized before comparing
    argument vectors. Arbitrary script blocks, assignments, early exits,
    conditional invocations and secondary command separators fail closed. This
    is not a general PowerShell interpreter; new syntax needs an explicit audit.
    """
    logical = re.sub(r'`[ \t]*\r?\n[ \t]*', ' ', script)
    lines = [line.strip() for line in logical.splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    calls: list[list[str]] = []
    guards: set[str] = set()
    index = 0
    while index < len(lines):
        line = lines[index]
        lexer = shlex.shlex(line, posix=True, punctuation_chars='|;')
        lexer.whitespace_split = True
        lexer.escape = ''  # PowerShell uses backticks, not backslash escapes.
        lexer.commenters = '#'
        try:
            tokens = list(lexer)
        except ValueError as error:
            raise AssertionError(f'malformed audio command: {error}') from error
        if tokens == ['$ErrorActionPreference', '=', 'Stop']:
            require('errors' not in guards and not calls, 'audio error policy must be set once before commands')
            guards.add('errors')
        elif tokens and tokens[0] == '&':
            if '|' in tokens:
                at = tokens.index('|')
                require(at > 0 and tokens[at-1] == '2>&1' and
                        tokens[at:at+3] == ['|', 'Tee-Object', '-FilePath'] and
                        len(tokens) == at+4 and tokens[-1].startswith('$env:LOG_DIR/'),
                        'audio logging must preserve the native command status')
                tokens = tokens[:at-1]
            require(not any(token in (';', '|', '&') for token in tokens[1:]),
                    'audio command contains an additional invocation/separator')
            require(index+1 < len(lines) and re.fullmatch(
                r"if\s*\(\$LASTEXITCODE\s+-ne\s+0\)\s*\{\s*throw\s+'[^']+'\s*\}", lines[index+1]),
                'audio native command must immediately propagate nonzero status')
            require('errors' in guards, 'audio native command precedes error policy')
            calls.append(tokens)
            index += 1
        else:
            fresh = re.fullmatch(
                r"if\s*\(Test-Path\s+-LiteralPath\s+\$env:(AUDIO_BUILD|AUDIO_STAGE)\)\s*\{\s*throw\s+'[^']+'\s*\}", line)
            short = re.fullmatch(
                r"if\s*\(\$env:AUDIO_BUILD.Length\s+-gt\s+32\)\s*\{\s*throw\s+'[^']+'\s*\}", line)
            require(not calls and (fresh is not None or short is not None),
                    'unsupported or reordered audio PowerShell statement')
            guard = fresh.group(1) if fresh else 'short'
            require(guard not in guards, 'duplicate audio preflight guard')
            guards.add(guard)
        index += 1
    return calls, guards


def validate_audio(root: dict[str, Any], core: dict[str, Any], steps: list[Any]) -> None:
    require('if' not in core and 'continue-on-error' not in core,
            'audio job cannot be conditional or ignore failures')
    require(core.get('runs-on') == 'windows-2025' and 'defaults' not in core,
            'audio requires the declared Windows runner without job-local directory overrides')
    defaults = mapping(mapping(root.get('defaults'), 'defaults').get('run'), 'defaults.run')
    require(defaults.get('working-directory') == 'pure', 'audio portable-prefix working directory changed')
    for event, branches in [('push', {'master', 'todo/**', 'codex/**'}), ('pull_request', {'master'})]:
        trigger = mapping(mapping(root.get('on'), 'on').get(event), event)
        paths = sequence(trigger.get('paths'), f'{event}.paths')
        declared_branches = sequence(trigger.get('branches'), f'{event}.branches')
        require(AUDIO_REQUIRED_PATHS <= set(paths), f'{event} audio trigger inputs are missing')
        require(branches <= set(declared_branches), f'{event} audio branches are missing')
        require('paths-ignore' not in trigger and 'branches-ignore' not in trigger and
                not any(str(value).startswith('!') for value in paths+declared_branches),
                'audio trigger exclusions can suppress the gate')
    environment = mapping(core.get('env'), 'audio job env')
    for key, value in AUDIO_ENVIRONMENT.items():
        require(environment.get(key) == value, f'audio job environment origin mismatch: {key}')
    prerequisite = step_by_name(steps, 'Install the CLANG64 build prerequisites')
    portable = step_by_name(steps, 'Install and validate the portable runtime')
    semantic = step_by_name(steps, 'Validate non-Linux workflow semantics')
    for step in (prerequisite, portable, semantic):
        require('if' not in step and 'continue-on-error' not in step, 'audio prerequisite is conditional')
    options = mapping(prerequisite.get('with'), 'audio prerequisites.with')
    require(prerequisite.get('uses') == 'msys2/setup-msys2@v2' and options.get('msystem') == 'CLANG64',
            'audio requires the declared CLANG64 prerequisite action')
    packages = str(options.get('install', '')).split()
    require(AUDIO_REQUIRED_PACKAGES <= set(packages),
            f'audio prerequisites missing: {sorted(AUDIO_REQUIRED_PACKAGES-set(packages))}')
    selected = [step_by_name(steps, name) for name in AUDIO_STEP_ORDER]
    positions = [steps.index(step) for step in [prerequisite, portable, *selected, semantic]]
    require(positions == sorted(set(positions)), 'audio release steps are not in dependency order')
    parsed = []
    for step in selected:
        require('if' not in step and 'continue-on-error' not in step and
                step.get('shell') == 'pwsh' and 'working-directory' not in step,
                f'audio step must be unconditional native PowerShell: {step["name"]}')
        require(mapping(step.get('env'), 'audio step env') == AUDIO_STEP_ENVIRONMENT,
                f'audio step must replace PATH and clear every Pure discovery variable: {step["name"]}')
        parsed.append(audio_native_calls(command(step, step['name'])))
    configure, guards = parsed[0]
    require(guards == {'errors', 'AUDIO_BUILD', 'short'}, 'audio configure needs fresh short-build preflight')
    prefix = ['&', '$env:CMAKE_EXE', '-S', '$env:AUDIO_SOURCE', '-B', '$env:AUDIO_BUILD', '-G', 'Ninja']
    require(len(configure) == 1 and configure[0][:8] == prefix, 'audio configure invocation changed')
    inputs = {}
    for argument in configure[0][8:]:
        match = re.fullmatch(r'-D([A-Z][A-Z0-9_]*)=(.+)', argument)
        require(match is not None, f'unsupported audio configure argument: {argument}')
        key, value = match.groups()
        require(key not in inputs, f'duplicate audio configure input: {key}')
        inputs[key] = value
    require(set(inputs) == set(AUDIO_CONFIGURE_INPUTS) | {'PURE_AUDIO_RUNTIME_SOURCES'},
            'audio configure must declare every exact input without overrides')
    for key, value in AUDIO_CONFIGURE_INPUTS.items():
        require(inputs[key] == value, f'audio configure input/origin mismatch: {key}')
    runtime = {}
    for row in inputs['PURE_AUDIO_RUNTIME_SOURCES'].split(';'):
        fields = row.split('|')
        require(len(fields) == 2 and fields[0] not in runtime, 'malformed/duplicate audio runtime source')
        runtime[fields[0]] = fields[1]
    require(runtime == AUDIO_RUNTIME_POLICY, 'audio runtime source names/origins differ from the exact policy')
    cmake = ['&', '$env:CMAKE_EXE']
    normal = cmake + ['--build', '$env:AUDIO_BUILD', '--parallel', '4']
    pe = cmake + ['--build', '$env:AUDIO_BUILD', '--target', 'verify-windows-dependencies', '--parallel', '4']
    require(parsed[1] == ([normal, pe], {'errors'}),
            'audio requires one normal then one distinct PE build, each with exactly four workers')
    ctest = ['&', '$env:CTEST_EXE', '--test-dir', '$env:AUDIO_BUILD', '-L', '^audio$',
             '-LE', '^hardware$', '-E', '^pure-audio-source-dist-contract$',
             '--output-on-failure', '--no-tests=error', '--parallel', '4']
    require(parsed[2] == ([ctest], {'errors'}),
            'audio must run the nonempty no-hardware label and defer only the exact source-dist contract')
    copy_prefix = cmake + ['-E', 'copy_directory', '$env:AUDIO_PREFIX', '$env:AUDIO_STAGE']
    install = cmake + ['--install', '$env:AUDIO_BUILD', '--prefix', '$env:AUDIO_STAGE', '--component']
    verify = cmake + ['-DAUDIO_INSTALL_CONTEXT=$env:AUDIO_BUILD/windows-install-context.cmake',
                      '-DSTAGE_PREFIX=$env:AUDIO_STAGE', '-P', '$env:AUDIO_SOURCE/cmake/VerifyInstalledPackage.cmake']
    require(parsed[3] == ([copy_prefix, install+['runtime'], install+['documentation'], verify],
                          {'errors', 'AUDIO_STAGE'}),
            'audio requires fresh baseline copy, ordered components and the complete public context verifier')
    dist = ['&', 'C:/msys64/clang64/bin/mingw32-make.exe', '-C', '$env:AUDIO_SOURCE',
            'SHELL=C:/msys64/usr/bin/sh.exe', 'DIST_CMAKE=C:/msys64/clang64/bin/cmake.exe',
            'DIST_AUDIT_BUILD=$env:AUDIO_BUILD', 'distcheck']
    require(parsed[4] == ([dist], {'errors'}),
            'audio must run exactly the deferred audited source contract via public make distcheck')
    semantic_calls = [
        ['&', 'C:/msys64/clang64/bin/python.exe',
         '../.github/scripts/test_validate_non_linux_release_workflow.py', '-v'],
        ['&', 'C:/msys64/clang64/bin/python.exe',
         '../.github/scripts/validate_non_linux_release_workflow.py',
         '../.github/workflows/non-linux-release-validation.yml'],
    ]
    require(audio_native_calls(command(semantic, semantic['name'])) == (semantic_calls, {'errors'}),
            'workflow semantics must actually run both mutation tests and pristine validation')


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
    invocations = cmake_build_invocations(build)
    normal = [
        "&", "$env:CMAKE_EXE", "--build", "$odbcBuild",
        "--parallel", "4",
    ]
    pe_target = [
        "&", "$env:CMAKE_EXE", "--build", "$odbcBuild", "--target",
        "verify-windows-dependencies", "--parallel", "4",
    ]
    require(len(invocations) == 2,
            "build step must contain exactly two CMake --build invocations")
    require(invocations.count(normal) == 1,
            "build step must contain exactly one normal --parallel 4 build")
    require(invocations.count(pe_target) == 1,
            "build step must contain exactly one PE-target --parallel 4 build")

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
    require("test_validate_non_linux_release_workflow.py" in semantic,
            "workflow semantic mutation-test command is missing")
    require("validate_non_linux_release_workflow.py" in semantic,
            "workflow semantic validation command is missing")
    require("C:/msys64/clang64/bin/python.exe" in semantic,
            "workflow validation must use the packaged PyYAML interpreter")
    validate_audio(root, core, steps)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("workflow", type=Path)
    args = parser.parse_args()
    validate(args.workflow.resolve())
    print(f"validated workflow semantics: {args.workflow}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
