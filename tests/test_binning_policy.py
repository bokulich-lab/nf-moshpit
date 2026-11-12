"""Exercise real BINNING orchestration with lightweight binner/QC doubles."""
import shutil
import unittest
from nf_process_support import ProcessTestCase, NEXTFLOW, ROOT
from nf_validation_support import ValidationCase


@unittest.skipUnless(NEXTFLOW, 'Set NEXTFLOW to the Nextflow executable')
class BinningPolicyTests(ProcessTestCase):
    def orchestration(self, das, busco, primary):
        modules = self.base / 'modules'
        subs = self.base / 'subworkflows'
        modules.mkdir()
        subs.mkdir()
        shutil.copy(ROOT / 'modules/binning_policy.nf', modules)
        shutil.copy(ROOT / 'subworkflows/binning.nf', subs)
        # QC doubles record the actual arguments supplied by BINNING.
        outputs = '''
    emit:
        bins = bins
        contig_map = bins
        contig_map_collated = bins
        unbinned_contigs = bins
        busco_results = bins
        bins_collated = bins
        completion = bins
        qzv = bins
'''
        (subs / 'run_binner.nf').write_text('''workflow RUN_BINNER {
    take:
        binner
        contigs
        maps
        q2_cache
        with_busco
        busco_db
    main:
        println "QC:${binner}:${with_busco}"
        bins = contigs.map { id, key -> tuple(id, file("${binner}.key")) }
''' + outputs + '        raw_bins = bins\n}\n')
        (subs / 'binning_qc.nf').write_text('''workflow BINNING_QC {
    take:
        binner
        bins
        contig_map
        unbinned_contigs
        q2_cache
        with_busco
        busco_db
    main:
        println "QC:${binner}:${with_busco}"
''' + outputs + '}\n')
        (modules / 'contig_binning.nf').write_text('''workflow FETCH_BUSCO_DB {
    main:
        db = Channel.value('db')
    emit:
        result = db
}
workflow REFINE_BINS_DAS_TOOL {
    take:
        candidates
    main:
        refined = candidates.map { id, keys, labels, contigs -> tuple(id, file('das_tool.key')) }
    emit:
        bins = refined
        summary = refined
        input_bins_evaluation = refined
}
workflow SUMMARIZE_BINNING {
    take:
        binner
        contigs
    emit:
        contig_map = contigs
        unbinned_contigs = contigs
}
''')
        with (self.base / 'nextflow.config').open('a') as out:
            out.write(f"params.binning.das_tool.enabled={str(das).lower()}\nparams.binning.semibin2.enabled=true\nparams.binning.primary='{primary}'\nparams.binning.qc.busco.enabled={str(busco).lower()}\n")
        script = f'''include {{ BINNING }} from './subworkflows/binning'
workflow {{
    result = BINNING(Channel.of(tuple('s1', file('contigs'))), Channel.empty(), Channel.empty())
    result.bins.view {{ id, key -> "SELECTED:${{key.name}}" }}
}}
'''
        import subprocess
        source = self.base / 'test.nf'
        source.write_text(script)
        result = subprocess.run([NEXTFLOW, 'run', str(source), '-ansi-log', 'false'], cwd=self.base, env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout)
        return result.stdout

    def test_without_das_evaluates_both_binners(self):
        output = self.orchestration(False, True, 'metabat2')
        self.assertIn('QC:metabat2:true', output)
        self.assertIn('QC:semibin2:true', output)
        self.assertIn('SELECTED:metabat2.key', output)

    def test_das_overrides_primary_and_only_refined_busco(self):
        output = self.orchestration(True, True, 'invalid-ignored')
        self.assertIn('QC:metabat2:false', output)
        self.assertIn('QC:semibin2:false', output)
        self.assertIn('QC:das_tool:true', output)
        self.assertIn('SELECTED:das_tool.key', output)

    def test_das_respects_disabled_busco(self):
        output = self.orchestration(True, False, 'semibin2')
        self.assertIn('QC:das_tool:false', output)
        self.assertNotIn(':true', output)
        self.assertIn('SELECTED:das_tool.key', output)

    def test_real_downstream_process_uses_resolved_cache_key(self):
        qiime = self.base / 'bin/qiime'
        qiime.write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$CAPTURE"\n')
        (self.base / 'bins').touch()
        (self.base / 'cache').mkdir()
        with (self.base / 'nextflow.config').open('a') as out:
            out.write("params.binning.das_tool.enabled=true\nparams.binning.primary='metabat2'\nparams.binning.qc.busco.enabled=false\n")
        capture = self.run_nf(f"include {{ CALCULATE_MINHASHES }} from '{ROOT}/modules/dereplication'\nworkflow {{ CALCULATE_MINHASHES(file('bins'), file('cache')) }}\n")
        self.assertIn('test_mags_das_tool_minhash', capture)
        self.assertNotIn('test_mags_metabat2', capture)


