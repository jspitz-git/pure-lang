#!/usr/bin/env python3
"""Mutation tests for the non-Linux release workflow semantic contract."""

from __future__ import annotations

import importlib.util
import copy
from functools import lru_cache
from pathlib import Path
import tempfile
import unittest

import yaml


SCRIPT_DIR = Path(__file__).resolve().parent
WORKFLOW = SCRIPT_DIR.parent / "workflows" / "non-linux-release-validation.yml"
SPEC = importlib.util.spec_from_file_location(
    "workflow_contract", SCRIPT_DIR / "validate_non_linux_release_workflow.py")
assert SPEC and SPEC.loader
CONTRACT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTRACT)

# Hand-authored interface fixture: no expected values are imported from the
# validator. It is a data control, never an executed replacement for CI.
AUDIO_NAMES = [
    'Configure strict pure-audio audit',
    'Build and verify pure-audio PE closure',
    'Run mandatory no-hardware pure-audio tests',
    'Install and verify the pure-audio package',
    'Verify pure-audio source distribution',
]
AUDIO_PATHS = ['pure-audio/**', 'pure/todo/TODO-33-windows-pure-audio.md',
               '.github/workflows/non-linux-release-validation.yml',
               '.github/scripts/validate_non_linux_release_workflow.py',
               '.github/scripts/test_validate_non_linux_release_workflow.py']
AUDIO_PACKAGES = ['tar', 'gzip', 'make'] + [
    'mingw-w64-clang-x86_64-' + name for name in (
        'clang', 'cmake', 'ninja', 'pkgconf', 'llvm', 'make', 'python-yaml',
        'portaudio', 'fftw', 'libsamplerate', 'libsndfile', 'libogg', 'libvorbis',
        'flac', 'opus', 'mpg123', 'lame', 'winpthreads', 'libc++', 'gmp',
        'mpfr', 'libiconv', 'pcre', 'readline', 'termcap', 'zstd', 'zlib')]
AUDIO_JOB_ENV = {
    'AUDIO_SOURCE': '${{ github.workspace }}/pure-audio',
    'AUDIO_BUILD': '${{ runner.temp }}/pa8',
    'AUDIO_STAGE': '${{ runner.temp }}/pa8/package',
    'AUDIO_PREFIX': '${{ github.workspace }}/pure/build/windows-clang64-prefix',
    'AUDIO_RUNTIME_PATH': '${{ github.workspace }}/pure/build/windows-clang64-prefix/bin;C:/msys64/clang64/bin;C:/msys64/usr/bin;C:/Windows/System32;C:/Windows',
}
AUDIO_ENV = {'PATH': '${{ env.AUDIO_RUNTIME_PATH }}',
             'PURELIB': '', 'PURE_INCLUDE': '', 'PURE_LIBRARY': ''}
AUDIO_INPUTS = {
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
    'PURE_AUDIO_WINDOWS_HEADER': 'C:/msys64/clang64/include/windows.h',
    'PURE_AUDIO_WINDOWS_SYSTEM_DIRECTORY': 'C:/Windows/System32',
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
}
BASELINE_DLLS = ('pure.exe libpure.dll libc++.dll libgmp-10.dll libiconv-2.dll '
                 'libmpfr-6.dll libpcre-1.dll libpcreposix-0.dll libreadline8.dll '
                 'libtermcap-0.dll libwinpthread-1.dll libzstd.dll zlib1.dll').split()
AUDIO_DLLS = ('libportaudio.dll libfftw3-3.dll libsamplerate-0.dll libsndfile-1.dll '
              'libogg-0.dll libvorbisenc-2.dll libFLAC.dll libopus-0.dll '
              'libmpg123-0.dll libmp3lame-0.dll libvorbis-0.dll').split()
RUNTIME_ROWS = ([f'{name}|$env:AUDIO_PREFIX/bin/{name}' for name in BASELINE_DLLS] +
                [f'{name}|C:/msys64/clang64/bin/{name}' for name in AUDIO_DLLS])
AUDIO_INPUTS['PURE_AUDIO_RUNTIME_SOURCES'] = ';'.join(RUNTIME_ROWS)
NORMAL_BUILD = '& $env:CMAKE_EXE --build "$env:AUDIO_BUILD" --parallel 4'
PE_BUILD = '& $env:CMAKE_EXE --build "$env:AUDIO_BUILD" --target verify-windows-dependencies --parallel 4'
AUDIO_CTEST = ('& $env:CTEST_EXE --test-dir "$env:AUDIO_BUILD" -L "^audio$" '
               '-LE "^hardware$" -E "^pure-audio-source-dist-contract$" '
               '--output-on-failure --no-tests=error --parallel 4')
