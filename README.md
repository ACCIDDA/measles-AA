# State data preparation for the measles dashboard

`measles-AA` is the template for state repositories such as `measles-NC` and
`measles-CA`. States supply the information they actually have, prepare it, and
validate a common CSV bundle for the static dashboard.

Iteration 1 extracts the existing NC and CA/model adapters and adds a minimal
CSV preparation path. Cross-repository publishing Actions are a later step.

## Quick start

Use Python 3.10+; no third-party Python packages are needed. From the repo root:

```sh
python3 scripts/prepare.py prepare --input examples/minimal --output /tmp/measles-example --state nc
python3 scripts/prepare.py validate --input /tmp/measles-example --state nc
python3 -m unittest discover -s tests -v
```

The output directory must not already exist. The example is **synthetic** and
must never be published as real NC data. Copy its structure into local `inputs/`
and replace its values with your approved data. Raw inputs and generated output
are ignored by Git by default; review data before deliberately publishing it.

## Minimum submission

Every submission needs `states.csv` with exactly one state identity row and at
least one coverage measurement (overall or per-grade) somewhere in the bundle.
County and school records are optional; supply only what is available.

| Input file | Required identity cells for each supplied row |
| --- | --- |
| `states.csv` | `state`, `state_fips`, `state_name` |
| `states/nc.csv` | `county` |
| `states/nc/schools.csv` | `school_id`, `county` |

Replace `nc` with your lowercase state code. Supplied school counties need
county identity rows, but those rows can have blank coverage. Use stable school
IDs with a documented source or assignment process. School names are recommended
but may be unavailable. County names must match the dashboard geography.

**Missing measurements are not zero.** Grades, credible intervals, enrollment,
coordinates, county FIPS, and aggregate statistics can be blank. Do not invent
records or measurements to fill the schema. Preparation supplies complete
ordered headers and header-only files for unavailable geographic levels.

These are iteration-1 submission requirements, not a claim that every partial
bundle is already supported throughout the dashboard. State-only, county-only,
and grade-only display behavior needs integration testing before publication.

See [validation instructions](docs/VALIDATION.md) and the
[NC/CA adapters and iteration plan](docs/ITERATION-1.md).
