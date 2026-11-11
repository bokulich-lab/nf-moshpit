from nf_validation_support import ValidationCase

class ProfileComposition(ValidationCase):
    def test_scales_compose_without_resetting(self):
        for profile in ('standard,high,cpu_intensive,mem_intensive,long_jobs',
                        'long_jobs,mem_intensive,cpu_intensive,high,standard'):
            with self.subTest(profile=profile):
                self.assert_success(profile=profile, assertions='''
                assert params.overall_cpu_scale == 4
                assert params.overall_mem_scale == 4
                assert params.overall_time_scale == 3
                assert params.cpu_intensive_task_multiplier == 2
                assert params.mem_intensive_task_multiplier == 2
                ''')

    def test_multiple_general_scales_are_rejected(self):
        self.assert_failure('Choose only one general scaling profile', profile='standard,low,high')
