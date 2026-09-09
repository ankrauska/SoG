# Results — how to read them

One directory per experiment, written by `code/04` and `code/05`. Everything
here is derived: delete it and rerun those two stages to rebuild it.

```
results/exp_001_codebook/
  rater_labels_long.csv           what was actually fitted  (audit trail)
  solving_probabilities.csv       how often each rater solves
  kappa_ratios_llm_vs_human.csv   the headline comparison
  pairwise_kappa.csv              raw agreement  (descriptive)
  rank_one_diagnostic.csv         does the model fit?       (read this first)
```

**Read them in this order:** the diagnostic, then the kappa-ratios, then the
solving probabilities, with the pairwise kappas as a sanity check. The
diagnostic comes first because it tells you whether the rest means anything.

---

## `rank_one_diagnostic.csv` — read this first

```csv
statistic,T_obs,B,p_value
rank_one_RSS,4.325968264759556e-4,1000,0.381
```

| Column | Meaning |
|---|---|
| `T_obs` | Observed departure from the model's predicted agreement structure (a residual sum of squares). Not interpretable on its own — only relative to the null distribution. |
| `B` | Simulated datasets used to build that null distribution. |
| `p_value` | Fraction of simulated datasets with departure at least as large as yours. |

**A LARGE p-value is the good outcome.** The logic runs opposite to a familiar
significance test: the null hypothesis here is *the model fits*, so you want to
fail to reject it. `p = 0.381` means the agreement pattern among these four
raters looks like something the solve-or-guess model would readily produce.

**If `p_value < 0.05`, stop.** The agreement structure is not consistent with
the model, and the solving probabilities are not trustworthy. The usual causes
are the assumptions in the root README's checklist failing: raters who conferred
or share a systematic bias, or a codebook vague enough that disagreement
reflects interpretation rather than ability.

A large p-value is **reassurance, not proof**.
It cannot certify that your raters were independent; only your study design can
do that.

## `kappa_ratios_llm_vs_human.csv` — the headline

```csv
comparison,ratio_hat,ci_lower,ci_upper
LLM / A,1.0494,0.8052,1.4017
LLM / B,1.0154,0.7695,1.3945
LLM / C,1.2632,0.8750,1.9798
```

`ratio_hat` is `p_LLM / p_human`, with a 95% nonparametric bootstrap interval.
This is the quantity the method exists to produce, and the one that needs no
gold standard.

- **> 1** — the LLM solves the task more often than that human.
- **< 1** — less often.
- **Interval contains 1** — the data cannot distinguish them.

In the worked example all three intervals contain 1, so the LLM is
statistically indistinguishable from each of the three reviewers.

**What "indistinguishable" does not mean.** An interval containing 1 is a
*failure to detect a difference*, not evidence of equivalence. With 100
abstracts these intervals are wide — `LLM / C` runs from 0.88 to 1.98, which
spans "slightly worse" to "twice as good." That is a weak statement being made
honestly, and it should be reported as such. If you need to demonstrate
equivalence rather than fail to demonstrate difference, you need far more items.

## `solving_probabilities.csv`

```csv
rater_id,p_hat,ci_lower,ci_upper
LLM,0.8462,0.6876,0.9991
B,0.8334,0.6440,0.9762
A,0.8064,0.6126,0.9875
C,0.6699,0.4614,0.8764
```

`p_hat` is the estimated probability that the rater *solves* a given item —
works out the true label rather than falling back on habit — with a 95%
bootstrap interval. All raters are on one common scale, so they can be ranked.

Two cautions:

**These are not accuracy rates.** `p_hat = 0.85` does not mean 85% correct. It
means that on an estimated 85% of items the rater engaged with the item and
recovered its true label; on the rest they guessed, and guessing is right some
of the time by luck. Reporting a solving probability as accuracy understates the
claim.

**Rankings are less stable than they look.** In the worked example the LLM has
the highest point estimate, but every interval overlaps every other. The
ordering of the top three is well inside the noise, and it moves under
reasonable changes to the abstain policy (below). Treat the ordering as
descriptive; the intervals are the finding.

A `p_hat` pinned near 1.0 with an interval touching the boundary usually means
that rater agrees with everyone almost always — plausible for an easy corpus,
but also what you would see if raters were not independent.

## `pairwise_kappa.csv`

```csv
rater_a,rater_b,kappa
A,B,0.759
A,C,0.702
A,LLM,0.785
B,C,0.714
B,LLM,0.733
C,LLM,0.611
```

Observed Cohen's kappa for every rater pair. This is **descriptive** — it is not
part of the fit, and it is reported so you can see the raw agreement the model
worked from.

The useful check: **does the LLM's agreement with the humans sit inside the
range of the humans' agreement with each other?** Here the humans agree with one
another at 0.70–0.76, and the LLM agrees with them at 0.61–0.79. Same band, so
the LLM is not an outlier in the agreement structure, and the model's conclusion
should not be a surprise.

If instead the LLM agreed with one human far more than any two humans agree with
each other, suspect a broken independence assumption before believing the result.

## `rater_labels_long.csv`

```csv
item_id,rater_id,evaluation
case_001,A,Exclude
case_001,B,Exclude
case_001,C,Exclude
case_001,LLM,Exclude
```

The tidy item × rater matrix that was actually fitted — **after** the abstain
policy was applied. It is written out as a result in its own right because it is
the audit trail: if you want to know exactly what the estimator saw, this is it.
`code/05` reads it back rather than rebuilding it, so both stages provably work
from the same labels.

## Worked example: does the abstain policy matter?

The codebook lets the LLM answer "Human Review"; the humans had no such option.
`analysis.human_review_action` decides what that becomes, and the honest way to
report the choice is to show it did not drive the result. Refitting the worked
example under all four policies (B = 1000):

| Policy | p̂ LLM | p̂ A | p̂ B | p̂ C | All ratio CIs contain 1? |
|---|---|---|---|---|---|
| `include` | 0.846 | 0.806 | 0.833 | 0.670 | yes |
| `exclude` | 0.861 | 0.854 | 0.877 | 0.645 | yes |
| `keep` | 0.844 | 0.850 | 0.874 | 0.648 | yes |
| `drop` | 0.857 | 0.849 | 0.878 | 0.660 | yes |

The conclusion is robust: every kappa-ratio interval contains 1 under every
policy. But note that the *ranking* is not — the LLM has the highest point
estimate under `include` and sits second under the other three. That is a good
illustration of the caution above: the ordering is inside the noise, and the
interval is the result worth reporting.

Run this check for your own study. Copy your experiment YAML, change
`human_review_action`, give it a new `id` so it writes to its own results
directory, and compare.

## Reproducibility

`code/04` and `code/05` are seeded from `analysis.seed_fit` and
`analysis.seed_diagnostic`, so rerunning them on unchanged inputs reproduces
these files byte-for-byte. If you get different numbers from the same inputs,
something changed — check the seeds, `B`, and the abstain policy first.
