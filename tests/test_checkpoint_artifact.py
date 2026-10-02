"""Run in a QIIME 2 environment; synthetic plugin fixtures exercise real archives."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

os.environ['RACHISTEST'] = '1'
os.environ['QIIMETEST'] = '1'
ROOT = Path(__file__).resolve().parents[1]
try:
    from qiime2 import Artifact, Cache
    from qiime2.core.testing.util import get_dummy_plugin
except ImportError:
    Artifact = None


def ancestors(path):
    with ZipFile(path) as archive:
        return {name.split('/')[3] for name in archive.namelist()
                if '/provenance/artifacts/' in name}


@unittest.skipUnless(Artifact, 'QIIME 2 is required for checkpoint checks')
class CheckpointTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = Cache(self.root / 'cache')
        with self.cache:
            self.original = Artifact.import_data('IntSequence1', [1, 2, 3])
            self.original = get_dummy_plugin().methods['identity_with_optional_metadata'](
                self.original)[0]
            self.cache.save(self.original, 'original')
        spec = importlib.util.spec_from_file_location('checkpoint', ROOT / 'bin/checkpoint_artifact.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def checkpoint(self):
        return self.module.checkpoint(self.cache.path, 'original', 'checkpoint',
                                      self.root / 'outputs', self.root / 'published', 'test')

    def test_payload_archive_link_and_retry(self):
        record = self.checkpoint()
        output = self.root / 'outputs'
        archived = Artifact.load(str(output / 'checkpoint.upstream.qza'))
        fresh = Artifact.load(str(output / 'checkpoint.qza'))
        self.assertEqual(archived.uuid, self.original.uuid)
        self.assertEqual(archived.view(list), fresh.view(list))
        self.assertEqual(archived.type, fresh.type)
        self.assertEqual(archived.format, fresh.format)
        self.assertNotEqual(archived.uuid, fresh.uuid)
        self.assertTrue(ancestors(output / 'checkpoint.upstream.qza'))
        self.assertFalse(ancestors(output / 'checkpoint.qza'))
        self.assertEqual(record['original_uuid'], str(archived.uuid))
        self.assertEqual(record['checkpoint_uuid'], str(fresh.uuid))
        self.assertTrue(record['payload_sha256'])
        self.assertEqual(record, self.checkpoint())
        self.assertEqual(self.cache.load('checkpoint').uuid, fresh.uuid)
        fresh.validate()

    def test_changed_payload_fails_before_cache_publication(self):
        import_data = self.module.Artifact.import_data
        with patch.object(self.module.Artifact, 'import_data',
                          side_effect=lambda *_args, **_kwargs:
                          import_data('IntSequence1', [9, 9, 9])):
            with self.assertRaisesRegex(ValueError, 'payload changed'):
                self.checkpoint()
        self.assertNotIn('checkpoint', self.cache.get_keys())
        self.assertFalse((self.root / 'outputs/checkpoint').exists())

    def test_refuse_overwriting_original_key(self):
        with self.assertRaisesRegex(ValueError, 'new cache key'):
            self.module.checkpoint(self.cache.path, 'original', 'original',
                                   self.root, self.root, 'test')
        self.assertEqual(self.cache.load('original').uuid, self.original.uuid)

    @unittest.skipUnless(os.environ.get('NEXTFLOW') or shutil.which('nextflow'),
                         'Nextflow is required for the checkpoint graph check')
    def test_nextflow_checkpoint_outputs_and_resume(self):
        nextflow = os.environ.get('NEXTFLOW', shutil.which('nextflow'))
        marker = self.root / 'original'
        marker.touch()
        workflow = self.root / 'test.nf'
        workflow.write_text(f"""
include {{ CHECKPOINT_DEREP_MAGS }} from '{ROOT}/modules/provenance'
workflow {{ CHECKPOINT_DEREP_MAGS(Channel.value(file('{marker}'))) }}
""")
        config = self.root / 'nextflow.config'
        config.write_text(f"""
params.outputDir = '{self.root}/results'
params.q2cacheDir = '{self.cache.path}'
params.runId = 'test'
process.memory = '100 MB'
process.maxRetries = 0
""")
        env = dict(os.environ, PATH=f'{ROOT}/bin:{os.environ["PATH"]}',
                   NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1')
        command = [nextflow, 'run', str(workflow)]
        for extra in [[], ['-resume']]:
            result = subprocess.run(command + extra, cwd=self.root, env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            record_file = self.root / 'results/provenance/original_checkpoint_v1.json'
            record = json.loads(record_file.read_text())
            if extra:
                self.assertEqual(record, previous)
            previous = record
        self.assertTrue((self.root / 'results/provenance/original_checkpoint_v1.upstream.qza').exists())


if __name__ == '__main__':
    unittest.main()
