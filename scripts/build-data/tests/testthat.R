# Standalone testthat runner for the #20 CSV producer helpers.
#
# The producers are scripts, not a package, so there is no R CMD check entry
# point. This runner sources the extracted helpers and runs the testthat suite
# in scripts/build-data/tests/testthat/. The producer-tests GitHub Actions
# workflow invokes it with:
#   Rscript scripts/build-data/tests/testthat.R
# from the repo root.
library(testthat)

# Resolve paths relative to this file so the runner works regardless of cwd.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grep("^--file=", args)])
here <- if (length(file_arg)) dirname(normalizePath(file_arg)) else getwd()
build_data <- normalizePath(file.path(here, ".."))

source(file.path(build_data, "R", "producer-helpers.R"))

reporter <- if (nzchar(Sys.getenv("CI"))) "summary" else "progress"
results <- test_dir(file.path(here, "testthat"), reporter = reporter, stop_on_failure = TRUE)
