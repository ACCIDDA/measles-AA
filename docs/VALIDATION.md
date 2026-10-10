# Cleaning and validating a submission

## 1. Establish what the source actually measures

Before uploading, record the source URL/owner, access restrictions, reporting
period, population/grades, MMR dose definition, units, suppression rules, and
whether values are reported or modeled. Keep this information in your state
repo's documentation. Do not upload student-level records or unrelated personal
information. The public output is aggregate coverage by state, county, or school.
The schema cannot establish that a value measures the right vaccine or period.

Use the minimum level available: state-only, county-only, or school data. A
county-only submission still needs a state identity row; unknown state coverage
stays blank. For school data, include county identity rows without inventing
county coverage. A state with no releasable coverage can retain its inputs locally
but should not publish an empty bundle as a ready data source.

## 2. Map and clean source data

Map source columns to the names in `schema/dashboard-schema.json` before using
`prepare.py`. This generic tool is a formatter, not a raw spreadsheet interpreter.
The NC and CA adapters perform their own source-specific transformations; see
[their instructions](ITERATION-1.md).

- Use proportions from 0 to 1. Convert percent values only when source metadata
  establishes their units; the tool rejects 94 rather than guessing it means .94.
- Leave unavailable cells empty. Convert documented suppression markers to blanks
  and record that decision. Do not replace suppression with zero or infer hidden
  values. Literal `NA`, `NaN`, infinity, and `<5` are not valid numeric cells.
- Preserve leading zeros in IDs and county FIPS. State FIPS permits one or two
  digits; county FIPS, when supplied, requires five digits.
- Select one documented reporting period/population. Do not combine incompatible
  years, count duplicate schools, or silently average conflicting observations.
- Do not manufacture credible intervals, probabilities, per-grade values, or
  totals. A published county estimate need not equal an average of its schools.
- Coordinates, when provided, must be longitude/latitude degrees. NC's native
  projected coordinates cannot be relabeled as longitude/latitude.

```sh
python3 scripts/prepare.py prepare --input inputs --output output/run-1 --state nc
python3 scripts/prepare.py validate --input output/run-1 --state nc
```

Preparation trims cell whitespace, keeps only schema columns, adds missing
columns as blanks, and puts columns in schema order. It derives `tier` only from
available overall coverage, and sets missing `no_data` to 1 for school rows with
no overall or per-grade coverage, otherwise 0. It does not estimate coverage or
aggregate school data. Missing geographic-level files become header-only files.

Extra columns and files are excluded from the output and listed in `report.json`.
Inputs are never deleted or overwritten. Review this report: a removed column
might be a misspelled required measurement that should have been mapped. Invalid
or duplicate rows cause failure instead of being silently dropped. Use a new
output directory per run to avoid carrying obsolete data into a later bundle.

## 3. Automated checks

Validation exits nonzero for missing bundle files, incorrect headers/order,
malformed rows, missing required identity cells, duplicate IDs/counties,
wrong state code, school counties absent from the county table, invalid types,
non-finite numbers, values outside schema bounds, invalid FIPS formats, reversed
interval bounds, inconsistent coverage tiers, or `no_data=1` with coverage data.
At least one coverage measurement is required; all optional blank cells pass.
Tier comparisons retain the dashboard's 0.0005 boundary tolerance.

Validation does **not** prove a state's code/name/FIPS combination is correct,
resolve county aliases, verify source permissions, validate modeling methodology,
or establish geographic coordinate accuracy. Review these against the source.
Paired interval bounds are checked for order; estimate-versus-interval consistency
needs review because existing producers can mix reported and modeled estimates.
A complete identity roster with no estimates is not a ready submission.

## 4. Review and dashboard integration

Check record counts and excluded fields against the source. Explain partial
coverage, suppressed cells, unmatched joins, and aggregate methods. Do not assume
`n_schools` is the number of all schools when the source counts only modeled
schools. Leave unavailable counts/shares blank, not zero.

Transfer only the three prepared CSV files to a dashboard test checkout's
`public/data/` tree; keep `report.json` with the supplier's review records. Merge
this state's `states.csv` row with the existing national file rather than
replacing the other states. Use the dashboard's state registration process.
Then, in that checkout:

```sh
npm run derive-county-csvs
npm run build-all-schools
npm run validate-data
npm test
npm run build
```

Review aggregate-consistency warnings; do not modify valid independent aggregate
estimates merely to make them match child rows. Test the national, state, county,
and download views, particularly with empty lower-level files or grade-only data.
A passing supplier validation is not permission to mark a state ready without
this integration check. Dashboard fetching and missing-data display may need
changes for these partial-data profiles.

## Regression checks in this repository

```sh
python3 -m unittest discover -s tests -v
Rscript scripts/build-data/tests/testthat.R
```

The R helper suite needs `testthat` and `data.table`; NC execution additionally
needs `jsonlite`; the model adapter additionally needs `imuGAP` and a compatible
fit/toolchain. The helper suite alone does not exercise real NC or CA inputs.
