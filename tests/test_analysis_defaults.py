from nf_validation_support import ValidationCase

class AnalysisDefaults(ValidationCase):
    def test_base_needs_no_database(self):
        self.assert_success(assertions="assert params.genome_assembly.enabled; assert !params.dereplication.enabled; assert !params.taxonomic_classification.kaiju.enabledFor")

    def test_reads_only_and_mags_presets(self):
        self.assert_success(profile='standard,reads_only', assertions="assert !params.genome_assembly.enabled")
        self.assert_success(profile='standard,mags', assertions="assert params.binning.enabled; assert params.dereplication.enabled; assert params.abundance_estimation.enabledFor == 'contigs,derep'")

    def test_impossible_requested_stage_fails(self):
        self.assert_failure('binning is disabled', params={'dereplication': {'enabled': True}})
        self.assert_failure('genome_assembly.enabled', profile='standard,reads_only', params={'abundance_estimation': {'enabledFor': 'contigs'}})
