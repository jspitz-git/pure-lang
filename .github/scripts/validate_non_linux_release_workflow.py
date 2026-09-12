#!/usr/bin/env python3
"""Structural YAML and native-command contracts for Windows release gates."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
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
    'AUDIO_PREFIX': '${{ github.workspace }}/pure/build/windows-clang64-prefix',
    'AUDIO_RUNTIME_PATH': '${{ github.workspace }}/pure/build/windows-clang64-prefix/bin;C:/msys64/clang64/bin;C:/msys64/usr/bin;C:/Windows/System32;C:/Windows',
}
AUDIO_STEP_ENVIRONMENT = {
    'AUDIO_BUILD': '${{ runner.temp }}/pa8',
    'AUDIO_STAGE': '${{ runner.temp }}/pa8/package',
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


def audio_command_tokens(line: str) -> list[str]:
    """Lex audited PS arguments without erasing whether variables expand.

    Each word is wholly bare, single quoted or double quoted. Concatenation,
    escapes, subexpressions and other variable forms require a separate audit.
    Only double/bare environment references and literal regex end anchors are
    allowed; a single-quoted environment reference is never an expansion.
    """
    words: list[tuple[str, str]] = []
    remaining = line.strip()
    while remaining:
        if remaining.startswith('#'):
            break
        match = re.match(r'''(?:"([^"\n]*)"|'([^'\n]*)'|([^\s"']+))(?=\s|$)''', remaining)
        require(match is not None, 'unsupported PowerShell quoting/concatenation')
        double, single, bare = match.groups()
        quote, value = ('double', double) if double is not None else (
            ('single', single) if single is not None else ('bare', bare))
        require('`' not in value and not any(char in value for char in '“”‘’'),
                'unsupported PowerShell escape/smart quote')
        references = re.findall(r'\$env:[A-Z_][A-Z0-9_]*', value)
        require(quote != 'single' or not references,
                'single-quoted environment reference does not expand')
        remainder = re.sub(r'\$env:[A-Z_][A-Z0-9_]*', '', value)
        require('$' not in remainder or re.fullmatch(r'\^[a-z-]+\$', value) is not None,
                'unsupported PowerShell variable/interpolation')
        if quote == 'bare' and value not in ('&', '|', '2>&1'):
            require(not any(char in value for char in ';|&<>(){}[],@#'),
                    'unsupported unquoted PowerShell metacharacter')
        words.append((value, quote))
        remaining = remaining[match.end():].lstrip()
    require(words and words[0] == ('&', 'bare'), 'native call requires the call operator')
    # These tokens are syntax, not strings/arguments that merely spell syntax.
    for value, quote in words:
        if value in ('&', '|', '2>&1', 'Tee-Object', '-FilePath'):
            require(quote == 'bare', 'quoted PowerShell operator/logging syntax')
    return [value for value, quote in words]


def audio_native_calls(script: str, namespace: str = 'AUDIO') -> tuple[list[list[str]], set[str]]:
    """Parse the deliberately small audited PowerShell command language.

    Expansion-aware quotes/continuations and logging pipelines are normalized
    before comparing argument vectors. Arbitrary script blocks, assignments, early exits,
    conditional invocations and secondary command separators fail closed. This
    is not a general PowerShell interpreter; new syntax needs an explicit audit.
    """
    # Backtick must immediately precede newline: a trailing space/tab escapes
    # that character instead and must not be silently turned into continuation.
    logical = re.sub(r'`\r?\n[ \t]*', ' ', script)
    lines = [line.strip() for line in logical.splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    calls: list[list[str]] = []
    guards: set[str] = set()
    index = 0
    while index < len(lines):
        line = lines[index]
        if re.fullmatch(r'''\$ErrorActionPreference\s*=\s*(?:'Stop'|"Stop")''', line):
            require('errors' not in guards and not calls, 'audio error policy must be set once before commands')
            guards.add('errors')
        elif line.startswith('&'):
            tokens = audio_command_tokens(line)
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
                r"if\s*\(Test-Path\s+-LiteralPath\s+\$env:(" + namespace +
                r"_BUILD|" + namespace + r"_STAGE)\)\s*\{\s*throw\s+'[^']+'\s*\}", line)
            short = re.fullmatch(
                r"if\s*\(\$env:" + namespace +
                r"_BUILD.Length\s+-gt\s+32\)\s*\{\s*throw\s+'[^']+'\s*\}", line)
            require(not calls and (fresh is not None or short is not None),
                    'unsupported or reordered audio PowerShell statement')
            guard = fresh.group(1) if fresh else 'short'
            require(guard not in guards, 'duplicate audio preflight guard')
            guards.add(guard)
        index += 1
    return calls, guards


def audio_run_defaults(scope: dict[str, Any], label: str) -> dict[str, str]:
    defaults = mapping(scope.get('defaults', {}), f'{label}.defaults')
    run = mapping(defaults.get('run', {}), f'{label}.defaults.run')
    require(set(run) <= {'shell', 'working-directory'}, 'unsupported run default')
    for key, expected in [('shell', 'pwsh'), ('working-directory', 'pure')]:
        require(key not in run or run[key] == expected,
                f'{label} unsafe run default: {key}')
    return run


def require_audio_run_context(defaults: dict[str, str], step: dict[str, Any]) -> None:
    effective = defaults | {key: step[key] for key in ('shell', 'working-directory') if key in step}
    require(effective == {'shell': 'pwsh', 'working-directory': 'pure'},
            f'audited step needs effective pwsh/pure context: {step["name"]}')


def validate_audio(root: dict[str, Any], core: dict[str, Any], steps: list[Any]) -> None:
    require('if' not in core and 'continue-on-error' not in core,
            'audio job cannot be conditional or ignore failures')
    require(core.get('runs-on') == 'windows-2025', 'audio requires the declared Windows runner')
    # GitHub precedence is workflow -> job -> step. Validate the defaults too:
    # an overridden unsafe default still affects the shared prerequisite steps.
    defaults = ({'shell': 'pwsh'} | audio_run_defaults(root, 'workflow') |
                audio_run_defaults(core, 'job'))
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
    unavailable_runner = re.compile(r'\$\{\{\s*runner\s*(?:\.|\[)')
    require(not any(unavailable_runner.search(str(value)) for value in environment.values()),
            'job environment cannot use the unavailable runner context')
    for key, value in AUDIO_ENVIRONMENT.items():
        require(environment.get(key) == value, f'audio job environment origin mismatch: {key}')
    prerequisite = step_by_name(steps, 'Install the CLANG64 build prerequisites')
    portable = step_by_name(steps, 'Install and validate the portable runtime')
    semantic = step_by_name(steps, 'Validate non-Linux workflow semantics')
    require_audio_run_context(defaults, semantic)
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
                step.get('shell') == 'pwsh',
                f'audio step must be unconditional native PowerShell: {step["name"]}')
        require_audio_run_context(defaults, step)
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


MIDI_STEP_ORDER = (
    'Configure strict pure-midi audit', 'Build and verify pure-midi PE closure',
    'Run mandatory no-hardware pure-midi tests',
    'Install and verify the pure-midi package', 'Verify pure-midi source distribution',
)
MIDI_PATHS = {
    'pure-midi/**', 'pure/todo/TODO-34-windows-pure-midi.md',
    '.github/workflows/non-linux-release-validation.yml',
    '.github/scripts/validate_non_linux_release_workflow.py',
    '.github/scripts/test_validate_non_linux_release_workflow.py',
}
MIDI_PACKAGES = {'make'} | {'mingw-w64-clang-x86_64-' + package for package in (
    'clang', 'cmake', 'llvm', 'ninja', 'pkgconf', 'make', 'python-yaml',
    'portmidi', 'gmp', 'mpfr', 'libc++', 'libiconv', 'pcre', 'readline',
    'termcap', 'winpthreads', 'zstd', 'zlib')}
MIDI_ENVIRONMENT = {
    'CMAKE_EXE': 'C:/msys64/clang64/bin/cmake.exe',
    'CTEST_EXE': 'C:/msys64/clang64/bin/ctest.exe',
    'INSTALL_PREFIX': 'build/windows-clang64-prefix',
    'MIDI_SOURCE': '${{ github.workspace }}/pure-midi',
    'MIDI_PREFIX': '${{ github.workspace }}/pure/build/windows-clang64-prefix',
    'MIDI_RUNTIME_PATH': '${{ github.workspace }}/pure/build/windows-clang64-prefix/bin;C:/msys64/clang64/bin;C:/msys64/usr/bin;C:/Windows/System32;C:/Windows',
}
MIDI_STEP_ENVIRONMENT = {
    'MIDI_BUILD': '${{ runner.temp }}/pm8',
    'MIDI_STAGE': '${{ runner.temp }}/pm8/package',
    'MIDI_DIST_ROOT': '${{ runner.temp }}/ms8',
    'PATH': '${{ env.MIDI_RUNTIME_PATH }}',
    'PURELIB': '', 'PURE_INCLUDE': '', 'PURE_LIBRARY': '',
}
MIDI_CONFIGURE_INPUTS = {
    'CMAKE_BUILD_TYPE': 'Release', 'BUILD_TESTING': 'ON',
    'PURE_MIDI_STRICT_WINDOWS_AUDIT': 'ON',
    'CMAKE_C_COMPILER': 'C:/msys64/clang64/bin/clang.exe',
    'CMAKE_C_COMPILER_TARGET': 'x86_64-w64-windows-gnu',
    'CMAKE_MAKE_PROGRAM': 'C:/msys64/clang64/bin/ninja.exe',
    'PKG_CONFIG_EXECUTABLE': 'C:/msys64/clang64/bin/pkgconf.exe',
    'LLVM_READOBJ': 'C:/msys64/clang64/bin/llvm-readobj.exe',
    'PURE_MIDI_MAKE_EXECUTABLE': 'C:/msys64/clang64/bin/mingw32-make.exe',
    'PURE_MIDI_SH_EXECUTABLE': 'C:/msys64/usr/bin/sh.exe',
    'PURE_MIDI_CLANG64_PREFIX': 'C:/msys64/clang64',
    'PURE_MIDI_PURE_PREFIX': '$env:MIDI_PREFIX',
    'PURE_INCLUDE_DIR': '$env:MIDI_PREFIX/include',
    'PURE_EXECUTABLE': '$env:MIDI_PREFIX/bin/pure.exe',
    'PURE_HEADER': '$env:MIDI_PREFIX/include/pure/runtime.h',
    'PURE_GLOB_HEADER': '$env:MIDI_PREFIX/include/glob.h',
    'PURE_IMPORT_LIBRARY': '$env:MIDI_PREFIX/lib/libpure.dll.a',
    'PURE_RUNTIME_DLL': '$env:MIDI_PREFIX/bin/libpure.dll',
    'PORTMIDI_HEADER': 'C:/msys64/clang64/include/portmidi.h',
    'PORTTIME_HEADER': 'C:/msys64/clang64/include/porttime.h',
    'PORTMIDI_IMPORT_LIBRARY': 'C:/msys64/clang64/lib/libportmidi.dll.a',
    'PORTMIDI_RUNTIME_DLL': 'C:/msys64/clang64/bin/libportmidi.dll',
    'GMP_HEADER': 'C:/msys64/clang64/include/gmp.h',
    'MPFR_HEADER': 'C:/msys64/clang64/include/mpfr.h',
    'PURE_MIDI_WINDOWS_HEADER': 'C:/msys64/clang64/include/windows.h',
    'PURE_MIDI_WINDOWS_SYSTEM_DIRECTORY': 'C:/Windows/System32',
}
MIDI_RUNTIME_POLICY = {
    name: f'$env:MIDI_PREFIX/bin/{name}' for name in (
        'pure.exe', 'libpure.dll', 'libc++.dll', 'libgmp-10.dll', 'libiconv-2.dll',
        'libmpfr-6.dll', 'libpcre-1.dll', 'libpcreposix-0.dll', 'libreadline8.dll',
        'libtermcap-0.dll', 'libwinpthread-1.dll', 'libzstd.dll', 'zlib1.dll')
} | {'libportmidi.dll': 'C:/msys64/clang64/bin/libportmidi.dll'}


def validate_midi(root: dict[str, Any], core: dict[str, Any], steps: list[Any]) -> None:
    """Fail closed on the public strict MIDI gate's effective command vectors."""
    require(core.get('runs-on') == 'windows-2025' and
            'if' not in core and 'continue-on-error' not in core,
            'MIDI requires the unconditional Windows 2025 job')
    defaults = ({'shell': 'pwsh'} | audio_run_defaults(root, 'workflow') |
                audio_run_defaults(core, 'job'))
    # runner/env/steps/job are not available at either env scope. Only GitHub
    # expression context roots are checked here; actionlint checks full syntax.
    for scope, allowed in [(root, {'github', 'secrets', 'inputs', 'vars'}),
                           (core, {'github', 'needs', 'strategy', 'matrix', 'vars', 'secrets', 'inputs'})]:
        for value in mapping(scope.get('env', {}), 'MIDI environment scope').values():
            for expression in re.findall(r'\$\{\{(.*?)\}\}', str(value)):
                # Keep quoted strings atomic, skip member names and functions,
                # and validate bare roots too (e.g. toJSON(runner)).
                tokens = re.findall(r"'(?:[^']|'')*'|[A-Za-z_][A-Za-z_0-9]*|[^\s]", expression)
                for index, token in enumerate(tokens):
                    if (re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', token) and
                            (index == 0 or tokens[index-1] != '.') and
                            (index+1 == len(tokens) or tokens[index+1] != '(')):
                        require(token in allowed | {'true', 'false', 'null'},
                                'unavailable GitHub expression context in environment')
    for event, branches in [('push', {'master', 'todo/**', 'codex/**'}), ('pull_request', {'master'})]:
        trigger = mapping(mapping(root.get('on'), 'on').get(event), event)
        paths = sequence(trigger.get('paths'), event+'.paths')
        actual = sequence(trigger.get('branches'), event+'.branches')
        require(MIDI_PATHS <= set(paths), f'{event} missing MIDI trigger inputs')
        require(set(actual) == branches and len(actual) == len(branches),
                f'{event} must preserve the exact existing branch policy')
        require('paths-ignore' not in trigger and 'branches-ignore' not in trigger and
                not any(str(p).startswith('!') for p in paths),
                f'{event} MIDI triggers cannot be excluded')
    environment = mapping(core.get('env'), 'MIDI job env')
    for key, value in MIDI_ENVIRONMENT.items():
        require(environment.get(key) == value, f'MIDI job input origin changed: {key}')
    prerequisite = step_by_name(steps, 'Install the CLANG64 build prerequisites')
    portable = step_by_name(steps, 'Install and validate the portable runtime')
    semantic = step_by_name(steps, 'Validate non-Linux workflow semantics')
    for step in (prerequisite, portable, semantic):
        require('if' not in step and 'continue-on-error' not in step, 'MIDI prerequisite cannot be skipped')
    require_audio_run_context(defaults, portable)
    require_audio_run_context(defaults, semantic)
    options = mapping(prerequisite.get('with'), 'MIDI prerequisite options')
    require(prerequisite.get('uses') == 'msys2/setup-msys2@v2' and options.get('msystem') == 'CLANG64',
            'MIDI requires explicit CLANG64 setup')
    require(MIDI_PACKAGES <= set(str(options.get('install', '')).split()),
            'missing MIDI build prerequisites')
    selected = [step_by_name(steps, name) for name in MIDI_STEP_ORDER]
    positions = [steps.index(s) for s in [prerequisite, portable, *selected, semantic]]
    require(positions == sorted(set(positions)), 'MIDI release steps are out of dependency order')
    parsed = []
    for step in selected:
        require('if' not in step and 'continue-on-error' not in step, 'MIDI step cannot be skipped')
        require_audio_run_context(defaults, step)
        require(mapping(step.get('env'), 'MIDI step env') == MIDI_STEP_ENVIRONMENT,
                'MIDI must replace PATH, clear Pure discovery, and use exact fresh roots')
        parsed.append(audio_native_calls(command(step, step['name']), 'MIDI'))
    configure, guards = parsed[0]
    require(guards == {'errors', 'MIDI_BUILD', 'short'}, 'MIDI configure requires a fresh short root')
    prefix = ['&', '$env:CMAKE_EXE', '-S', '$env:MIDI_SOURCE', '-B', '$env:MIDI_BUILD', '-G', 'Ninja']
    require(len(configure) == 1 and configure[0][:8] == prefix, 'MIDI strict configure command changed')
    inputs = {}
    for argument in configure[0][8:]:
        match = re.fullmatch(r'-D([A-Z][A-Z0-9_]*)=(.+)', argument)
        require(match is not None, f'unsupported MIDI configure argument: {argument}')
        key, value = match.groups()
        require(key not in inputs, f'duplicate MIDI configure input: {key}')
        inputs[key] = value
    require(set(inputs) == set(MIDI_CONFIGURE_INPUTS) | {'PURE_MIDI_RUNTIME_SOURCES'},
            'MIDI must declare all strict inputs without overrides')
    for key, value in MIDI_CONFIGURE_INPUTS.items():
        require(inputs[key] == value, f'MIDI strict input origin changed: {key}')
    runtime = {}
    for row in inputs['PURE_MIDI_RUNTIME_SOURCES'].split(';'):
        fields = row.split('|')
        require(len(fields) == 2 and fields[0] not in runtime, 'duplicate/malformed MIDI runtime row')
        runtime[fields[0]] = fields[1]
    require(runtime == MIDI_RUNTIME_POLICY, 'MIDI requires the complete exact runtime origins')
    cmake = ['&', '$env:CMAKE_EXE']
    normal = cmake + ['--build', '$env:MIDI_BUILD', '--parallel', '4']
    pe = cmake + ['--build', '$env:MIDI_BUILD', '--target', 'verify-windows-dependencies', '--parallel', '4']
    require(parsed[1] == ([normal, pe], {'errors'}), 'MIDI requires distinct normal/PE four-worker builds')
    tests = ['&', '$env:CTEST_EXE', '--test-dir', '$env:MIDI_BUILD', '-L', '^no-hardware$',
             '-LE', '^hardware$', '--output-on-failure', '--no-tests=error']
    require(parsed[2] == ([tests], {'errors'}), 'MIDI must run every mandatory nonempty no-hardware test')
    copy = cmake + ['-E', 'copy_directory', '$env:MIDI_PREFIX', '$env:MIDI_STAGE']
    install = cmake + ['--install', '$env:MIDI_BUILD', '--prefix', '$env:MIDI_STAGE', '--component']
    verify = cmake + ['-DMIDI_INSTALL_CONTEXT=$env:MIDI_BUILD/windows-install-context.cmake',
                     '-DSTAGE_PREFIX=$env:MIDI_STAGE', '-P', '$env:MIDI_SOURCE/cmake/VerifyInstalledPackage.cmake']
    require(parsed[3] == ([copy, install+['runtime'], install+['documentation'], verify],
                         {'errors', 'MIDI_STAGE'}),
            'MIDI requires fresh baseline, runtime/docs components, then full installed verification')
    dist = ['&', 'C:/msys64/clang64/bin/mingw32-make.exe', '-C', '$env:MIDI_SOURCE', 'distcheck',
            'DLL=.dll', 'CMAKE=C:/msys64/clang64/bin/cmake.exe', 'CLANG64_PREFIX=C:/msys64/clang64',
            'PURE_PREFIX=$env:MIDI_PREFIX', 'DIST_ROOT=$env:MIDI_DIST_ROOT',
            'DIST_DIR=$env:MIDI_DIST_ROOT', 'SHELL=C:/msys64/usr/bin/sh.exe']
    directory = cmake + ['-E', 'make_directory', '$env:MIDI_DIST_ROOT']
    require(parsed[4] == ([directory, dist], {'errors'}),
            'MIDI requires checked output-directory creation then public make distcheck with exact inputs')


