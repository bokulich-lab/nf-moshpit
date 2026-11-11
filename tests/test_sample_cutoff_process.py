import unittest
from nf_process_support import ProcessTestCase, NEXTFLOW, ROOT

@unittest.skipUnless(NEXTFLOW, 'Set NEXTFLOW to the Nextflow executable')
class SampleCutoffProcessTests(ProcessTestCase):
    def test_inclusive_minimum_boundary(self):
        command = self.base / 'bin/qiime'
        command.write_text('''#!/usr/bin/env python3
import pathlib,sqlite3,sys
args=sys.argv
query=args[args.index('--p-where')+1]
# The shell removes outer single quotes; evaluate the supplied SQL predicate.
conn=sqlite3.connect(':memory:')
conn.execute('create table samples ("Demultiplexed sequence count" integer)')
conn.execute('insert into samples values (?)',(int(args[args.index('--i-demux')+1].rsplit('_',1)[-1]),))
if not conn.execute('select * from samples where '+query).fetchall():
 print('No filtering requested')
 sys.exit(1)
''')
        for count in [9,10,11]: (self.base / f'reads_{count}').touch()
        (self.base / 'metadata').touch()
        script = f'''include {{ FILTER_SAMPLES }} from '{ROOT}/modules/data_prep'
include {{ sampleReadQuery }} from '{ROOT}/modules/validation'
workflow {{
    data = Channel.of(9,10,11).map {{ n -> tuple("s$n", file("{self.base}/reads_$n"), file('{self.base}/metadata')) }}
    FILTER_SAMPLES(data, sampleReadQuery(10), false).result.map {{ id, key -> id }}.collect().view {{ ids -> "KEPT=" + ids.sort().join(',') }}
}}
'''
        source = self.base / 'test.nf'
        source.write_text(script)
        import subprocess
        result = subprocess.run([NEXTFLOW,'run',str(source),'-ansi-log','false'],cwd=self.base,env=self.env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
        self.assertEqual(result.returncode,0,result.stdout)
        self.assertIn('KEPT=s10,s11',result.stdout)
