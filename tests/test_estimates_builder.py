import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_prepare import ROOT, prepare


class EstimatesBuilderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('Rscript'):
            raise unittest.SkipTest('Rscript is not installed')
        check = subprocess.run(['Rscript', '-e',
            'quit(status=if (all(sapply(c("data.table","jsonlite"), requireNamespace, quietly=TRUE))) 0 else 1)'],
            capture_output=True)
        if check.returncode:
            raise unittest.SkipTest('R packages data.table and jsonlite are required')

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / 'input'
        self.source.mkdir()
        self.output = Path(self.temp.name) / 'output'
        shutil.copy(ROOT / 'examples/minimal/Meta.json', self.source / 'Meta.json')
        self.features = [
            {'type': 'Feature', 'properties': {'NAME': 'Example County', 'coverage': .92},
             'geometry': {'type': 'Polygon', 'coordinates': [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]]}},
            {'type': 'Feature', 'properties': {'NAME': 'Example School', 'location_id': '001', 'coverage': .93},
             'geometry': {'type': 'Point', 'coordinates': [5, 5]}},
            {'type': 'Feature', 'properties': {'NAME': 'No Estimate School', 'location_id': '002'},
             'geometry': {'type': 'Point', 'coordinates': [6, 6]}},
        ]
        self.estimates = 'id,est,ci_low,ci_high,population,age_group\n001,.91,.89,.93,100,5_6\n'

    def run_builder(self):
        (self.source / 'locations.geojson').write_text(json.dumps({'type': 'FeatureCollection', 'features': self.features}))
        (self.source / 'estimates.csv').write_text(self.estimates)
        env = {**os.environ, 'INPUT_DIR': str(self.source), 'META_PATH': str(self.source / 'Meta.json'), 'OUT_DIR': str(self.output)}
        return subprocess.run(['Rscript', str(ROOT / 'scripts/build-data/build_from_estimates.R')],
                              cwd=ROOT, env=env, capture_output=True, text=True)

    def test_sparse_grades_ids_missing_coverage_and_validation(self):
        result = self.run_builder()
        self.assertEqual(result.returncode, 0, result.stderr)
        data, _, _ = prepare.process(self.output)
        rows = {row['school_id']: row for row in data['Schools.csv']}
        self.assertEqual(rows['001']['coverage_K'], '0.91')
        self.assertEqual(rows['001']['coverage_5'], '')
        self.assertEqual(rows['002']['no_data'], '1')
        self.assertEqual(data['State.csv'][0]['coverage'], '0.93')
        self.assertNotEqual(self.run_builder().returncode, 0)

    def test_duplicate_estimates_rejected(self):
        self.estimates += '001,.92,.90,.94,100,5_6\n'
        result = self.run_builder()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Duplicate', result.stderr)
        self.assertFalse(self.output.exists())

    def test_unmatched_school_rejected(self):
        self.features[1]['geometry']['coordinates'] = [20, 20]
        result = self.run_builder()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('match a county', result.stderr)

    def test_polygon_holes_rejected(self):
        self.features[0]['geometry']['coordinates'].append([[1, 1], [2, 1], [2, 2], [1, 1]])
        result = self.run_builder()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('holes', result.stderr)

    def test_missing_weights_remain_blank(self):
        self.estimates = self.estimates.replace(',100,', ',,')
        result = self.run_builder()
        self.assertEqual(result.returncode, 0, result.stderr)
        data, _, _ = prepare.process(self.output)
        self.assertEqual(data['State.csv'][0]['coverage'], '')
        self.assertEqual(data['Schools.csv'][0]['enrollment'], '')
