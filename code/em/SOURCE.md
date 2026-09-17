# Vendored solve-or-guess estimator

These three R files are copied **verbatim** from the solve-or-guess methodology
code of Rohe et al. They are included here so this kit runs without an external
checkout.

The method paper itself is not in this repository. It is cited by
`../../worked_example_paper.pdf`, which applies the method rather than
developing it.

- `spectral_initializer.R` — spectral initialization for the EM intercepts.
- `tidy_solve_or_guess_fast.R` — the EM fit (`solve_or_guess_fast`).
- `tidy_bootstrap_nonparametric.R` — the nonparametric item bootstrap.

`code/04_run_solve_or_guess.R` and `code/05_rank_one_diagnostic.R` load them via
`source(here("code", "em", "...R"))`. They are unmodified; do not edit them here.
For the canonical version and updates, see the solve-or-guess project.

**To understand or call them, read [`GUIDE.md`](GUIDE.md)** — a map of the two
functions you actually need, what they return, and the one easy mistake (the
ability estimates come back on the logit scale, not as probabilities). The guide
describes these files without modifying them.

These files are copyright Rohe et al., and are licensed under PolyForm
Noncommercial 1.0.0, the same license as the rest of this repository. See
[`../../LICENSE`](../../LICENSE).

Copyright is not the whole picture. The method these files implement is
separately the subject of a pending patent application owned by Karl Rohe, who
has publicly covenanted not to assert it against noncommercial use. His note in
[`../../NOTICE.md`](../../NOTICE.md) states the terms in full.
