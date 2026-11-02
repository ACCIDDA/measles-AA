# Optional data builders

The default workflow accepts mapped CSVs. The R builders support two additional
input contracts and emit the same `State.csv`, `Counties.csv`, `Schools.csv`, and
`Meta.json` bundle. Run them from the repository root, then run `prepare.py` on
their output. Each builder requires a completed metadata file and a new output
directory; no state identity is embedded in the code.

Install `data.table` and `jsonlite`. Install `testthat` to run the R suite.
Record package versions with the source processing records.

## Existing estimates and geography

```sh
INPUT_DIR=inputs/estimates META_PATH=inputs/Meta.json \
OUT_DIR=output/estimates Rscript scripts/build-data/build_from_estimates.R
python3 scripts/prepare.py prepare --input output/estimates --output output/prepared
```

The input directory contains:

| File | Required structure |
| --- | --- |
| `estimates.csv` | `id`, `est`, `ci_low`, `ci_high`, `population`, `age_group` |
| `locations.geojson` | A FeatureCollection of school Points and county Polygons |

School features use `location_id` and `NAME`; optional `coverage`, `cov_low`,
and `cov_high` properties supply overall coverage and intervals. County features
use a unique `NAME` and the same optional measurement properties. Coverage uses
proportions. Keep location IDs as strings to preserve leading zeros.

Estimate IDs must match school locations. Age groups `5_6`, `6_7`, `7_8`, `8_9`,
`9_10`, and `10_11` map to grades K–5. Missing grades remain blank. Duplicate
school/age-group estimates and unknown age groups fail instead of being averaged.

Points and polygons must share a coordinate system suitable for planar
point-in-polygon assignment. Only closed, single-ring Polygons are supported;
holes and other geometry types fail explicitly. Schools without a county match
fail. Review boundary and overlapping-polygon assignments: the geometry helper
uses the first containing polygon. Output longitude and latitude remain blank.

County coverage comes directly from polygon properties. School enrollment uses
the maximum available grade population. State coverage uses enrollment-weighted
school coverage, excluding unavailable values and nonpositive or missing weights.
A missing denominator produces a blank estimate. Counts include supplied school
locations, while below-threshold shares use schools with overall coverage.
These policies must match the source definition before using this builder;
otherwise map the source into the CSV templates with a documented transformation.

## Fitted model

Install the `imuGAP` version and toolchain compatible with the supplied fit.

```sh
FIT_PATH=inputs/model/fit.rds \
CLEANED_PATH=inputs/model/cleaned_data.rds \
LINKAGE_PATH=inputs/model/linkage_key.rds \
META_PATH=inputs/Meta.json OUT_DIR=output/model \
COV_CACHE=output/model-cache.rds \
Rscript scripts/build-data/build_state.R
python3 scripts/prepare.py prepare --input output/model --output output/prepared
```

The fit supplies location nodes and predictions. The cleaned data requires
`school_name`, `county_name`, `year`, `enrollment`, `current`, `lon`, and `lat`.
The linkage table requires `school_id`, `school_loc_id`, `county_loc_id`,
`school_name`, and `county_name`. These are standardized RDS objects, not raw
spreadsheets. Review `assemble()` when adapting an upstream cleaning workflow.

The builder predicts grades K–5, joins schools by normalized name and county,
selects the latest cleaned row, prefers available reported kindergarten coverage,
and retains linkage schools without fitted estimates as `no_data`. Review
ambiguous joins, model coverage gaps, and the combination of reported and modeled
values. County and state coverage come from modeled location nodes; school-count
statistics exclude schools without fitted coverage.

The optional prediction cache records the fit checksum, producer/helper code
checksums, and `imuGAP` version. A mismatch regenerates predictions.
`FORCE_PREDICT=1` forces regeneration. `CHUNK_NODES` controls prediction batch
size. Validation of a real fit remains part of the supplier's integration review.
