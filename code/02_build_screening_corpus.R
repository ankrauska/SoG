# Build the LLM screening corpus: titles and abstracts only, no human labels.
#
# Input:   data/inputs/reviewerA.csv
# Output:  data/inputs/screening_corpus.csv
#
# Strip the reviewer label columns (CONSORT flag, Reasoning, Difficulty) and
# add a stable case_id. The corpus is what the LLM sees. The same titles and
# abstracts were labelled by all three human reviewers (sanity-checked in
# 01_merge_human_reviewers.R), so the row order here matches the merged
# human-label dataset and the two can be joined by Title.

library(tidyverse)
library(here)

corpus <- read_csv(here("data/inputs/reviewerA.csv"), show_col_types = FALSE) |>
  mutate(case_id = sprintf("case_%03d", row_number())) |>
  select(case_id, title = Title, abstract = Abstract)

write_csv(corpus, here("data/inputs/screening_corpus.csv"))

message("Wrote ", nrow(corpus), " abstracts to data/inputs/screening_corpus.csv")
