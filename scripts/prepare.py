#!/usr/bin/env python3
"""Prepare, validate, or export a state submission using the pinned dashboard contract."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit

SCHEMA = json.loads((Path(__file__).resolve().parents[1] / 'schema/dashboard-schema.json').read_text())['files']
META_SCHEMA = json.loads((Path(__file__).resolve().parents[1] / 'schema/meta-schema.json').read_text())
SHAPES = [
    ('state.csv', 'data/states.csv', ['state', 'state_fips', 'state_name']),
    ('counties.csv', 'data/states/{state}.csv', ['county']),
    ('schools.csv', 'data/states/{state}/schools.csv', ['school_id', 'county']),
]
MEASURES = ['coverage', 'coverage_K', *[f'coverage_{i}' for i in range(1, 6)]]


def bundle_files(source):
    """List input files, excluding the reserved template and example directories."""
    for entry in sorted(source.iterdir()):
        if entry.is_dir() and entry.name in {'templates', 'examples'}:
            continue
        if entry.is_file():
            yield entry
        elif entry.is_dir():
            yield from sorted(p for p in entry.rglob('*') if p.is_file())


def unique_object(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError(f'meta.json: duplicate key {key}')
        obj[key] = value
    return obj


def load_metadata(source, filename='meta.json'):
    path = source / filename
    if not path.is_file():
        raise ValueError(f'{filename}: missing required file')
    meta = json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=unique_object)
    if not isinstance(meta, dict):
        raise ValueError('meta.json: expected an object')
    properties = META_SCHEMA['properties']
    if set(meta) != set(properties):
        raise ValueError('meta.json: keys must match ' + ', '.join(properties))
    for name, rule in properties.items():
        value = meta[name]
        if not isinstance(value, str) or not value.strip() or value != value.strip():
            raise ValueError(f'meta.json: {name} must be a nonempty, trimmed string')
        if 'pattern' in rule and not re.fullmatch(rule['pattern'], value):
            raise ValueError(f'meta.json: invalid {name}')
    url = urlsplit(meta['sourceUrl'])
    if url.scheme not in ('https', 'http') or not url.hostname or any(c.isspace() for c in meta['sourceUrl']):
        raise ValueError('meta.json: sourceUrl must be an absolute HTTP(S) URL')
    if meta['name'] != meta['code'].upper():
        raise ValueError('meta.json: name must be the uppercase code')
    return meta


def aggregate_warnings(data):
    warnings = []
    def compare(label, parent, children):
        values = [float(row['coverage']) for row in children if row['coverage']]
        if parent['coverage'] and values:
            value = float(parent['coverage'])
            if value < min(values) - .0005 or value > max(values) + .0005:
                warnings.append({'warning': f'{label}: coverage outside child coverage range'})
    for county in data['counties.csv']:
        compare(county['county'], county, [row for row in data['schools.csv'] if row['county'] == county['county']])
    compare('state.csv', data['state.csv'][0], data['counties.csv'])
    return warnings


def process(source, state=None, clean=False, published=False):
    source = Path(source)
    if not source.is_dir():
        raise ValueError('input directory does not exist')
    if clean and published:
        raise ValueError('published data must be validated without normalization')
    meta = load_metadata(source)
    state = state or meta['code']
    if state != meta['code']:
        raise ValueError('meta.json: code disagrees with --state')
    shapes = SHAPES
    result, report, errors = {}, [], []
    allowed = {'meta.json', *[name for name, _, _ in SHAPES]} | (set() if published else {'report.json'})
    extras = sorted(str(p.relative_to(source)) for p in bundle_files(source)
                    if str(p.relative_to(source)) not in allowed)
    if extras:
        if clean:
            report.append({'excluded_files': extras})
        else:
            errors.append('unexpected files: ' + ', '.join(extras))
    for relative, shape, required in shapes:
        filename = relative
        path = source / filename
        columns = SCHEMA[shape]['columns']
        names = [c['name'] for c in columns]
        result[relative] = []
        if not path.exists():
            if relative == 'state.csv' or not clean:
                errors.append(f'{filename}: missing required file')
            continue
        with path.open(encoding='utf-8-sig', newline='') as handle:
            reader = csv.DictReader(handle, strict=True)
            header = reader.fieldnames or []
            if not header or len(set(header)) != len(header):
                errors.append(f'{filename}: missing or duplicate headers')
                continue
            if not clean and header != names:
                errors.append(f'{filename}: header must match pinned schema order')
            removed = [n for n in header if n not in names]
            if removed:
                report.append({'file': relative, 'removed_columns': removed})
            seen = set()
            for line, raw in enumerate(reader, 2):
                label = f'{filename}:{line}'
                if None in raw or any(v is None for v in raw.values()):
                    errors.append(f'{label}: malformed CSV row')
                    continue
                row = {n: raw.get(n, '').strip() if clean else raw.get(n, '') for n in names}
                if not clean and any(value != value.strip() for value in row.values()):
                    errors.append(f'{label}: cells must not contain surrounding whitespace')
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
                            if not re.fullmatch(r'[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?', value):
                                raise ValueError()
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
    if len(result.get('state.csv', [])) != 1:
        errors.append('state.csv must contain exactly one state row')
    counties = {r['county'] for r in result.get('counties.csv', [])}
    if any(r['county'] not in counties for r in result.get('schools.csv', [])):
        errors.append('school county missing from county table')
    if not any(r[n] for rows in result.values() for r in rows for n in MEASURES):
        errors.append('submission needs at least one coverage measurement')
    for row in result['state.csv']:
        if row['state_fips'].zfill(2) != meta['fips'] or row['state_name'] != meta['fullName']:
            errors.append('state.csv: identity disagrees with meta.json')
    county_fips = set()
    for row in result['counties.csv']:
        fips = row['county_fips']
        if fips:
            if not fips.startswith(meta['fips']):
                errors.append('counties.csv: county_fips must start with state FIPS')
            if fips in county_fips:
                errors.append('counties.csv: duplicate county_fips')
            county_fips.add(fips)
    if errors:
        raise ValueError('\n'.join(errors))
    report.extend(aggregate_warnings(result))
    return result, report, shapes


def write_bundle(output, data, meta, report, export=False):
    # Exclusive directory creation prevents overwriting an earlier run.
    output.mkdir(parents=True, exist_ok=False)
    target = output / 'data' if export else output
    target.mkdir(exist_ok=True)
    for relative, shape, _ in SHAPES:
        path = target / relative
        with path.open('w', newline='', encoding='utf-8') as handle:
            writer = csv.DictWriter(handle, fieldnames=[c['name'] for c in SCHEMA[shape]['columns']], lineterminator='\n')
            writer.writeheader()
            writer.writerows(data[relative])
    (target / 'meta.json').write_text(json.dumps(meta, indent=2) + '\n', encoding='utf-8')
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'validate', 'validate-published', 'export'])
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--state', help='Optional expected lowercase state code; defaults to meta.json')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.state and not re.fullmatch('[a-z]{2}', args.state):
        parser.error('--state must be a lowercase two-letter code')
    try:
        clean = args.command == 'prepare'
        writing = args.command in ('prepare', 'export')
        if writing and (args.output is None or args.output.exists()):
            raise ValueError(f'{args.command} requires a new --output directory')
        if not writing and args.output is not None:
            raise ValueError(f'{args.command} does not accept --output')
        if writing and args.output.resolve().is_relative_to(args.input.resolve()):
            raise ValueError('output must be outside the input directory')
        data, report, _ = process(args.input, args.state, clean,
                                  published=args.command == 'validate-published')
        if writing:
            hashes = {str(p.relative_to(args.input)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in bundle_files(args.input)}
            report.append({'input_sha256': hashes})
            write_bundle(args.output, data, load_metadata(args.input), report, args.command == 'export')
            print(f'{args.command.capitalize()} complete; review report.json.')
        else:
            print('Valid bundle. Source provenance and dashboard integration still require review.')
        for entry in report:
            if 'warning' in entry:
                print('Warning: ' + entry['warning'])
    except (ValueError, OSError, csv.Error) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
