# Measles data preparation template

This repository provides a reproducible workflow for preparing and validating
state, county, and school coverage data for the
[measles dashboard](https://github.com/kgbrown5/measles-dashboard).
It contains blank templates, a versioned data contract, preparation and
validation scripts, and optional R builders for estimates and fitted models.

## Submission files

Copy the files in `templates/` to a local `inputs/` directory. The CSV templates
contain headers only; `Meta.json` contains empty fields to complete.

| File | Contents |
| --- | --- |
| `State.csv` | Exactly one state identity row, with available summary measurements |
| `Counties.csv` | County identities and available measurements |
| `Schools.csv` | School identities, county assignments, and available measurements |
| `Meta.json` | State identity, display configuration, and source attribution |

Use the filenames and capitalization shown. Coverage values are proportions
between 0 and 1. Leave unavailable measurements blank. County and school tables
may be header-only; every school needs a matching county identity row. A completed
bundle needs at least one overall or per-grade coverage measurement.

## Prepare and validate

Python 3.10 or later is required; no third-party Python packages are needed.
Run commands from the repository root:

```sh
mkdir -p inputs
cp templates/* inputs/
# Populate the CSV files and complete inputs/Meta.json.
python3 scripts/prepare.py prepare --input inputs --output output/prepared
python3 scripts/prepare.py validate --input output/prepared
```

Preparation normalizes mapped CSVs, adds absent optional columns, and validates
the complete bundle before writing. It does not interpret arbitrary spreadsheets
or estimate missing measurements. Each run requires a new output directory.
Review `report.json` for excluded fields, advisory warnings, and source-file
checksums. Local inputs and generated outputs are ignored by Git.

To exercise the workflow with fictional data:

```sh
python3 scripts/prepare.py prepare --input examples/minimal --output output/example
python3 scripts/prepare.py validate --input output/example
```

The example uses a fictional identity and is only a development fixture.
Blank templates are starting points and intentionally fail submission validation.

## Dashboard handoff

```sh
python3 scripts/prepare.py export --input output/prepared --output output/site
```

Export validates the prepared bundle and writes `data/state.csv`,
`data/counties.csv`, `data/schools.csv`, and `data/meta.json` beneath the new
output directory. These lowercase paths match the consumer's deployment
contract. Publishing and registry changes are separate operations.

See [validation and review](docs/VALIDATION.md),
[optional data builders](docs/BUILDERS.md), and
[contract maintenance](docs/DATA-CONTRACT.md).

## Development checks

```sh
python3 -m unittest discover -s tests -v
Rscript scripts/build-data/tests/testthat.R
```

The R suite requires `testthat`, `data.table`, and `jsonlite`. Python tests also
exercise the estimates builder when R and its dependencies are available.
The fitted-model builder additionally requires a compatible `imuGAP` installation.
