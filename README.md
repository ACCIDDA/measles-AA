# Measles data preparation template

This template helps state data contributors prepare vaccination coverage data
for the [measles dashboard](https://github.com/kgbrown5/measles-dashboard).
It provides a common format for state, county, and school records, along with
metadata describing the state and its data sources.

The repository includes:

- `data/`: completed submission files, with blank starting files in `templates/`
  and fictional sample data in `examples/`.
- `schema/`: the versioned data contract used to check submissions.
- `scripts/`: preparation, validation, and export tools, plus optional R builders
  for existing estimates and fitted models.
- `tests/` and a GitHub Actions workflow: automated checks for the tools and
  submitted data.

The workflow takes mapped source data through preparation, validation, and export
for dashboard publication. Contributors remain responsible for reviewing their
sources, measurements, and modeling choices.

See the [data preparation and publication instructions](docs/instructions.md)
for setup, file requirements, commands, review steps, and dashboard handoff.
