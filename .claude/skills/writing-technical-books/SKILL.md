---
name: writing-technical-books
description: Use when writing, structuring, or editing a technical or programming book, tutorial series, or multi-chapter code walkthrough — especially literate / code-walkthrough books that explain real source line by line; when facing dense code listings, keeping readers oriented across many chapters, designing exercises, or deciding what a chapter should contain.
---

# Writing Technical Books

## Overview

A code listing is *reference material*; a book is *a narrative*. The
whole craft is keeping the reader in narrative mode while feeding them
dense technical detail. Every device below serves one principle:

**Never make the reader hold an unexplained listing in their head.**

The trap this skill exists to break: an agent *asked for advice* recites
these principles fluently, but an agent *actually writing* defaults to
dumping prose-wrapped source and rationalizing the choices afterward. The
knowledge is latent; it must be **applied as named moves during the work**,
and the discipline rules must survive the pressure to "just write it."

Two layers: a **general core** (any technical book) and a
**code-walkthrough layer** (books that explain real source line by line —
Crafting Interpreters, Nand to Tetris, JONESFORTH, literate programs). The
attributable evidence and source citations for every device live in
[references.md](references.md) — read it when you want the "why" or to cite.

## When to use

- Drafting or restructuring a chapter, tutorial, or multi-part walkthrough.
- A listing is long (roughly >40 lines) and you're tempted to show it whole.
- The book spans many chapters and readers may lose the thread.
- Deciding what belongs in a chapter and in what order.
- Designing or tagging exercises.
- Editing: code or prose changed and they may have drifted apart.

Not for: API reference docs, a single short how-to, or README-scale writing.

## The named moves (apply these *while* writing, not after)

| Move | Do this |
|---|---|
| **Persona + narrow scope** | Before outlining, write one sentence: *who* the reader is (novice building a mental model / practitioner filling gaps / expert wanting tradeoffs) and what slice you teach. Narrow beats broad. |
| **The ladder** | Each chapter builds *one* artifact that later chapters treat as a black-box primitive. Keep a visible ladder/"rung map" table: what each span builds and who later relies on it. |
| **Chapter contract** | Open each chapter with a 4-line header (template below): missing capability → new idea → artifact gained → payoff link. |
| **Grow, don't dump** | Never present a big listing whole. Show the skeleton (signature / struct / empty switch), then fill **one responsibility per fragment** (~5–30 lines). One sentence of *why* before each fragment; one sentence of *what now works / what's now broken* after. The after-sentence is the hook into the next fragment. |
| **Orient every fragment** | Each snippet says which file it belongs in and where, with a few faded/elided context lines so the reader can place it. |
| **Code tiers** | Mark code as **focus** (new, load-bearing, gets prose), **context** (faded / `// ...` elision, just enough to locate), or **boilerplate** (show one representative case, relegate the rest — "the other cases follow the same pattern"). A uniform gray block lies that every line matters equally. |
| **Run-it payoff** | Every chapter ends with the thing *running* on real input → real output (REPL transcript, passing test). Aim for a working program from chapter one that grows each chapter. A chapter ending mid-listing feels like homework. |
| **You-are-here map** | Reprint one architecture diagram with the current chapter's box highlighted. Add two-sentence "where we were / where we're going" tissue at each chapter boundary. |
| **Working-memory budget** | ≤ ~4 genuinely new chunks per section (Cowan). One new concept per fragment — split a fragment that introduces a new structure *and* a new algorithm. Re-anchor by name ("recall `peek()` returns the current token") instead of reprinting. |
| **Use first, understand later** | Hand the reader a working tool with usage shown, and explicitly defer its gnarly internals. Make hard low-level detail skippable ("you can skip this section"). |
| **Motif threading** | Name recurring patterns once, then call them out at each recurrence *at the new scale* ("same emit-then-patch from Ch 5, now across function calls"). Repetition-with-naming is how readers chunk. |
| **Worked examples** | For novice-facing material, teach with fully worked examples before asking the reader to solve unaided. (Fades as the reader gains expertise.) |
| **Exercise taxonomy** | Tag each exercise by *purpose* and difficulty. Purpose: **Trace** (follow a mechanism by hand), **Verify** (run a command, explain output), **Modify** (small change, predict/test), **Extend** (design beyond the target — mark when it won't preserve the book's invariants). At least one low-friction Trace/Verify per chapter. |

