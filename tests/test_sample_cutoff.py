from nf_validation_support import ValidationCase

class SampleCutoff(ValidationCase):
    def test_valid_minimum(self):
        self.assert_success(params={'sample_filtering': {'enabled': True, 'minReads': 1000}})

    def test_obsolete_and_conflicting_alias(self):
        for settings in ({'min_reads': 1000}, {'min_reads': 999, 'minReads': 1000}):
            with self.subTest(settings=settings):
                self.assert_failure('Obsolete sample_filtering.min_reads', params={'sample_filtering': settings})

    def test_invalid_minimum(self):
        for value in (-1, 0.5):
            with self.subTest(value=value):
                self.assert_failure('must be a nonnegative integer', params={'sample_filtering': {'minReads': value}})
