# Wide #20 schema column set + order contract (build_state.R / build_nc_from_estimates.R).
#
# The producers emit a fixed column order at every level (state/county/school).
# The consumer side pins the same order in src/data/schema.js (COVERAGE_BLOCK +
# the per-file identity columns) and csvSchema.test.js validates the real CSVs
# against it. These tests pin the PRODUCER side so a reorder/rename in the R
# helpers is caught here, before the CSVs are regenerated.
#
# The expected lists below are transcribed from src/data/schema.js; if that file
# changes the column contract, this test must be updated in lockstep (and so must
# the producers).

GRADES <- c("K", "1", "2", "3", "4", "5")

expected_cov_block <- c(
  "coverage", "coverage_ci_low", "coverage_ci_high",
  paste0("coverage_", GRADES),
  paste0("coverage_ci_low_", GRADES),
  paste0("coverage_ci_high_", GRADES),
  "prob_below_95", "tier"
)

test_that("cov_block matches the schema.js COVERAGE_BLOCK order", {
  expect_equal(cov_block(), expected_cov_block)
  expect_length(cov_block(), 3 + 3 * length(GRADES) + 2)  # 23 columns
})

test_that("cov_block ends with prob_below_95 then tier", {
  cb <- cov_block()
  expect_equal(tail(cb, 2), c("prob_below_95", "tier"))
})

test_that("state file column order matches schema.js (STATE_ID + COVERAGE_BLOCK)", {
  expect_equal(
    state_columns(),
    c("state", "state_fips", "state_name", "n_schools", "pct_schools_below_95",
      expected_cov_block)
  )
})

test_that("county file column order matches schema.js (COUNTY_ID + COVERAGE_BLOCK)", {
  expect_equal(
    county_columns(),
    c("county", "county_fips", "n_schools", "pct_schools_below_95",
      expected_cov_block)
  )
})

test_that("school file column order matches schema.js (SCHOOL_ID + COVERAGE_BLOCK)", {
  expect_equal(
    school_columns(),
    c("school_id", "school_name", "county", "enrollment",
      "lon", "lat", "no_data", expected_cov_block)
  )
})

test_that("cov_block is grade-label driven (custom labels propagate in order)", {
  cb <- cov_block(c("K", "1"))
  expect_equal(cb, c("coverage", "coverage_ci_low", "coverage_ci_high",
                     "coverage_K", "coverage_1",
                     "coverage_ci_low_K", "coverage_ci_low_1",
                     "coverage_ci_high_K", "coverage_ci_high_1",
                     "prob_below_95", "tier"))
})
