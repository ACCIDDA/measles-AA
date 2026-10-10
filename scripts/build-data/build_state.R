# Generic imuGAP -> dashboard CSV producer (#20).
#
# State-agnostic: give it a fitted imuGAP object + the standardized
# tidyschoolvax/run_imugap outputs (cleaned_data, linkage_key) + state metadata,
# and it emits the #20 schema:
#   <out>/states.csv                          (one row per state; appended)
#   <out>/states/<slug>.csv                   (one row per county)
#   <out>/states/<slug>/counties/<cty>.csv    (one row per school)
#
# Approach settled in probe_aggregate.R: coverage at every level = predict() at
# that loc_id NODE (state=root, counties=layer2, schools=layer3), grades K-5 =
# ages 5-10 taken as a single-year cross-section via create_target(mode="snapshot").
#
# Modes:
#   FIT_PATH=<rds>            real run (also needs CLEANED_PATH, LINKAGE_PATH, STATE)
#   STUB=1                    join/format test on real inputs w/ placeholder coverage
suppressMessages({library(imuGAP); library(data.table)})

# Fit-independent helpers (slugify, title_case, no_data_flag, cov_block, ...) are
# factored into R/producer-helpers.R so the producer-tests workflow can exercise
# them with tiny fixtures. See scripts/build-data/R/producer-helpers.R.
HELPERS <- Sys.getenv("PRODUCER_HELPERS",
                      unset = "scripts/build-data/R/producer-helpers.R")
source(HELPERS)

GRADE_AGES <- 5:10
GRADE_LAB  <- c("K", "1", "2", "3", "4", "5")   # age 5 -> K ... age 10 -> 5th
THRESHOLD  <- 0.95

# linkage_key and cleaned_data use DIFFERENT school_id systems, so we bridge
# them on normalized school-name + county (96% match; ids don't correspond).
norm_name <- function(x) {
  x <- tolower(trimws(x)); x <- gsub("[[:punct:]]", " ", x)
  x <- gsub("\\b(school|schools)\\b", "", x); gsub("\\s+", " ", trimws(x))
}
nm_key <- function(name, county) paste(norm_name(name), norm_name(county), sep = "|")
# covtier kept local (data.table fifelse) for the vectorized predict path; the
# base-R variant in producer-helpers.R is behavior-equivalent and used by tests.
covtier  <- function(v) fifelse(is.na(v), NA_character_,
                                fifelse(v >= 0.95, "H", fifelse(v >= 0.90, "M", "L")))

#' Predict coverage at every location node, per grade and overall
#'
#' Batched because predicting all ~7936 nodes x 6 grades in one `gqs()` call
#' exhausts RAM (4000 draws x 47616 obs). The node list is chunked, each chunk
#' predicted, and reduced to per-(loc_id, grade) + per-(loc_id) summaries
#' immediately so only summaries (not raw draws) accumulate. Each loc_id lives
#' wholly within one chunk, so the overall-coverage CI and `prob_below_95`
#' (per-node reductions over draws) remain exact.
#'
#' @param fit a fitted `imugap_fit` object.
#' @param grade_ages integer ages mapped to grades K-5 (default 5:10).
#' @param dose integer dose to predict (default 2L).
#' @param grade_lab character labels for `grade_ages` (default K,1..5).
#' @param ref_cohort reference cohort for the snapshot; derived from the fit if NULL.
#' @param chunk_nodes nodes predicted per `gqs()` call (default env CHUNK_NODES or 800).
#' @return list(per_grade, overall, grade_lab) of coverage summaries by loc_id.
predict_coverage <- function(fit, grade_ages = GRADE_AGES, dose = 2L,
                             grade_lab = GRADE_LAB, ref_cohort = NULL,
                             chunk_nodes = as.integer(Sys.getenv("CHUNK_NODES", "800"))) {
  if (is.null(ref_cohort)) {
    ref_cohort <- fit$data$n_cohort - diff(range(grade_ages))
  }
  loc <- as.data.table(fit$locations)
  glab_map <- setNames(grade_lab, as.character(grade_ages))
  ids <- loc$loc_id
  chunks <- split(ids, ceiling(seq_along(ids) / chunk_nodes))
  message(sprintf("predicting %d nodes x %d grades in %d chunks of <=%d",
                  length(ids), length(grade_ages), length(chunks), chunk_nodes))

  pg <- vector("list", length(chunks)); ov <- vector("list", length(chunks))
  for (i in seq_along(chunks)) {
    target <- create_target(fit, location = chunks[[i]], age = grade_ages,
                            cohort = ref_cohort, dose = dose, mode = "snapshot")
    pred <- as.data.table(predict(fit, target))
    pred[, grade := glab_map[as.character(age)]]
    ct <- build_cov_tables(pred, loc[loc_id %in% chunks[[i]]], grade_lab)
    pg[[i]] <- ct$per_grade; ov[[i]] <- ct$overall
    rm(target, pred, ct); gc(FALSE)
    message(sprintf("  chunk %d/%d done", i, length(chunks)))
  }
  list(per_grade = rbindlist(pg), overall = rbindlist(ov), grade_lab = grade_lab)
}

