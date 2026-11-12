import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get('MOSHPIT_TEST_ROOT', Path(__file__).resolve().parents[1]))
NEXTFLOW = os.environ.get('NEXTFLOW', shutil.which('nextflow'))


class ValidationCase(unittest.TestCase):
    def run_nf(self, params=None, profile='standard', assertions='', extra_config='', conda_exit=0, validate=True):
        if not NEXTFLOW:
            self.skipTest('Nextflow required (set NEXTFLOW)')
        with tempfile.TemporaryDirectory() as td:
            work = Path(td)
            (work / 'manifest.csv').write_text('id,forward\ns1,unused.fastq\n')
            selected = {'runId': 'test', 'outputDir': str(work / 'results'),
                        'inputReadsManifest': str(work / 'manifest.csv'), 'container': 'test:image'}
            selected.update(params or {})
            (work / 'params.json').write_text(json.dumps(selected))
            (work / 'test.config').write_text(f"includeConfig '{ROOT}/nextflow.config'\n" + extra_config)
            (work / 'main.nf').write_text(f"include {{ validateParameters; validateInputTable }} from '{ROOT}/modules/validation'\nworkflow {{\n" + ('validateParameters()\n' if validate else '') + assertions + '\n}\n')
            conda = work / 'conda'
            conda.write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{work}/conda-args"\nexit {conda_exit}\n')
            conda.chmod(0o755)
            result = subprocess.run([NEXTFLOW, 'run', 'main.nf', '-c', 'test.config', '-params-file', 'params.json', '-profile', profile, '-ansi-log', 'false'], cwd=work,
                                    env={**os.environ, 'NXF_OFFLINE': 'true', 'CONDA_EXE': str(conda)},
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            args = work / 'conda-args'
            return result, args.read_text() if args.exists() else ''

    def assert_success(self, *args, **kwargs):
        result, probes = self.run_nf(*args, **kwargs)
        self.assertEqual(result.returncode, 0, result.stdout)
        return probes

    def assert_failure(self, message, *args, **kwargs):
        result, probes = self.run_nf(*args, **kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stdout)
        return probes
