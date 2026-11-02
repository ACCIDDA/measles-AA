# Data contract maintenance

The consumer is [measles-dashboard](https://github.com/kgbrown5/measles-dashboard).
The CSV contract in `schema/dashboard-schema.json` is an exact snapshot of its
`src/data/schema.js` export, verified against commit
`09e090d024a8baa4cae64e4310ea4eafa560e5b6`.
The R helpers and builders originate from consumer commit
`6655c7e54a9739380c3cf4eb64c2ba1bc9393b7b` and are maintained here as configurable
submission producers.

The flat submission filenames map to the consumer's logical schemas:

| Submission file | Pinned schema key | Deployment path |
| --- | --- | --- |
| `State.csv` | `data/states.csv` | `data/state.csv` |
| `Counties.csv` | `data/states/{state}.csv` | `data/counties.csv` |
| `Schools.csv` | `data/states/{state}/schools.csv` | `data/schools.csv` |
| `Meta.json` | `schema/meta-schema.json` | `data/meta.json` |

The JSON snapshot retains consumer schema keys for traceability, including
national and per-county download shapes. Those derived files are not supplier
templates. Each supplier submits one state, while national aggregation belongs
to the consumer.

The metadata fields preserve the state configuration object formerly defined
in `src/config/states.js`. The inspected consumer now loads this object from
each deployment's `data/meta.json`; its map loader reads the three lowercase
CSV paths shown above. The supplier's capitalized filenames are converted only
by the explicit export command.

The Python validator implements the consumer's numeric bounds, enumerations,
patterns, tier tolerance, and advisory aggregate checks without frontend
dependencies. It adds submission-level requirements: metadata, identities,
relationships, interval ordering, missing-data consistency, and at least one
coverage measurement. Passing supplier validation is therefore more restrictive
than cell conformance alone.

When updating the contract:

1. Inspect the consumer's schema, validation rules, metadata, and fetching paths
   at a specific commit.
2. Update the JSON snapshot deliberately; regenerate the three CSV template
   headers from the corresponding `columns` arrays in schema order.
3. Update metadata rules, producer helpers, export paths, and regression tests
   when the contract changes.
4. Run both test suites and validate a representative prepared bundle against
   the intended consumer version, including partial-data profiles.
5. Record the verified consumer commit and any migration requirements here.

CSV templates must contain exactly one header row and no observations. The JSON
template contains all metadata keys with empty strings. Tests enforce template
alignment with the pinned contract. These empty templates are intentionally not
publishable submissions.
