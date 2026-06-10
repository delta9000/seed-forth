# Learning Story Improvement Plan

This is an editorial plan for improving the book's learning arc while
preserving its identity: an exact, literate, auditable walkthrough of a
real bootstrap artifact.

The north stars are:

- **The Elements of Computing Systems / Nand2Tetris** for ladder
  discipline: each chapter builds one abstraction, names the artifact,
  and hands that artifact to the next chapter.
- **Crafting Interpreters** for incremental momentum: each chapter
  should make the system feel more capable, with a clear runnable or
  inspectable increment.

This book should not become either of those books. Its distinctive
payoff is the byte-level audit trail from a 2,040-byte seed to a
M2-Planet-compatible compiler whose emitted `.M1` text matches the
GCC-built reference. The improvement is to make that payoff easier to
track while the reader is inside dense implementation chapters.

## Editorial Goals

1. **Make every chapter feel like a rung.**
   A reader should know what capability was missing, what concept
   solves it, what artifact now exists, and what later chapter can
   treat as machinery.

2. **Keep the exact-source promise intact.**
   Do not replace code walks with vague pedagogy. Add orientation
   around the code so the exact details are easier to absorb.

3. **Reduce Part III cognitive load.**
   The compiler chapters should feel like a sequence of compiler
   organs being installed, not a long source listing to survive.

4. **Repeat the book's core motifs deliberately.**
   The reader should recognize the same few ideas scaling upward:
   fixups, fixed buffers, parallel arrays, newest-first lookup,
   simple linear scans, and byte emission.

5. **Tie local detail back to the proof.**
   Especially in Part III, each chapter should say how its mechanism
   contributes to the Stage-A parity claim.

## What To Borrow

### From Nand2Tetris

- A visible ladder of abstractions.
- A chapter-level contract: what abstraction is being built and what
  the next layer can assume.
- Concrete artifacts after each step.
- Repeated system diagrams that keep the reader oriented.
- Projects/exercises whose purpose is obvious.

### From Crafting Interpreters

- A sense that the program gets more capable chapter by chapter.
- Clear incremental checks.
- Feature-sized framing around implementation.
- Permission to read complex listings for shape first, then return to
  the details through the prose walk.

## What Not To Borrow

- Do not turn the book into a greenfield project book. The reader is
  auditing a canonical artifact, not inventing an implementation.
- Do not hide byte layout, addresses, flags, or exact calling
  conventions behind friendly abstraction.
- Do not add broad compiler theory unless it directly helps read this
  compiler.
- Do not make exercises depend on large unverified rewrites unless
  they are explicitly marked as extension work.

## Core Editorial Device: The Chapter Contract

Add a short recurring block near the top of each chapter. Use it
lightly in Parts I and II; use it consistently in Part III.

Template:

```text
Missing capability:
New pattern:
Artifact after this chapter:
Proof link:
```

Example for Chapter 25:

```text
Missing capability: compiled C needs executable bytes.
New pattern: emit machine-code bytes into cc-out-buf, then patch.
Artifact after this chapter: a valid ELF header plus instruction encoders.
Proof link: later stages can write /tmp/cc-out and compare emitted .M1.
```

Rules:

- Keep each line one sentence.
- Prefer concrete nouns over chapter-summary prose.
- The "Proof link" may be "none yet" in early Part I, but by Part III
  it should point toward Stage-A parity.
- Do not duplicate the whole introduction. This is a reader handrail,
  not a replacement for prose.

## Core Editorial Device: The Rung Map

Add a compact ladder table to `book/README.md` or `book/CONCEPTS.md`.
It should show what each span builds and when later chapters can treat
it as primitive.

Draft:

