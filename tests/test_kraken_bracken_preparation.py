import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NEXTFLOW = os.environ.get('NEXTFLOW', shutil.which('nextflow') or '')

@unittest.skipUnless(NEXTFLOW, 'Set NEXTFLOW to the Nextflow executable')
class KrakenBrackenTests(unittest.TestCase):
    def test_kraken_only_and_independent_missing_bracken(self):
        for bracken, existing, collection, success in [(False, True, '', True), (False, False, 'standard', True), (True, True, '', False), (True, True, 'standard', True)]:
            with self.subTest(bracken=bracken, existing=existing, collection=collection), tempfile.TemporaryDirectory() as td:
                work = Path(td)
                cache = work / 'cache'
                (cache / 'keys').mkdir(parents=True)
                if existing: (cache / 'keys/kraken').write_text('data: kraken-uuid\n')
                (work / 'bin').mkdir()
                cmd = work / 'bin/qiime'
                cmd.write_text('''#!/usr/bin/env python3
from pathlib import Path
import json,sys
args=sys.argv
Path('called.json').write_text(json.dumps(args))
for flag in ['--o-kraken2-db','--o-bracken-db']:
 value=args[args.index(flag)+1]
 if ':' in value:
  cache,key=value.split(':')
  target=Path(cache)/'keys'/key
  target.parent.mkdir(parents=True,exist_ok=True)
  target.write_text('data: uuid\\n')
 else: Path(value).touch()
''')
                cmd.chmod(0o755)
                (work / 'nextflow.config').write_text(f"""
includeConfig '{ROOT}/conf/defaults.config'
params.taxonomic_classification.enabledFor='reads'
params.taxonomic_classification.bracken.enabled={str(bracken).lower()}
params.databases.kraken2=[cache:'{cache}', key:'kraken', fetchCollection:'{collection}']
params.databases.bracken=[cache:'{cache}' , key:'bracken']
process.maxRetries=0
""")
                (work / 'main.nf').write_text(f"include {{ FETCH_KRAKEN2_DB }} from '{ROOT}/modules/taxonomic_classification'\nworkflow {{ FETCH_KRAKEN2_DB() }}\n")
                result = subprocess.run([NEXTFLOW, 'run', 'main.nf', '-ansi-log', 'false'], cwd=work, env=dict(os.environ,NXF_OFFLINE='true'), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
                self.assertEqual(result.returncode == 0, success, result.stdout)
                if success and bracken: self.assertTrue((cache / 'keys/bracken').is_file())
                if not bracken: self.assertFalse((cache / 'keys/bracken').exists())
                if not success: self.assertIn('Missing Kraken2 or required Bracken artifact', result.stdout)
