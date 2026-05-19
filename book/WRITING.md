# How to write a chapter

This is the protocol for turning a chapter stub into prose.  It exists
so you can sit down, follow the checklist, and finish a chapter without
re-deriving "wait, what was I supposed to do?" each time.

> **Note.**  The 32-chapter book is now complete (all rows ✅ in the
> [README.md](README.md) TOC and `tools/tangle.sh verify --strict`
> passing).  The procedure below is preserved for two cases: editing
> an existing chapter, and writing entirely new chapters (e.g. for a
> future extension of the bootstrap chain).  Status transitions
> (✏️ → 📝 → ✅) no longer apply during normal maintenance.

## Before you start

1. **Pick a chapter whose dependencies are written.**  Open
   [CONCEPTS.md](CONCEPTS.md), find the chapter in the dependency
   graph, and confirm every chapter it lists in "Concepts carried in"
   is at least partly written (📝 or ✅ in [README.md](README.md)).
   If not, write those first.

2. **Open three panes:**
   - the chapter `.md` (the stub you're filling in)
   - the source file under discussion
   - a terminal at the repo root for tangle / build / test

3. **Re-read the immediately preceding chapter's "Concepts
   introduced" and "Takeaways"** so the prose you write picks up the
   thread instead of restarting it.

## Writing the chapter

The stub structure is already in place.  Fill in prose between the
existing headings; don't restructure unless something is obviously
wrong.

The section plan is the writing skeleton.  Each numbered beat
becomes 1–3 paragraphs.  Aim for ~120–250 lines of finished prose
per Part I chapter, ~80–180 for Parts II and III.

### What goes where

- **Goal:** already written; touch only if you discover the chapter
  actually proves a different thing.
- **Source coverage:** already pinned to a line range; only edit if
  you discover the range is wrong (and update [CONCEPTS.md](CONCEPTS.md)
  if so).
- **Concepts introduced / carried in / deferred:** these are the
  contract with future chapters.  Treat them like an API.  If you
  add a new concept while writing, add it here too.
- **Section plan:** write prose under each numbered beat.  Promote
  the beat to a subhead (`## 1. Why "logic from nand" matters`).
- **Canonical source:** Part I — already filled in, do not edit.
  Parts II/III — when you write the chapter, replace the `TODO when
  writing` comment with actual `file=` and `chunk=` fenced blocks.
- **Try it:** every command must run.  Test before you commit.  See
  "Validating Try-it" below.
- **Exercises:** keep 3–5.  At least one should be hands-on (touch
  source or run a script), at least one should be analytical (read
  + reason), at least one should be open-ended.  Prepend a
  difficulty tag using `**★**` / `**★★**` / `**★★★**` per the
  rubric:
  - **★** *warm-up* — re-reading the chapter answers it (<10 min).
  - **★★** *standard* — synthesise two or three ideas (10–30 min).
  - **★★★** *depth* — hack the codebase, run tools, design a
    variant, or genuinely reach beyond the chapter.
- **Takeaways:** three bullets, each one a single sentence.  They
  are the cliff-notes; if a reader reads only the bullets they
  should understand the chapter's payload.
- **Next pointer:** one sentence.  Already in place.

### Voice

Match the tone of [00-prologue.md](00-prologue.md) and
[01-stacks-and-words.md](01-stacks-and-words.md):
- second-person ("you") for instructions, first-person plural
  ("we") for shared reasoning
- short paragraphs (2–4 sentences)
- inline code for word names (`emit`), block code for examples
- no apology, no hedging, no "as we'll see"-style forward refs;
  prefer "Ch N covers X" with the actual number

## Validating Try-it

### Part I (`010-lib.fth`) — gforth playground

```sh
cd seed-forth
gforth book/playground.fth -e "include 010-lib.fth  bye"
```

Or run a single snippet:

```sh
echo "your snippet here" | gforth book/playground.fth -e \
  "include 010-lib.fth"
```

If gforth's behaviour differs from the seed's (e.g. `[lit]` is not a
gforth primitive), the playground shim should cover the gap — but
test before claiming the snippet works.

### Parts II & III — built seed-forth

```sh
./build.sh && echo 'your snippet here' | ./seed-forth
```

For Part III examples that build the C compiler:

```sh
./build.sh && tests/cc/stage-a-check.sh
```

If you can't test a snippet (e.g. it requires interactive input,
or it's a hypothetical "what if you added this"), say so explicitly
in the chapter rather than presenting it as runnable.

## Adding canonical chunks (Parts II/III only)

When you write a Part II chapter, you add two kinds of fenced blocks:

1. **A root-block contribution** referencing the chunks this chapter
   defines:

   ````
   ```hex0 file=000-seed.hex0
   <<dup-code>>
   <<drop-code>>
   <<swap-code>>
   ```
   ````

   These accumulate across chapters in chapter-order (the tangler
   concatenates same-named `file=` blocks).

2. **One `chunk=` block per chunk name**, with the actual hex from
   the corresponding range of `000-seed.hex0`:

   ````
   ```hex0 chunk=dup-code
   ;; dup_code @ 0x13B
   48 83 ED 08     ;; sub rbp, 8
   48 89 7D 00     ;; mov [rbp+0], rdi
   C3              ;; ret
   ```
   ````

The same pattern applies for Part III, swapping `file=000-seed.hex0`
for `file=NNN-cc-NAME.fth` and using Forth blocks instead of hex.

## Updating the status

After committing a chapter's prose:

1. Open [README.md](README.md).
2. Find the chapter row in the TOC table.
3. Change ✏️ to 📝 (in progress) or ✅ (done).
4. Re-run `tools/tangle.sh status` to confirm coverage rose.
5. Re-run `tools/tangle.sh verify --strict` to confirm no drift.

A chapter is "✅ done" when:
- prose under every section-plan beat is written
- every Try-it snippet has been run successfully
- exercises read clearly and have at least one hands-on item
- `tangle status` shows 100% coverage for the file(s) this chapter
  covers (Part I) **or** the chunks this chapter owns are all
  defined (Parts II/III)
- a friend or future-you read it once and didn't get stuck

## Committing

One commit per chapter is the sweet spot.  Message format:

```
book: write Ch N — <chapter title>

<1-3 sentences on what landed and what concept the chapter teaches>

Brings 010-lib.fth coverage to ... / Adds chunks <<a>>, <<b>>, <<c>>
to 000-seed.hex0.
```

Stage selectively: `git add book/NN-*.md book/README.md` — avoid
sweeping in unrelated changes.

## Common pitfalls

- **Stub drift.**  If you change the line range in "Source coverage,"
  also update [CONCEPTS.md](CONCEPTS.md) and the corresponding row in
  [README.md](README.md).
- **Forward references.**  If you write "we'll see this in Ch X"
  and then move things around later, the reference rots.  Prefer
  "Ch N introduces this" with the actual current number, and grep
  for forward refs before committing.
- **Untested Try-it.**  The most embarrassing book bug.  Run every
  snippet.
- **Implicit primitive use.**  In Parts II/III, you can use primitives
  introduced in Part I and the seed.  But if you reach for `: foo
  ... ;` syntax in a chapter that hasn't covered `:`, the reader is
  lost.  Re-check "Concepts carried in."
- **Skipping section plan beats.**  The beats are calibrated to the
  chapter's word budget.  If you skip beat 3, the chapter is
  underweight; if you merge beats, you've changed the curriculum.
  Either is fine but be deliberate.

## When you finish a chapter

1. Re-read it cold.  Note where you got stuck or bored.
2. Fix those spots.
3. Update the status legend.
4. Commit.
5. Pick the next chapter (use [CONCEPTS.md](CONCEPTS.md) to pick
   one whose deps are satisfied).
