# Data preparation and publication instructions

Run commands from the repository root. Python 3.10+ is required; the Python
workflow has no third-party dependencies. R is needed only for optional builders.

## 1. Map source data

Record the source owner/URL, reporting period, population/grades, MMR dose,
units, suppression rules, and whether values are reported or modeled. Retain
original files and transformation code. Publish aggregate coverage records only.

```sh
mkdir -p inputs
cp templates/* inputs/
```

Populate these files using the template headers:

| File | Required contents |
| --- | --- |
| `State.csv` | Exactly one row with `state`, `state_fips`, and `state_name` |
| `Counties.csv` | Unique `county` identities and available measurements |
| `Schools.csv` | Unique, stable `school_id` values; each `county` must match a county row |
| `Meta.json` | The seven metadata strings below; no extra or duplicate keys |

County and school tables may be header-only. County identity rows may have
blank measurements. A completed bundle needs at least one overall or K–5
coverage measurement at any level. Blank templates intentionally fail validation.

- Use proportions in `[0, 1]`, never percentages. Leave missing/suppressed values
  blank; map source suppression markers explicitly. `NA`, `NaN`, infinity, and
  text markers are invalid numeric cells. Do not replace missing values with zero
  or invent intervals, grade estimates, or totals.
- Preserve leading zeros in IDs. State FIPS accepts one or two digits in CSV,
  but metadata requires two. Optional county FIPS must have five digits, be
  unique, and start with the state FIPS.
- County names must match the dashboard geography. Coordinates, if supplied,
  must be longitude/latitude degrees; transform projected coordinates upstream.
- Use one reporting period/population and document aggregation methods,
  denominators, and the source or assignment rule for school IDs.

| Metadata field | Requirement |
| --- | --- |
| `code` | Lowercase two-letter code matching `State.csv` |
| `name` | Uppercase version of `code` |
| `fullName` | State display name matching `state_name` |
| `dataDir` | Identifier containing only letters, digits, underscores, or hyphens |
| `fips` | Two digits matching zero-padded `state_fips` |
| `sourceUrl` | Absolute HTTP(S) attribution URL |
| `sourceLabel` | Nonempty source display label |

All metadata values must be nonempty, trimmed strings. Metadata is preserved
during preparation. Validation checks internal state identity agreement, not
whether the code/name/FIPS is officially assigned.

## 2. Prepare, validate, and review

```sh
python3 scripts/prepare.py prepare --input inputs --output output/prepared
python3 scripts/prepare.py validate --input output/prepared
```

Use a new output directory outside the input folder for each run. Inputs are
never overwritten. Optional `--state xx` asserts an expected state code; otherwise
the code comes from metadata. `inputs/` and `output/` are ignored by Git.

Preparation trims CSV cells, orders schema columns, adds missing optional columns,
and reports excluded columns/files. Missing county/school files become header-only
tables; state and metadata files are required. It derives a missing `tier` from
overall coverage (`H` ≥ .95, `M` ≥ .90, otherwise `L`) and a missing school
`no_data` flag from the presence of overall or per-grade coverage. It does not
infer units, aggregate records, or repair invalid measurements.

Both commands reject invalid numeric values, duplicate/missing identities,
orphan school counties, inconsistent metadata/FIPS, reversed interval bounds,
inconsistent tiers (with .0005 boundary tolerance), and `no_data=1` alongside
coverage fields. Validation also requires all four files, exact ordered headers,
trimmed cells, and no extra files except `report.json`. Failures return a nonzero
exit status; validation never modifies data.

Review `report.json` for excluded fields/files, aggregate warnings, and input
SHA-256 checksums. Coverage outside the range of child records is advisory:
independent aggregate estimates can legitimately differ. Retain the report,
source versions, transformation code, and dependency versions as review records.

