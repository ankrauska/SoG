# Notice — provenance and licensing

> **⚠️ PLACEHOLDER — NOT YET SETTLED.**
> The terms below are a description of the situation, not a licence grant.
> Confirm the actual terms with the patent holder and, if applicable, the
> university technology-transfer office before publishing or sharing this
> repository. Nothing here has been reviewed by a lawyer.

## Two things with different owners

This repository contains two kinds of material, and they do not carry the same
terms.

**1. The kit.** The pipeline scripts (`code/01`–`code/05`, `code/config.R`), the
codebook prompt and schema, the experiment configuration, the documentation, and
the worked example's data and results. This is the application layer, written
for this project.

**2. The solve-or-guess method and estimator.** The files under `code/em/` are
copied verbatim from the published solve-or-guess methodology (Rohe et al.), and
they implement a method that is **the subject of a patent held by Karl Rohe**.
See `code/em/SOURCE.md`.

The second is not this project's to license. Vendoring the estimator here is a
convenience so the kit runs without an external checkout; it does not grant
anyone rights to the underlying method.

## Intent

This kit is published for **academic research use** — reproducing the worked
example, and running the same validation on other screening tasks in a research
context. Commercial use of the solve-or-guess method requires permission from
the patent holder.

## Why this is not simply an open-source licence

A patent changes the calculus in a way a standard licence file does not capture,
and choosing the wrong one gives away more than intended:

- **MIT / BSD** grant copyright permissions but say nothing about patents. A
  user who complied with them could still be infringing, so the licence would
  not actually convey what a user needs.
- **Apache 2.0** includes an *express patent grant* from contributors. Applying
  it to this repository could be read as granting a patent licence to every
  recipient for any use — likely far broader than intended.
- **Academic-use-only** terms are a real and common arrangement for patented
  methods, but they are not open-source under the OSI definition, and the text
  has to be drafted deliberately rather than adapted from a template.

## To resolve

- [ ] Confirm with Karl Rohe how the patented method should be licensed for reuse.
- [ ] Check with the university technology-transfer office (for UW–Madison, WARF),
      which will typically have standard research-use licence text for exactly
      this situation.
- [ ] Decide terms for the kit layer, which may be more permissive than the
      method layer.
- [ ] Replace this placeholder with the settled terms, and add a `LICENSE` file.

## Citing the method

Rohe, K., Krauska, A. N., Collins, G., Higgins, J., and Pustejovsky, J.
*The solve or guess model: Validating automated systems against heterogeneous
human raters.* Working paper, 2026.

Cite the source for the method itself; this kit is an application of it.