# shared by real + stub paths: turn long (loc_id, grade, sample_id, p_obs) draws
# into per-grade + overall summaries keyed by loc_id, tagged with level.
build_cov_tables <- function(pred, loc, grade_lab = GRADE_LAB) {
  # loc_id is coerced to character because it is used as a join key across
  # several tables whose id columns arrive with inconsistent types (integer
  # loc_ids from the fit vs. linkage's school_loc_id/county_loc_id); a single
  # consistent type avoids data.table join-type errors downstream.
  pred <- as.data.table(pred)[, loc_id := as.character(loc_id)]
  loc  <- as.data.table(loc)[,  loc_id := as.character(loc_id)]
  per_grade <- pred[, .(coverage = median(p_obs),
                        ci_low   = quantile(p_obs, .025),
                        ci_high  = quantile(p_obs, .975)), by = .(loc_id, grade)]
  overall_draws <- pred[, .(p = mean(p_obs)), by = .(loc_id, sample_id)]
  overall <- overall_draws[, .(coverage = median(p),
                               ci_low = quantile(p, .025),
                               ci_high = quantile(p, .975),
                               prob_below_95 = mean(p < THRESHOLD)), by = loc_id]
  lvl <- loc[, .(loc_id, level = fifelse(layer == 1L, "state",
                                  fifelse(layer == 2L, "county", "school")))]
  list(per_grade = lvl[per_grade, on = "loc_id"],
       overall   = lvl[overall, on = "loc_id"],
       grade_lab = grade_lab)
}