Before publication, compare counts, joins, omissions, suppression, and denominators
with the source. Confirm the vaccine/dose/year, official state identity, county
aliases, coordinates, source permissions, and modeling methods independently.
Point-estimate/interval consistency needs review when reported and modeled values
are combined. Automated conformance checks cannot establish these facts.

## 3. Export and submit for the CI check

The dashboard's API is static files fetched over HTTP. Its
[map loader](https://github.com/kgbrown5/measles-dashboard/blob/1fe95b854c43dbcb3fa72cfac5ff4209c292f449/src/hooks/useUnifiedMapData.js)
fetches `data/state.csv`, `data/counties.csv`, and `data/schools.csv` from each
registered supplier URL; its
[metadata loader](https://github.com/kgbrown5/measles-dashboard/blob/1fe95b854c43dbcb3fa72cfac5ff4209c292f449/src/config/states.js)
fetches `data/meta.json`. The capitalized bundle is an intermediate preparation
format. Commit the lowercase export for publication; both formats need not be
published. The consumer's older API docs still describe central `states/` paths,
which are not the supplier URLs used by these loaders.

```sh
python3 scripts/prepare.py export --input output/prepared --output output/site
mkdir -p data
cp output/site/data/* data/
python3 scripts/prepare.py validate-published --input data
```

Export revalidates the prepared bundle and produces these publication paths:

| Prepared file | Committed/dashboard path | Pinned schema key |
| --- | --- | --- |
| `State.csv` | `data/state.csv` | `data/states.csv` |
| `Counties.csv` | `data/counties.csv` | `data/states/{state}.csv` |
| `Schools.csv` | `data/schools.csv` | `data/states/{state}/schools.csv` |
| `Meta.json` | `data/meta.json` | `schema/meta-schema.json` |

Commit the four files in `data/` together and open a pull request. Keep reports
and source documentation outside `data/`; that directory must contain only the
four publication files. `validate-published` applies the same strict checks
directly to lowercase publication files, without preparing or rewriting them.

The [Validate workflow](../.github/workflows/validate.yml) runs on pull requests,
pushes, merge queues, and manual dispatch. It supplies three status checks:

| Check | What it validates |
| --- | --- |
| `Python contract tests` | Preparation, validation, export, and template/schema regression tests |
| `R builder tests` | R helpers and an estimates-to-bundle integration test, with required packages installed |
| `Published data validation` | Preparation/export example, then the actual committed `data/` bundle |

The third check is a repository check after local preparation and review. It
fails for malformed or incomplete publication data, including deletion of all
published files. Before any `data/` exists in the branch history, it explicitly
reports that no submission is present; only the fictional example is exercised.
Warnings remain advisory and appear in the Actions log. No production fit is
available here, so CI does not run `imuGAP` prediction.

After the first workflow run, a repository administrator should require all three
named checks in the default branch ruleset and require pull requests. A failed
push check alone cannot prevent a direct commit from being served. Any deployment
workflow must wait for successful validation before publishing. If an automated
publisher commits with `GITHUB_TOKEN`, its push does not normally start another
workflow: call validation in the publishing workflow before deployment, or
explicitly dispatch this workflow. See GitHub's
[workflow trigger rules](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow).

Hosting and dashboard registration remain separate operations: serve `data/`
at the supplier base URL with cross-origin access, add that URL (with a trailing
slash) to the dashboard's `public/data/stateRegistry.json`, and mark the state
`ready` in `public/data/states.json` to enable county/school loading. Committing
files here alone does not host them or register the supplier. Test the dashboard's
national, state, county, and school views, especially header-only levels,
grade-only coverage, attribution, and suppression. Downloads are disabled in the
inspected consumer; verify them if re-enabled.

## Optional R builders

Use a builder only if its input and aggregation policies fit the source.
Install `data.table` and `jsonlite`, supply completed metadata, and use a new
output directory. Run `prepare.py prepare` on the builder output before export.

### Existing estimates and geography

```sh
INPUT_DIR=inputs/estimates META_PATH=inputs/Meta.json \
OUT_DIR=output/estimates Rscript scripts/build-data/build_from_estimates.R
python3 scripts/prepare.py prepare --input output/estimates --output output/prepared
```

`INPUT_DIR` contains `estimates.csv` with `id,est,ci_low,ci_high,population,age_group`
and `locations.geojson`, a FeatureCollection of school Points and county Polygons.
School properties require string `location_id` and `NAME`; counties require unique
`NAME`. Optional `coverage`, `cov_low`, and `cov_high` properties supply overall
coverage and intervals as proportions. Estimate IDs must match school locations.
Age groups `5_6`, `6_7`, `7_8`, `8_9`, `9_10`, `10_11` map to K–5; missing grades
stay blank. Duplicate school/age rows and unknown ages fail.

Geometry must share a coordinate system suitable for planar point-in-polygon
assignment. Only closed, single-ring Polygons are supported; holes and other
geometry types fail. Every school must match a county. Review boundaries and
overlaps because the first containing polygon wins. Output coordinates stay blank.

County coverage comes from polygon properties. School enrollment is the maximum
grade population; state coverage is enrollment-weighted school coverage, excluding
missing coverage and missing/nonpositive weights. No denominator yields a blank
estimate. School counts include all supplied locations; below-threshold shares
use only schools with overall coverage. Map CSVs directly if these policies do
not match the source.

### Fitted model

Install the `imuGAP` version/toolchain compatible with the fit, then run:

```sh
FIT_PATH=inputs/model/fit.rds \
CLEANED_PATH=inputs/model/cleaned_data.rds \
LINKAGE_PATH=inputs/model/linkage_key.rds \
META_PATH=inputs/Meta.json OUT_DIR=output/model \
COV_CACHE=output/model-cache.rds Rscript scripts/build-data/build_state.R
python3 scripts/prepare.py prepare --input output/model --output output/prepared
```

The cleaned RDS table requires `school_name`, `county_name`, `year`, `enrollment`,
`current`, `lon`, `lat`. Linkage requires `school_id`, `school_loc_id`,
`county_loc_id`, `school_name`, `county_name`. These are standardized inputs;
review `assemble()` when adapting source cleaning.

The builder predicts K–5, joins normalized school/county names, selects the latest
cleaned row, prefers available reported kindergarten coverage for fitted schools,
and retains linkage schools without fitted estimates as `no_data`. County/state
coverage comes from modeled nodes; school-count statistics exclude schools without
fitted coverage. Review ambiguous joins, coverage gaps, and mixed reported/modeled
values with a real fit before publication.

The optional prediction cache checks the fit/code checksums and `imuGAP` version.
`FORCE_PREDICT=1` regenerates it; `CHUNK_NODES` controls batch size.

## Maintaining the contract

[`schema/dashboard-schema.json`](../schema/dashboard-schema.json) is the consumer
`src/data/schema.js` snapshot verified at
`1fe95b854c43dbcb3fa72cfac5ff4209c292f449` in
[measles-dashboard](https://github.com/kgbrown5/measles-dashboard).
R builders/helpers originated at `6655c7e54a9739380c3cf4eb64c2ba1bc9393b7b`.
The snapshot includes derived national/per-county shapes; those are not supplier
submissions. Each bundle represents one state.

When updating, inspect the consumer schema, validation, metadata, and fetch paths
at a specific commit. Update the snapshot, template headers, metadata rules,
builders/helpers, export paths, and tests together. Keep CSV templates header-only
and metadata placeholders empty. Run the checks below, validate representative
partial-data bundles against the consumer, and update the verified commit here.

```sh
python3 -m unittest discover -s tests -v
Rscript scripts/build-data/tests/testthat.R
```

R checks require `testthat`, `data.table`, and `jsonlite`. The Python estimates
tests skip locally if R dependencies are absent; CI installs and verifies them.
For a fictional end-to-end trial, replace `inputs` in step 2 with `examples/minimal`.
