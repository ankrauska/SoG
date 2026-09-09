# A reader's map of the vendored estimator

The three `.R` files here are copied **verbatim** from the published
solve-or-guess method (Rohe et al.) so this kit runs without an external
checkout. See `SOURCE.md` for provenance.

**Do not edit them.** This guide exists so you can understand and call them
without having to read a thousand lines of EM internals first. Nothing here
changes their behaviour; it only describes it.

---

## What you actually need to call

Two functions. `code/04` and `code/05` use only these.

### `solve_or_guess_fast(evaluations, ...)`

Fits the model by EM and returns the parameters.

```r
fit <- solve_or_guess_fast(
  evaluations,                  # tidy data frame, see below
  difficulty      = NULL,       # optional per-item features
  system_rater_id = "LLM",      # which rater is the automated one
  max_iter        = 100,
  tol             = 1e-6,
  verbose         = TRUE
)
```

`evaluations` must have exactly three columns:

| Column | Meaning |
|---|---|
| `item_id` | The thing being rated (an abstract). |
| `rater_id` | Who rated it. |
| `evaluation` | The label, as a string. |

This is precisely `results/<experiment>/rater_labels_long.csv`, which is why
`code/04` writes that file out — it is the estimator's input, preserved.

The full signature also declares `yes_label = "yes"` and `no_label = "no"`.
**Ignore them** — they are vestigial: declared in the signature and never
referenced in the body. You do not need to set them to match your label
vocabulary, and setting them has no effect. Labels are handled generically as
factor levels, which is why `"Include"` / `"Exclude"` work untouched.

Two behaviours worth knowing:

- **Missing combinations become a class.** The function builds the full
  item × rater grid and fills gaps with the literal label `"MISSING"`, warning
  as it does. That is rarely what you want: a rater who skipped items gets a
  guessing distribution concentrated on "MISSING". `code/01` enforces a
  complete design so this never fires.
- **`system_rater_id` must exist** in the data, or it stops. It reorders raters
  to put the system first internally; it does not otherwise privilege it.

### `nonparametric_bootstrap_solve_or_guess(evaluations, ...)`

Resamples **items** with replacement, refits, and collects the estimates.

```r
boot <- nonparametric_bootstrap_solve_or_guess(
  evaluations,
  system_rater_id = "LLM",
  B               = 1000,
  verbose         = TRUE
)
boot$bootstrap_rater_ability   # bootstrap_iter, rater_id, parameter_id, estimate
```

Resampling whole items — not individual labels — is deliberate. An item carries
the agreement structure across all raters at once; resampling labels
independently would destroy the correlation the model is estimating.

Repeated draws of the same item are renamed (`case_017.3`) so the refit treats
them as distinct items. This is the standard cluster bootstrap.

It prints per-replicate progress, which is why `code/04` wraps it in
`capture.output()`.

## What comes back

`solve_or_guess_fast()` returns a list of four tidy tibbles.

### `rater_ability` — the one you want

```
rater_id  parameter_id  estimate
LLM       intercept     1.71
A         intercept     1.43
```

> **`estimate` is on the logit scale, not a probability.** Convert it:
> `p_hat <- plogis(estimate)`, i.e. `1 / (1 + exp(-estimate))`. Reporting the
> raw estimate as a solving probability is the easiest mistake to make here.

With no `difficulty` features each rater has a single row, `parameter_id =
"intercept"`, and `plogis(estimate)` is their solving probability. With
difficulty features there is one row per feature, and the intercept is the
solving probability at the feature baseline rather than overall.

### `guessing_distribution`

```
rater_id  evaluation  probability
LLM       Exclude     0.919
LLM       Include     0.081
```

Each rater's fallback distribution — the labels they produce when they do not
solve. Rows per rater sum to 1. This is what lets the model discount agreement
that is merely two raters sharing a habit: a rater who says "Exclude" 92% of the
time when guessing will agree often with another such rater for no good reason,
and the model knows it.

### `class_distribution`

```
item_id   evaluation  prior_prob  posterior_prob
case_001  Exclude     0.767       1.000
case_001  Include     0.233       0.000372
```

`prior_prob` is the estimated base rate of each true label (the same for every
item). `posterior_prob` is the model's belief about *this* item's true label
after seeing all raters. A posterior near 0.5 marks an item the raters could not
collectively resolve.

`code/05` uses `prior_prob` as the class prior it simulates from.

### `item_estimates`

```
item_id   rater_id  success_prob  expected_success
case_001  LLM       0.846         0.857
```

Per item and rater: the modelled probability of solving, and the posterior
expectation of having solved *this* item. Under the homogeneous fit
`success_prob` is constant across items for a given rater — it varies only when
difficulty features are supplied.

## The supporting file

`spectral_initializer.R` provides `spectral_initializer(M, H, R)`, which seeds
the EM intercepts from the leading eigenvector of the agreement matrix, and
`cohens_kappa_numerator(Y)`, which computes observed-minus-expected agreement
for all column pairs. EM finds a local optimum, so a good starting point
matters; this gives one derived from the data rather than from zeros. You call
neither directly — `solve_or_guess_fast()` does — but both must be `source()`d
first, which is why `code/04` and `code/05` source the initializer before the
estimator.

## Extending

Two capabilities the kit does not currently use:

- **Heterogeneous fit.** Pass a `difficulty` data frame (`item_id`,
  `feature_id`, `value`) to let solving probability vary with per-item
  covariates. The reviewer files carry a `Difficulty` column that is merged
  through but never modelled — that is the obvious starting point.
- **More label classes.** Nothing assumes binary labels. Ordinal or
  multi-category screening decisions work as-is, though with more classes you
  need more items to estimate each guessing distribution.
