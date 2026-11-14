# Data preparation and publication instructions

Use this guide in your own state data repository created from this template.
Upload or edit completed files under `data/` and open a pull request for automated
validation. For local preparation, run the commands below from your repository root.

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

Copy the template files into `data/` using GitHub's file editor or these local commands:

```sh
mkdir -p data
cp data/templates/* data/
```

The CSV templates contain headers only; the metadata template contains empty
fields. Populate these files directly in `data/`:

| File | Required contents |
| --- | --- |
| `state.csv` | Exactly one row with `state`, `state_fips`, and `state_name` |
| `counties.csv` | Unique `county` identities and available measurements |
| `schools.csv` | Unique, stable `school_id` values; each `county` must match a county row |
| `meta.json` | The seven metadata strings below; no extra or duplicate keys |

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
| `code` | Lowercase two-letter code matching `state.csv` |
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

For local preparation and complete submission validation, use Python 3.10+.
The optional R builders prepare data and validate metadata using R. An independent
R route for complete submission validation remains to be implemented.

```sh
python3 scripts/prepare.py prepare --input data --output output/prepared
python3 scripts/prepare.py validate --input output/prepared
```

For a local trial with fictional data, use `data/examples` as the input and
`output/example` as the output. The example is a development fixture.

Use a new output directory outside the input folder for each run. Inputs are
never overwritten. Optional `--state xx` asserts an expected state code; otherwise
the code comes from metadata. `output/` is ignored by Git; completed `data/`
files are committed after review.

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
trimmed cells, and no extra files except `report.json`. The reserved `templates/`
and `examples/` subdirectories are skipped during preparation, validation, and
input checksumming. Failures return a nonzero exit status; validation never
modifies data.

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
fetches `data/meta.json`. Export revalidates the prepared bundle and places
these four files under a `data/` subdirectory for deployment.

```sh
python3 scripts/prepare.py export --input output/prepared --output output/site
mkdir -p data
cp output/site/data/* data/
python3 scripts/prepare.py validate-published --input data
```

For submissions prepared through GitHub, upload or edit the four completed files
directly in `data/`, following the file requirements above. GitHub Actions validates
the submitted files as they are; source mapping and preparation happen before submission.

Commit the four files in `data/` together and open a pull request into your own
repository's default branch. Keep reports and source documentation outside
`data/`. `validate-published` applies the strict checks directly to the publication
files, without preparing or rewriting them; it also rejects `report.json`.

The [Validate workflow](../.github/workflows/validate.yml) runs on pull requests,
pushes, merge queues, and manual dispatch. It supplies three status checks:

| Check | What it validates |
| --- | --- |
| `Python contract tests` | Preparation, validation, export, and template/schema regression tests |
| `R builder tests` | R helpers and an estimates-to-bundle integration test, with required packages installed |
| `Published data validation` | Preparation/export example, then the actual committed `data/` bundle |

The third check validates the committed submission after preparation and review. It
fails for malformed or incomplete publication data, including deletion of all
published files. Before any publication files exist in the branch history
(excluding `data/templates/` and `data/examples/`), it explicitly
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

## 4. Publish your data with GitHub Pages

Do this in your state data repository before registering it with the dashboard.
The template validates files; the dashboard registration workflow records their
hosting address. Neither currently enables GitHub Pages for your repository.

1. Merge the reviewed data into your public repository's default branch after
   the validation checks pass. Include an empty `.nojekyll` file at the repository
   root to publish the files without Jekyll processing.
2. Open **Settings → Pages** in that repository. Under **Build and deployment**,
   select **Deploy from a branch**, choose your default branch (usually `main`),
   select **/(root)**, and save. You need permission to manage Pages settings.
3. Wait for the Pages build and deployment to finish in **Actions**. Copy the
   site address displayed in **Settings → Pages**. For a standard project site,
   it is `https://OWNER.github.io/REPOSITORY/`.
4. Open each of these addresses, replacing `OWNER` and `REPOSITORY` with yours,
   and confirm that it serves the expected file:

   ```text
   https://OWNER.github.io/REPOSITORY/data/state.csv
   https://OWNER.github.io/REPOSITORY/data/counties.csv
   https://OWNER.github.io/REPOSITORY/data/schools.csv
   https://OWNER.github.io/REPOSITORY/data/meta.json
   ```

These files are the provider's API; no separate web application is required.
If a file returns 404, check the deployment result, selected branch, and committed
`data/` files before registering. See GitHub's
[Pages publishing instructions](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

After this one-time setup, pushes to the publishing branch trigger deployment.
Branch-based Pages publishing does not wait for this template's validation
workflow, so require passing checks before merging changes into that branch.
The `GITHUB_TOKEN` publishing exception described above still applies.

## 5. Register with the dashboard

Follow the dashboard's
[registration instructions](https://github.com/kgbrown5/measles-dashboard/blob/dev/docs/REGISTRATION.md):
run **Register State Repository** in the dashboard repository with your state
code and state repository's HTTPS GitHub URL. The workflow validates the repository
data and opens a registration PR for review.

The current registration script generates `base_url` using the standard
`https://OWNER.github.io/REPOSITORY/` pattern. Confirm that the PR's address matches
your working Pages address, especially after a repository rename or when using
a custom domain. Registration checks repository files through GitHub's API;
it does not establish that the hosted files are reachable.

After the registration is merged and the dashboard is deployed, confirm that
your state, counties, schools, attribution, and missing values display correctly.

## Optional R builders

Use a builder only if its input and aggregation policies fit the source.
Install `data.table`, `jsonlite`, and `jsonvalidate`, supply completed metadata,
and use a new output directory. Keep raw builder sources outside the publication directory;
the examples below use the ignored `output/sources/` working directory.
Run `prepare.py prepare` on the builder output before export.

Builders validate metadata against `schema/meta-schema.json`, then check trimmed
values and agreement between the state code and name.

### Existing estimates and geography

```sh
INPUT_DIR=output/sources/estimates META_PATH=data/meta.json \
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
FIT_PATH=output/sources/model/fit.rds \
CLEANED_PATH=output/sources/model/cleaned_data.rds \
LINKAGE_PATH=output/sources/model/linkage_key.rds \
META_PATH=data/meta.json OUT_DIR=output/model \
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


## Development checks

Run the test suites when changing the preparation tools or builders:

```sh
python3 -m unittest discover -s tests -v
Rscript scripts/build-data/tests/testthat.R
```

The R suite requires `testthat`, `data.table`, `jsonlite`, and `jsonvalidate`.
Python tests also exercise the estimates builder when R and its dependencies
are available.
