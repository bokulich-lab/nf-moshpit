"""Execute the NCBI copy block from FETCH_SEQS with temporary home paths."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NcbiConfigCopyTests(unittest.TestCase):
    def check_copy(self, mode):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            target = root / 'container home'
            target.mkdir()
            source = target if mode == 'same' else root / 'source home'
            if mode != 'same':
                source.mkdir()
            (source / '.ncbi').mkdir()
            config = source / '.ncbi/user-settings.mkfg'
            config.write_text('existing settings\n')
            if mode in ('symlink', 'existing'):
                (target / '.ncbi').mkdir()
                dest = target / '.ncbi/user-settings.mkfg'
                if mode == 'symlink':
                    dest.symlink_to(config)
                else:
                    dest.write_text('old settings\n')
            text = (ROOT / 'modules/data_prep.nf').read_text()
            start = text.index('          if [ -d "/home/qiime2" ]; then')
            end = text.index('\n        else\n', start)
            script = text[start:end].replace('\\$HOME', str(source)).replace('/home/qiime2', str(target))
            # Quote the unchanged mkdir/ls commands after substituting a spaced path.
            script = script.replace(f'mkdir -p {target}/.ncbi', f'mkdir -p "{target}/.ncbi"')
            script = script.replace(f'ls {target}/.ncbi', f'ls "{target}/.ncbi"')
            result = subprocess.run(['bash', '-euc', script], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((target / '.ncbi/user-settings.mkfg').read_text(), 'existing settings\n')
            self.assertIn('already available' if mode in ('same', 'symlink') else 'Copying NCBI', result.stdout)

    def test_same_home(self):
        self.check_copy('same')

    def test_symlink_to_same_file(self):
        self.check_copy('symlink')

    def test_different_home_missing_destination(self):
        self.check_copy('missing')

    def test_different_home_existing_destination(self):
        self.check_copy('existing')