## Templates

Chapter contract (keep each line to one sentence):

```text
Missing capability: <what the reader can't do yet>
New idea: <the one concept this chapter installs>
Artifact after this chapter: <the concrete thing that now exists>
Payoff link: <how it serves the book's end goal / "none yet" early on>
```

Rung map (one row per span; stays stable across edits):

```text
| Rung | Built in | Artifact | Treated as machinery by |
|------|----------|----------|-------------------------|
```

## Discipline rules (these are what gets skipped under pressure)

**Violating the letter of these is violating the spirit.** They are the
difference between a book readers trust and one they catch lying.

1. **The book IS the source.** Every snippet comes from real,
   compilable/runnable source — not hand-typed approximations. If you
   type in all the code in the book, you get a working program. No tricks,
   no `...elided the hard part...` where the hard part is the point.
2. **Every snippet runs — and you've actually run it, this session.**
   Don't claim a command or its output until you've executed it and *seen*
   that output. The most embarrassing book bug is a Try-it that errors.
   **If you have not run it** — interactive, hypothetical, depends on code
   the reader hasn't assembled yet, or you can't in this environment — you
   must mark it at that spot ("expected output; not yet verified against a
   build") instead of presenting predicted output as observed fact.
   Predicted output shown as real is the *same defect* as a broken snippet,
   and "behind schedule" is not an exception — it's exactly when this slips.
3. **Re-verify after every edit.** Editing code or prose silently desyncs
   them. After any change, re-read the surrounding discussion to confirm
   it still matches the code. Automation (regenerating examples) does not
   remove this — "automate, but proofread."
4. **Read it cold.** Re-read each finished chapter cold, a day later or as
   a fresh reader. The exact spot where *you* get bored or lost is where
   the reader quits — usually a listing shown too whole or a payoff
   deferred too long. Fix that spot.
5. **No forward-reference rot.** Cite actual chapter numbers, not "we'll
   see later"; grep for forward refs before finalizing — reorders rot them.

## Common mistakes

| Mistake | Fix |
|---|---|
| Dumping a 200-line listing whole | Grow it: skeleton → motivated fragments. If it truly can't be decomposed, the *code* is doing too much for one chapter. |
| Teaching two new things at once (e.g. high-level concept + low-level memory) | Split across chapters or implementations; one new axis at a time. |
| Deferring the payoff for many pages | Insert a runnable checkpoint; track "pages since last runnable result." |
| Writing for everyone | Pick one persona; "for everyone" reads as "for no one." |
| Uniform code formatting | Apply code tiers — focus / context / boilerplate. |
| Renaming the same concept across chapters | Name things once, consistently; a rename is a silent reader tax. |
| Code and prose drifted after an edit | Re-verify (rule 3); the per-fragment "what now works" line catches most drift. |

## Red flags — STOP, you're rationalizing

- "I'll just paste the whole function, it's clearer in one piece."
- "The snippet basically runs / I'll verify the examples later."
- "I'll show the output the reader *should* see" — without having run it and without marking it as expected-not-verified.
- "The reader can figure out where this code goes."
- "This chapter is just setup — it doesn't need a payoff."
- "I'll nail down the audience once I've drafted a few chapters."
- "Showing iteration would break the build, so I'll fake the source."

Each of these means: go back to the named moves and discipline rules above.

## Relationship to project conventions

These are reusable devices. A given book's mechanics — its tangle/build
tooling, status legend, voice rules, file layout — belong in that
project's own docs (e.g. a `WRITING.md` / `CONCEPTS.md`), not here. This
skill tells you *what makes the writing work*; the project tells you *how
this book is wired*. Several moves above (chapter contract, rung map,
motif threading, exercise taxonomy) have a worked instantiation in the
`seed-forth` literate book if you want a concrete reference.
