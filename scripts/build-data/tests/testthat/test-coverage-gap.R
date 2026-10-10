# Coverage-gap detection (build_state.R assemble: no_data flag, #56/#60).
#
# A school present in the linkage roster but absent from the fit must be flagged
# no_data (rendered as a grey dot, excluded from aggregate stats). This is what
# surfaced Yolo + Yuba in the CA fit. no_data_flag(linkage_ids, fit_ids) is the
# extracted predicate.

test_that("schools in linkage but absent from the fit are flagged no_data", {
  linkage_ids <- c("1", "2", "3", "4")
  fit_ids     <- c("1", "3")          # 2 and 4 are missing from the fit
  expect_equal(no_data_flag(linkage_ids, fit_ids),
               c(FALSE, TRUE, FALSE, TRUE))
})

test_that("all schools present in the fit -> no gaps", {
  ids <- c("a", "b", "c")
  expect_equal(no_data_flag(ids, ids), c(FALSE, FALSE, FALSE))
})

test_that("no schools in the fit -> all flagged no_data", {
  linkage_ids <- c("x", "y")
  expect_equal(no_data_flag(linkage_ids, character(0)), c(TRUE, TRUE))
})

test_that("flag is type-agnostic when both sides are character (the producer coerces ids)", {
  # build_state.R coerces all loc_ids to character before this comparison.
  linkage_ids <- as.character(c(10, 20, 30))
  fit_ids     <- as.character(c(20))
  expect_equal(no_data_flag(linkage_ids, fit_ids), c(TRUE, FALSE, TRUE))
})

test_that("the reported gap counties match the missing schools", {
  # Mirror the producer's reporting: which county names own the no_data schools.
  schools <- data.frame(
    loc_id      = c("1", "2", "3"),
    county_name = c("yolo", "yuba", "los angeles"),
    stringsAsFactors = FALSE
  )
  fit_ids <- c("3")   # only LA school is in the fit
  schools$no_data <- no_data_flag(schools$loc_id, fit_ids)
  gap_counties <- sort(unique(schools$county_name[schools$no_data]))
  expect_equal(gap_counties, c("yolo", "yuba"))
})
