#!/usr/bin/env python3
"""Prepare or validate a partial state submission against the dashboard schema."""
import argparse
import csv
import json
import math
from pathlib import Path
import re
import sys

SCHEMA = json.loads((Path(__file__).resolve().parents[1] / 'schema/dashboard-schema.json').read_text())['files']
MEASURES = ['coverage', 'coverage_K', *[f'coverage_{i}' for i in range(1, 6)]]


def process(source, state, clean=False):
    shapes = [
        ('states.csv', 'data/states.csv', ['state', 'state_fips', 'state_name']),
        (f'states/{state}.csv', 'data/states/{state}.csv', ['county']),
        (f'states/{state}/schools.csv', 'data/states/{state}/schools.csv', ['school_id', 'county']),
    ]
    result, report, errors = {}, [], []
    if not source.is_dir():
        raise ValueError('input directory does not exist')
    allowed = {p for p, _, _ in shapes} | {'report.json'}
    extras = sorted(str(p.relative_to(source)) for p in source.rglob('*') if p.is_file() and str(p.relative_to(source)) not in allowed)
    if extras:
        if clean:
            report.append({'excluded_files': extras})
        else:
            errors.append('unexpected files: ' + ', '.join(extras))
    for relative, shape, required in shapes:
        path = source / relative
        columns = SCHEMA[shape]['columns']
        names = [c['name'] for c in columns]
        result[relative] = []
        if not path.exists():
            if relative == 'states.csv' or not clean:
                errors.append(f'{relative}: missing required file')
            continue
        with path.open(encoding='utf-8-sig', newline='') as handle:
            reader = csv.DictReader(handle)
            header = reader.fieldnames or []
            if not header or len(set(header)) != len(header):
                errors.append(f'{relative}: missing or duplicate headers')
                continue
            if not clean and header != names:
                errors.append(f'{relative}: header must match pinned schema order')
            removed = [n for n in header if n not in names]
            if removed:
                report.append({'file': relative, 'removed_columns': removed})
            seen = set()
            for line, raw in enumerate(reader, 2):
                label = f'{relative}:{line}'
                if None in raw or any(v is None for v in raw.values()):
                    errors.append(f'{label}: malformed CSV row')
                    continue
                row = {n: raw.get(n, '').strip() if clean else raw.get(n, '') for n in names}
                for n in required:
                    if not row[n].strip():
                        errors.append(f'{label}: {n} is required')
                key = row.get('school_id', row.get('county', row.get('state')))
                if key in seen:
                    errors.append(f'{label}: duplicate identity')
                seen.add(key)
                if 'state' in row and row['state'] != state:
                    errors.append(f'{label}: state must be {state}')
                if clean:
                    if row['coverage'] and not row['tier']:
                        try:
                            c = float(row['coverage'])
                            row['tier'] = 'H' if c >= .95 else 'M' if c >= .90 else 'L'
                        except ValueError:
                            pass
                    if 'no_data' in row and not row['no_data']:
                        row['no_data'] = '0' if any(row[n] for n in MEASURES) else '1'
                for col in columns:
                    value = row[col['name']]
                    if value == '':
                        continue
                    rule = col.get('constraints', {})
                    try:
                        if col['type'] in ('number', 'integer'):
                            number = float(value)
                            if not math.isfinite(number):
                                raise ValueError()
                            if col['type'] == 'integer' and not re.fullmatch(r'-?\d+', value):
                                raise ValueError()
                            if number < rule.get('min', -math.inf) or number > rule.get('max', math.inf):
                                raise ValueError()
                        if 'enum' in rule and value not in list(map(str, rule['enum'])):
                            raise ValueError()
                        if 'pattern' in rule and not re.fullmatch(rule['pattern'], value):
                            raise ValueError()
                    except ValueError:
                        errors.append(f"{label}: invalid {col['name']}")
                for suffix in ['', '_K', *[f'_{i}' for i in range(1, 6)]]:
                    lo, hi = row['coverage_ci_low' + suffix], row['coverage_ci_high' + suffix]
                    try:
                        if lo and hi and float(lo) > float(hi):
                            errors.append(f'{label}: reversed interval{suffix}')
                    except ValueError:
                        pass
                try:
                    c = float(row['coverage']) if row['coverage'] else None
                    if c is not None and row['tier']:
                        tier = 'H' if c >= .95 else 'M' if c >= .90 else 'L'
                        if tier != row['tier'] and min(abs(c-.95), abs(c-.90)) > .0005:
                            errors.append(f'{label}: tier disagrees with coverage')
                except ValueError:
                    pass
                if row.get('no_data') == '1' and any(row[n] for n in names if n.startswith('coverage') or n in ('tier', 'prob_below_95')):
                    errors.append(f'{label}: no_data=1 conflicts with coverage data')
                result[relative].append(row)
    if len(result.get('states.csv', [])) != 1:
        errors.append('states.csv must contain exactly one state row')
    counties = {r['county'] for r in result.get(f'states/{state}.csv', [])}
    if any(r['county'] not in counties for r in result.get(f'states/{state}/schools.csv', [])):
        errors.append('school county missing from county table')
    if not any(r[n] for rows in result.values() for r in rows for n in MEASURES):
        errors.append('submission needs at least one coverage measurement')
    if errors:
        raise ValueError('\n'.join(errors))
    return result, report, shapes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'validate'])
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--state', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not re.fullmatch('[a-z]{2}', args.state):
        parser.error('--state must be a lowercase two-letter code')
    try:
        clean = args.command == 'prepare'
        if clean and (args.output is None or args.output.exists()):
            raise ValueError('prepare requires a new --output directory')
        data, report, shapes = process(args.input, args.state, clean)
        if clean:
            args.output.mkdir(parents=True)
            for relative, shape, _ in shapes:
                path = args.output / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                with path.open('w', newline='', encoding='utf-8') as handle:
                    writer = csv.DictWriter(handle, fieldnames=[c['name'] for c in SCHEMA[shape]['columns']])
                    writer.writeheader()
                    writer.writerows(data[relative])
            (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
            print('Prepared bundle; review report.json for excluded fields and files.')
        else:
            print('Valid bundle. Source provenance and dashboard integration still require review.')
    except (ValueError, OSError, csv.Error) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
