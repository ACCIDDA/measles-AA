# Data preparation and publication instructions

Use this guide in your own state data repository created from this template.
Run commands from your repository root. Python 3.10+ is required; the Python
workflow has no third-party dependencies. R is needed only for optional builders.

## Set up your repository once

The template includes `.github/workflows/validate.yml`, so you do not need to
write CI checks. GitHub settings for running checks and requiring them before
merging are configured in your own repository.

1. Keep the workflow file on your default branch. Open your repository's
   **Actions** tab and enable Actions if prompted. Forks require this explicitly;
   see [GitHub's fork workflow guidance](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflows-in-forked-repositories).
2. Run **Actions → Validate → Run workflow** on your default branch, or push a
   commit to trigger it. The checks install their own dependencies and need no
   additional secrets.
3. To prevent merging invalid data, have an administrator open **Settings →
   Rules → Rulesets** and create an active branch ruleset targeting your default
   branch. Require pull requests and the three status checks listed under
   "Export and submit for the CI check" below, unless your organization already
   enforces them. These requirements are
   GitHub settings, not part of the copied workflow file. See
   [GitHub's ruleset setup](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository).

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

For a fictional trial before mapping your own data, use `examples/minimal`
instead of `inputs` in the preparation command below.

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
published.

```sh
python3 scripts/prepare.py export --input output/prepared --output output/site
mkdir -p data
cp output/site/data/* data/
python3 scripts/prepare.py validate-published --input data
```

Export revalidates the prepared bundle and produces these publication paths:

| Prepared file | Committed/dashboard path |
| --- | --- |
| `State.csv` | `data/state.csv` |
| `Counties.csv` | `data/counties.csv` |
| `Schools.csv` | `data/schools.csv` |
| `Meta.json` | `data/meta.json` |

Commit the four files in `data/` together and open a pull request into your own
repository's default branch. Keep reports
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
Warnings remain advisory and appear in the Actions log. CI checks exported data
and synthetic builder fixtures; validate your own model fit separately if using
the fitted-model builder.

Wait for all three checks to pass before merging. If your repository deploys
automatically, make deployment wait for validation: a failed push check alone
does not stop hosting. If your automated publisher commits with `GITHUB_TOKEN`,
its push does not normally start another
workflow: call validation in the publishing workflow before deployment, or
explicitly dispatch this workflow. See GitHub's
[workflow trigger rules](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow).

To make your data available to the dashboard, configure hosting for your
repository so the four `data/` URLs are publicly accessible with cross-origin
access. Send your state code and deployed base URL (with a trailing slash) to
the dashboard maintainers for registration and activation. Confirm that your
state, counties, schools, attribution, and missing values display correctly.

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
