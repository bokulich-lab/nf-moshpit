"""Run real Nextflow process interfaces with a QIIME command double."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NEXTFLOW = os.environ.get('NEXTFLOW', shutil.which('nextflow') or '')

class ProcessTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        bindir = self.base / 'bin'
        bindir.mkdir()
        qiime = bindir / 'qiime'
        qiime.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args=sys.argv[1:]
def arg(flag): return args[args.index(flag)+1]
if args[:2] == ['tools','cache-create']:
 pathlib.Path(arg('--cache')).mkdir(parents=True,exist_ok=True)
elif args[:2] == ['tools','cache-import']:
 manifest=pathlib.Path(arg('--input-path')).read_text()
 pathlib.Path(os.environ['CAPTURE']).write_text(manifest)
elif args[:2] == ['demux','filter-samples']:
 pathlib.Path(os.environ['CAPTURE']).write_text(json.dumps(args))
else: sys.exit('unexpected '+repr(args))
''')
        qiime.chmod(0o755)
        self.env = dict(os.environ, PATH=str(bindir)+os.pathsep+os.environ['PATH'], NXF_OFFLINE='true', CAPTURE=str(self.base / 'capture'))
        (self.base / 'nextflow.config').write_text(f"includeConfig '{ROOT}/nextflow.config'\nprocess.memory='1 GB'\nparams.runId='test'\nparams.q2TemporaryCachesDir='{self.base}/cache'\n")

    def run_nf(self, script):
        source = self.base / 'test.nf'
        source.write_text(script)
        result = subprocess.run([NEXTFLOW, 'run', str(source), '-ansi-log', 'false'], cwd=self.base, env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout)
        return (self.base / 'capture').read_text()

