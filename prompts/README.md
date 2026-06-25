# Prompts

Versioned prompt artifacts. Each file is an immutable, citable unit. Once a prompt has been used in an experiment reported in the writeup, we do not edit it. We create a new version.

## Naming

`{task}_v{n}_{strategy}.txt`

Examples for the CONSORT-eligibility screening task:

- `screen_v1_codebook.txt` — current baseline. Six-question structured codebook with definitions and per-question examples (chain-of-thought built into Question 5; JSON output).
- `screen_v2_persona.txt` — adds a clinical-trial methodologist persona on top of the codebook.
- `screen_v3_persona_fewshot.txt` — persona + held-out few-shot abstracts.
- `screen_v4_ensemble.txt` — same codebook prompt, run n=5 with majority vote on the final flag.

## Header

Each prompt file begins with a comment block:

```
# id: screen_v2_persona
# task: abstract screening for CONSORT eligibility
# parent: screen_v1_codebook
# strategy: persona assignment
# created: 2026-06-04
```

The `parent` field makes the lineage between variants explicit, which matters for the A/B narrative in the writeup.
