# Fit-independent helpers shared by the #20 CSV producers.
#
# These functions hold the discrete, pure logic the producers depend on but that
# does NOT require a fitted imuGAP object: point-in-polygon county assignment,
# county-name title-casing, coverage-gap (school-in-linkage-not-in-fit)
# detection, and the wide #20 schema column order. They are factored out so both
# build_state.R and build_nc_from_estimates.R can source() them, and so the
# producer-tests workflow can exercise them with tiny synthetic fixtures instead
# of the 484 MB CA stanfit.
#
# Keep this file dependency-light: data.table is the only hard dependency, and
# only cov_block()/the schema helpers touch it indirectly. The geometry and
# string helpers are base R so they can be tested without sf/imuGAP installed.

# ---- string + slug helpers ----

# Lowercase, collapse non-alphanumerics to single hyphens. Used for file slugs.
slugify <- function(x) gsub("[^a-z0-9]+", "-", tolower(trimws(x)))

# Title-case county names so they match the us-atlas polygon names the dashboard
# joins on (linkage_key ships them lowercased, e.g. "los angeles" -> "Los Angeles").
# This is the bug that shipped twice during #54 (gray counties, then 0-schools).
title_case <- function(x) gsub("\\b([a-z])", "\\U\\1", tolower(x), perl = TRUE)

# Coverage tier from a fraction in 0..1: H >= 0.95, M >= 0.90, else L; NA -> NA.
# base-R ifelse variant (build_nc_from_estimates.R, which does not load data.table
# fifelse semantics for character NA in the same way).
covtier <- function(v) {
  ifelse(is.na(v), NA_character_,
         ifelse(v >= 0.95, "H", ifelse(v >= 0.90, "M", "L")))
}

# ---- ray-casting point-in-polygon (works in the native planar CRS) ----
# poly ring: an Nx2 matrix of [x, y]; point: (x, y). Outer ring only.
point_in_ring <- function(x, y, ring) {
  n <- nrow(ring); inside <- FALSE; j <- n
  for (i in seq_len(n)) {
    xi <- ring[i, 1]; yi <- ring[i, 2]; xj <- ring[j, 1]; yj <- ring[j, 2]
    if (((yi > y) != (yj > y)) &&
        (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) inside <- !inside
    j <- i
  }
  inside
}

# Assign a point to the first county polygon whose bbox contains it and whose
# outer ring contains it (ray casting). `counties` is a list of entries with
# $name, $ring (Nx2 matrix), $xr (x range), $yr (y range). Returns the county
# name or NA_character_ when the point falls in no polygon.
assign_county <- function(x, y, counties) {
  for (c in counties) {
    if (x < c$xr[1] || x > c$xr[2] || y < c$yr[1] || y > c$yr[2]) next
    if (point_in_ring(x, y, c$ring)) return(c$name)
  }
  NA_character_
}

# Build the county geometry list (name/ring/bbox + coverage props) from parsed
# geojson Polygon features. Factored out so assign_county is testable on a tiny
# synthetic polygon set without reading a geojson file.
# nz: null-safe accessor; geojson props may be JSON null -> R NULL.
build_counties <- function(county_geo, nz = function(v) if (is.null(v) || length(v) == 0) NA else v) {
  lapply(county_geo, function(f) {
    ring <- do.call(rbind, lapply(f$geometry$coordinates[[1]], function(p) c(p[[1]], p[[2]])))
    list(name = f$properties$NAME, ring = ring,
         xr = range(ring[, 1]), yr = range(ring[, 2]),
         coverage = nz(f$properties$coverage), cov_low = nz(f$properties$cov_low),
         cov_high = nz(f$properties$cov_high), herd = nz(f$properties$herd_immune_fraction))
  })
}

# ---- coverage-gap detection (#56/#60) ----
# Given the loc_ids the fit actually produced (fit_ids) and the loc_ids present
# in the linkage roster (linkage_ids), flag which roster loc_ids are absent from
# the fit. These are the "have location data but no fit coverage" schools that
# the producer emits as no_data (grey dots) and that surfaced Yolo + Yuba in the
# CA fit. Returns a logical vector aligned to linkage_ids (TRUE = no_data).
no_data_flag <- function(linkage_ids, fit_ids) {
  !(linkage_ids %in% fit_ids)
}

# ---- wide #20 schema column order ----
# The per-row coverage block, shared by every level (state/county/school) and by
# both producers. grade_lab defaults to K..5. This is the column-set/order
# contract the consumer side (csvSchema.test.js) joins against.
cov_block <- function(grade_lab = c("K", "1", "2", "3", "4", "5")) {
  c("coverage", "coverage_ci_low", "coverage_ci_high",
    paste0("coverage_", grade_lab),
    paste0("coverage_ci_low_", grade_lab),
    paste0("coverage_ci_high_", grade_lab),
    "prob_below_95", "tier")
}

# Full column order for each emitted CSV file type, given the cov_block above.
state_columns  <- function(grade_lab = c("K", "1", "2", "3", "4", "5"))
  c("state", "state_fips", "state_name", "n_schools", "pct_schools_below_95",
    cov_block(grade_lab))

county_columns <- function(grade_lab = c("K", "1", "2", "3", "4", "5"))
  c("county", "county_fips", "n_schools", "pct_schools_below_95",
    cov_block(grade_lab))

school_columns <- function(grade_lab = c("K", "1", "2", "3", "4", "5"))
  c("school_id", "school_name", "county", "enrollment",
    "lon", "lat", "no_data", cov_block(grade_lab))
