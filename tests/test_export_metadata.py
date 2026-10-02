"""Check typed metadata round-trips and native provenance using real QIIME data."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from zipfile import ZipFile

os.environ['RACHISTEST'] = '1'
os.environ['QIIMETEST'] = '1'
ROOT = Path(__file__).resolve().parents[1]
try:
    import pandas as pd
    from qiime2 import Artifact, Cache, Metadata
    from qiime2.core.testing.util import get_dummy_plugin
    from qiime2.sdk import PluginManager
    from q2_types.plugin_setup import plugin as types_plugin
except ImportError:
    Artifact = None


def ancestors(path):
    with ZipFile(path) as archive:
        return {name.split('/')[3] for name in archive.namelist()
                if '/provenance/artifacts/' in name}


@unittest.skipUnless(Artifact, 'QIIME 2 and q2-types are required for metadata checks')
class MetadataExportTests(unittest.TestCase):
    def test_typed_values_selection_archive_and_detached_provenance(self):
        manager = PluginManager()
        if types_plugin.name not in manager.plugins:
            manager.add_plugin(types_plugin, project_name='q2-types')
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            cache = Cache(base / 'cache')
            with cache:
                source = Artifact.import_data('ImmutableMetadata', Metadata(pd.DataFrame(
                    {'Taxon': ['Bacteria', 'Archaea'], 'Confidence': [0.8, 0.4]},
                    index=pd.Index(['mag-A', 'mag-B'], name='Feature ID'))))
                cache.save(source, 'metadata')
                sys.path.insert(0, str(ROOT / 'bin'))
                try:
                    spec = importlib.util.spec_from_file_location('export_metadata', ROOT / 'bin/export_metadata.py')
                    module = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(module)
                finally:
                    sys.path.pop(0)
                record = module.export_metadata(cache.path, 'metadata', base / 'output',
                                                base / 'published', 'sample-A', 'QC')
                original = source.view(Metadata)
                detached = Metadata.load(str(base / 'output/metadata.tsv'))
                self.assertTrue(original.to_dataframe().equals(detached.to_dataframe()))
                self.assertEqual(original.columns, detached.columns)
                self.assertFalse(detached.artifacts)
                self.assertEqual(original.get_ids('Confidence >= 0.5'), {'mag-A'})
                self.assertEqual(original.get_ids('Confidence >= 0.5'),
                                 detached.get_ids('Confidence >= 0.5'))
                self.assertEqual(record['source_uuid'], str(source.uuid))
                self.assertEqual(record['column_types']['Confidence'], 'numeric')
                archive = Artifact.load(str(base / 'output/metadata.metadata-source.qza'))
                self.assertEqual(archive.uuid, source.uuid)
                archive.validate()
                # Passing the saved TSV removes the metadata source's UUID from ancestry.
                sample = Artifact.import_data('IntSequence1', [1, 2, 3])
                action = get_dummy_plugin().methods['identity_with_metadata']
                native = action(sample, original)[0]
                lean = action(sample, detached)[0]
                native_path = native.save(str(base / 'native.qza'))
                lean_path = lean.save(str(base / 'lean.qza'))
                self.assertIn(str(source.uuid), ancestors(native_path))
                self.assertNotIn(str(source.uuid), ancestors(lean_path))
                self.assertIn(str(sample.uuid), ancestors(lean_path))
                self.assertEqual(native.view(list), lean.view(list))

    @unittest.skipUnless(os.environ.get('NEXTFLOW') or shutil.which('nextflow'),
                         'Nextflow is required for the read-count routing check')
    def test_read_count_export_and_sample_filter_routing(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            tools = base / 'bin'
            tools.mkdir()
            (tools / 'qiime').write_text('''#!%s
import sys
from pathlib import Path
from qiime2 import Metadata
args = sys.argv[1:]
assert args[:2] == ['demux', 'filter-samples'], args
metadata_path = args[args.index('--m-metadata-file') + 1]
sample = Path(args[args.index('--i-demux') + 1].split(':')[0]).name
assert ':' not in metadata_path, metadata_path
metadata = Metadata.load(metadata_path)
assert metadata.to_dataframe().loc['0', 'sample'] == sample
''' % sys.executable)
            (tools / 'qiime').chmod(0o755)
            counts, reads = [], []
            for sample in ['B', 'A']:
                cache = Cache(base / 'caches' / sample)
                with cache:
                    cache.save(Artifact.import_data('Mapping', {'sample': sample}), f'counts_{sample}')
                for key, destination in [(f'counts_{sample}', counts), (f'reads_{sample}', reads)]:
                    (base / key).touch()
                    destination.append(f"tuple('{sample}', file('{base / key}'))")
            workflow = base / 'test.nf'
            workflow.write_text(f"""
include {{ EXPORT_ARTIFACT_METADATA as EXPORT_READ_COUNT_METADATA }} from '{ROOT}/modules/provenance'
include {{ FILTER_SAMPLES }} from '{ROOT}/modules/data_prep'
workflow {{
    counts = Channel.of({', '.join(counts)})
    reads = Channel.of({', '.join(reads)})
    metadata = EXPORT_READ_COUNT_METADATA(counts.map {{ id, key -> tuple(id, 'read_counts', key) }}).metadata
        .map {{ id, _context, tsv -> tuple(id, tsv) }}
    FILTER_SAMPLES(reads.combine(metadata, by: 0), "'1=1'", false)
}}
""")
            (base / 'nextflow.config').write_text(f"""
params.weblog = [enabled: false, url: '', basicToken: '']
includeConfig '{ROOT}/conf/defaults.config'
params.runId = 'test'
params.publishDir = '{base}/results'
params.storeDir = '{base}/keys'
params.outputDir = '{base}/results'
params.q2TemporaryCachesDir = '{base}/caches'
params.metadataProvenance = 'tsv'
process.memory = '100 MB'
process.maxRetries = 0
""")
            env = dict(os.environ, PATH=f'{tools}:{ROOT}/bin:{os.environ["PATH"]}',
                       NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1')
            nextflow = os.environ.get('NEXTFLOW', shutil.which('nextflow'))
            result = subprocess.run([nextflow, 'run', str(workflow)], cwd=base, env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for sample in ['A', 'B']:
                self.assertTrue((base / f'keys/test_reads_filtered_tsv_{sample}').exists())
                self.assertTrue((base / f'results/provenance/metadata/counts_{sample}.metadata-source.qza').exists())


if __name__ == '__main__':
    unittest.main()