| Rung | Built in | Artifact | Treated as machinery by |
|---|---:|---|---|
| Forth vocabulary | Ch 1-12 | `010-lib.fth` helpers | Parts II and III |
| Seed VM | Ch 13-20 | `seed-forth` interpreter | Part III |
| Compiler buffers | Ch 21 | source/output streams | Ch 22-32 |
| Preprocessed source | Ch 22 | flattened C stream + macro table | Ch 23-32 |
| Token stream | Ch 23 | `tok-*` globals | Ch 24-31 |
| Type/symbol database | Ch 24 | type words + symbol slots | Ch 26-31 |
| Code emitter | Ch 25-26 | ELF and x86-64 encoders | Ch 27-31 |
| Expression compiler | Ch 27-28 | value/lvalue codegen | Ch 29-31 |
| Declaration/statement/function compiler | Ch 29-31 | complete C-subset parser | Ch 32 |
| Proof harness | Ch 32 | Stage-A `.M1` parity | Appendices |

This table should be short enough to scan and stable enough to survive
minor chapter edits.

## Part Bridges

Add bridge sections at the places where the reader's mental model has
to change.

### After Chapter 12: What Part I Bought Us

Location options:

- End of `book/12-defining-words-and-bytes-eq.md`
- Start of `book/13-elf-and-entry.md`
- A short companion section linked from both

Purpose:

- Say that Part I taught Forth as a usable language while treating the
  seed primitives as black boxes.
- Name the vocabulary the reader now owns: stack shuffles, memory
  writers, defining words, constants, control-flow combinators, and
  byte comparison.
- Prepare the inversion in Part II: the words that were black boxes
  now become bytes.

Acceptance:

- The reader should understand why Part II appears to "go backward"
  into machine code.

### After Chapter 20: The Seed Is Now A Host

Location:

- End of `book/20-number-parser-and-repl.md`

Purpose:

- State that the seed now has enough language machinery to load and run
  the compiler vocabulary.
- Explain the shift from "how the Forth exists" to "what we build with
  that Forth."
- Preview the Part III patterns.

Acceptance:

- The reader should enter Chapter 21 expecting compiler infrastructure,
  not another seed-internals chapter.

### Before Chapter 21: Patterns Of The Compiler

Location:

- Start of `book/21-arena-and-io-buffers.md`, or a short new section
  immediately before its first source block.

Purpose:

- Name the repeated Part III implementation patterns up front:
  fixed buffers, parallel arrays, integer IDs, newest-first lookup,
  emit/patch/finalize, and "M2-Planet-shaped" limits.
- Explain that the compiler is intentionally narrow: it compiles the
  subset needed to match M2-Planet, not C in general.

Acceptance:

- A reader should be able to identify the pattern in Ch 22-31 when it
  reappears.

## Part III Artifact Map

Each Part III chapter should open by naming the artifact it installs.

| Chapter | Artifact | What Now Works |
|---:|---|---|
| 21 | source buffer, output buffer, allocator | bytes can flow in, bytes can be emitted and patched |
| 22 | preprocessed source + macro table | project includes and integer macros flatten into one stream |
| 23 | lexer token state | parser can ask for identifiers, keywords, numbers, strings, and punctuation |
| 24 | type and symbol tables | names and C types have compact runtime representations |
| 25 | ELF header + instruction encoders | the compiler can write executable bytes |
| 26 | calls, shims, string/global fixups | compiled code can call functions and runtime shims |
| 27 | precedence-climbing expression parser | arithmetic/comparison/logical expressions emit code |
| 28 | assignment, postfix, lvalues | expressions can read and write memory-shaped C objects |
| 29 | declarations and globals | types, structs, typedefs, and file-scope data can be parsed |
| 30 | statements and control flow | blocks, branches, loops, switch, labels, break/continue/goto compile |
| 31 | functions and program driver | a full translation unit compiles into an ELF |
| 32 | shell harness and parity check | the compiler is tested against the GCC-built reference |

Use this map to rewrite chapter openings away from "this covers lines
X-Y" as the primary hook. Source ranges can stay, but they should be
secondary to the artifact.

## Recurring Motifs To Surface

### Emit, Remember, Patch

This is the strongest through-line in the book.

Appearances:

- Ch 11: `if,` emits a slot and `then,` patches it.
- Ch 19: `branch` and `0branch` explain why the inline slot works.
- Ch 21: output buffer patch helpers make patching a compiler backend
  operation.
