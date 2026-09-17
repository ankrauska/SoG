# Prompts — writing a codebook

A **codebook** is the prompt that turns your eligibility criteria into
instructions precise enough that two careful raters, working separately, reach
the same label. In this kit the LLM screens each abstract by working through
one, and the human reviewers work from the same document.

This directory holds the codebook prompts and their JSON output schemas.
`screen_v1_codebook.txt` is the worked example: six questions that decide
whether an abstract describes an individually-randomised trial evaluating
patient-level health outcomes.

---

## Why the codebook is part of the method

It is tempting to treat prompt-writing as tuning — try some wording, see what
scores better. For solve-or-guess that framing is actively wrong, because the
codebook is load-bearing for the statistics.

The model assumes **solver consensus**: each item has a single correct label
that conscientious raters converge on when they solve it. That is exactly a
claim about your codebook. If a criterion is vague, two careful reviewers can
reach different labels *for good reasons*, and then there is no single target
for anyone to recover. Disagreement no longer means someone guessed; it means
the question was ambiguous. The kappa-ratio silently stops measuring solving
ability and starts measuring how differently your raters interpreted an
under-specified instruction.

The failure is invisible in the output. You still get solving probabilities,
they still look plausible, and nothing warns you. So:

> **Repair the codebook before you grade any rater against it.** A sharp
> codebook is a precondition for the comparison, not preparation for it.

This also cuts the other way, and it is the one real weakness of the design: if
your codebook has a systematic gap, and all your raters follow it, they will all
make the same mistake and agree with each other about it. Shared instructions
produce shared blind spots, and the model reads agreement as competence. The
rank-one diagnostic (`code/05`) will sometimes catch this and often will not.

## What makes a codebook sharp

### Decompose the judgment; do not ask for it directly

The weak version of a screening prompt asks the question you actually care
about: *"Should this abstract be included?"* That forces the whole judgment into
one opaque step, and gives two raters nothing to converge on except intuition.

The strong version breaks the decision into observable sub-questions, each
answerable from the text, and derives the decision from those answers. The
worked example uses six:

| Q | Asks | Type |
|---|---|---|
| 1 | Is this analyzing empirical data? | evidence |
| 2 | Does it evaluate patient-level health outcomes? | evidence |
| 3 | What allocation language does the abstract contain? | evidence |
| 4 | Was the intervention individually randomised? | evidence |
| 5 | Synthesize the above — should this be flagged? | reasoning |
| 6 | Include / Exclude / Human Review | decision |

The shape is **evidence → reasoning → decision**, and each part earns its place:

- **Evidence questions (1–4)** ask for things you can point at in the text.
  Two raters can check each other's answer to "does the abstract contain
  allocation language" in a way they cannot for "is this eligible." Break each
  part of the eligibility into individual questions. 
- **Q3 asks for a quotation**, not a judgment. Requiring the rater to copy the
  allocation sentence forces them to look, and leaves an audit trail you can
  inspect afterwards — if the decision is wrong, you can see whether the model
  misread the text or misapplied the rule.
- **The reasoning step (5)** makes the chain of thought explicit before the
  decision is committed. It also gives you something to read when you
  disagree with a label.
- **The decision (6)** should follow mechanically from the answers above it.
  In the worked example it is stated as a rule over the earlier fields:
  Include iff patient-level outcomes AND `intervention_randomized` is "Yes".

Ordering matters: evidence first, decision last. A rater who commits to a label
early will rationalize the evidence to match it.

### Give every question four parts

Each question in `screen_v1_codebook.txt` has the same anatomy. All four exist
to close a specific gap:

1. **Question** — the literal ask, with the permitted answers named. Constrain
   the answer space explicitly ("Answer Yes, No, or Not Applicable"); an
   open-ended answer cannot be tabulated or compared.
2. **Description** — the decision rule, including the boundary cases. This is
   where sharpness lives. Say what counts *and* what does not.
3. **Examples** — at least one per permitted answer, and at least one near a
   boundary. Examples resolve ambiguity that prose cannot: they are the
   cheapest way to communicate where a line sits.
4. **Default if missing** — what to answer when the abstract is silent.
   Without this, every rater invents their own convention for absent
   information, and you get disagreement that has nothing to do with the
   studies.

That fourth part is the one people leave out, and it is a common source of
avoidable disagreement.

### Sharp versus vague

The difference is whether the rule names its own edge cases.

> **Vague.** *Exclude studies that aren't proper randomized trials.*
>
> Two careful reviewers will split on cluster-randomised trials, on stepped-wedge
> designs, on quasi-experiments, and on trials that mention randomization but
> never say what was randomized.

> **Sharp.** *Answer "No" if no randomisation language was found, if it is
> cluster-randomised, if it is a single-arm trial, or if it relies on inverse
> probability weighting / "pseudo-randomisation" of observational data. Answer
> "Unclear" if the abstract mentions randomisation but is ambiguous about
> whether it was at the individual or cluster level.*
>
> The edge cases are named, and the ambiguous case has somewhere to go.

A practical test: **can you predict how a second reviewer would answer?** If you
find yourself thinking "it depends how they read it," the question is not sharp
enough yet.

### Give ambiguity a destination

Notice that "Unclear" above is a permitted answer. If a codebook offers no way
to express genuine uncertainty, raters are forced to guess — which is precisely
the behaviour the model is trying to measure, injected by your instrument.

But an abstain label costs something at analysis time, because it is not a third
opinion about the world; it is a refusal to give one. If your humans could only
say Include or Exclude, and the LLM can also say "Human Review", the label
spaces do not match, and you have to decide what an abstain means before
fitting. `analysis.human_review_action` in the experiment YAML records that
choice, and `code/04` documents the four options.

