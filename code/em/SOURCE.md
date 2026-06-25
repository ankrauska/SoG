# Vendored solve-or-guess estimator

These three R files are copied **verbatim** from the solve-or-guess methodology
code (Rohe et al., the published method described in `../../paper.pdf`). They are
included here so this kit runs without an external checkout.

- `spectral_initializer.R` — spectral initialization for the EM intercepts.
- `tidy_solve_or_guess_fast.R` — the EM fit (`solve_or_guess_fast`).
- `tidy_bootstrap_nonparametric.R` — the nonparametric item bootstrap.

`code/04_run_solve_or_guess.R` and `code/05_rank_one_diagnostic.R` load them via
`source(file.path(here("code"), "em/...R"))`. They are unmodified; do not edit
them here. For the canonical version, updates, and license, see the solve-or-guess
project.