- Ch 25: `rel32` placeholders for jumps and calls.
- Ch 26: forward calls and global-address placeholders.
- Ch 30: statement-level jumps, loops, switch dispatch, labels.
- Ch 31: function definitions patch call lists and entry-stub calls.

Plan:

- Add one sentence at each recurrence: "This is the same emit,
  remember, patch pattern from Ch N, now at [new scale]."
- Add the motif to `book/CONCEPTS.md` as a first-class concept, not
  only "Fixup-on-the-stack."

### Small Tables, Linear Search, Newest Wins

Appearances:

- Ch 17: dictionary lookup.
- Ch 22: macro table.
- Ch 24: symbol table.
- Ch 30: label table and fixup lists.
- Ch 31: typedefs, globals, function symbols.

Plan:

- Name this as an intentional design pattern: bounded inputs,
  predictable memory, no allocator complexity in hot paths.
- Connect it to bootstrap constraints: clarity and sufficiency beat
  generality.

### One Buffer Per Responsibility

Appearances:

- Ch 21: source buffer, output buffer, arena.
- Ch 22: preprocessor output buffer and include pool.
- Ch 26: string pool and global fixup arrays.
- Ch 31: globals buffer.

Plan:

- Give readers a compact memory-flow diagram before Part III:
  stdin -> `cc-src-buf` -> `cc-prep-out-buf` -> `cc-src-buf`
  -> lexer/parser -> `cc-out-buf` + globals -> `/tmp/cc-out`.

## Try-It Normalization

Make the Try-it sections answer the same three questions where
possible:

```text
Small check:
Layer check:
Bootstrap relevance:
```

Definitions:

- **Small check**: a minimal snippet or command that exercises the
  chapter's mechanism.
- **Layer check**: the existing unit/layer script that covers the
  relevant file.
- **Bootstrap relevance**: whether `stage-a-check.sh` covers this
  mechanism and why.

Examples:

- Ch 22 small check: run a tiny include/define through the compiler
  pipeline.
- Ch 23 layer check: `./test.sh` covering `test-050-cc-lex.fth`.
- Ch 31 bootstrap relevance: Stage-A exercises calls, globals, shims,
  params, and entry-stub patching together.

Acceptance:

- A reader should never have to infer whether a snippet is runnable,
  illustrative, or only conceptual.
- Existing commands must stay tested.

## Exercise Taxonomy

Retain the star difficulty, but add purpose tags. This makes the
exercises feel more like projects without requiring a full project-book
rewrite.

Tags:

- **Trace**: follow a mechanism by hand.
- **Verify**: run a command and explain the output.
- **Modify**: make a small local change and predict/test behavior.
- **Extend**: design or implement beyond the bootstrap target.

Format:

```markdown
1. **★ Trace.** ...
2. **★★ Verify.** ...
3. **★★★ Modify.** ...
```

Rules:

- Each chapter should have at least one Trace or Verify exercise.
- Part III chapters should include at least one Bootstrap-relevance
  exercise when practical.
- Extension exercises should say explicitly when they are not expected
  to preserve Stage-A parity.

## Source Listing Guidance

Some chapters, especially Ch 28-31, include long source listings. Add a
standard note before those listings:

```text
Read this block once for shape. The sections after it walk the paths
that matter. You do not need to memorize every helper on first pass.
```

Use this sparingly in shorter chapters. It matters most where the
reader faces hundreds of lines before the prose resumes.

## Implementation Phases

### Phase 1: Orientation Spine

Files:

- `book/README.md`
- `book/CONCEPTS.md`
- `book/20-number-parser-and-repl.md`
- `book/21-arena-and-io-buffers.md`

Work:

- Add the rung map.
- Add or strengthen the Part II -> Part III bridge.
- Add the Part III patterns preview.
- Add the motif names to the concept index.

Validation:

- `mdbook build`
- `tools/tangle.sh verify --strict`

### Phase 2: Chapter Contracts For Part III

