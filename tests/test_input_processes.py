import unittest
from nf_process_support import ProcessTestCase, NEXTFLOW, ROOT

@unittest.skipUnless(NEXTFLOW, "Set NEXTFLOW to the Nextflow executable")
class ReadImportTests(ProcessTestCase):
    def test_single_end_staged_path(self):
        fastq = self.base / 'forward.fastq'
        fastq.write_text('AAAA')
        capture = self.run_nf(f"include {{ IMPORT_READS }} from '{ROOT}/modules/data_prep'\nworkflow {{ IMPORT_READS(Channel.of(tuple('s1', [file('{fastq}')], false))) }}\n")
        self.assertEqual(capture.splitlines()[0], 'sample-id\tabsolute-filepath')
        self.assertEqual(len(capture.splitlines()[1].split('\t')), 2)
        self.assertIn('/forward.fastq', capture)

    def test_paired_same_basename_staged_safely(self):
        mates = []
        for name in ['one', 'two']:
            path = self.base / name / 'reads.fastq'
            path.parent.mkdir()
            path.write_text(name)
            mates.append(str(path))
        capture = self.run_nf(f"include {{ IMPORT_READS }} from '{ROOT}/modules/data_prep'\nworkflow {{ IMPORT_READS(Channel.of(tuple('s1', [file('{mates[0]}'),file('{mates[1]}')], true))) }}\n")
        rows = capture.splitlines()
        self.assertEqual(len(rows[1].split('\t')), 3)
        self.assertNotEqual(*rows[1].split('\t')[1:])

