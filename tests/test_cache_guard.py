import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('guard', Path(__file__).resolve().parents[1] / 'bin/cache_guard.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class CacheGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        (self.source / 'main.nf').write_text('workflow {}')
        self.read = self.root / 'read.fastq'
        self.read.write_text('AAAA')
        self.manifest = self.root / 'manifest.csv'
        self.manifest.write_text(f'id,forward\ns1,{self.read}\n')
        out = self.root / 'output'
        self.params = dict(outputDir=str(out), storeDir=str(out / 'keys'), q2cacheDir=str(out / 'caches/main'), q2TemporaryCachesDir=str(out / 'caches'), inputReadsManifest=str(self.manifest), runId='test')

    def begin(self):
        guard.guard(self.params, self.source)

    def test_identical_resume_and_resource_changes(self):
        self.begin()
        self.params.update(timestamp='new', overall_cpu_scale=4)
        self.begin()

    def test_replaced_read_same_path(self):
        self.begin()
        self.read.write_text('CCCC')
        with self.assertRaisesRegex(ValueError, 'Input bytes'):
            self.begin()

    def test_changed_manifest_options_or_source(self):
        for target in ['manifest', 'option', 'source']:
            with self.subTest(target=target):
                state = Path(self.params['outputDir']) / '.moshpit-cache-identity.json'
                if state.exists(): state.unlink()
                self.begin()
                if target == 'manifest': self.manifest.write_text(self.manifest.read_text() + f's2,{self.read}\n')
                if target == 'option': self.params['fastp'] = {'deduplicate': True}
                if target == 'source': (self.source / 'main.nf').write_text('workflow { changed() }')
                with self.assertRaisesRegex(ValueError, 'Input bytes'): self.begin()

    def make_artifact(self, root, name, uuid):
        key = root / 'keys' / name
        key.parent.mkdir(parents=True, exist_ok=True)
        key.write_text(f'data: {uuid}\n')
        data = root / 'data' / uuid / 'data'
        data.mkdir(parents=True, exist_ok=True)
        (data / 'seqs.fastq').write_text('AAAA')
        return key

    def test_completed_marker_needs_real_artifact(self):
        self.begin()
        key = self.make_artifact(Path(self.params['q2cacheDir']), 'reads', 'uuid1')
        guard.guard(self.params, self.source, finish=True)
        self.begin()
        key.unlink()
        with self.assertRaisesRegex(ValueError, 'missing'): self.begin()

    def test_missing_artifact_data_rejected(self):
        self.begin()
        key = self.make_artifact(Path(self.params['q2cacheDir']), 'reads', 'uuid1')
        guard.guard(self.params, self.source, finish=True)
        (key.parent.parent / 'data/uuid1/data/seqs.fastq').unlink()
        with self.assertRaisesRegex(ValueError, 'no artifact data'): self.begin()

    def test_cached_input_uuid_change(self):
        root = self.root / 'input-cache'
        key = self.make_artifact(root, 'reads', 'uuid1')
        self.params.update(inputReads='reads', inputReadsCache=str(root))
        self.begin()
        self.make_artifact(root, 'reads', 'uuid2')
        with self.assertRaisesRegex(ValueError, 'Input bytes'): self.begin()

    def test_simulation_profile_is_a_value(self):
        genomes = self.root / 'genomes'
        genomes.mkdir()
        (genomes / 'genome.fasta').write_text('>g\nACGT\n')
        samples = self.root / 'samples.csv'
        samples.write_text(f'id,profile,readCount,readLength,genomesPath\ns1,lognormal,10,100,{genomes}\n')
        self.params['read_simulation'] = {'samples': str(samples)}
        self.begin()
        self.begin()
        (genomes / 'genome.fasta').write_text('>g\nTGCA\n')
        with self.assertRaisesRegex(ValueError, 'Input bytes'): self.begin()

    def test_shared_database_pool_and_unrelated_keys_are_ignored(self):
        database = self.root / 'database'
        self.make_artifact(database, 'db', 'uuid1')
        (database / 'keys/pool').write_text('pool: pool1\n')
        (database / 'keys/unrelated').write_text('data: missing\n')
        self.params['databases'] = {'kraken2': {'cache': str(database), 'key': 'db'}}
        self.begin()
        guard.guard(self.params, self.source, finish=True)
        self.begin()

    def test_nextflow_precreated_trace_directory_is_allowed(self):
        trace = Path(self.params['outputDir']) / 'pipeline_info'
        trace.mkdir(parents=True)
        (trace / 'trace.txt').touch()
        self.params['traceDir'] = str(trace)
        self.begin()

    def test_legacy_outputs_fail(self):
        output = Path(self.params['outputDir'])
        output.mkdir()
        (output / 'old-marker').touch()
        with self.assertRaisesRegex(ValueError, 'legacy markers'): self.begin()