INSTALL_RUNTIME = '& $env:CMAKE_EXE --install "$env:AUDIO_BUILD" --prefix "$env:AUDIO_STAGE" --component runtime'
INSTALL_DOCS = INSTALL_RUNTIME.replace('--component runtime', '--component documentation')
INSTALLED_VERIFY = ('& $env:CMAKE_EXE "-DAUDIO_INSTALL_CONTEXT=$env:AUDIO_BUILD/windows-install-context.cmake" '
                    '"-DSTAGE_PREFIX=$env:AUDIO_STAGE" -P "$env:AUDIO_SOURCE/cmake/VerifyInstalledPackage.cmake"')
SOURCE_DIST = ('& C:/msys64/clang64/bin/mingw32-make.exe -C "$env:AUDIO_SOURCE" '
               'SHELL=C:/msys64/usr/bin/sh.exe DIST_CMAKE=C:/msys64/clang64/bin/cmake.exe '
               '"DIST_AUDIT_BUILD=$env:AUDIO_BUILD" distcheck')


@lru_cache(maxsize=1)
def data_workflow():
    return yaml.load(WORKFLOW.read_text(encoding='utf-8'), Loader=yaml.BaseLoader)


def audio_step(document, index):
    return next(step for step in document['jobs']['windows-pure-core']['steps']
                if step.get('name') == AUDIO_NAMES[index])


def candidate():
    document = copy.deepcopy(data_workflow())
    core = document['jobs']['windows-pure-core']
    core['env'].update(AUDIO_JOB_ENV)
    if 'codex/**' not in document['on']['push']['branches']:
        document['on']['push']['branches'].append('codex/**')
    for event in ('push', 'pull_request'):
        paths = document['on'][event]['paths']
        paths.extend(path for path in AUDIO_PATHS if path not in paths)
    steps = core['steps']
    prerequisite = next(step for step in steps if step.get('name') == 'Install the CLANG64 build prerequisites')
    packages = prerequisite['with']['install'].split()
    packages.extend(package for package in AUDIO_PACKAGES if package not in packages)
    prerequisite['with']['install'] = ' '.join(packages)
    def run(*lines):
        result = "$ErrorActionPreference = 'Stop'\n"
        for line in lines:
            result += line + '\n'
            if line.startswith('& '):
                result += "if ($LASTEXITCODE -ne 0) { throw 'Native audio gate failed' }\n"
        return result
    configure = '& $env:CMAKE_EXE -S "$env:AUDIO_SOURCE" -B "$env:AUDIO_BUILD" -G Ninja '
    configure += ' '.join(f'"-D{name}={value}"' for name, value in AUDIO_INPUTS.items())
    commands = [
        run('if ($env:AUDIO_BUILD.Length -gt 32) { throw \'Short audio build root required\' }',
            'if (Test-Path -LiteralPath $env:AUDIO_BUILD) { throw \'Fresh audio build required\' }', configure),
        run(NORMAL_BUILD, PE_BUILD), run(AUDIO_CTEST),
        run('if (Test-Path -LiteralPath $env:AUDIO_STAGE) { throw \'Fresh audio stage required\' }',
            '& $env:CMAKE_EXE -E copy_directory "$env:AUDIO_PREFIX" "$env:AUDIO_STAGE"',
            INSTALL_RUNTIME, INSTALL_DOCS, INSTALLED_VERIFY), run(SOURCE_DIST)]
    steps[:] = [step for step in steps if step.get('name') not in AUDIO_NAMES]
    at = next(i for i, step in enumerate(steps) if step.get('name') == 'Install and validate the portable runtime') + 1
    steps[at:at] = [dict(name=name, shell='pwsh', env=copy.deepcopy(AUDIO_ENV), run=script)
                   for name, script in zip(AUDIO_NAMES, commands)]
    return document


def validate_data(document):
    # One atomically created owned file; exact unlink only, no recursive cleanup.
    with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', prefix='.audio-workflow-',
                                     dir=SCRIPT_DIR, encoding='utf-8', delete=False) as stream:
        yaml.safe_dump(document, stream, sort_keys=False)
        path = Path(stream.name)
    try:
        CONTRACT.validate(path)
    finally:
        path.unlink()


