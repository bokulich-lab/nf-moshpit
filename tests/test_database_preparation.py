"""Run actual database consumers against lightweight QIIME command doubles.

NEXTFLOW=/path/to/nextflow python3 -m unittest discover -s tests -p test_database_preparation.py
No databases or biological tools are downloaded by these tests.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NEXTFLOW = os.environ.get("NEXTFLOW", shutil.which("nextflow"))


@unittest.skipUnless(NEXTFLOW, "Nextflow is required (set NEXTFLOW)")
class DatabasePreparationTests(unittest.TestCase):
    def test_cold_and_populated_cache_broadcast_to_all_consumers(self):
        for populated in (False, True):
            with self.subTest(populated=populated), tempfile.TemporaryDirectory() as td:
                work = Path(td)
                cache = work / "cache"
                if populated:
                    (cache / "keys").mkdir(parents=True)
                    (cache / "data/artifact").mkdir(parents=True)
                    (cache / "keys/db").write_text("data: artifact\n")
                    (cache / "data/artifact/index").write_bytes(b"database")
                (work / "input").touch()
                (work / "bin").mkdir()
                qiime = work / "bin/qiime"
                qiime.write_text("#!/bin/sh\nexit 0\n")
                qiime.chmod(0o755)
                (work / "test.config").write_text(f'''
includeConfig '{ROOT}/conf/defaults.config'
params {{
    q2TemporaryCachesDir = '{work}/sample-caches'
    runId = 'fixture'
    databases.kraken2 = [cache: '{cache}', key: 'db']
    databases.kaiju = [cache: '{cache}', key: 'db']
    databases.eggnogOrthologs = [cache: '{cache}', key: 'db']
    databases.eggnogAnnotations = [cache: '{cache}', key: 'db']
}}
process {{
    cpus = 1
    maxRetries = 0
}}
trace {{
    enabled = true
    file = '{work}/trace.tsv'
    fields = 'name,status,memory'
}}
''')
                (work / "main.nf").write_text(f'''
include {{ prepareDatabase }} from '{ROOT}/modules/utils'
include {{ CLASSIFY_KRAKEN2; CLASSIFY_KAIJU }} from '{ROOT}/modules/taxonomic_classification'
include {{ SEARCH_ORTHOLOGS_EGGNOG; ANNOTATE_EGGNOG }} from '{ROOT}/modules/functional_annotation'

process PREPARE {{
    output:
    path 'db', emit: ready
    script:
    """
    sleep 0.2
    mkdir -p '{cache}/keys' '{cache}/data/artifact'
    printf 'data: artifact\\n' > '{cache}/keys/db'
    printf database > '{cache}/data/artifact/index'
    touch db
    """
}}
workflow {{
    prepared = PREPARE().ready.map {{ marker ->
        prepareDatabase(marker, params.databases.kraken2, true)
    }}.first()
    disk = prepared.map {{ marker, ignored ->
        prepareDatabase(marker, params.databases.eggnogAnnotations, false)
    }}.first()
    reads = Channel.of(tuple('one', file('{work}/input')), tuple('two', file('{work}/input')))
    CLASSIFY_KRAKEN2(reads, prepared, 'reads')
    CLASSIFY_KAIJU(reads, prepared, 'reads')
    SEARCH_ORTHOLOGS_EGGNOG(reads, prepared, 'contigs')
    ANNOTATE_EGGNOG(reads, disk, 'contigs')
}}
''')
                result = subprocess.run(
                    [NEXTFLOW, "run", "main.nf", "-c", "test.config", "-ansi-log", "false"],
                    cwd=work, env={**os.environ, "NXF_OFFLINE": "true"},
                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                )
                self.assertEqual(result.returncode, 0, result.stdout)
                rows = [line.split("\t") for line in (work / "trace.tsv").read_text().splitlines()[1:]]
                consumers = [r for r in rows if not r[0].startswith("PREPARE")]
                self.assertEqual(len(consumers), 8, rows)
                for name, status, memory in consumers:
                    self.assertEqual(status, "COMPLETED")
                    self.assertEqual(memory, "2 GB" if name.startswith("ANNOTATE_EGGNOG") else "1 GB")

    def test_size_rounding_and_disk_mode(self):
        with tempfile.TemporaryDirectory() as td:
            work = Path(td)
            (work / "keys").mkdir()
            (work / "data/artifact").mkdir(parents=True)
            (work / "keys/db").write_text('data: "artifact"\n')
            with (work / "data/artifact/index").open("wb") as handle:
                handle.truncate(1024 ** 3)  # Sparse 1 GiB fixture, no large allocation.
            (work / "main.nf").write_text(f"""
include {{ prepareDatabase }} from '{ROOT}/modules/utils'
workflow {{
    assert prepareDatabase('marker', [cache: '{work}', key: 'db'], true) == ['marker', 2]
    assert prepareDatabase('marker', [cache: '{work}', key: 'db'], false) == ['marker', 2]
}}
""")
            result = subprocess.run([NEXTFLOW, "run", "main.nf", "-ansi-log", "false"],
                                    cwd=work, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    env={**os.environ, "NXF_OFFLINE": "true"})
            self.assertEqual(result.returncode, 0, result.stdout)

    def test_missing_cache_data_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            work = Path(td)
            (work / "keys").mkdir()
            (work / "keys/db").write_text("data: missing\n")
            (work / "main.nf").write_text(f'''
include {{ prepareDatabase }} from '{ROOT}/modules/utils'
workflow {{
    prepareDatabase('marker', [cache: '{work}', key: 'db'], true)
}}
''')
            result = subprocess.run([NEXTFLOW, "run", "main.nf", "-ansi-log", "false"],
                                    cwd=work, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    env={**os.environ, "NXF_OFFLINE": "true"})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Cache artifact data directory does not exist", result.stdout)


if __name__ == "__main__":
    unittest.main()
