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

    def publish_fixture(self):
        prepared = Path(self.temp.name) / 'prepared'
        site = Path(self.temp.name) / 'site'
        for command, source, output in [('prepare', self.source, prepared),
                                        ('export', prepared, site)]:
            result = self.run_cli(command, source, output)
            self.assertEqual(result.returncode, 0, result.stderr)
        return site / 'data'

    def test_published_roundtrip_is_read_only_and_accepts_sparse_grades(self):
        self.write('State.csv', 'state,state_fips,state_name\naa,00,Example State\n')
        self.write('Counties.csv', 'county\nExample County\n')
        self.write('Schools.csv', 'school_id,county,coverage_K\n001,Example County,.93\n')
        published = self.publish_fixture()
        before = {p.name: p.read_bytes() for p in published.iterdir()}
        result = self.run_cli('validate-published', published)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {p.name: p.read_bytes() for p in published.iterdir()})
        self.assertEqual(prepare.process(published, published=True)[0]['Schools.csv'][0]['school_id'], '001')
        with self.assertRaisesRegex(ValueError, 'disagrees with --state'):
            prepare.process(published, state='bb', published=True)
        self.assertNotEqual(self.run_cli('validate-published', published,
                                       Path(self.temp.name) / 'unused').returncode, 0)

    def test_published_requires_all_four_exact_filenames(self):
        published = self.publish_fixture()
        for name in ['state.csv', 'counties.csv', 'schools.csv', 'meta.json']:
            with self.subTest(name=name):
                path = published / name
                original = path.read_bytes()
                path.unlink()
                result = self.run_cli('validate-published', published)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'{name}: missing required file', result.stderr)
                path.write_bytes(original)
                renamed = path.with_name(name.capitalize())
                path.rename(renamed)
                self.assertNotEqual(self.run_cli('validate-published', published).returncode, 0)
                renamed.rename(path)

    def test_published_rejects_bad_data_without_normalizing(self):
        published = self.publish_fixture()
        path = published / 'state.csv'
        original = path.read_text()
        for bad in [original.replace('.94', '94'),
                    original.replace('Example State', ' Example State'),
                    original.replace('state,state_fips', 'state_fips,state')]:
            with self.subTest(bad=bad):
                path.write_text(bad)
                self.assertNotEqual(self.run_cli('validate-published', published).returncode, 0)
                self.assertEqual(path.read_text(), bad)
        path.write_text(original)
        for name in ['report.json', 'unexpected.csv', 'nested/source.txt']:
            extra = published / name
            extra.parent.mkdir(exist_ok=True)
            extra.write_text('unexpected')
            self.assertNotEqual(self.run_cli('validate-published', published).returncode, 0)
            extra.unlink()

    def test_published_checks_relationships_and_metadata(self):
        self.write('Counties.csv', 'county\nExample County\n')
        self.write('Schools.csv', 'school_id,county,coverage\n001,Example County,.93\n')
        published = self.publish_fixture()
        schools = published / 'schools.csv'
        original = schools.read_text()
        schools.write_text(original.replace('Example County', 'Unknown County'))
        result = self.run_cli('validate-published', published)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('school county missing', result.stderr)
        schools.write_text(original)
        meta_path = published / 'meta.json'
        meta = json.loads(meta_path.read_text())
        meta['fips'] = '99'
        meta_path.write_text(json.dumps(meta))
        result = self.run_cli('validate-published', published)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('identity disagrees', result.stderr)

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