Files:

- `book/21-arena-and-io-buffers.md` through
  `book/32-main-and-bootstrap-chain.md`

Work:

- Add the four-line chapter contract to each Part III chapter.
- Reframe openings around artifacts before source ranges.
- Keep source coverage details, but make them secondary.

Validation:

- `mdbook build`
- Spot-read all Part III chapter openings in sequence.

### Phase 3: Motif Pass

Files:

- Ch 11, 17, 19, 21, 22, 24, 25, 26, 30, 31
- `book/CONCEPTS.md`
- `book/GLOSSARY.md` if new terms need definitions

Work:

- Surface "emit, remember, patch" at every scale where it appears.
- Surface "small tables, linear search, newest wins."
- Surface buffer ownership and memory-flow patterns.

Validation:

- `rg -n "emit, remember, patch|newest wins|parallel arrays|fixed buffers" book`
  should show intentional recurrence, not accidental repetition.

### Phase 4: Try-It Normalization

Files:

- All chapter files, with priority on Part III.

Work:

- Normalize Try-it sections around small check, layer check, and
  bootstrap relevance.
- Mark conceptual snippets as conceptual.
- Run every command that claims to be runnable.

Validation:

- `./build.sh`
- `./test.sh`
- `tests/cc/stage-a-check.sh`
- Any extra per-chapter commands introduced by the pass.

### Phase 5: Exercise Taxonomy

Files:

- All chapter files.
- `book/A4-worked-exercises.md`

Work:

- Add Trace/Verify/Modify/Extend tags.
- Ensure each chapter has at least one low-friction confidence check.
- Update Appendix D labels to match the new taxonomy.

Validation:

- Read the exercise list only, without chapter prose, and confirm it
  tells a coherent practice path.

### Phase 6: Final Flow Read

Files:

- `book/SUMMARY.md`
- `book/README.md`
- All chapters

Work:

- Read only chapter openings, Try-it sections, Takeaways, and Next
  pointers in order.
- Fix places where the global learning story drops out.
- Check that Part III does not over-explain the same bridge in every
  chapter.

Validation:

- `mdbook build`
- `tools/tangle.sh verify --strict`
- `./test.sh`
- `tests/cc/stage-a-check.sh`

## Acceptance Criteria

The plan is complete when:

- A reader can state the artifact produced by every chapter from
  Ch 21 to Ch 32 before reading the source listing.
- The Part III opening sequence clearly explains why fixed buffers,
  parallel arrays, and patch lists are the compiler's normal shape.
- The phrase "emit, remember, patch" or equivalent appears at each
  major recurrence, with the new scale named.
- Try-it sections consistently identify what is runnable and what
  each command proves.
- Exercises are tagged by learning purpose, not only difficulty.
- The byte-identity claim remains precise: matching emitted `.M1`,
  not matching compiler ELFs.
- `tools/tangle.sh verify --strict`, `mdbook build`, `./test.sh`, and
  `tests/cc/stage-a-check.sh` pass after the editorial pass.

## Risks

- **Over-scaffolding.** Too many repeated boxes can make the book feel
  mechanical. Keep contracts short.
- **Reader-facing vs maintainer-facing confusion.** This plan is
  editorial. Only promote pieces into `SUMMARY.md` if they help
  readers directly.
- **Breaking the literate contract.** Any edit inside `file=` fenced
  blocks must be mirrored to source, or avoided unless the source
  comment really needs to change.
- **Diluting the audit voice.** The book should stay exact and
  source-grounded. The learning scaffolding should orient, not soften.

## First Concrete Edit

Start with Phase 1. It has the highest leverage and lowest risk:

1. Add the rung map to `book/CONCEPTS.md`.
2. Add a concise Part III patterns preview to the end of Ch 20 or the
   start of Ch 21.
3. Add "emit, remember, patch" and "small tables, newest wins" to the
   concept index.
4. Run `mdbook build` and `tools/tangle.sh verify --strict`.

After that, Chapter 21-32 contracts can be added in one focused pass.
