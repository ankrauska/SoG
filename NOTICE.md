# Notice — licensing and patents

This repository contains two things with different owners and different terms:
the kit, and the method it implements. Both are settled. Read this file before
reusing either.

## The code

All of the code in this repository is licensed under **PolyForm Noncommercial
1.0.0**. See [`LICENSE`](LICENSE). Two parties hold the copyright:

- **The kit** — the pipeline scripts, the codebook prompt and schema, the
  experiment configuration, the documentation, and the worked example's data
  and results — is Auden Krauska's.
- **The vendored estimator** under `code/em/` is Rohe et al.'s, copied verbatim
  from the methodology code (see [`code/em/SOURCE.md`](code/em/SOURCE.md)).

Same license either way, so for a user the distinction is about attribution
rather than permission.

## The method

Copyright is not the only thing covering `code/em/`. The method those files
implement is separately the subject of a pending patent application, which a
copyright license does not address. The following note from the applicant
states the terms.

---

### A note on patents, from Karl Rohe

I personally own a pending international patent application (PCT/US2026/036035)
that describes methods related to this software. No patent has issued yet. I
filed it so that commercial use of these methods stays my decision, not so it
could get in the way of the people this work was made for.

So here is the promise. If you use or share this software, or practice anything
claimed in that application or its patent family (details below), for a
noncommercial purpose, I will never assert any patent in that family against you
for doing so. Not this code, not your fork of it, not your own implementation
from scratch. Replicate it, extend it, teach with it, break it and tell us how.

The promise stops at commercial use, and PolyForm's definition draws the line.
Outside a university, charity, or government body, that means use by or for a
business is not covered: research and development inside a company, evaluating
the methods for a product, use in a commercial product or service, and
consulting, advisory, or contract work for a business on your own account, paid
or unpaid, even if you are an academic. I reserve all patent rights for those
uses.

The details, so nobody has to guess:

- "Noncommercial purpose" means a permitted purpose under the Noncommercial
  Purposes, Personal Uses, and Noncommercial Organizations sections of PolyForm
  Noncommercial 1.0.0
  (https://polyformproject.org/licenses/noncommercial/1.0.0). Only those purpose
  sections are borrowed, as a fixed definition, whether or not that license
  still governs the copy you are using. They count use by a university, charity,
  or government body as noncommercial regardless of who funds the work, and I
  mean it to, including the students and staff doing that institution's work.
  That coverage does not extend to a business's own use.
- The promise is made to everyone, needs no signature, and is irrevocable. It
  covers any patent that issues from this application or claims priority,
  directly or indirectly, to it or to its provisional, anywhere in the world,
  including national and regional patents, continuations, continuations-in-part,
  divisionals, and reissues, and any right to compensation for use before a
  patent issues (35 U.S.C. § 154(d) or similar laws elsewhere).
- It runs with the patents. Anyone who later owns, controls, or is exclusively
  licensed under these rights takes them subject to it, and I will make every
  transfer or license of these rights expressly subject to it.
- What you did while your use was noncommercial stays covered if you later go
  commercial. What you do commercially afterward does not.
- This is a covenant not to sue. It does not authorize anyone to make, sell, or
  hand over a copy for commercial use, whoever they got it from.
- The code itself is Auden Krauska's, licensed under PolyForm Noncommercial
  1.0.0. Nothing here changes that license. This note grants no other rights and
  comes with no warranty. It binds me, and you may rely on it. If I ever update
  this note, it will only widen the promise.

— Karl Rohe, September 14, 2026

Last updated: September 14, 2026

---

## What this means in practice

If you are at a university, a charity, or a government body, or working on this
for personal research or study, you are covered for both the code and the
method. Reproduce the worked example, run the validation on your own screening
task, fork it, teach with it.

If you are at a business, or doing contract or consulting work for one, neither
the code license nor the patent covenant covers you, even if you are an
academic doing that work on your own account. Contact Karl Rohe about the
patent, and Auden Krauska about the code.

## Citing the method

Rohe, K., Krauska, A. N., Collins, G., Higgins, J., and Pustejovsky, J.
*The solve or guess model: Validating automated systems against heterogeneous
human raters.* Working paper, 2026.

Cite the source for the method itself; this kit is an application of it.