GL_STEP_ORDER = (
    'Prepare pure-gl audit inputs', 'Configure strict pure-gl audit',
    'Build and verify pure-gl PE closure',
    'Run mandatory noninteractive pure-gl tests',
    'Verify pure-gl source distribution', 'Install and verify the pure-gl package',
)
GL_REQUIRED_PATHS = {
    'pure-gl/**', 'pure/todo/TODO-35-windows-pure-gl.md',
    'docs/superpowers/specs/2026-09-11-windows-pure-gl-audit-hardening-design.md',
    'docs/superpowers/plans/2026-09-12-windows-pure-gl-audit-hardening.md',
}
GL_ENVIRONMENT = {
    'GL_CHECKOUT_SOURCE': '${{ github.workspace }}/pure-gl',
    'GL_CHECKOUT_WORKFLOWS': '${{ github.workspace }}/.github',
    'GL_PURE_ORIGIN': '${{ github.workspace }}/pure/build/windows-clang64-prefix',
    'GL_CLANG64_PREFIX': 'C:/msys64/clang64',
    'GL_WINDOWS_SYSTEM_DIRECTORY': 'C:/Windows/System32',
    'GL_CC': 'C:/msys64/clang64/bin/clang.exe',
    'GL_NINJA': 'C:/msys64/clang64/bin/ninja.exe',
    'GL_PKG_CONFIG': 'C:/msys64/clang64/bin/pkgconf.exe',
    'GL_READOBJ': 'C:/msys64/clang64/bin/llvm-readobj.exe',
    'GL_READOBJ_SHA256': '040c4cb0740d2a9d9f7b488bc676c0406eb12c7b349acba1797c2f58865087cb',
    'GL_STRINGS': 'C:/msys64/clang64/bin/llvm-strings.exe',
    'GL_STRINGS_SHA256': '8d04b5a905fc4d42ee21ae075ced38f5d9a937dbbc03aa571f409002f1bbd411',
    'GL_MAKE': 'C:/msys64/clang64/bin/mingw32-make.exe',
    'GL_LOG_DIR': '${{ github.workspace }}/pure/build/native-logs/windows-11-x86_64/pure-gl',
}
GL_STEP_ENVIRONMENT = {
    'GL_REPOSITORY': '${{ runner.temp }}/pure gl source',
    'GL_SOURCE': '${{ runner.temp }}/pure gl source/pure-gl',
    'GL_BUILD': '${{ runner.temp }}/gl8',
    'GL_PURE_PREFIX': '${{ runner.temp }}/glp',
    'GL_STAGE': '${{ runner.temp }}/gl package café',
    'PATH': 'C:/msys64/clang64/bin;C:/Windows/System32;C:/Windows',
    'PURELIB': '', 'PURE_INCLUDE': '', 'PURE_LIBRARY': '',
    'PKG_CONFIG_PATH': '', 'PKG_CONFIG_SYSROOT_DIR': '',
    'PKG_CONFIG_LIBDIR': '${{ runner.temp }}/glp/lib/pkgconfig;C:/msys64/clang64/lib/pkgconfig',
}
GL_CONFIGURE_INPUTS = {
    'CMAKE_BUILD_TYPE': 'Release', 'BUILD_TESTING': 'ON', 'PURE_GL_STRICT_AUDIT': 'ON',
    'CMAKE_C_COMPILER': '$env:GL_CC',
    'CMAKE_C_COMPILER_TARGET': 'x86_64-w64-windows-gnu',
    'CMAKE_MAKE_PROGRAM': '$env:GL_NINJA',
    'PKG_CONFIG_EXECUTABLE': '$env:GL_PKG_CONFIG',
    'LLVM_READOBJ_EXECUTABLE': '$env:GL_READOBJ',
    'LLVM_READOBJ_SHA256': '$env:GL_READOBJ_SHA256',
    'LLVM_STRINGS_EXECUTABLE': '$env:GL_STRINGS',
    'LLVM_STRINGS_SHA256': '$env:GL_STRINGS_SHA256',
    'GNU_MAKE_EXECUTABLE': '$env:GL_MAKE',
    'PURE_EXECUTABLE': '$env:GL_PURE_PREFIX/bin/pure.exe',
    'PURE_GL_PURE_PREFIX': '$env:GL_PURE_PREFIX',
    'PURE_GL_CLANG64_PREFIX': '$env:GL_CLANG64_PREFIX',
    'PURE_GL_WINDOWS_SYSTEM_DIRECTORY': '$env:GL_WINDOWS_SYSTEM_DIRECTORY',
}
GL_COMMAND_LOGS = (
    ('prepare-source.log', 'prepare-workflows.log', 'prepare-baseline.log'),
    ('configure.log',), ('build.log', 'pe.log'), ('ctest-inventory.log', 'ctest.log'), ('distcheck.log',),
    ('prepare-stage.log', 'install-runtime.log', 'install-documentation.log', 'installed.log'),
)


