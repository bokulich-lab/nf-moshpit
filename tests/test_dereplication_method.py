from nf_validation_support import ValidationCase

class DereplicationMethod(ValidationCase):
    def test_skani_is_rejected(self):
        self.assert_failure('supports only sourmash', profile='standard,mags', params={'dereplication': {'method': 'skani'}})
