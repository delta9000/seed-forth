# Learning Story Plan — third version (post-rollout)

An editorial plan for the book's learning arc. This version replaces two
earlier ones, and the history matters because it explains the shape:

- **v1** proposed a six-phase template rollout (chapter contracts,
  normalized Try-its, exercise tags) across the whole book. That rollout
  was **executed** — commits `db43be3` (rung map, contracts, motifs,
  exercise tags) and `8383afd` (scaffolding aligned across all 32
  chapters), net **about +1,000 lines** of prose.
- **v2** correctly repudiated v1's uniformity-machinery instincts but was
  written as if the rollout were still in the future. Its "first concrete
  edits" were already done; its prohibitions (no contracts on Chs 29–31)
  were already violated by the committed text it never audited.
- **v3** (this file) is grounded in the tree as it stands today.

## Identity guardrails (unchanged, load-bearing)

The distinctive payoff is the byte-level audit trail from a 2,040-byte
seed to an M2-Planet-compatible compiler whose emitted `.M1` text matches
the GCC-built reference. Everything below serves that.

- **Do not** become a greenfield project book. The reader audits a
  canonical artifact; they do not invent an implementation.
- **Do not** hide byte layout, addresses, flags, or calling conventions
  behind friendly abstraction.
- **Do not** add compiler theory unless it directly helps read *this*
  compiler.
- **Do not** replace a code walk with vague pedagogy.

## Current state (audited, not assumed)

What already exists in the tree:

- **Rung map, capability ladder, five named motifs** — all in
  `book/CONCEPTS.md`. (This plan deliberately does not duplicate those
  tables; v2 carried inline copies that had already drifted in wording.)
- **Part II → III bridge** — the "Reading Part III" section at the end of
  Ch 20: names the three core motifs, describes the contract/receipt
  blocks, points at `CONCEPTS.md`.
- **Chapter contracts** — on *every* chapter except the prologue,
  including Chs 29–31 (which v2 called contrived) and all of Parts I–II
  (which no plan version proposed). Sampling them: the Part III ones read
  well, because each opening states the `110-cc-decl.fth` source split
  honestly. Whether the Part I/II ones and the 29–31 ones earn their keep
  is a question for the acceptance test, not for a sweep in either
  direction.
- **Motif threading** — "same emit, remember, patch from Ch 11" sentences
  at the recurrences (Chs 19, 21, 25, 26, 30, 31).
- **"Bootstrap relevance" blocks** — Part III chapters tie mechanisms to
  the Stage-A gate and cite `tests/cc/G*.c` fixtures.
- **Bug-fix gates A–H** — `tests/cc/{A..H}-*.c` plus `run-gates.sh`,
  wired into `check-all.sh`. The fixed code is mirrored into the
  chapters' fences (the literate invariant held), **but no chapter cites
  a gate file by name**. This is the one substantive gap.

## Step 1 — Run the acceptance test (before any editing)

The only completion criterion, now with a procedure:

> Give a fresh reader the **openings of Chapters 21–32** — title,
> contract block, and opening prose up to the first source fence, with
> all listings removed. For each chapter they answer two questions:
> **(1) what artifact does this chapter install? (2) which earlier
> artifact does it build on?**

Procedure: a human volunteer, or — honest cheap proxy for an AI-built
book — a fresh model session given *only* the excerpts, no repo access.
Score each chapter pass/fail per question.

**Pass bar: at least 10 of 12 chapters get both questions right, and no
chapter misses both.** Below that, the failing chapters name exactly
where to work; above it, the orientation spine is done and the remaining
work is the committed list below plus pruning.

v2's diagnosis ("Part III reads as a long listing to survive") described
the **pre-rollout** book. The rollout may already have fixed it. Do not
edit for orientation until the test says orientation is still broken.

## Step 2 — Committed work (independent of the test outcome)

These three items are justified on their own terms, not by orientation
failures.

### 2a. Gate cross-references — the proof-link at its finest grain

Each A–H gate documents a real compiler defect and the exact behavior
that now holds. Referencing the gate from the chapter whose mechanism it
guards is audit-voice content — the book's thesis — not scaffolding.
One or two sentences per site, in the existing "Bootstrap relevance"
blocks where present. Suggested mapping (verify each against the
`6649728` diff before writing):

| Gate | Defect area | Owning chapter |
|---|---|---|
| `A-locals18.c` | local slots ≥16 needed disp32 | Ch 25 (frame encoders) |
| `B-switch-continue.c` | scrutinee leak on early exit | Ch 30 (switch) |
| `C-struct-global.c` | global struct sized as 8 bytes | Ch 29/31 (globals) |
| `D-charptr-store.c` | store width from scalar type | Ch 28 (lvalue store) |
| `E-chained-subscript.c` | element type across `[][]` | Ch 28 (postfix) |
| `F-wide-const.c` | imm32 vs movabs for wide literals | Ch 26/28 (immediates) |
| `G-indented-define.c` | indented `#define` skipped | Ch 22 (preprocessor) |
| `H-comment-directive.c` | comment-aware skip-to-eol | Ch 22 (preprocessor) |

Where a gate's mechanism is *not* otherwise covered by Stage-A parity
(the gates exist precisely because Stage-A's input never exercised these
paths), say so plainly — honesty about the proof's edges is part of the
voice. This is the one place where *adding* prose is the point.

### 2b. The first subtraction edit

