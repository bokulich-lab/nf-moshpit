import unittest
from nf_process_support import ProcessTestCase, NEXTFLOW, ROOT

@unittest.skipUnless(NEXTFLOW, "Set NEXTFLOW to the Nextflow executable")
class CachedReadPartitionTests(ProcessTestCase):
    def test_cached_key_is_a_value(self):
        cache = self.base / 'input-cache'
        (cache / 'keys').mkdir(parents=True)
        (cache / 'keys' / 'not-a-launch-file').write_text('data: test')
        with (self.base / 'nextflow.config').open('a') as out: out.write(f"params.inputReadsCache='{cache}'\n")
        capture = self.run_nf(f"include {{ PARTITION_CACHED_READS }} from '{ROOT}/modules/data_prep'\nworkflow {{ PARTITION_CACHED_READS(Channel.of(tuple('s1', 'not-a-launch-file'))) }}\n")
        self.assertIn(str(cache)+':not-a-launch-file', capture)