def audio_mutations():
    cases = []
    def mutate(label, operation):
        document = candidate()
        operation(document)
        cases.append((label, document))
    def replace_run(label, index, old, new):
        def operation(document):
            step = audio_step(document, index)
            assert old in step['run'], (label, old)
            step['run'] = step['run'].replace(old, new, 1)
        mutate(label, operation)
    for event in ('push', 'pull_request'):
        for path in AUDIO_PATHS:
            mutate(f'{event}:missing:{path}', lambda d, e=event, p=path: d['on'][e]['paths'].remove(p))
        mutate(f'{event}:missing', lambda d, e=event: d['on'].pop(e))
        mutate(f'{event}:paths-type', lambda d, e=event: d['on'][e].update(paths='pure-audio/**'))
        mutate(f'{event}:paths-ignore', lambda d, e=event: d['on'][e].update({'paths-ignore': ['pure-audio/**']}))
        mutate(f'{event}:negative-filter', lambda d, e=event: d['on'][e]['paths'].append('!pure-audio/**'))
    for event, branches in [('push', ['master', 'todo/**', 'codex/**']), ('pull_request', ['master'])]:
        for branch in branches:
            mutate(f'{event}:branch:{branch}', lambda d, e=event, b=branch: d['on'][e]['branches'].remove(b))
    for key in ('CMAKE_EXE', 'CTEST_EXE', 'INSTALL_PREFIX'):
        mutate(f'tool-env-missing:{key}', lambda d, k=key: d['jobs']['windows-pure-core']['env'].pop(k))
        mutate(f'tool-env-origin:{key}', lambda d, k=key: d['jobs']['windows-pure-core']['env'].update({k: 'C:/untrusted'}))
    mutate('job-disabled', lambda d: d['jobs']['windows-pure-core'].update({'if': 'false'}))
    mutate('job-failure-ignored', lambda d: d['jobs']['windows-pure-core'].update({'continue-on-error': 'true'}))
    mutate('wrong-runner', lambda d: d['jobs']['windows-pure-core'].update({'runs-on': 'ubuntu-latest'}))
    mutate('job-default-directory', lambda d: d['jobs']['windows-pure-core'].update({'defaults': {'run': {'working-directory': 'elsewhere'}}}))
    mutate('working-directory', lambda d: d['defaults']['run'].update({'working-directory': 'elsewhere'}))
    for package in AUDIO_PACKAGES:
        def remove_package(d, package=package):
            step = next(s for s in d['jobs']['windows-pure-core']['steps']
                        if s.get('name') == 'Install the CLANG64 build prerequisites')
            step['with']['install'] = ' '.join(p for p in step['with']['install'].split() if p != package)
        mutate(f'package:{package}', remove_package)
    for key in AUDIO_JOB_ENV:
        mutate(f'job-env-missing:{key}', lambda d, k=key: d['jobs']['windows-pure-core']['env'].pop(k))
        mutate(f'job-env-origin:{key}', lambda d, k=key: d['jobs']['windows-pure-core']['env'].update({k: 'C:/untrusted'}))
    for i, name in enumerate(AUDIO_NAMES):
        mutate(f'step-missing:{name}', lambda d, i=i: d['jobs']['windows-pure-core']['steps'].remove(audio_step(d, i)))
        mutate(f'step-duplicate:{name}', lambda d, i=i: d['jobs']['windows-pure-core']['steps'].append(copy.deepcopy(audio_step(d, i))))
        for field, value in [('if', 'false'), ('continue-on-error', 'true'), ('shell', 'bash')]:
            mutate(f'step-{field}:{name}', lambda d, i=i, f=field, v=value: audio_step(d, i).update({f: v}))
        for key in AUDIO_ENV:
            mutate(f'env-missing:{i}:{key}', lambda d, i=i, k=key: audio_step(d, i)['env'].pop(k))
            mutate(f'env-inherited:{i}:{key}', lambda d, i=i, k=key: audio_step(d, i)['env'].update({k: '${{ env.PATH }}'}))
        mutate(f'extra-env-override:{i}', lambda d, i=i: audio_step(d, i)['env'].update({'CMAKE_EXE': 'C:/untrusted/cmake.exe'}))
        replace_run(f'failure-propagation:{i}', i, "if ($LASTEXITCODE -ne 0) { throw 'Native audio gate failed' }", '')
    def reorder(d):
        steps = d['jobs']['windows-pure-core']['steps']
        a, b = steps.index(audio_step(d, 0)), steps.index(audio_step(d, 1))
        steps[a], steps[b] = steps[b], steps[a]
    mutate('reordered-configure-build', reorder)
    def before_portable(d):
        steps = d['jobs']['windows-pure-core']['steps']
        step = audio_step(d, 0)
        steps.remove(step)
        steps.insert(0, step)
    mutate('audio-before-portable', before_portable)
    for i in (1, 2, 3):
        def swap_adjacent(d, i=i):
            steps = d['jobs']['windows-pure-core']['steps']
            a, b = steps.index(audio_step(d, i)), steps.index(audio_step(d, i+1))
            steps[a], steps[b] = steps[b], steps[a]
        mutate(f'order:{i}', swap_adjacent)
    for name in ('Install the CLANG64 build prerequisites', 'Install and validate the portable runtime'):
        def find(d, name=name):
            return next(step for step in d['jobs']['windows-pure-core']['steps'] if step.get('name') == name)
        mutate(f'prerequisite-disabled:{name}', lambda d, f=find: f(d).update({'if': 'false'}))
        mutate(f'prerequisite-missing:{name}', lambda d, f=find: d['jobs']['windows-pure-core']['steps'].remove(f(d)))
    def wrong_msystem(d):
        next(step for step in d['jobs']['windows-pure-core']['steps']
             if step.get('name') == 'Install the CLANG64 build prerequisites')['with']['msystem'] = 'MINGW64'
    mutate('wrong-msystem', wrong_msystem)
    semantic_test = '& C:/msys64/clang64/bin/python.exe ../.github/scripts/test_validate_non_linux_release_workflow.py -v'
    semantic_validate = '& C:/msys64/clang64/bin/python.exe ../.github/scripts/validate_non_linux_release_workflow.py ../.github/workflows/non-linux-release-validation.yml'
    semantic_guard = "\nif ($LASTEXITCODE -ne 0) { throw 'Workflow contract failed' }\n"
    for label, script in [
        ('comments-only', '# '+semantic_test+'\n# '+semantic_validate),
        ('tests-only', semantic_test+semantic_guard),
        ('validate-only', '# '+semantic_test+'\n'+semantic_validate+semantic_guard),
        ('wrong-workflow', semantic_test+semantic_guard+semantic_validate.replace('../.github/workflows/non-linux-release-validation.yml', '../other.yml')+semantic_guard),
    ]:
        def change_semantic(d, script=script):
            next(step for step in d['jobs']['windows-pure-core']['steps']
                 if step.get('name') == 'Validate non-Linux workflow semantics')['run'] = "$ErrorActionPreference = 'Stop'\n"+script
        mutate(f'semantic:{label}', change_semantic)
    replace_run('missing-build-freshness', 0, "if (Test-Path -LiteralPath $env:AUDIO_BUILD) { throw 'Fresh audio build required' }", '')
    replace_run('missing-path-budget', 0, "if ($env:AUDIO_BUILD.Length -gt 32) { throw 'Short audio build root required' }", '')
    replace_run('missing-stage-freshness', 3, "if (Test-Path -LiteralPath $env:AUDIO_STAGE) { throw 'Fresh audio stage required' }", '')
    for key, value in AUDIO_INPUTS.items():
        token = f'"-D{key}={value}"'
        replace_run(f'input-missing:{key}', 0, token, '')
        replace_run(f'input-origin:{key}', 0, token, f'"-D{key}=C:/untrusted"')
        replace_run(f'input-duplicate:{key}', 0, token, token + ' ' + token)
    for row in RUNTIME_ROWS:
        changed = ';'.join(entry for entry in RUNTIME_ROWS if entry != row)
        replace_run(f'runtime-missing:{row.split("|")[0]}', 0, AUDIO_INPUTS['PURE_AUDIO_RUNTIME_SOURCES'], changed)
    for label, old, new in [
        ('missing-normal', NORMAL_BUILD, ''), ('missing-pe', PE_BUILD, ''),
        ('duplicate-normal', NORMAL_BUILD, NORMAL_BUILD+'\n'+NORMAL_BUILD),
        ('duplicate-pe', PE_BUILD, PE_BUILD+'\n'+PE_BUILD),
        ('pe-substitutes-normal', NORMAL_BUILD, PE_BUILD),
        ('normal-substitutes-pe', PE_BUILD, NORMAL_BUILD),
        ('wrong-workers-normal', NORMAL_BUILD, NORMAL_BUILD.replace('--parallel 4', '--parallel 2')),
        ('wrong-workers-pe', PE_BUILD, PE_BUILD.replace('--parallel 4', '--parallel 2')),
        ('conflicting-workers', NORMAL_BUILD, NORMAL_BUILD+' --parallel 2'),
        ('native-worker-override', PE_BUILD, PE_BUILD+' -- -j8'),
        ('extra-target', NORMAL_BUILD, NORMAL_BUILD+' --target audio'),
        ('substituted-tool', NORMAL_BUILD, NORMAL_BUILD.replace('$env:CMAKE_EXE', 'cmake.exe')),
        ('inline-extra-build', NORMAL_BUILD, NORMAL_BUILD+'; '+PE_BUILD),
    ]:
        replace_run(label, 1, old, new)
    # Swap whole command+guard pairs so this tests order, not a malformed script.
    def swap_builds(d):
        step = audio_step(d, 1)
        step['run'] = step['run'].replace(NORMAL_BUILD, '__FIRST__').replace(PE_BUILD, NORMAL_BUILD).replace('__FIRST__', PE_BUILD)
    mutate('pe-before-normal', swap_builds)
    guard = "if ($LASTEXITCODE -ne 0) { throw 'Native audio gate failed' }"
    for label, invocation in [('normal', NORMAL_BUILD), ('pe', PE_BUILD)]:
        replace_run(f'well-formed-duplicate:{label}', 1, invocation, invocation+'\n'+guard+'\n'+invocation)
    for label, old, new in [
        ('missing-label', '-L "^audio$"', ''), ('empty-label', '^audio$', '^absent$'),
        ('hardware-enabled', '-LE "^hardware$"', ''),
        ('empty-selection-allowed', '--no-tests=error', ''),
        ('missing-defer', '-E "^pure-audio-source-dist-contract$"', ''),
        ('extra-exclusion', '--parallel 4', '--parallel 4 -E bounds'),
        ('other-exclusion', '^pure-audio-source-dist-contract$', '^pure-audio-install-contract$'),
        ('positive-selection', '--parallel 4', '--parallel 4 -R load'),
        ('ignored-failure', '--output-on-failure', '--output-on-failure --rerun-failed')]:
        replace_run(label, 2, old, new)
    for label, old, new in [
        ('missing-runtime', INSTALL_RUNTIME, ''), ('missing-documentation', INSTALL_DOCS, ''),
        ('duplicate-runtime', INSTALL_DOCS, INSTALL_RUNTIME),
        ('missing-verifier', INSTALLED_VERIFY, ''),
        ('missing-context', '"-DAUDIO_INSTALL_CONTEXT=$env:AUDIO_BUILD/windows-install-context.cmake"', ''),
        ('wrong-context', 'windows-install-context.cmake', 'elsewhere.cmake'),
        ('missing-stage', '"-DSTAGE_PREFIX=$env:AUDIO_STAGE"', ''),
        ('verifier-seal-bypass', INSTALLED_VERIFY, INSTALLED_VERIFY+' -DAUDIO_INSTALL_MODE=seal'),
        ('helper-state-bypass', INSTALLED_VERIFY, INSTALLED_VERIFY+' -DPURE_AUDIO_RUNNER_HELPERS_ONLY=ON')]:
        replace_run(label, 3, old, new)
    for label, old, new in [
        ('wrong-dist-target', ' distcheck', ' dist'),
        ('missing-dist-build', '"DIST_AUDIT_BUILD=$env:AUDIO_BUILD"', ''),
        ('wrong-dist-source', '"$env:AUDIO_SOURCE"', '"C:/untrusted"'),
        ('wrong-dist-shell', 'SHELL=C:/msys64/usr/bin/sh.exe', 'SHELL=sh'),
        ('dist-extra-filter', ' distcheck', ' distcheck FOCUSED_ONLY=ON')]:
        replace_run(label, 4, old, new)
    return cases


class AudioWorkflowMutationTests(unittest.TestCase):
    def test_independently_authored_pristine(self):
        validate_data(candidate())

    def test_actual_pristine_workflow(self):
        CONTRACT.validate(WORKFLOW)

    def test_accepts_structural_formatting_controls(self):
        reordered = candidate()
        script = audio_step(reordered, 0)
        script['run'] = script['run'].replace(';'.join(RUNTIME_ROWS), ';'.join(reversed(RUNTIME_ROWS)))
        validate_data(reordered)
        continued = candidate()
        for index in range(5):
            script = audio_step(continued, index)
            script['run'] = '# Audited formatting control\n' + script['run'].replace(' --', ' `\n    --')
        validate_data(continued)

    def test_rejects_audio_semantic_mutations(self):
        cases = audio_mutations()
        for label, document in cases:
            with self.subTest(mutation=label), self.assertRaises(AssertionError):
                validate_data(document)
        print(f'AUDIO_WORKFLOW_CASES negatives={len(cases)}')


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