Whatever you choose, **check that it does not drive your result.** In the worked
example only 2 of 100 abstracts abstain, and all four policies leave every
kappa-ratio interval containing 1. If the choice does change your conclusion,
that is a finding about your codebook, not a detail to bury in a footnote.

## The development protocol

How you build the codebook matters as much as what is in it.

1. **Develop on a held-out set.** Draft and revise against abstracts you will
   *not* use for evaluation. The worked example used 20 preprints posted
   immediately before the evaluation corpus, drawn by the same search.
2. **Freeze before evaluating.** Once the codebook runs on the evaluation
   corpus, stop editing it. A prompt revised in response to evaluation results
   has been tuned on its own test set, and the resulting numbers are optimistic
   in a way you cannot quantify.
3. **Give humans and the LLM the same codebook.** This is what makes the
   comparison fair — you are measuring raters against a common task, not
   measuring differently-instructed raters. (In the worked example the humans
   recorded only the final label, not the intermediate reasoning.)
4. **Version rather than edit.** Once a codebook has produced results you
   report, it is immutable. Improvements become a new file.

The freeze is enforceable, not just a good intention: `code/03` records a
`prompt_sha` in every run record, so you can detect after the fact whether the
prompt file changed between the run and the write-up.

## Versioning and lineage

Naming convention:

```
{task}_v{n}_{strategy}.txt
```

so a series of variants on this task might run `screen_v1_codebook.txt`,
then a persona variant, then a persona-plus-few-shot variant, each as its own
file. (Only `screen_v1_codebook.txt` exists in this kit — the rest are
illustrations of the convention, not files you will find here.)

Each prompt begins with a header comment recording its identity and ancestry:

```
# id: screen_v1_codebook
# task: abstract screening for CONSORT compliance review eligibility
# parent: (none — baseline)
# strategy: codebook (structured chain-of-thought with definitions and examples)
# created: 2026-06-04
# schema: prompts/screen_v1_codebook.schema.json
```

The `parent` field makes the lineage between variants explicit, which is what
lets you attribute a change in results to a specific change in wording.

To compare two variants, add them as two `conditions` in one experiment YAML
rather than as two experiments — they then run over the same corpus and land in
sibling directories under `runs/`.

## The schema sidecar

Every codebook is paired with a JSON Schema file of the same stem:

```
screen_v1_codebook.txt          the prompt
screen_v1_codebook.schema.json  the shape of its output
```

`code/03` finds the schema by that naming convention, so the pairing is
structural rather than configured.

The schema is not documentation — it is enforced twice. `code/03` passes it to
the API as a tool `input_schema` and forces the model to call that tool, so the
reply is constrained as it is generated; then the response is validated against
the same schema with `jsonschema`. The first makes conforming output the default
path; the second catches drift between the prompt and the schema.

Keep the schema's field order and `description` strings aligned with the
codebook's questions. When they disagree, the prompt is what the model reads
and the schema is what the pipeline believes — an easy and confusing bug.

One consequence worth knowing: because the tool call constrains the output, any
"respond only with JSON" instructions in the prompt body are belt-and-braces
rather than the mechanism. The API contract is what governs.

### If you are adapting this codebook, update the mechanism

`screen_v1_codebook.txt` is published exactly as it was run, and it is dated in
two places you should not copy forward.

Its header says to pass the schema "as `response_format` to the API", and its
closing `## Output format` section instructs the model to reply with bare JSON.
Neither describes what `code/03` actually does, which is to force a tool call.
`response_format` is not an Anthropic parameter at all; the current equivalents
are structured outputs (`output_config.format`) or a tool definition with
`strict: true`. The bare-JSON instruction is inert here — every one of the 100
recorded runs returned `stop_reason: tool_use` and a schema-valid object — but
it is roughly 130 tokens, 6.5% of the prompt, telling the model to do something
the API prevents.

**We are not fixing it, on purpose.** The prompt is the instrument that produced
the results in `results/`, and publishing the exact text that was run is the
point. Its `prompt_sha` (`c1572450`) appears in all 100 run records; editing one
character would break that chain and leave the repo showing a prompt that never
produced these numbers. The same argument applies to `code/03`: adding
`strict: true` would tighten generation, which means the runner would no longer
be the one that made `runs/`. Both stay as they were run.

The transparency you get is a faithful record. The cost is that the record is
dated. So when you write your own codebook:

- **Describe the mechanism your runner actually uses**, and check it against
  current API documentation rather than copying this header.
- **Drop the "respond with JSON only" section** if you constrain output through
  the API. It is dead weight when the API already guarantees the shape.
- **Consider `strict: true`** on the tool definition. This schema already has
  `additionalProperties: false` and a `required` array, so it is strict-ready.
- **Check your model supports forced tool use.** `tool_choice: {"type": "tool"}`
  is rejected on the newest Claude models; see `experiments/README.md`.

Treat the frozen prompt as evidence of what was done, not as a template to copy
verbatim.

## Checklist

Before freezing a codebook:

- [ ] The decision is decomposed into observable evidence questions.
- [ ] Evidence comes before reasoning, which comes before the decision.
- [ ] Every question names its permitted answers.
- [ ] Every question states what does *not* count, not just what does.
- [ ] Every question has examples, including at least one boundary case.
- [ ] Every question has a "default if missing" value.
- [ ] Ambiguity has somewhere to go, and you have decided what an abstain means.
- [ ] At least one question asks for quoted evidence, for auditability.
- [ ] It was developed on abstracts held out from the evaluation set.
- [ ] The humans and the LLM are working from this same document.
- [ ] A schema sidecar exists and matches the questions.
- [ ] The header records id, task, parent, strategy, and date.