class BinningValidationTests(ValidationCase):
    def test_das_ignores_invalid_primary(self):
        result, _ = self.run_nf(profile='standard,mags', params={'binning': {'primary': 'ignored', 'semibin2': {'enabled': True}, 'das_tool': {'enabled': True}}})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("configured binning.primary 'ignored' is ignored", result.stdout)

    def test_without_das_validates_primary(self):
        self.assert_failure('must be one of the enabled binners', profile='standard,mags', params={'binning': {'primary': 'semibin2'}})

    def test_das_still_requires_two_binners(self):
        self.assert_failure('DAS Tool requires at least two enabled binners', profile='standard,mags', params={'binning': {'das_tool': {'enabled': True}}})

@unittest.skipUnless(NEXTFLOW, 'Set NEXTFLOW to the Nextflow executable')
class BuscoFilteringTests(ProcessTestCase):
    def test_real_qc_filters_only_when_busco_is_enabled_for_that_binner(self):
        modules = self.base / 'modules'
        subs = self.base / 'subworkflows'
        modules.mkdir()
        subs.mkdir()
        shutil.copy(ROOT / 'subworkflows/binning_qc.nf', subs)
        shutil.copy(ROOT / 'modules/binning_policy.nf', modules)

        def workflow(name, inputs, body, outputs):
            return (f'workflow {name} {{\n    take:\n' +
                    ''.join(f'        {i}\n' for i in inputs) +
                    '    main:\n' + body + '\n    emit:\n' +
                    ''.join(f'        {k} = {v}\n' for k, v in outputs.items()) + '}\n')

        (modules / 'data_prep.nf').write_text(
            workflow('COLLATE_PARTITIONS', ['items', 'key', 'action', 'input_flag', 'output_flag', 'use_cache'],
                     '        result = items.map { file(key) }', {'result': 'result'}) +
            workflow('FETCH_ARTIFACT', ['items'], '        result = items', {'result': 'result'}))
        (modules / 'contig_binning.nf').write_text(
            workflow('EVALUATE_BINS_BUSCO', ['binner', 'bins', 'db'],
                     '''        result = binner.combine(bins).map { label, lineage, id, key, unbinned ->
            println "BUSCO:${label}"
            tuple(lineage, file('busco'))
        }''', {'busco_results': 'result'}) +
            workflow('EVALUATE_BINS_CHECKM', ['binner', 'bins'],
                     '        result = bins', {'qzv': 'result'}) +
            workflow('VISUALIZE_BUSCO', ['binner', 'bins', 'cache'],
                     '        result = bins', {'qzv': 'result'}) +
            workflow('COLLATE_BUSCO_RESULTS', ['lineages', 'items', 'key', 'action', 'input_flag', 'output_flag', 'use_cache'],
                     "        result = lineages.map { tuple(it, file('busco')) }", {'collated_results': 'result'}) +
            workflow('FILTER_MAGS', ['binner', 'bins', 'results', 'plugin', 'cache'],
                     '''        result = binner.combine(bins).map { label, id, key, lineage ->
            println "FILTER:${label}"
            tuple(id, key, lineage)
        }''', {'mags_filtered': 'result'}))
        with (self.base / 'nextflow.config').open('a') as out:
            out.write('params.binning.qc.filtering.enabled=true\nparams.binning.qc.busco.enabled=true\n')
        # With DAS disabled both binners receive true. With DAS enabled only the
        # refined QC receives true. Execute the actual QC workflow in each case.
        for das in (False, True):
            with self.subTest(das=das):
                script = f'''include {{ BINNING_QC as QC_A; BINNING_QC as QC_B; BINNING_QC as QC_DAS }} from './subworkflows/binning_qc'
include {{ evaluateBinnerBusco }} from './modules/binning_policy'
workflow {{
    def config = [das_tool: [enabled: {str(das).lower()}], qc: [busco: [enabled: true]]]
    QC_A('metabat2', Channel.of(tuple('s1', file('bins'))), Channel.empty(), Channel.of(tuple('s1', file('unbinned'))), Channel.empty(), evaluateBinnerBusco(config), Channel.value('db'))
    QC_B('semibin2', Channel.of(tuple('s1', file('bins'))), Channel.empty(), Channel.of(tuple('s1', file('unbinned'))), Channel.empty(), evaluateBinnerBusco(config), Channel.value('db'))
    if ({str(das).lower()}) {{
        QC_DAS('das_tool', Channel.of(tuple('s1', file('bins'))), Channel.empty(), Channel.of(tuple('s1', file('unbinned'))), Channel.empty(), true, Channel.value('db'))
    }}
}}
'''
                import subprocess
                source = self.base / 'test.nf'
                source.write_text(script)
                result = subprocess.run([NEXTFLOW, 'run', str(source), '-ansi-log', 'false'], cwd=self.base, env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
                self.assertEqual(result.returncode, 0, result.stdout)
                for label in ('metabat2', 'semibin2', 'das_tool'):
                    expected = (label == 'das_tool') == das
                    for action in ('BUSCO', 'FILTER'):
                        self.assertEqual(f'{action}:{label}' in result.stdout, expected, result.stdout)