# --- 2. join identity / enrollment / reported, compute aggregates -> level tables ---
assemble <- function(cov, cleaned, linkage, state_meta, county_fips_map = NULL) {
  cleaned <- copy(as.data.table(cleaned)); linkage <- copy(as.data.table(linkage))
  # normalize join keys to character (school_id/loc_ids differ in type across files)
  for (c in c("school_id", "school_loc_id", "county_loc_id", "county_name"))
    if (c %in% names(linkage)) linkage[[c]] <- as.character(linkage[[c]])
  if ("school_id" %in% names(cleaned)) cleaned[, school_id := as.character(school_id)]
  glab <- cov$grade_lab

  # widen coverage + CIs into the schema's per-grade columns
  w <- function(val, prefix) {
    d <- dcast(cov$per_grade, loc_id ~ grade, value.var = val)
    setnames(d, glab, paste0(prefix, glab)); d
  }
  base <- cov$overall[w("coverage", "coverage_"), on = "loc_id"]
  base <- base[w("ci_low",  "coverage_ci_low_"),  on = "loc_id"]
  base <- base[w("ci_high", "coverage_ci_high_"), on = "loc_id"]
  setnames(base, c("ci_low", "ci_high"), c("coverage_ci_low", "coverage_ci_high"))

  # ---- schools: identity (from linkage, by model loc_id) + enrollment/reported
  #      (from cleaned, bridged on normalized name+county since school_ids differ)
  # Build identity from linkage rows that have a loc_id (rows with NA loc_id are
  # junk). Some fit schools have a loc_id + county but no school_name in the
  # linkage; they're kept (valid coverage, just unlabeled / placed via fallback).
  sch_key <- unique(linkage[!is.na(school_loc_id),
                            .(loc_id = as.character(school_loc_id), school_id,
                              school_name, county_name)])
  sch_key[, nm := nm_key(school_name, county_name)]
  cl <- copy(cleaned)[, nm := nm_key(school_name, county_name)]
  # latest year's row per school: enrollment, reported K, and lon/lat
  enr <- cl[order(year), .SD[.N], by = nm][, .(nm, enrollment, current, lon, lat)]
  enr[, reported_K := fifelse(!is.na(enrollment) & enrollment > 0,
                              current / enrollment, NA_real_)]
  sch_key <- enr[sch_key, on = "nm"]
  sch_key[, nm := NULL]
  # Keep ALL linkage schools, not just those with a coverage row (#60). Join is
  # driven by the linkage roster (sch_key) so schools present in the location
  # data but absent from the fit survive with NA coverage; they're flagged
  # no_data and the UI renders a grey dot at their lon/lat instead of dropping
  # them. (base is the per-loc_id coverage from predict.)
  base_sch <- base[level == "school"]
  fit_ids <- base_sch$loc_id                       # loc_ids the model actually produced
  schools <- base_sch[sch_key, on = "loc_id"]
  schools[, no_data := no_data_flag(loc_id, fit_ids)]  # in linkage but not in the fit (#56/#60)

  # Use reported kindergarten coverage where available, else the model value
  # (#58). Only for fit schools; no_data schools have no model coverage at all.
  schools[no_data == FALSE & !is.na(reported_K), coverage_K := reported_K]
  # overall = mean of per-grade where present; NA for no_data schools.
  schools[, coverage := {
    m <- rowMeans(as.matrix(.SD), na.rm = TRUE)
    fifelse(is.nan(m), NA_real_, m)
  }, .SDcols = paste0("coverage_", glab)]
  schools[no_data == TRUE, coverage := NA_real_]   # belt-and-suspenders: no estimate
  schools[, tier := covtier(coverage)]

  # Integrity check (#60): a school in the fit but with no location record at all
  # (no county to even associate it with) is a real data-sync problem -> fail the
  # build. Schools that have a county but lack a name and/or lon/lat are kept:
  # they have valid coverage and fall back to deterministic in-polygon placement.
  in_fit_orphaned <- schools[!no_data & is.na(county_name)]
  if (nrow(in_fit_orphaned)) {
    stop(sprintf("%d school(s) are in the fit but absent from the location data (no county). loc_ids: %s",
                 nrow(in_fit_orphaned),
                 paste(utils::head(in_fit_orphaned$loc_id, 20), collapse = ", ")))
  }
  # Report the reverse (have location, not in fit) -> rendered as grey no-data dots.
  nd <- sum(schools$no_data)
  if (nd) {
    message(sprintf("%d school(s) have location data but no fit coverage; emitting as no_data (grey dots): %s",
                    nd, paste(sort(unique(schools[no_data == TRUE]$county_name)), collapse = ", ")))
  }

  # ---- per-school below-threshold -> county / state aggregates ----
  # no_data schools have no coverage, so they're excluded from aggregate stats.
  below <- schools[no_data == FALSE, .(school_id, county_name, below = coverage < THRESHOLD)]
  cty_stat <- below[, .(n_schools = .N, pct_schools_below_95 = mean(below)), by = county_name]
  st_stat  <- below[, .(n_schools = .N, pct_schools_below_95 = mean(below))]

  # ---- counties: node-predict coverage + identity + stats ----
  cty_key <- unique(linkage[, .(loc_id = county_loc_id, county_name)])
  counties <- cty_key[base[level == "county"], on = "loc_id", nomatch = 0]
  counties <- cty_stat[counties, on = "county_name"]
  counties[, tier := covtier(coverage)]
  counties[, county_fips := if (!is.null(county_fips_map))
    county_fips_map[match(county_name, names(county_fips_map))] else NA_character_]

  # ---- state row ----
  state <- base[level == "state"]
  state[, `:=`(state = state_meta$slug, state_fips = state_meta$fips,
               state_name = state_meta$name,
               n_schools = st_stat$n_schools,
               pct_schools_below_95 = st_stat$pct_schools_below_95,
               tier = covtier(coverage))]

  list(schools = schools, counties = counties, state = state, grade_lab = glab)
}

