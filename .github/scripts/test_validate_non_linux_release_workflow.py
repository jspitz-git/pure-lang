#!/usr/bin/env python3
"""Mutation tests for the non-Linux release workflow semantic contract."""

from __future__ import annotations

import importlib.util
import copy
from functools import lru_cache
from pathlib import Path
import tempfile
import unittest
import re

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
    'AUDIO_PREFIX': '${{ github.workspace }}/pure/build/windows-clang64-prefix',
    'AUDIO_RUNTIME_PATH': '${{ github.workspace }}/pure/build/windows-clang64-prefix/bin;C:/msys64/clang64/bin;C:/msys64/usr/bin;C:/Windows/System32;C:/Windows',
}
AUDIO_ENV = {'AUDIO_BUILD': '${{ runner.temp }}/pa8',
             'AUDIO_STAGE': '${{ runner.temp }}/pa8/package',
             'PATH': '${{ env.AUDIO_RUNTIME_PATH }}',
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


def semantic_step(document):
    return next(step for step in document['jobs']['windows-pure-core']['steps']
                if step.get('name') == 'Validate non-Linux workflow semantics')


def candidate():
    document = copy.deepcopy(data_workflow())
    core = document['jobs']['windows-pure-core']
    core['env'].update(AUDIO_JOB_ENV)
    semantic_step(document).update(shell='pwsh', **{'working-directory': 'pure'})
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
    mutate('job-env-unavailable-runner-context',
           lambda d: d['jobs']['windows-pure-core']['env'].update(
               {'AUDIO_BUILD': '${{ runner.temp }}/pa8'}))
    mutate('job-env-unavailable-runner-context-compact',
           lambda d: d['jobs']['windows-pure-core']['env'].update(
               {'AUDIO_BUILD': '${{runner.temp}}/pa8'}))
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


def execution_context_mutations():
    cases = []
    for layer in ('step', 'job', 'workflow'):
        for field, value in [('shell', 'bash'), ('shell', 'pwsh -Command "exit 0" # {0}'),
                             ('working-directory', 'elsewhere')]:
            document = candidate()
            if layer == 'step':
                target = semantic_step(document)
            else:
                # Remove step overrides: the bad value really is inherited.
                semantic_step(document).pop(field)
                scope = document if layer == 'workflow' else document['jobs']['windows-pure-core']
                target = scope.setdefault('defaults', {}).setdefault('run', {})
            target[field] = value
            cases.append((f'{layer}:{field}:{value}', document))
    for field, value in [('if', 'false'), ('if', '${{ always() }}'),
                         ('continue-on-error', 'true'), ('continue-on-error', '${{ failure() }}')]:
        for layer in ('step', 'job'):
            if layer == 'job' and (field, value) in [('if', 'false'), ('continue-on-error', 'true')]:
                continue  # Already independent cases in audio_mutations().
            document = candidate()
            target = semantic_step(document) if layer == 'step' else document['jobs']['windows-pure-core']
            target[field] = value
            cases.append((f'{layer}:{field}:{value}', document))
    # Unsafe defaults stay disallowed even when the semantic step overrides them:
    # other prerequisite steps share these defaults.
    for layer in ('job', 'workflow'):
        document = candidate()
        scope = document if layer == 'workflow' else document['jobs']['windows-pure-core']
        scope.setdefault('defaults', {}).setdefault('run', {})['shell'] = 'pwsh -Command "exit 0" # {0}'
        cases.append((f'{layer}:masked-custom-shell', document))
    return cases


def expansion_mutations():
    cases = []
    document = candidate()
    selected = [audio_step(document, i) for i in range(5)] + [semantic_step(document)]
    for index, step in enumerate(selected):
        script = step['run']
        # Test each lexical occurrence independently, including logging paths.
        for occurrence, match in enumerate(re.finditer(r'"[^"\n]*\$env:[^"\n]*"', script)):
            changed = candidate()
            target = audio_step(changed, index) if index < 5 else semantic_step(changed)
            target['run'] = script[:match.start()] + "'"+match[0][1:-1]+"'" + script[match.end():]
            cases.append((f'literal-expansion:{index}:{occurrence}', changed))
    for old, new in [('& $env:CMAKE_EXE', "'&' $env:CMAKE_EXE"),
                     ('$env:CMAKE_EXE', "'$env:CMAKE_EXE'"),
                     ('"$env:AUDIO_BUILD"', '"`$env:AUDIO_BUILD"'),
                     ('"$env:AUDIO_BUILD"', '"$($env:AUDIO_BUILD)"'),
                     ('"$env:AUDIO_BUILD"', '"$env:AUDIO_"BUILD'),
                     ('"$env:AUDIO_BUILD"', '"$env:AUDIO_BUILD"; exit 0')]:
        changed = candidate()
        target = audio_step(changed, 1)
        target['run'] = target['run'].replace(old, new, 1)
        cases.append((f'unsupported-PS:{new}', changed))
    for index in range(5):
        lines = audio_step(candidate(), index)['run'].splitlines()
        for occurrence, line in enumerate(lines):
            if not line.startswith('& '):
                continue
            changed = candidate()
            altered = lines.copy()
            altered[occurrence] += " 2>&1 | Tee-Object -FilePath '$env:LOG_DIR/audio-contract.log'"
            audio_step(changed, index)['run'] = '\n'.join(altered)
            cases.append((f'literal-audio-log:{index}:{occurrence}', changed))
    for whitespace in (' ', '\t'):
        changed = candidate()
        target = audio_step(changed, 1)
        target['run'] = target['run'].replace(' --parallel', ' `'+whitespace+'\n --parallel', 1)
        cases.append((f'invalid-continuation:{whitespace!r}', changed))
    return cases


class AudioWorkflowMutationTests(unittest.TestCase):
    def test_job_environment_uses_only_available_expression_contexts(self):
        core_environment = data_workflow()['jobs']['windows-pure-core']['env']
        for key, value in core_environment.items():
            with self.subTest(variable=key):
                self.assertIsNone(re.search(r'\$\{\{\s*runner\s*(?:\.|\[)', value))

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

    def test_rejects_execution_context_mutations(self):
        cases = execution_context_mutations()
        for label, document in cases:
            with self.subTest(mutation=label), self.assertRaises(AssertionError):
                validate_data(document)
        print(f'EXECUTION_CONTEXT_CASES negatives={len(cases)}')

    def test_rejects_literal_or_unsupported_expansions(self):
        cases = expansion_mutations()
        for label, document in cases:
            with self.subTest(mutation=label), self.assertRaises(AssertionError):
                validate_data(document)
        print(f'EXPANSION_CASES negatives={len(cases)}')

    def test_accepts_safe_execution_context_inheritance(self):
        for layer in ('job', 'workflow'):
            document = candidate()
            semantic_step(document).pop('shell')
            semantic_step(document).pop('working-directory')
            scope = document if layer == 'workflow' else document['jobs']['windows-pure-core']
            scope['defaults'] = {'run': {'shell': 'pwsh', 'working-directory': 'pure'}}
            validate_data(document)

    def test_accepts_literal_regex_and_expanding_quotes(self):
        document = candidate()
        target = audio_step(document, 2)
        for regex in ('^audio$', '^hardware$', '^pure-audio-source-dist-contract$'):
            target['run'] = target['run'].replace('"'+regex+'"', "'"+regex+"'")
        target['run'] = target['run'].replace('$env:CTEST_EXE', '"$env:CTEST_EXE"')
        target['run'] = target['run'].replace('--parallel 4',
            '--parallel 4 2>&1 | Tee-Object -FilePath "$env:LOG_DIR/audio-contract.log"')
        validate_data(document)


# Independent MIDI fixture, authored from the public Tasks 4-7 interfaces.
# It does not copy the shipped MIDI block or import validator expectations.
MIDI_NAMES = [
    'Configure strict pure-midi audit', 'Build and verify pure-midi PE closure',
    'Run mandatory no-hardware pure-midi tests',
    'Install and verify the pure-midi package', 'Verify pure-midi source distribution',
]
MIDI_PATHS = ['pure-midi/**', 'pure/todo/TODO-34-windows-pure-midi.md',
              '.github/workflows/non-linux-release-validation.yml',
              '.github/scripts/validate_non_linux_release_workflow.py',
              '.github/scripts/test_validate_non_linux_release_workflow.py']
MIDI_PACKAGES = ['make'] + ['mingw-w64-clang-x86_64-' + name for name in
    ('clang', 'cmake', 'llvm', 'ninja', 'pkgconf', 'make', 'python-yaml',
     'portmidi', 'gmp', 'mpfr', 'libc++', 'libiconv', 'pcre', 'readline',
     'termcap', 'winpthreads', 'zstd', 'zlib')]
MIDI_JOB_ENV = {
    'MIDI_SOURCE': '${{ github.workspace }}/pure-midi',
    'MIDI_PREFIX': '${{ github.workspace }}/pure/build/windows-clang64-prefix',
    'MIDI_RUNTIME_PATH': '${{ github.workspace }}/pure/build/windows-clang64-prefix/bin;C:/msys64/clang64/bin;C:/msys64/usr/bin;C:/Windows/System32;C:/Windows',
}
MIDI_ENV = {
    'MIDI_BUILD': '${{ runner.temp }}/pm8',
    'MIDI_STAGE': '${{ runner.temp }}/pm8/package',
    'MIDI_DIST_ROOT': '${{ runner.temp }}/ms8',
    'PATH': '${{ env.MIDI_RUNTIME_PATH }}',
    'PURELIB': '', 'PURE_INCLUDE': '', 'PURE_LIBRARY': '',
}
MIDI_INPUTS = {
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
    'PURE_HEADER': '$env:MIDI_PREFIX/include/pure/runtime.h',
    'PURE_GLOB_HEADER': '$env:MIDI_PREFIX/include/glob.h',
    'PURE_IMPORT_LIBRARY': '$env:MIDI_PREFIX/lib/libpure.dll.a',
    'PURE_RUNTIME_DLL': '$env:MIDI_PREFIX/bin/libpure.dll',
    'PURE_EXECUTABLE': '$env:MIDI_PREFIX/bin/pure.exe',
    'PORTMIDI_HEADER': 'C:/msys64/clang64/include/portmidi.h',
    'PORTTIME_HEADER': 'C:/msys64/clang64/include/porttime.h',
    'PORTMIDI_IMPORT_LIBRARY': 'C:/msys64/clang64/lib/libportmidi.dll.a',
    'PORTMIDI_RUNTIME_DLL': 'C:/msys64/clang64/bin/libportmidi.dll',
    'GMP_HEADER': 'C:/msys64/clang64/include/gmp.h',
    'MPFR_HEADER': 'C:/msys64/clang64/include/mpfr.h',
    'PURE_MIDI_WINDOWS_HEADER': 'C:/msys64/clang64/include/windows.h',
    'PURE_MIDI_WINDOWS_SYSTEM_DIRECTORY': 'C:/Windows/System32',
}
MIDI_RUNTIME = [
    f'{name}|$env:MIDI_PREFIX/bin/{name}' for name in (
        'pure.exe', 'libpure.dll', 'libc++.dll', 'libgmp-10.dll', 'libiconv-2.dll',
        'libmpfr-6.dll', 'libpcre-1.dll', 'libpcreposix-0.dll', 'libreadline8.dll',
        'libtermcap-0.dll', 'libwinpthread-1.dll', 'libzstd.dll', 'zlib1.dll')
] + ['libportmidi.dll|C:/msys64/clang64/bin/libportmidi.dll']
MIDI_INPUTS['PURE_MIDI_RUNTIME_SOURCES'] = ';'.join(MIDI_RUNTIME)
MIDI_NORMAL = '& $env:CMAKE_EXE --build "$env:MIDI_BUILD" --parallel 4'
MIDI_PE = '& $env:CMAKE_EXE --build "$env:MIDI_BUILD" --target verify-windows-dependencies --parallel 4'
MIDI_TEST = ('& $env:CTEST_EXE --test-dir "$env:MIDI_BUILD" -L "^no-hardware$" '
             '-LE "^hardware$" --output-on-failure --no-tests=error')
MIDI_INSTALL = '& $env:CMAKE_EXE --install "$env:MIDI_BUILD" --prefix "$env:MIDI_STAGE" --component'
MIDI_VERIFY = ('& $env:CMAKE_EXE "-DMIDI_INSTALL_CONTEXT=$env:MIDI_BUILD/windows-install-context.cmake" '
               '"-DSTAGE_PREFIX=$env:MIDI_STAGE" -P "$env:MIDI_SOURCE/cmake/VerifyInstalledPackage.cmake"')
MIDI_DIST = ('& C:/msys64/clang64/bin/mingw32-make.exe -C "$env:MIDI_SOURCE" distcheck '
             'DLL=.dll CMAKE=C:/msys64/clang64/bin/cmake.exe CLANG64_PREFIX=C:/msys64/clang64 '
             '"PURE_PREFIX=$env:MIDI_PREFIX" "DIST_ROOT=$env:MIDI_DIST_ROOT" '
             '"DIST_DIR=$env:MIDI_DIST_ROOT" SHELL=C:/msys64/usr/bin/sh.exe')
MIDI_DIST_DIRECTORY = '& $env:CMAKE_EXE -E make_directory "$env:MIDI_DIST_ROOT"'
MIDI_FAILURE = "if ($LASTEXITCODE -ne 0) { throw 'MIDI native command failed' }"


def midi_step(document, index):
    return next(step for step in document['jobs']['windows-pure-core']['steps']
                if step.get('name') == MIDI_NAMES[index])


def midi_candidate():
    document = candidate()  # Preserve independent unrelated audio/ODBC controls.
    core = document['jobs']['windows-pure-core']
    core['env'].update(MIDI_JOB_ENV)
    for event in ('push', 'pull_request'):
        paths = document['on'][event]['paths']
        paths.extend(path for path in MIDI_PATHS if path not in paths)
    steps = core['steps']
    prereq = next(s for s in steps if s.get('name') == 'Install the CLANG64 build prerequisites')
    packages = prereq['with']['install'].split()
    packages.extend(p for p in MIDI_PACKAGES if p not in packages)
    prereq['with']['install'] = ' '.join(packages)
    def run(*lines):
        return "$ErrorActionPreference = 'Stop'\n" + ''.join(
            line + '\n' + (MIDI_FAILURE + '\n' if line.startswith('& ') else '')
            for line in lines)
    config = '& $env:CMAKE_EXE -S "$env:MIDI_SOURCE" -B "$env:MIDI_BUILD" -G Ninja '
    config += ' '.join(f'"-D{k}={v}"' for k, v in MIDI_INPUTS.items())
    commands = [
        run("if ($env:MIDI_BUILD.Length -gt 32) { throw 'Short MIDI root required' }",
            "if (Test-Path -LiteralPath $env:MIDI_BUILD) { throw 'Fresh MIDI root required' }", config),
        run(MIDI_NORMAL, MIDI_PE), run(MIDI_TEST),
        run("if (Test-Path -LiteralPath $env:MIDI_STAGE) { throw 'Fresh MIDI stage required' }",
            '& $env:CMAKE_EXE -E copy_directory "$env:MIDI_PREFIX" "$env:MIDI_STAGE"',
            MIDI_INSTALL+' runtime', MIDI_INSTALL+' documentation', MIDI_VERIFY),
        run(MIDI_DIST_DIRECTORY, MIDI_DIST),
    ]
    steps[:] = [s for s in steps if s.get('name') not in MIDI_NAMES]
    at = next(i for i, s in enumerate(steps) if s.get('name') == 'Install and validate the portable runtime') + 1
    steps[at:at] = [dict(name=n, shell='pwsh', env=copy.deepcopy(MIDI_ENV), run=r)
                   for n, r in zip(MIDI_NAMES, commands)]
    return document


def midi_mutations():
    cases = []
    def mutate(label, operation):
        document = midi_candidate()
        operation(document)
        cases.append((label, document))
    def replace(label, index, old, new):
        def operation(d):
            s = midi_step(d, index)
            assert old in s['run'], (label, old)
            s['run'] = s['run'].replace(old, new, 1)
        mutate(label, operation)
    for event, branches in [('push', ['master', 'todo/**', 'codex/**']), ('pull_request', ['master'])]:
        for path in MIDI_PATHS:
            mutate(f'{event}:path:{path}', lambda d, e=event, p=path: d['on'][e]['paths'].remove(p))
        for branch in branches:
            mutate(f'{event}:branch:{branch}', lambda d, e=event, b=branch: d['on'][e]['branches'].remove(b))
        for field, value in [('paths-ignore', ['pure-midi/**']), ('branches-ignore', ['master']),
                             ('paths', 'pure-midi/**'), ('branches', 'master')]:
            mutate(f'{event}:{field}', lambda d, e=event, f=field, v=value: d['on'][e].update({f:v}))
        for field in ('paths', 'branches'):
            mutate(f'{event}:negative:{field}', lambda d, e=event, f=field: d['on'][e][f].append('!*'))
        mutate(f'{event}:extra-branch', lambda d, e=event: d['on'][e]['branches'].append('unreviewed'))
    def prerequisite(d):
        return next(s for s in d['jobs']['windows-pure-core']['steps']
                    if s.get('name') == 'Install the CLANG64 build prerequisites')
    for package in MIDI_PACKAGES:
        mutate('package:'+package, lambda d, p=package: prerequisite(d)['with'].update(
            install=' '.join(x for x in prerequisite(d)['with']['install'].split() if x != p)))
    for field, value in [('uses', 'msys2/setup-msys2@v1'), ('if', 'false'), ('continue-on-error', 'true')]:
        mutate('prereq:'+field, lambda d, f=field, v=value: prerequisite(d).update({f:v}))
    mutate('prereq:msystem', lambda d: prerequisite(d)['with'].update(msystem='MINGW64'))
    for key in ('CMAKE_EXE', 'CTEST_EXE', 'INSTALL_PREFIX', *MIDI_JOB_ENV):
        mutate('job-env:'+key, lambda d, k=key: d['jobs']['windows-pure-core']['env'].update({k:'C:/wrong'}))
    for context in ('runner.temp', "runner['temp']", 'env.PATH', 'steps.setup.outputs.path', 'job.status'):
        mutate('job-unavailable:'+context, lambda d, c=context: d['jobs']['windows-pure-core']['env'].update(
            EXTRA='${{ '+c+' }}'))
        mutate('workflow-unavailable:'+context, lambda d, c=context: d.update(env={'EXTRA':'${{ '+c+' }}'}))
    for field, value in [('runs-on', 'windows-latest'), ('if', 'false'), ('continue-on-error', 'true')]:
        mutate('job:'+field, lambda d, f=field, v=value: d['jobs']['windows-pure-core'].update({f:v}))
    for scope in ('workflow', 'job'):
        for key, value in [('shell', 'bash'), ('working-directory', 'pure-midi'),
                           ('working-directory', '${{ runner.temp }}')]:
            mutate(f'default:{scope}:{key}:{value}', lambda d, s=scope, k=key, v=value:
                (d if s=='workflow' else d['jobs']['windows-pure-core']).update(defaults={'run':{k:v}}))
    for index in range(5):
        mutate(f'missing-step:{index}', lambda d, i=index: d['jobs']['windows-pure-core']['steps'].remove(midi_step(d,i)))
        mutate(f'duplicate-step:{index}', lambda d, i=index: d['jobs']['windows-pure-core']['steps'].append(copy.deepcopy(midi_step(d,i))))
        for field, value in [('shell','bash'), ('working-directory','pure-midi'),
                             ('if','false'), ('continue-on-error','true')]:
            mutate(f'step:{index}:{field}', lambda d, i=index, f=field, v=value: midi_step(d,i).update({f:v}))
        for key in MIDI_ENV:
            mutate(f'env-missing:{index}:{key}', lambda d, i=index, k=key: midi_step(d,i)['env'].pop(k))
            mutate(f'env-poison:{index}:{key}', lambda d, i=index, k=key: midi_step(d,i)['env'].update({k:'${{ env.PATH }}'}))
        mutate(f'env-extra:{index}', lambda d, i=index: midi_step(d,i)['env'].update(CMAKE_EXE='C:/wrong.exe'))
        for old,new,label in [("$ErrorActionPreference = 'Stop'", "$ErrorActionPreference = 'Continue'",'errors'),
                              ("$ErrorActionPreference = 'Stop'",'exit 0','early-exit'),
                              ('& ','if ($false) { & ','conditional')]:
            replace(f'{label}:{index}',index,old,new)
        lines = midi_step(midi_candidate(), index)['run'].splitlines()
        for call in [n for n, line in enumerate(lines) if line.startswith('& ')]:
            def drop_guard(d, i=index, n=call):
                altered = midi_step(d,i)['run'].splitlines()
                del altered[n+1]
                midi_step(d,i)['run'] = '\n'.join(altered)
            mutate(f'failure-guard:{index}:{call}', drop_guard)
    ordered = ['Install the CLANG64 build prerequisites', 'Install and validate the portable runtime',
               *MIDI_NAMES, 'Validate non-Linux workflow semantics']
    for first, second in zip(ordered, ordered[1:]):
        def swap(d, a=first, b=second):
            steps = d['jobs']['windows-pure-core']['steps']
            x, y = (next(i for i,s in enumerate(steps) if s.get('name')==n) for n in (a,b))
            steps[x], steps[y] = steps[y], steps[x]
        mutate(f'order:{first}:{second}', swap)
    for key, value in MIDI_INPUTS.items():
        argument = f'"-D{key}={value}"'
        replace('input-missing:'+key, 0, argument, '')
        replace('input-wrong:'+key, 0, argument, f'"-D{key}=OFF"')
        replace('input-duplicate:'+key, 0, argument, argument+' '+argument)
    replace('input-override', 0, '-G Ninja', '-G Ninja -DCMAKE_SUPPRESS_REGENERATION=ON')
    for row in MIDI_RUNTIME:
        replace('runtime-missing:'+row.split('|')[0], 0, ';'.join(MIDI_RUNTIME),
                ';'.join(r for r in MIDI_RUNTIME if r != row))
        replace('runtime-origin:'+row.split('|')[0], 0, row, row.split('|')[0]+'|C:/wrong/file.dll')
    for index in (0, 3):
        for line in midi_step(midi_candidate(), index)['run'].splitlines():
            if line.startswith('if ') and '$LASTEXITCODE' not in line:
                replace(f'preflight:{index}:{line}', index, line, '')
    for old,new,label in [
        (MIDI_NORMAL, MIDI_PE, 'pe-for-normal'), (MIDI_PE,MIDI_NORMAL,'normal-for-pe'),
        (MIDI_NORMAL,MIDI_NORMAL+'\n'+MIDI_FAILURE+'\n'+MIDI_NORMAL,'duplicate-normal'),
        ('--parallel 4','--parallel 2','two-workers'),
        ('--parallel 4','--parallel 2 --parallel 4','duplicate-workers'),
        ('--parallel 4','--parallel','implicit-workers'),
        ('--parallel 4','--parallel 4 --target pmlib','partial-build'),
        ('--target verify-windows-dependencies','--target pmlib','wrong-pe-target')]:
        replace('build:'+label,1,old,new)
    replace('build:pe-workers',1,MIDI_PE,MIDI_PE.replace('--parallel 4','--parallel 1'))
    for old,new in [('-L "^no-hardware$"',''), ('^no-hardware$','^absent$'),
                    ('-LE "^hardware$"',''), ('--no-tests=error',''),
                    ('--output-on-failure','--output-on-failure -E install'),
                    ('--no-tests=error','--no-tests=ignore')]:
        replace('test:'+old+':'+new,2,old,new)
    for old,new in [(' runtime',' documentation'), (' documentation',' runtime'),
                    ('-E copy_directory','-E make_directory'),
                    ('windows-install-context.cmake','wrong-context.cmake'),
                    ('-DSTAGE_PREFIX=$env:MIDI_STAGE','-DSTAGE_PREFIX=$env:MIDI_PREFIX'),
                    ('VerifyInstalledPackage.cmake','VerifyWindowsDependencies.cmake')]:
        replace('install:'+old,3,old,new)
    for atom in MIDI_DIST.split()[1:]:
        replace('dist-missing:'+atom,4,atom,'')
    for old,new in [('distcheck','dist'), ('DLL=.dll','DLL=.so'),
                    ('C:/msys64/clang64/bin/mingw32-make.exe','make'),
                    ('CLANG64_PREFIX=C:/msys64/clang64','CLANG64_PREFIX=C:/other')]:
        replace('dist-wrong:'+old,4,old,new)
    for index in range(5):
        script = midi_step(midi_candidate(), index)['run']
        for ref in sorted(set(re.findall(r'\$env:[A-Z_]+', script))):
            if '"'+ref+'"' in script:
                replace(f'literal:{index}:{ref}', index, '"'+ref+'"', "'"+ref+"'")
        mutate('appended-exit:'+str(index), lambda d, i=index: midi_step(d,i).update(
            run=midi_step(d,i)['run']+'exit 0\n'))
    return cases


class MidiWorkflowMutationTests(unittest.TestCase):
    def test_distcheck_requires_directory_creation(self):
        for mutation in ('missing', 'wrong-root', 'unchecked', 'reordered'):
            d = midi_candidate()
            s = midi_step(d,4)
            pair = MIDI_DIST_DIRECTORY+'\n'+MIDI_FAILURE+'\n'
            if mutation == 'missing':
                s['run'] = s['run'].replace(pair,'')
            elif mutation == 'wrong-root':
                s['run'] = s['run'].replace(MIDI_DIST_DIRECTORY,
                    MIDI_DIST_DIRECTORY.replace('$env:MIDI_DIST_ROOT','$env:MIDI_BUILD'))
            elif mutation == 'unchecked':
                s['run'] = s['run'].replace(pair,MIDI_DIST_DIRECTORY+'\n')
            else:
                s['run'] = s['run'].replace(pair,'')+pair
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                validate_data(d)
        print('MIDI_DIST_DIRECTORY_CASES negatives=4')

    def test_rejects_bare_unavailable_context_references(self):
        cases = 0
        for scope in ('workflow', 'job'):
            for context in ('runner', 'env', 'steps', 'job'):
                for expression in (context, f'toJSON({context})'):
                    d = midi_candidate()
                    target = d if scope == 'workflow' else d['jobs']['windows-pure-core']
                    target.setdefault('env', {})['EXTRA'] = '${{ '+expression+' }}'
                    with self.subTest(scope=scope, expression=expression), self.assertRaises(AssertionError):
                        validate_data(d)
                    cases += 1
        print(f'MIDI_CONTEXT_CASES negatives={cases}')

    def test_actual_workflow_has_midi_gate(self):
        names = [s.get('name') for s in data_workflow()['jobs']['windows-pure-core']['steps']]
        self.assertTrue(set(MIDI_NAMES) <= set(names), 'old workflow omits the mandatory pure-midi gate')

    def test_independent_pristine_and_formatting_variants(self):
        validate_data(midi_candidate())
        for variant in ('reordered', 'continued', 'inherited-job', 'inherited-workflow', 'quoted', 'expression'):
            d = midi_candidate()
            if variant == 'reordered':
                s = midi_step(d,0)
                s['run'] = s['run'].replace(';'.join(MIDI_RUNTIME), ';'.join(reversed(MIDI_RUNTIME)))
            elif variant == 'continued':
                for i in range(5):
                    s = midi_step(d,i)
                    s['run'] = '# harmless comment\n'+s['run'].replace(' --', ' `\n  --')
            elif variant.startswith('inherited'):
                scope = d if variant.endswith('workflow') else d['jobs']['windows-pure-core']
                scope['defaults'] = {'run':{'shell':'pwsh','working-directory':'pure'}}
                for i in range(5):
                    midi_step(d,i).pop('shell')
            elif variant == 'quoted':
                s = midi_step(d,2)
                s['run'] = s['run'].replace('"^no-hardware$"', "'^no-hardware$'")
                s['run'] = s['run'].replace('$env:CTEST_EXE', '"$env:CTEST_EXE"')
                s['run'] = s['run'].replace('--no-tests=error',
                    '--no-tests=error 2>&1 | Tee-Object -FilePath "$env:LOG_DIR/midi.log"')
            else:
                d['jobs']['windows-pure-core']['env']['EXTRA'] = "${{ format('{0}', toJSON(github)) }}"
            validate_data(d)
        print('MIDI_WORKFLOW_PRISTINE independent=7')

    def test_rejects_midi_semantic_mutations(self):
        cases = midi_mutations()
        for label, document in cases:
            with self.subTest(mutation=label), self.assertRaises(AssertionError):
                validate_data(document)
        print(f'MIDI_WORKFLOW_CASES negatives={len(cases)}')


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
