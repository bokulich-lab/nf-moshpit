"""Exercise the real RUN_BINNER graph with lightweight external-command fixtures.

Run with NEXTFLOW=/path/to/nextflow python -m unittest discover -s tests -v.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NEXTFLOW = os.environ.get('NEXTFLOW', shutil.which('nextflow'))


@unittest.skipUnless(NEXTFLOW, 'Nextflow is required for workflow integration checks')
class BuscoWorkflowTests(unittest.TestCase):
    def run_workflow(self, rejected):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            tools = base / 'bin'
            tools.mkdir()
            events = base / 'events.jsonl'
            (tools / 'qiime').write_text('''#!%s
import json, os, sys, time
from pathlib import Path
args = sys.argv[1:]
def option(flag):
    return args[args.index(flag) + 1]
if args[:2] == ['mag', 'filter-mags']:
    metadata = option('--m-metadata-file')
    sample = Path(option('--i-mags').split(':')[0]).name
    assert Path(metadata.split(':')[0]).name == sample, (sample, metadata)
    time.sleep(0.2)
    event = {'kind': 'filtered', 'sample': sample, 'metadata': metadata}
elif args[:2] == ['mag', 'collate-busco-results']:
    event = {'kind': 'collated'}
elif args[:2] == ['tools', 'cache-remove']:
    event = {'kind': 'removed', 'sample': Path(option('--cache')).name}
    existing = [json.loads(line) for line in Path(os.environ['EVENTS']).read_text().splitlines()]
    assert any(e['kind'] == 'collated' for e in existing), existing
    assert {e['sample'] for e in existing if e['kind'] == 'filtered'} == {'A', 'B'}, existing
elif args[:2] == ['tools', 'audit-finished']:
    existing = [json.loads(line) for line in Path(os.environ['EVENTS']).read_text().splitlines()]
    assert len([e for e in existing if e['kind'] == 'removed']) == 4, existing
    event = {'kind': 'finished'}
else:
    event = {'kind': args[1]}
with open(os.environ['EVENTS'], 'a') as handle:
    handle.write(json.dumps(event) + '\\n')
if event['kind'] == 'filtered' and event['sample'] in os.environ['REJECTED'].split(','):
    print('No MAGs remain after filtering')
    sys.exit(1)
''' % sys.executable)
            (tools / 'qiime').chmod(0o755)
            # Only the report renderer imports Python QIIME; the fixture emits its file.
            (tools / 'python').write_text('''#!%s
import re, sys
from pathlib import Path
script = Path(sys.argv[1]).read_text()
Path(re.search(r"viz.save\\('([^']+)'\\)", script)[1]).touch()
''' % sys.executable)
            (tools / 'python').chmod(0o755)
            contigs = []
            maps = []
            for sample in ['B', 'A']:
                for suffix, collection in [('contigs', contigs), ('maps', maps)]:
                    marker = base / f'{sample}_{suffix}'
                    marker.touch()
                    collection.append(f"tuple('{sample}', file('{marker}'))")
            db = base / 'db'
            db.touch()
            cache = base / 'cache'
            cache.mkdir()
            config = base / 'nextflow.config'
            config.write_text(f"""
params.weblog = [enabled: false, url: '', basicToken: '']
includeConfig '{ROOT}/conf/defaults.config'
params.runId = 'test'
params.storeDir = '{base}/keys'
params.publishDir = '{base}/results'
params.q2cacheDir = '{cache}'
params.q2TemporaryCachesDir = '{base}/caches'
params.databases.busco.cache = '{cache}'
params.databases.busco.key = 'db'
params.binning.qc.busco.cleanUp = true
params.binning.qc.filtering.enabled = true
params.binning.qc.busco.lineageDatasets = 'bacteria_odb12,archaea_odb12'
params.binning.qc.busco.selectLineage = 'bacteria_odb12'
process.executor = 'local'
process.memory = '100 MB'
process.cpus = 1
process.maxRetries = 0
""")
            workflow = base / 'test.nf'
            workflow.write_text(f"""
include {{ RUN_BINNER }} from '{ROOT}/subworkflows/run_binner'
process CHECK_FINISHED {{
    input:
    val reports
    script:
    'qiime tools audit-finished'
}}
workflow {{
    RUN_BINNER('metabat2', Channel.of({', '.join(contigs)}),
        Channel.of({', '.join(maps)}), Channel.value(file('{cache}')),
        true, Channel.value(file('{db}')))
    CHECK_FINISHED(RUN_BINNER.out.qzv.toList())
}}
""")
            env = dict(os.environ, PATH=f'{tools}:{os.environ["PATH"]}',
                       EVENTS=str(events), REJECTED=','.join(rejected),
                       NXF_OFFLINE='true', NXF_ANSI_LOG='false')
            result = subprocess.run([NEXTFLOW, '-c', str(config), 'run', str(workflow)],
                                    cwd=base, env=env, capture_output=True, text=True)
            diagnostic = (base / '.nextflow.log').read_text() if result.returncode else ''
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr + diagnostic)
            resumed = subprocess.run([NEXTFLOW, '-c', str(config), 'run', str(workflow), '-resume'],
                                     cwd=base, env=env, capture_output=True, text=True)
            self.assertEqual(resumed.returncode, 0, resumed.stdout + resumed.stderr)
            records = [json.loads(line) for line in events.read_text().splitlines()]
            filtered = [e for e in records if e['kind'] == 'filtered']
            self.assertEqual(len(filtered), 2, 'Resume reran a completed filter')
            self.assertEqual({e['sample'] for e in filtered}, {'A', 'B'})
            self.assertTrue(all('bacteria_odb12' in e['metadata'] for e in filtered))
            self.assertEqual(len([e for e in records if e['kind'] == 'removed']), 4)

    def test_sample_pairing_and_cleanup(self):
        self.run_workflow(['B'])

    def test_cleanup_when_all_filters_reject_mags(self):
        self.run_workflow(['A', 'B'])


if __name__ == '__main__':
    unittest.main()
