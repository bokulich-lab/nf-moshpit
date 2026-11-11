from nf_validation_support import ValidationCase


class MasonTableValidationTests(ValidationCase):
    def test_csv_header(self):
        self.assert_success(validate=False, assertions='''
def samples = file("${launchDir}/samples.csv")
samples.text = 'id,profile,readCount,readLength,genomesPath\\ns1,uniform,10,100,/genomes\\n'
validateInputTable(samples, ['id','profile','readCount','readLength','genomesPath'], ',', 'MASON samples')
''')

    def test_wrong_delimiter(self):
        self.assert_failure('must use CSV (comma) delimiters', validate=False, assertions='''
def samples = file("${launchDir}/samples.tsv")
samples.text = 'id\\tprofile\\treadCount\\treadLength\\tgenomesPath\\ns1\\tuniform\\t10\\t100\\t/genomes\\n'
validateInputTable(samples, ['id','profile','readCount','readLength','genomesPath'], ',', 'MASON samples')
''')
