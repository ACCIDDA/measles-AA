import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('prepare', ROOT / 'scripts/prepare.py')
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class SubmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / 'input'
        self.source.mkdir()
        self.write('Meta.json', (ROOT / 'examples/minimal/Meta.json').read_text())
        self.write('State.csv', 'state,state_fips,state_name,coverage\naa,00,Example State,.94\n')

    def write(self, path, text):
        target = self.source / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def test_state_only_roundtrip(self):
        output = Path(self.temp.name) / 'output'
        for args in [
            ['prepare', '--input', str(self.source), '--output', str(output)],
            ['validate', '--input', str(output)],
        ]:
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/prepare.py'), *args, '--state', 'aa'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        with (output / 'State.csv').open() as handle:
            row = next(csv.DictReader(handle))
        self.assertEqual(row['coverage_ci_low'], '')
        self.assertEqual(row['tier'], 'M')
        with (output / 'Schools.csv').open() as handle:
            self.assertEqual(list(csv.DictReader(handle)), [])

    def test_county_only_and_missing_grades(self):
        self.write('State.csv', 'state,state_fips,state_name\naa,00,Example State\n')
        self.write('Counties.csv', 'county,coverage_K\nExample County,.92\n')
        data, _, _ = prepare.process(self.source, 'aa', True)
        self.assertEqual(data['Counties.csv'][0]['coverage'], '')

    def test_school_optional_fields_and_no_data(self):
        self.write('Counties.csv', 'county\nExample County\n')
        self.write('Schools.csv', 'school_id,county,coverage_K\n001,Example County,.93\n002,Example County,\n')
        data, _, _ = prepare.process(self.source, 'aa', True)
        rows = data['Schools.csv']
        self.assertEqual([r['no_data'] for r in rows], ['0', '1'])
        self.assertEqual(rows[0]['school_id'], '001')

    def test_extras_reported_and_source_preserved(self):
        self.write('State.csv', 'state,state_fips,state_name,coverage,notes\naa,00,Example State, .94 ,internal\n')
        self.write('unrelated.txt', 'not for publication')
        data, report, _ = prepare.process(self.source, 'aa', True)
        self.assertNotIn('notes', data['State.csv'][0])
        self.assertIn('internal', (self.source / 'State.csv').read_text())
        self.assertIn('notes', json.dumps(report))
        self.assertIn('unrelated.txt', json.dumps(report))

    def test_bad_numbers_rejected(self):
        for value in ['94', '-1', 'NaN', 'inf', '<5', 'NA', '0_1']:
            with self.subTest(value=value):
                self.write('State.csv', f'state,state_fips,state_name,coverage\naa,00,Example State,{value}\n')
                with self.assertRaisesRegex(ValueError, 'invalid coverage'):
                    prepare.process(self.source, 'aa', True)

    def test_missing_measurements_rejected(self):
        self.write('State.csv', 'state,state_fips,state_name\naa,00,Example State\n')
        with self.assertRaisesRegex(ValueError, 'at least one coverage'):
            prepare.process(self.source, 'aa', True)

    def test_duplicates_and_orphan_counties(self):
        self.write('Schools.csv', 'school_id,county\n1,Example County\n1,Example County\n')
        with self.assertRaisesRegex(ValueError, 'duplicate identity'):
            prepare.process(self.source, 'aa', True)
        self.write('Schools.csv', 'school_id,county\n1,Example County\n')
        with self.assertRaisesRegex(ValueError, 'school county missing'):
            prepare.process(self.source, 'aa', True)

    def test_intervals_tiers_and_no_data_conflicts(self):
        for columns, values, error in [
            ('coverage_ci_low,coverage_ci_high', '.99,.90', 'reversed interval'),
            ('tier', 'L', 'tier disagrees'),
        ]:
            self.write('State.csv', f'state,state_fips,state_name,coverage,{columns}\naa,00,Example State,.94,{values}\n')
            with self.assertRaisesRegex(ValueError, error):
                prepare.process(self.source, 'aa', True)
        self.write('State.csv', 'state,state_fips,state_name,coverage\naa,00,Example State,.94\n')
        self.write('Counties.csv', 'county\nExample County\n')
        self.write('Schools.csv', 'school_id,county,coverage,no_data\n1,Example County,.92,1\n')
        with self.assertRaisesRegex(ValueError, 'no_data=1 conflicts'):
            prepare.process(self.source, 'aa', True)

    def test_empty_input_and_wrong_state_rejected(self):
        with self.assertRaises(ValueError):
            prepare.process(self.source, 'bb', True)
        (self.source / 'State.csv').unlink()
        with self.assertRaisesRegex(ValueError, 'missing required file'):
            prepare.process(self.source, 'aa', True)

    def test_ragged_rows_rejected(self):
        self.write('State.csv', 'state,state_fips,state_name,coverage\naa,00,Example State,.94,extra\n')
        with self.assertRaisesRegex(ValueError, 'malformed CSV row'):
            prepare.process(self.source, 'aa', True)


if __name__ == '__main__':
    unittest.main()
