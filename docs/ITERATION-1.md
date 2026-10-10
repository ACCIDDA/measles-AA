# Iteration 1: extraction and integration plan

## Provenance and scope

Copied from the local `kgbrown5/measles-dashboard` fork (upstream
`ACCIDDA/measles-dashboard`) at commit
`6655c7e54a9739380c3cf4eb64c2ba1bc9393b7b`:

- `scripts/build-data/build_nc_from_estimates.R`
- `scripts/build-data/build_state.R`
- `scripts/build-data/R/producer-helpers.R`
- `scripts/build-data/tests/`

The R scripts and tests are retained unchanged as reference adapters.
`schema/dashboard-schema.json` is a snapshot serialized from that commit's
`src/data/schema.js` SCHEMA export. The dashboard remains the upstream contract
owner; refresh this snapshot deliberately alongside adapter compatibility tests.
No model fit, source dataset, frontend, or credentials are copied here.

These adapters consume estimates or cleaned/model inputs. They are not the
upstream raw-data cleaning pipeline. `build_state.R` references outputs of
`tidyschoolvax/run_imugap`; those upstream cleaning scripts and their maintainers'
requirements were not present in the inspected dashboard checkout. Obtaining and
reviewing them remains necessary before promising arbitrary raw-state uploads.

## NC: existing estimates and geography

Install `data.table` and `jsonlite` in your R environment. From this repo root:

```sh
NC_IN=inputs/nc OUT_DIR=output/nc-adapter Rscript scripts/build-data/build_nc_from_estimates.R
python3 scripts/prepare.py prepare --input output/nc-adapter --output output/nc-bundle --state nc
python3 scripts/prepare.py validate --input output/nc-bundle --state nc
```

Input directory requirements from the original adapter:

- `estimates.csv`: `id`, `est`, `ci_low`, `ci_high`, `population`, `age_group`
  (the source also carries `is_est`, which is not published). Age groups
  `5_6` through `10_11` map to K–5; values are proportions.
- `locations.geojson`: school Points and county Polygons in EPSG:2264, with
  `NAME`, school `location_id`, and coverage/interval properties. The adapter's
  header and property accesses document the detailed expected shape.

It joins estimates to schools, assigns counties by point-in-polygon, reshapes
K–5 values, uses source county estimates, and derives enrollment-weighted state
coverage. This is a source-specific policy, not a default for other states.

Known constraints: assumes all six grade columns; polygon logic uses outer rings
only (not holes or MultiPolygons); unmatched counties can lead to omitted schools;
enrollment uses the maximum grade population; school coordinates are left blank.
Review join counts and these assumptions before publication. Historical per-county
files from this adapter lack newer identity columns; the generic preparation step
excludes those derived files and the dashboard rebuilds them from `schools.csv`.

## CA / generic fitted-model adapter

Install `data.table`, a compatible `imuGAP`, and the toolchain used for the supplied
fit. Obtain approved model inputs separately. From the repo root:

```sh
FIT_PATH=inputs/ca/fit.rds \
CLEANED_PATH=inputs/ca/cleaned_data.rds \
LINKAGE_PATH=inputs/ca/linkage_key.rds \
STATE=ca STATE_FIPS=06 STATE_NAME=California \
COV_CACHE=output/ca-cache.rds FORCE_PREDICT=1 \
OUT_DIR=output/ca-adapter Rscript scripts/build-data/build_state.R
python3 scripts/prepare.py prepare --input output/ca-adapter --output output/ca-bundle --state ca
python3 scripts/prepare.py validate --input output/ca-bundle --state ca
```

The fit supplies modeled location nodes and predictions. `cleaned_data` supplies
school name/county, year, enrollment, current vaccination count, and lon/lat.
`linkage_key` supplies school/model/county identifiers and names. See `assemble()`
for the exact accesses; RDS shape must match that adapter's expectations.

This path predicts K–5 coverage and intervals, bridges school IDs using normalized
name+county, prefers reported kindergarten coverage where available, and keeps
linkage schools without fit estimates as `no_data`. It assumes much more than
the minimum CSV path and must not be required of every state.

Review unmatched/ambiguous joins, the latest-year selection, and the mixture of
reported kindergarten and modeled values. Use a distinct cache for every fit or
force regeneration; the original cache is not keyed by input contents. The
`STUB=1` path fabricates coverage for development and must never be published.

## Next milestones

1. Obtain upstream NC/CA raw cleaning scripts and approved representative inputs;
   verify the copied adapters against actual source outputs and document changes.
2. Test state-only, county-only, school-only estimates with county identity rows,
   and missing-grade bundles in the dashboard. Resolve missing-data display and
   registration behavior before enabling these sources.
3. Define state metadata/provenance and versioned output manifests. Keep one
   schema contract across producers and consumer; add representative fixtures.
4. Add supplier Actions that prepare, validate, and publish only reviewed output.
   Add a dashboard collection workflow for registered state sources, merging
   state summaries and rebuilding national/per-county downloads. A failed update
   must not overwrite the last valid dataset.
5. Pilot NC then CA, check dashboard parity, and document the fork/setup workflow.

The consumer remains a static GitHub Pages dashboard. Its public CSV URLs can
continue to serve the combined API even when preparation belongs to state repos.
No cross-repository publishing or registration automation is included yet.
