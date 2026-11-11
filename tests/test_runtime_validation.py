from nf_validation_support import ValidationCase

class RuntimeValidation(ValidationCase):
    def test_conda_optional_plugins_without_images(self):
        args = self.assert_success(profile='standard,conda,mags', params={
            'container': None, 'condaEnv': 'fixture-env',
            'binning': {'qc': {'checkm': {'enabled': True}}},
            'humann3': {'enabled': True},
            'databases': {'checkm': {'path': '/fixture/checkm'},
                          'humann3Chocophlan': {'cache': '/fixture/cache', 'key': 'choco'},
                          'humann3TranslatedSearch': {'cache': '/fixture/cache', 'key': 'translated'},
                          'humann3Metaphlan': {'cache': '/fixture/cache', 'key': 'metaphlan'}}})
        for plugin in ('checkm', 'humann3', 'sourmash'):
            self.assertIn(f'-n fixture-env qiime {plugin} --help', args)

    def test_unused_image_cannot_hide_missing_conda_plugin(self):
        args = self.assert_failure('lacks a working qiime sourmash', profile='standard,conda,mags',
                                   params={'condaEnv': '/fixture/env'}, conda_exit=1)
        self.assertIn('-p /fixture/env qiime sourmash --help', args)

    def test_docker_ignores_unused_conda_environment(self):
        args = self.assert_success(profile='standard,docker,mags', params={'condaEnv': 'unused-env'}, conda_exit=1)
        self.assertEqual(args, '')
        self.assert_failure('no Sourmash container', profile='standard,docker,mags', params={
            'container': None, 'containerAnnotate': 'annotate', 'containerAssembly': 'assembly',
            'containerMag': 'mag', 'condaEnv': 'unused-env'})

    def test_conda_requires_environment(self):
        self.assert_failure('requires condaEnv', profile='standard,conda', params={'condaEnv': None})
