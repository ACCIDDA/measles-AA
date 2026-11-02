# Shared helpers for data producers. Geometry and string helpers use base R.

# ---- string + slug helpers ----

# Lowercase, collapse non-alphanumerics to single hyphens. Used for file slugs.
slugify <- function(x) gsub("[^a-z0-9]+", "-", tolower(trimws(x)))

# Normalize county names to title case for geography joins.
title_case <- function(x) gsub("\\b([a-z])", "\\U\\1", tolower(x), perl = TRUE)

# Coverage tier from a fraction in 0..1: H >= 0.95, M >= 0.90, else L; NA -> NA.
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

# Flag roster locations without fitted estimates.
no_data_flag <- function(linkage_ids, fit_ids) {
  !(linkage_ids %in% fit_ids)
}

# ---- shared schema column order ----
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

# Metadata is supplied explicitly; no state identity is built into a producer.
read_state_metadata <- function() {
  path <- Sys.getenv("META_PATH")
  if (!nzchar(path) || !file.exists(path)) stop("META_PATH must name a completed Meta.json")
  meta <- jsonlite::fromJSON(path)
  fields <- c("code", "name", "fullName", "dataDir", "fips", "sourceUrl", "sourceLabel")
  if (!is.list(meta) || !setequal(names(meta), fields) ||
      !all(vapply(meta, function(v) is.character(v) && length(v) == 1L &&
                  !is.na(v) && nzchar(trimws(v)) && v == trimws(v), logical(1))))
    stop("Meta.json must contain the seven nonempty metadata strings")
  if (!grepl("^[a-z]{2}$", meta$code) || !grepl("^[0-9]{2}$", meta$fips) ||
      meta$name != toupper(meta$code)) stop("Invalid metadata identity")
  meta
}

safe_mean <- function(x) if (any(is.finite(x))) mean(x[is.finite(x)]) else NA_real_

safe_weighted_mean <- function(x, w) {
  keep <- is.finite(x) & is.finite(w) & w > 0
  if (any(keep)) weighted.mean(x[keep], w[keep]) else NA_real_
}

write_submission <- function(state, counties, schools, out, meta) {
  if (file.exists(out)) stop("OUT_DIR must be a new directory")
  if (!dir.create(out, recursive = TRUE)) stop("Cannot create OUT_DIR")
  tables <- list(State = state, Counties = counties, Schools = schools)
  columns <- list(State = state_columns(), Counties = county_columns(), Schools = school_columns())
  for (name in names(tables)) {
    tab <- data.table::copy(tables[[name]])
    for (column in names(tab)) {
      if (is.numeric(tab[[column]])) {
        if (any(!is.finite(tab[[column]]) & !is.na(tab[[column]])))
          stop(paste(name, column, "contains non-finite values"))
        data.table::set(tab, j = column, value = round(tab[[column]], 4))
      }
    }
    data.table::fwrite(tab[, columns[[name]], with = FALSE],
                      file.path(out, paste0(name, ".csv")), na = "")
  }
  jsonlite::write_json(meta, file.path(out, "Meta.json"), auto_unbox = TRUE, pretty = TRUE)
}