def gl_native_calls(script: str, logs: tuple[str, ...]) -> tuple[list[list[str]], set[str]]:
    """Audit unconditional calls, parent sanitation, logs and failure propagation."""
    logical = re.sub(r'`\r?\n[ \t]*', ' ', script)
    lines = [line.strip() for line in logical.splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    calls: list[list[str]] = []
    guards: set[str] = set()
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith('&'):
            require('purelib' in guards, 'GL must remove PURELIB before commands')
            require('errors' in guards, 'GL must set Stop before commands')
            tokens = audio_command_tokens(line)
            suffix = ['2>&1', '|', 'Tee-Object', '-FilePath']
            require(len(calls) < len(logs) and len(tokens) >= 6 and tokens[-5:-1] == suffix and
                    tokens[-1] == '$env:GL_LOG_DIR/'+logs[len(calls)],
                    'GL native command requires its retained log')
            require(index+1 < len(lines) and re.fullmatch(
                r"if\s*\(\$LASTEXITCODE\s+-ne\s+0\)\s*\{\s*throw\s+'[^']+'\s*\}", lines[index+1]),
                'GL native command must immediately propagate nonzero status')
            calls.append(tokens[:-5])
            index += 2
            continue
        require(not calls, 'GL unsupported PowerShell statement after commands')
        if re.fullmatch(r'''\$ErrorActionPreference\s*=\s*(?:'Stop'|"Stop")''', line):
            guard = 'errors'
        elif line == 'Remove-Item Env:PURELIB -ErrorAction SilentlyContinue':
            guard = 'purelib'
        elif re.fullmatch(r'''New-Item\s+-ItemType\s+Directory\s+-Path\s+"\$env:GL_LOG_DIR"\s+-Force\s+\|\s+Out-Null''', line):
            guard = 'logs'
        else:
            fresh = re.fullmatch(r"if\s*\(Test-Path\s+-LiteralPath\s+\$env:(GL_REPOSITORY|GL_PURE_PREFIX|GL_BUILD|GL_STAGE)\)\s*\{\s*throw\s+'[^']+'\s*\}", line)
            short = re.fullmatch(r"if\s*\(\$env:GL_BUILD\.Length\s+-gt\s+32\)\s*\{\s*throw\s+'[^']+'\s*\}", line)
            require(fresh is not None or short is not None, 'GL unsupported PowerShell statement')
            guard = fresh.group(1) if fresh else 'short'
        require(guard not in guards, 'GL preflight changed: duplicate statement')
        guards.add(guard)
        index += 1
    return calls, guards


def validate_gl(root: dict[str, Any], core: dict[str, Any], steps: list[Any]) -> None:
    for event in ('push', 'pull_request'):
        trigger = mapping(mapping(root.get('on'), 'on').get(event), event)
        paths = sequence(trigger.get('paths'), 'GL '+event+'.paths')
        for path in sorted(GL_REQUIRED_PATHS):
            require(path in paths, f'GL {event} missing trigger input: {path}')
    environment = mapping(core.get('env'), 'GL job environment')
    for key, value in GL_ENVIRONMENT.items():
        require(environment.get(key) == value, 'GL job input origin changed: '+key)
    prerequisite = step_by_name(steps, 'Install the CLANG64 build prerequisites')
    packages = str(mapping(prerequisite.get('with'), 'GL prerequisites').get('install', '')).split()
    require('mingw-w64-clang-x86_64-freeglut' in packages,
            'GL prerequisite missing: mingw-w64-clang-x86_64-freeglut')
    portable = step_by_name(steps, 'Install and validate the portable runtime')
    selected = [step_by_name(steps, name) for name in GL_STEP_ORDER]
    positions = [steps.index(s) for s in [prerequisite, portable, *selected]]
    # The Pure baseline is copied before any other package can add files. The
    # separate copy remains sealed even when later package gates use the origin.
    later = [steps.index(step_by_name(steps, name)) for name in (
        'Install and verify the pure-midi package', 'Install and verify the pure-audio package',
        'Install and verify the pure-odbc package', 'Validate non-Linux workflow semantics')]
    require(positions == sorted(set(positions)) and positions[-1] < min(later) and
            positions[2] == positions[1]+1,
            'GL release steps are out of dependency order')
    defaults = ({'shell': 'pwsh'} | audio_run_defaults(root, 'workflow') |
                audio_run_defaults(core, 'job'))
    parsed = []
    for index, step in enumerate(selected):
        effective = defaults | {k: step[k] for k in ('shell', 'working-directory') if k in step}
        require('if' not in step and 'continue-on-error' not in step and
                effective == {'shell': 'pwsh', 'working-directory': 'pure'},
                'GL step execution context must be unconditional PowerShell in pure')
        expected_env = dict(GL_STEP_ENVIRONMENT)
        if index >= 3:
            expected_env['PATH'] = 'C:/Windows/System32;C:/Windows'
        require(mapping(step.get('env'), 'GL step environment') == expected_env,
                'GL step environment changed: explicit disjoint roots and sanitized discovery required')
        calls, guards = gl_native_calls(command(step, step['name']), GL_COMMAND_LOGS[index])
        expected_guards = {'errors', 'purelib'} | {
            0: {'GL_REPOSITORY', 'GL_PURE_PREFIX', 'logs'},
            1: {'GL_BUILD', 'short'}, 5: {'GL_STAGE'},
        }.get(index, set())
        require(guards == expected_guards, 'GL preflight changed: fresh roots and log initialization required')
        parsed.append(calls)
    cmake = ['&', '$env:CMAKE_EXE']
    prefix = cmake + ['-S', '$env:GL_SOURCE', '-B', '$env:GL_BUILD', '-G', 'Ninja']
    require(len(parsed[1]) == 1 and parsed[1][0][:8] == prefix, 'GL configure invocation changed')
    inputs = {}
    for argument in parsed[1][0][8:]:
        match = re.fullmatch(r'-D([A-Z][A-Z0-9_]*)=(.+)', argument)
        require(match is not None, 'GL unexpected configure input: '+argument)
        key, value = match.groups()
        require(key not in inputs, 'GL duplicate configure input: '+key)
        require(key in GL_CONFIGURE_INPUTS, 'GL unexpected configure input: '+key)
        inputs[key] = value
    for key, value in GL_CONFIGURE_INPUTS.items():
        require(key in inputs, 'GL configure missing input: '+key)
        require(inputs[key] == value, 'GL configure input changed: '+key)
    copy = cmake + ['-E', 'copy_directory']
    install = cmake + ['--install', '$env:GL_BUILD', '--prefix', '$env:GL_STAGE', '--component']
    commands = {
        0: [copy+['$env:GL_CHECKOUT_SOURCE', '$env:GL_SOURCE'],
            copy+['$env:GL_CHECKOUT_WORKFLOWS', '$env:GL_REPOSITORY/.github'],
            copy+['$env:GL_PURE_ORIGIN', '$env:GL_PURE_PREFIX']],
        2: [cmake+['--build', '$env:GL_BUILD', '--parallel', '4'],
            cmake+['--build', '$env:GL_BUILD', '--target', 'verify-windows-dependencies', '--parallel', '4']],
        3: [cmake+['-DBINARY_DIR=$env:GL_BUILD', '-P', '$env:GL_SOURCE/tests/VerifyCTestInventory.cmake'],
            ['&', '$env:CTEST_EXE', '--test-dir', '$env:GL_BUILD', '-L', 'gl',
             '--output-on-failure', '--no-tests=error']],
        4: [['&', '$env:GL_MAKE', '--no-print-directory', '-C', '$env:GL_SOURCE', 'distcheck',
             'CMAKE=$env:CMAKE_EXE', 'PKG_CONFIG=$env:GL_PKG_CONFIG', 'DIST_AUDIT_BUILD=$env:GL_BUILD']],
        # The native-authenticated context supplies every sealed manifest,
        # runtime/source/license/tool pin and the supervisor. No alternate caller
        # origins or helpers-only mode may override that complete public verifier.
        5: [copy+['$env:GL_PURE_PREFIX', '$env:GL_STAGE'], install+['runtime'], install+['documentation'],
            cmake+['-DGL_INSTALL_CONTEXT=$env:GL_BUILD/pure-gl-install-context.cmake',
                   '-DSTAGE_PREFIX=$env:GL_STAGE', '-P', '$env:GL_SOURCE/cmake/VerifyInstalledPackage.cmake']],
    }
    for index, expected in commands.items():
        require(parsed[index] == expected, 'GL command sequence changed: '+GL_STEP_ORDER[index])
    upload = step_by_name(steps, 'Upload pure-gl audit evidence')
    require(upload.get('if') == 'always()' and upload.get('uses') == 'actions/upload-artifact@v4' and
            'continue-on-error' not in upload and steps.index(upload) > positions[-1],
            'GL logs require unconditional artifact retention')
    options = mapping(upload.get('with'), 'GL log artifact inputs')
    expected_upload = {
        'name': 'pure-gl-windows-audit', 'retention-days': '14', 'if-no-files-found': 'warn',
        'path': '${{ github.workspace }}/pure/build/native-logs/windows-11-x86_64/pure-gl\n${{ runner.temp }}/gl8\n',
    }
    require(options == expected_upload, 'GL log artifact inputs changed')


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
    validate_gl(root, core, steps)
    validate_audio(root, core, steps)
    validate_midi(root, core, steps)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("workflow", type=Path)
    args = parser.parse_args()
    validate(args.workflow.resolve())
    print(f"validated workflow semantics: {args.workflow}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
