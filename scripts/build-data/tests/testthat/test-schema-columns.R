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

test_that("producer columns match the pinned JSON contract", {
  schema <- jsonlite::fromJSON(file.path(build_data, "..", "..", "schema", "dashboard-schema.json"))$files
  expect_equal(state_columns(), schema[["data/states.csv"]]$columns$name)
  expect_equal(county_columns(), schema[["data/states/{state}.csv"]]$columns$name)
  expect_equal(school_columns(), schema[["data/states/{state}/schools.csv"]]$columns$name)
})