The rollout net-added about +1,000 lines to a book whose stated problem
is density. Start paying it down with the duplication already visible:
the end of Ch 20 ("Reading Part III") and the start of Ch 21 ("Part
III's repeated shapes") name the same motif set back-to-back across one
chapter boundary. Keep the Ch 20 version (it's the part-boundary bridge);
cut Ch 21's section down to a pointer plus the byte-path diagram, which
is the only content Ch 20 doesn't have.

Rule going forward: **edits to chapter bodies are net-neutral or
subtractive**, except 2a above.

### 2c. Part I proof-link honesty pass

The contract template said "Proof link: … 'none yet' in early Part I,"
but every Part I chapter stretched to find one (Ch 3's "the C compiler's
lvalues and control-flow use these without ever re-deriving them" is a
reach for a NAND-logic chapter). Pick one policy and apply it:

- **Keep the links but make them checkable** — each must name a specific
  consumer ("the lexer (Ch 23) reuses these classifiers" passes; vague
  "the compiler relies on this" fails), or
- **Allow "none yet — this chapter is vocabulary"** where that's the
  truth.

Either is fine; mixed stretching is not. This is a small pass over twelve
4-line blocks.

## Step 3 — Evaluate, then prune (gated on Step 1)

- **If the test passes:** the conditional devices from v2 (per-chapter
  on-ramps, Try-it normalization, more contract work) stay dead. Consider
  one pruning question only: do the Part I/II contracts earn their keep,
  or are twelve "Proof link: fluency" boxes the over-scaffolding v2
  warned about? Decide by reading three Part I chapters cold, not by
  policy.
- **If specific chapters fail:** fix only those, choosing the device that
  matches the failure — a rewritten contract if the artifact was
  misnamed, a source-listing on-ramp if the reader drowned before the
  first section break, consolidation of the 29–31 contracts into one
  shared "which third of `110-cc-decl.fth` you're in" note if the split
  confused them. Never as a sweep; the sweep already happened.

## Validation (every edit session)

- `./check-all.sh` — the canonical gate: build, tests, asm, A–H gates,
  `tangle.sh verify --strict`, `check-numbers.py`, Stage-A.
- `mdbook build` for anything touching `SUMMARY.md` or rendered structure.
- Gate references in 2a cite test files by path; keep paths exact so
  `rg -n "tests/cc/[A-H]-" book/` can audit coverage mechanically.

## Risks

- **Re-sweeping.** The failure mode of v1 was committing to templates in
  advance; the failure mode now would be "fixing" chapters the test never
  flagged. The test result is the work order.
- **Plan/book desync.** v2's defect. After any edit batch, re-read this
  file's "Current state" section and update it — a plan that misdescribes
  the tree is worse than no plan.
- **Breaking the literate contract.** 2a adds prose *near* fences, never
  inside them. `tangle.sh verify --strict` after every chapter touched.

## Order of work

1. Run the acceptance test (Step 1). Record per-chapter results here.
2. Gate cross-references (2a) — verify mapping, write, validate.
3. Ch 20/21 dedupe (2b).
4. Part I proof-link pass (2c).
5. Evaluate gate (Step 3): prune or fix per test results, then stop.

## Results (2026-06-10)

**Step 1 — acceptance test: PASS.** Administered to a fresh Sonnet
session given only the Ch 21–32 openings (title + contract + prose up
to first fence), no repo access. Score: 12/12 on artifact-naming,
11/12 on builds-on, no double miss (bar was 10/12). The one miss:
Ch 24's opening gave no way to tell which earlier artifact it builds
on ("cannot tell" — honest answer, real gap). The reader also flagged
Ch 24's one-word-encoding motivation as thin and noted Ch 30's
trampoline dependency on Ch 31 leaves the reading-order implication
implicit (acknowledged in the chapter's callout; no edit).

**Targeted fix from the test:** Ch 24's opening now anchors struct
descriptors to Ch 21's arena and the symbol columns to Ch 12's
`create`/`allot` + `bytes-eq` (net-neutral rewording, no added
paragraph).

**2a — done.** All eight gates verified against the `6649728` diff
(the mapping table above held, with two spans noted: B's helper is
defined in Ch 29's span but cited from Ch 30, which owns the switch
mechanism; F's call site is Ch 28 but the encoder and citation live
in Ch 26). Each owning chapter's "Bootstrap relevance" block now
cites its gate file and states the parity edge: every fix left the
Stage-A bytes unchanged, so each gate is the only check on its path.
Coverage is mechanically auditable: `rg -o "tests/cc/[A-H]-" book/`
returns all eight.

**2b — done.** Ch 21's "Part III's repeated shapes" section reduced to
a pointer at Ch 20's bridge plus the byte-path diagram (the only
content Ch 20 lacked). Net subtraction.

**2c — done.** Policy chosen: keep the links, make them checkable.
Rewrote the five stretched ones (Chs 3, 4, 7, 8, 12) to name specific
consumers, each verified against the compiler source. Chs 1, 2, 5, 6,
9, 10, 11 already passed the rubric and were left alone.

**Step 3 — verdict: the spine passes; conditional devices stay dead.**
Pruning question (do the Part I/II contracts earn their keep): keep
them. They are four lines each against 300–600-line chapters, and
post-2c every Part I proof link names a checkable consumer; the
over-scaffolding risk was in stretched claims, not in the boxes.
