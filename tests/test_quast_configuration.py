from nf_validation_support import ValidationCase

class QuastConfiguration(ValidationCase):
    def test_assembly_without_user_quast_block(self):
        self.assert_success(params={'genome_assembly': {'enabled': True}}, assertions='''
        assert params.assembly_qc.quast.enabled == false
        assert params.assembly_qc.quast.useMappedReads == false
        assert params.assembly_qc.quast.additionalFlags == ''
        ''')
