# Preparing and validating a submission

## Establish the source contract

Record the source owner and URL, reporting period, population and grades,
MMR dose definition, units, suppression rules, and whether values are reported
or modeled. Retain the original files and document every transformation in the
supplier repository. Public outputs should contain aggregate coverage records;
exclude student-level information and unrelated personal data.

Select a consistent reporting period and population. A schema check cannot
establish that a measurement describes the intended vaccine, dose, or year.
Document aggregate methods and the denominator used for school counts and shares.

## Complete the templates

Copy `templates/State.csv`, `Counties.csv`, `Schools.csv`, and `Meta.json` into
`inputs/`. Map source columns to the pinned schema before preparation. For
supported estimates or fitted-model inputs, see [the builders](BUILDERS.md).

- `State.csv` needs exactly one row with `state`, `state_fips`, and `state_name`.
- Every county row needs `county`. Every school row needs `school_id` and `county`.
  School IDs must be stable and unique; document their source or assignment rule.
- School counties must match county identity rows. Those rows may have blank
  coverage. County names must also match the consumer's geography.
- Supply only available measurements. Header-only county and school files are
  valid when those levels are unavailable. At least one overall or per-grade
  coverage measurement must exist somewhere in a completed bundle.
- Preserve leading zeros in identifiers. State FIPS permits one or two digits
  in the CSV; metadata requires two digits. Supplied county FIPS requires five.
- Use proportions in `[0, 1]`. Convert percentages only when the source establishes
  the units. Literal `NA`, `NaN`, infinity, and suppression markers are invalid
  numeric cells. Map documented suppression markers to empty cells.
- Missing and suppressed measurements remain blank. Do not substitute zero,
  invent intervals, or manufacture per-grade estimates or totals.
- Coordinates must be longitude/latitude degrees. Transform projected coordinates
  before supplying them; do not simply rename coordinate columns.

Complete all seven metadata fields:

| Field | Requirement |
| --- | --- |
| `code` | Lowercase two-letter state code, matching `State.csv` |
| `name` | Uppercase abbreviation corresponding to `code` |
| `fullName` | State display name, matching `state_name` |
| `dataDir` | Data directory identifier using letters, digits, underscores, or hyphens |
| `fips` | Two-digit state FIPS, matching `state_fips` after zero-padding |
| `sourceUrl` | Absolute HTTP or HTTPS source attribution URL |
| `sourceLabel` | Nonempty display label for the source |

`Meta.json` must be a single object with these keys and string values. Unknown
or duplicate keys fail validation. Metadata is preserved during preparation;
empty placeholders are not valid submission metadata.

## Prepare the bundle

```sh
python3 scripts/prepare.py prepare --input inputs --output output/run-1
python3 scripts/prepare.py validate --input output/run-1
```

The optional `--state` argument asserts an expected state code; otherwise the
code comes from `Meta.json`. Output must be a new directory outside the input
folder. Inputs are never overwritten.

Preparation trims CSV cell whitespace, retains schema columns, adds missing
columns as blanks, and orders headers. Missing county or school files become
header-only files. `State.csv` and `Meta.json` are always required. Preparation
derives a missing `tier` from overall coverage and a missing school `no_data`
flag from the presence of overall or per-grade coverage. It does not aggregate
rows, infer units, repair invalid values, or silently discard invalid records.

Review `report.json`: excluded columns may reveal a misspelled measurement,
excluded files may contain data that should have been mapped, and advisory
warnings may identify aggregate discrepancies. Input SHA-256 checksums identify
the exact files used. Keep source versions, transformation code, and dependency
versions alongside this report to reproduce a run.

## Automated checks

Both preparation and validation fail for invalid types, non-finite values,
out-of-range measurements, malformed CSV records, duplicate identities, missing
identity cells, incorrect state identity, orphan school counties, invalid FIPS,
duplicate county FIPS, county FIPS from a different state, reversed interval
bounds, inconsistent tiers, or `no_data=1` with coverage fields populated.

Validation additionally requires all four files, exact ordered CSV headers,
trimmed cells, and no unexpected files other than `report.json`. Blank optional
cells remain valid. Tier checks retain the consumer's `0.0005` boundary tolerance.
State coverage outside the county coverage range, or county coverage outside the
school coverage range, produces advisory warnings without failing a submission.
Independent aggregate estimates may legitimately differ from child records.

A nonzero exit status indicates failure. Validation does not modify files.

## Review before publication

Compare record counts, joins, omitted measurements, suppression handling, and
aggregate denominators against the source. Confirm the state code/name/FIPS
combination against an authoritative geography source: validation checks their
internal agreement, not their official assignment. Confirm county aliases,
coordinate accuracy, source permissions, and modeling methodology independently.
Paired intervals are checked for order; consistency between a point estimate and
its interval requires review when reported and modeled values are combined.

```sh
python3 scripts/prepare.py export --input output/run-1 --output output/site
```

Export requires a fully valid prepared bundle and produces the four lowercase
files under `output/site/data/` expected by the dashboard. Retain `report.json`
with review records. Deploy the reviewed data and register the supplier base URL
through the consumer's maintained deployment process. This repository does not
publish data or change the consumer's registry automatically.

Test the national, state, county, school, and download views against the intended
consumer version. Pay particular attention to header-only lower levels,
grade-only coverage, attribution, and suppressed values. Supplier validation
alone does not establish correct display behavior for every partial-data profile.

## Regression checks

```sh
python3 -m unittest discover -s tests -v
Rscript scripts/build-data/tests/testthat.R
```

Use `testthat`, `data.table`, and `jsonlite` for R checks. Synthetic fixtures
exercise transformation and validation behavior. Production model fits and
source datasets require separate integration validation.
