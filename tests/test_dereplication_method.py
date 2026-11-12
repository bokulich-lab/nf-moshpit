import json
from nf_validation_support import ValidationCase
from nf_process_support import ProcessTestCase, ROOT


class DereplicationMethod(ValidationCase):
    def test_unknown_method_is_rejected(self):
        self.assert_failure('must be sourmash or skani', profile='standard,mags', params={'dereplication': {'method': 'unknown'}})

    def test_skani_conda_plugin(self):
        args = self.assert_success(profile='standard,conda,mags', params={'condaEnv': 'fixture-env', 'dereplication': {'method': 'skani'}})
        self.assertIn('qiime skani --help', args)
        self.assertNotIn('qiime sourmash --help', args)
        self.assert_failure('lacks a working qiime skani', profile='standard,conda,mags', params={'condaEnv': 'fixture-env', 'dereplication': {'method': 'skani'}}, conda_exit=1)

    def test_skani_container_and_options(self):
        base = {'container': None, 'containerAnnotate': 'annotate', 'containerAssembly': 'assembly', 'containerMag': 'mag', 'dereplication': {'method': 'skani'}}
        self.assert_failure('no Skani container', profile='standard,docker,mags', params=base)
        self.assert_success(profile='standard,docker,mags', params={**base, 'containerSkani': 'skani'})
        for options, message in [({'preset': 'invalid'}, 'skani.preset'), ({'markerC': 0}, 'skani.markerC'), ({'markerC': 1.5}, 'skani.markerC')]:
            self.assert_failure(message, profile='standard,mags', params={'dereplication': {'method': 'skani', 'skani': options}})


class DereplicationRouting(ProcessTestCase):
    def run_method(self, method, options=''):
        qiime = self.base / 'bin' / 'qiime'
        qiime.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['CAPTURE'], 'a') as out:
    out.write(json.dumps(sys.argv[1:]) + '\\n')
''')
        (self.base / 'bins').touch()
        (self.base / 'cache').mkdir()
        with (self.base / 'nextflow.config').open('a') as config:
            config.write(f"\nparams.q2cacheDir='{self.base}/cache'\nparams.dereplication.method='{method}'\nparams.dereplication.threshold=0.42\nparams.binning.qc.busco.enabled=false\n{options}\n")
        calls = self.run_nf(f"""include {{ DEREPLICATE }} from '{ROOT}/subworkflows/dereplication'
workflow {{ DEREPLICATE(Channel.value(file('{self.base}/bins')), Channel.value(file('{self.base}/cache'))) }}
""")
        return [json.loads(line) for line in calls.splitlines()]

    def test_skani_route(self):
        calls = self.run_method('skani', 'params.dereplication.skani.median=true\nparams.dereplication.skani.fasterSmall=true\nparams.dereplication.skani.additionalFlags="--p-min-af 20"')
        self.assertEqual([c[:2] for c in calls], [['skani', 'compare-seqs'], ['mag', 'dereplicate-mags']])
        compare, derep = calls
        self.assertEqual(compare[compare.index('--i-genomes')+1], f'{self.base}/cache:bins')
        for flag in ('--p-robust', '--p-median', '--p-faster-small', '--p-threads', '--p-marker-c', '--p-preset', '--p-min-af'):
            self.assertIn(flag, compare)
        matrix = compare[compare.index('--o-distance-matrix')+1]
        self.assertIn('_skani_dist_matrix', matrix)
        self.assertEqual(derep[derep.index('--i-distance-matrix')+1], matrix)
        self.assertEqual(derep[derep.index('--p-threshold')+1], '0.42')

    def test_sourmash_route(self):
        calls = self.run_method('sourmash')
        self.assertEqual([c[:2] for c in calls], [['sourmash', 'compute'], ['sourmash', 'compare'], ['mag', 'dereplicate-mags']])
        matrix = calls[1][calls[1].index('--o-compare-output')+1]
        self.assertIn('_sourmash_dist_matrix', matrix)
        self.assertEqual(calls[2][calls[2].index('--i-distance-matrix')+1], matrix)
