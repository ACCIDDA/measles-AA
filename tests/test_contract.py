import csv
import json
import unittest
import subprocess
import sys
from pathlib import Path

from test_prepare import ROOT, SubmissionTests, prepare


class ContractTests(unittest.TestCase):
    setUp = SubmissionTests.setUp
    write = SubmissionTests.write

    def run_cli(self, command, source=None, output=None):
        args = [sys.executable, str(ROOT / 'scripts/prepare.py'), command,
                '--input', str(source or self.source)]
        if output is not None:
            args += ['--output', str(output)]
        return subprocess.run(args, capture_output=True, text=True)

    def test_templates_are_empty_and_match_schema(self):
        for name, shape, _ in prepare.SHAPES:
            with (ROOT / 'templates' / name).open(newline='') as handle:
                rows = list(csv.reader(handle))
            self.assertEqual(rows, [[c['name'] for c in prepare.SCHEMA[shape]['columns']]])
        meta = json.loads((ROOT / 'templates/Meta.json').read_text())
        self.assertEqual(set(meta), set(prepare.META_SCHEMA['required']))
        self.assertEqual(set(meta.values()), {''})
        with self.assertRaises(ValueError):
            prepare.process(ROOT / 'templates', clean=True)

    def test_metadata_required_and_strict(self):
        original = json.loads((self.source / 'Meta.json').read_text())
        cases = [[], {**original, 'extra': 'value'}]
        for field in original:
            cases.extend([{k: v for k, v in original.items() if k != field},
                          {**original, field: ''}, {**original, field: None}])
        cases += [{**original, key: value} for key, value in [
            ('code', 'AA'), ('name', 'BB'), ('fips', '0'), ('dataDir', '../data'),
            ('sourceUrl', 'javascript:alert(1)'), ('sourceUrl', 'https://'),
            ('sourceUrl', 'https://example.org/space here')]]
        for meta in cases:
            with self.subTest(meta=meta):
                self.write('Meta.json', json.dumps(meta))
                with self.assertRaisesRegex(ValueError, 'Meta.json'):
                    prepare.process(self.source, clean=True)
        self.write('Meta.json', '{"code":"aa","code":"bb"}')
        with self.assertRaisesRegex(ValueError, 'duplicate key'):
            prepare.process(self.source, clean=True)
        (self.source / 'Meta.json').unlink()
        with self.assertRaisesRegex(ValueError, 'missing required file'):
            prepare.process(self.source, clean=True)

    def test_identity_and_county_fips_consistency(self):
        self.write('State.csv', 'state,state_fips,state_name,coverage\naa,1,Example State,.94\n')
        with self.assertRaisesRegex(ValueError, 'identity disagrees'):
            prepare.process(self.source, clean=True)
        self.write('State.csv', 'state,state_fips,state_name,coverage\naa,0,Example State,.94\n')
        prepare.process(self.source, clean=True)
        self.write('Counties.csv', 'county,county_fips\nExample County,01001\n')
        with self.assertRaisesRegex(ValueError, 'start with state FIPS'):
            prepare.process(self.source, clean=True)
        self.write('Counties.csv', 'county,county_fips\nWest,00001\nEast,00001\n')
        with self.assertRaisesRegex(ValueError, 'duplicate county_fips'):
            prepare.process(self.source, clean=True)

    def test_strict_validation_headers_files_and_whitespace(self):
        output = Path(self.temp.name) / 'prepared'
        self.assertEqual(self.run_cli('prepare', output=output).returncode, 0)
        path = output / 'State.csv'
        original = path.read_text()
        for invalid in [original.replace('state,state_fips', 'state_fips,state'),
                        original.replace('Example State', ' Example State')]:
            path.write_text(invalid)
            self.assertNotEqual(self.run_cli('validate', output).returncode, 0)
        path.write_text(original)
        (output / 'Schools.csv').unlink()
        self.assertNotEqual(self.run_cli('validate', output).returncode, 0)

    def test_export_paths_reproducibility_and_no_overwrite(self):
        first, second, site = [Path(self.temp.name) / name for name in ('first', 'second', 'site')]
        for output in (first, second):
            result = self.run_cli('prepare', output=output)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({p.name: p.read_bytes() for p in first.iterdir()},
                         {p.name: p.read_bytes() for p in second.iterdir()})
        self.assertIn('input_sha256', json.loads((first / 'report.json').read_text())[-1])
        before = (first / 'State.csv').read_bytes()
        self.assertNotEqual(self.run_cli('prepare', output=first).returncode, 0)
        self.assertEqual((first / 'State.csv').read_bytes(), before)
        result = self.run_cli('export', first, site)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({p.name for p in (site / 'data').iterdir()},
                         {'state.csv', 'counties.csv', 'schools.csv', 'meta.json'})
        for name in ('State.csv', 'Counties.csv', 'Schools.csv', 'Meta.json'):
            self.assertEqual((site / 'data' / name.lower()).read_bytes(), (first / name).read_bytes())
        nested = self.source / 'nested'
        self.assertNotEqual(self.run_cli('prepare', output=nested).returncode, 0)
        self.assertFalse(nested.exists())

    def test_failed_preparation_writes_nothing(self):
        self.write('State.csv', 'state,state_fips,state_name,coverage\naa,00,Example State,94\n')
        output = Path(self.temp.name) / 'invalid'
        self.assertNotEqual(self.run_cli('prepare', output=output).returncode, 0)
        self.assertFalse(output.exists())

    def test_aggregate_warnings_are_advisory(self):
        self.write('Counties.csv', 'county,coverage\nExample County,.80\n')
        self.write('Schools.csv', 'school_id,county,coverage\n001,Example County,.90\n')
        _, report, _ = prepare.process(self.source, clean=True)
        self.assertEqual(len([entry for entry in report if 'warning' in entry]), 2)

    def test_boundary_tolerance_and_strict_csv(self):
        self.write('State.csv', 'state,state_fips,state_name,coverage,tier\naa,00,Example State,.95,M\n')
        prepare.process(self.source, clean=True)
        self.write('State.csv', 'state,state_fips,state_name,coverage\naa,00,"Example State,.94\n')
        with self.assertRaises(csv.Error):
            prepare.process(self.source, clean=True)


# Avoid running the imported base suite twice through unittest module discovery.
del SubmissionTests