# --- 3. write the three CSV file types in schema column order ---
write_csvs <- function(tab, out_dir, state_meta) {
  glab <- tab$grade_lab
  cov_block <- cov_block(glab)
  rnd <- function(d) { for (c in names(d)) if (is.numeric(d[[c]])) d[[c]] <- round(d[[c]], 4); d }
  slug <- state_meta$slug
  dir.create(file.path(out_dir, "states", slug, "counties"), recursive = TRUE, showWarnings = FALSE)

  # county rows -> states/<slug>.csv
  cty <- tab$counties[, c("county_name", "county_fips", "n_schools",
                          "pct_schools_below_95", cov_block), with = FALSE]
  setnames(cty, "county_name", "county")
  cty[, county := title_case(county)]
  fwrite(rnd(cty), file.path(out_dir, "states", paste0(slug, ".csv")))

  # combined states/<slug>/schools.csv: one row per school, the file the app
  # loads. Carries county, lon/lat (for map dot placement), and a no_data flag
  # for schools with location but no fit coverage (#60). The per-county download
  # files are derived from this at build time (#65), not written here.
  sch_cols <- c("school_id", "school_name", "county_name", "enrollment",
                "lon", "lat", "no_data", cov_block)
  schools_all <- tab$schools[!is.na(county_name), ..sch_cols]
  setnames(schools_all, "county_name", "county")
  schools_all[, county := title_case(county)]   # match atlas county names (loader joins on these)
  schools_all[, no_data := as.integer(no_data)]  # emit 0/1 not TRUE/FALSE
  fwrite(rnd(schools_all), file.path(out_dir, "states", slug, "schools.csv"))

  # state row -> states.csv (create/replace this state's row)
  st <- tab$state[, c("state", "state_fips", "state_name", "n_schools",
                      "pct_schools_below_95", cov_block), with = FALSE]
  states_csv <- file.path(out_dir, "states.csv")
  if (file.exists(states_csv)) {
    cur <- fread(states_csv); cur <- cur[state != slug]
    st <- rbind(cur, st, fill = TRUE)
  }
  fwrite(rnd(st), states_csv)
  invisible(tab)
}

# ============================ driver ============================
OUT <- Sys.getenv("OUT_DIR", unset = "scripts/build-data/out")

if (Sys.getenv("STUB") == "1") {
  message("STUB MODE: placeholder coverage on real loc_ids; tests join + schema output")
  cleaned <- readRDS("scripts/build-data/inputs/cleaned_data.rds")
  linkage <- readRDS("scripts/build-data/inputs/linkage_key.rds")
  locs    <- as.data.table(readRDS("scripts/build-data/inputs/locations.rds"))
  setnames(locs, "id", "loc_id", skip_absent = TRUE)
  state_id <- locs[is.na(parent_id), loc_id]
  locs[, layer := fifelse(loc_id == state_id, 1L,
                   fifelse(parent_id == state_id, 2L, 3L))]
  # fabricate per-draw predictions on the real loc_ids (8 draws, plausible coverage)
  set.seed(1)
  draws <- CJ(loc_id = locs$loc_id, grade = GRADE_LAB, sample_id = 1:8)
  base_cov <- setNames(runif(nrow(locs), 0.85, 0.97), locs$loc_id)
  gbump <- setNames(c(-0.04, 0, .01, .015, .02, .02), GRADE_LAB)
  draws[, p_obs := pmin(0.999, pmax(0.5,
        base_cov[as.character(loc_id)] + gbump[grade] + rnorm(.N, 0, 0.01)))]
  cov <- build_cov_tables(draws, locs)
  meta <- list(slug = "ca", fips = "06", name = "California")
  tab <- assemble(cov, cleaned, linkage, meta)
  write_csvs(tab, OUT, meta)
  message("wrote stub CSVs under ", OUT)
} else if (nzchar(Sys.getenv("FIT_PATH"))) {
  cleaned <- readRDS(Sys.getenv("CLEANED_PATH"))
  linkage <- readRDS(Sys.getenv("LINKAGE_PATH"))
  meta <- list(slug = Sys.getenv("STATE"),
               fips = Sys.getenv("STATE_FIPS"),
               name = Sys.getenv("STATE_NAME"))
  message("REAL RUN for ", meta$slug)
  # cache the expensive predict step so format iteration is cheap
  cache <- Sys.getenv("COV_CACHE", unset = file.path(OUT, "..", "cov_cache.rds"))
  if (file.exists(cache) && Sys.getenv("FORCE_PREDICT") != "1") {
    message("using cached coverage: ", cache)
    cov <- readRDS(cache)
  } else {
    fit <- readRDS(Sys.getenv("FIT_PATH"))
    cov <- predict_coverage(fit)
    dir.create(dirname(cache), recursive = TRUE, showWarnings = FALSE)
    saveRDS(cov, cache); message("cached coverage -> ", cache)
  }
  tab <- assemble(cov, cleaned, linkage, meta)
  write_csvs(tab, OUT, meta)
  message("wrote CSVs under ", OUT)
} else {
  stop("set STUB=1 or FIT_PATH=... (with CLEANED_PATH, LINKAGE_PATH, STATE, STATE_FIPS, STATE_NAME)")
}
