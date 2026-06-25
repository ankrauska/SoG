# Merge three human reviewer CSVs into a single analysis-ready dataset.
#
# Inputs:  data/inputs/reviewer{A,E,H}.csv
# Output:  data/derived/human_reviewer_labels_merged.csv
#
# Each reviewer file has columns Title, Abstract, CONSORT flag, Reasoning,
# Difficulty. We join on Title, keep Abstract from reviewer A as the
# canonical text, and suffix the per-reviewer label columns with _A, _E, _H.

library(tidyverse)
library(here)

A <- read_csv(here("data/inputs/reviewerA.csv"), show_col_types = FALSE) |>
  rename(consort_flag_A = `CONSORT flag`,
         reasoning_A    = Reasoning,
         difficulty_A   = Difficulty)

E <- read_csv(here("data/inputs/reviewerE.csv"), show_col_types = FALSE) |>
  rename(consort_flag_E = `CONSORT flag`,
         reasoning_E    = Reasoning,
         difficulty_E   = Difficulty)

H <- read_csv(here("data/inputs/reviewerH.csv"), show_col_types = FALSE) |>
  rename(consort_flag_H = `CONSORT flag`,
         reasoning_H    = Reasoning,
         difficulty_H   = Difficulty)

stopifnot(
  setequal(A$Title, E$Title),
  setequal(A$Title, H$Title)
)

merged <- A |>
  left_join(E |> select(-Abstract), by = "Title") |>
  left_join(H |> select(-Abstract), by = "Title")

dir.create(here("data/derived"), showWarnings = FALSE, recursive = TRUE)
write_csv(merged, here("data/derived/human_reviewer_labels_merged.csv"))

message("Wrote ", nrow(merged), " rows x ", ncol(merged),
        " cols to data/derived/human_reviewer_labels_merged.csv")
