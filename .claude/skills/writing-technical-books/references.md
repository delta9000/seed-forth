# Evidence base — attributable techniques and sources

Each device in [SKILL.md](SKILL.md) traces to a primary source. This file
is the "why" and the citations; load it when you want to justify a choice
or quote an authority, not on every use. Findings were gathered by a
multi-source research pass and adversarially fact-checked (most confirmed
3-0; the worked-example finding split 2-1 but rests on a broad
meta-analytic base).

## General craft

**Learner persona + narrow audience.** Write to a fictional learner — "a
novice (who is trying to build a mental model), a competent practitioner,
or an expert" — and target a narrow slice ("Python for Web Scraping," not
general Python). Haberman & Wilson, *Ten Simple Rules for Writing a
Technical Book*, PLOS Comp Biol (2023),
https://pmc.ncbi.nlm.nih.gov/articles/PMC10414569/

**Test against a live audience before finishing.** "If you run even a
single workshop based on the material for your book while you are writing
it, you will almost certainly realize that several of your core
assumptions about your audience and material are completely wrong while
you still have time and energy to fix things." (same source)

**Automate, but proofread — re-verify code against prose after every
edit.** "You may be able to regenerate all of the examples in your book
with a single command, but you must still reread the discussion about
those examples every time you make a change to make sure they haven't
fallen out of step." (same source, Rule 8)

## Cognitive load

**Working memory ≈ 4 chunks.** "An average person can only hold about four
chunks of information in their working memory at one time (Cowan 2001)."
Range is debated (3–5, more with chunking), but ~4 is the estimate for
novel, un-chunked material — exactly a reader meeting new technical
content. NSW CESE, *Cognitive Load Theory* review (2017), summarizing
Cowan (2001).

**Simple-to-complex sequencing lowers intrinsic load.** Intrinsic
difficulty is relative to expertise; "introduce the elements of the
material to the learner in a simple-to-complex order so that the learner
does not initially experience the full complexity" (van Merriënboer,
Kirschner & Kester 2003, via CESE). This is *why* prerequisites and a
graded ladder matter.

**Worked-example effect.** Novices taught with many worked examples learn
faster and transfer better than those left to solve problems unaided
(Sweller & Cooper 1985; meta-analytic g≈0.48). Caveat — the **expertise
reversal effect**: the benefit fades and can reverse as the reader becomes
expert, so fade worked examples toward problems as a book advances.

## The code-walkthrough subgenre

**Program as literature (Knuth).** "Instead of imagining that our main
task is to instruct a computer what to do, let us concentrate rather on
explaining to human beings what we want a computer to do" — present
concepts "in an order that is best for human understanding, using a
mixture of formal and informal methods that reinforce each other." Knuth,
*Literate Programming* (1984),
http://www.literateprogramming.com/knuthweb.pdf

**Single source, two outputs (WEAVE/TANGLE).** One WEB file yields both
human documentation (WEAVE) and the executable program (TANGLE), so "the
program and its documentation are both generated from the same source, so
they are consistent with each other." Consistency follows from common
origin — this is the mechanical backbone of "the book IS the source."

**Include every line; orient at the insertion point (Nystrom).** "Every
single line of code needed is included, and each snippet tells you where
to insert it... a few faded out lines above or below to show where it
goes... a little blurb telling you in which file and where to place the
snippet." "If you type in all of the code in the book, you get two
complete, working interpreters. No tricks." Crafting Interpreters intro,
https://www.craftinginterpreters.com/

**Keep the underlying source real and compilable.** Nystrom hand-authors
valid programs and wraps superseded code in block comments "so the code as
it is in the raw source file is still valid" — the listing can show
iteration without breaking the build.
https://journal.stuffwithstuff.com/2020/04/05/crafting-crafting-interpreters/

**Per-chapter buildability.** A custom tool collects each chapter's
snippets plus all prior chapters into source files and builds a runnable
interpreter *per chapter*, with a test runner tracking which tests pass at
each step — proving the in-progress program works at every point. (same
blog) The tooling is bespoke; the *technique* — verify the reader's
program at every chapter — generalizes.

**Dual ladder of abstraction.** "It's hard to teach high-level concepts
like parsing and name resolution while also tracking pointers and managing
memory. OK, so we'll build two interpreters. First, a simple one in a
high-level language to focus on concepts. Then a second bytecode VM in C."
One new axis of difficulty at a time. (same blog)

**Fixed chapter scaffold + momentum.** "Each chapter takes a single
language feature, teaches you the concepts behind it, and walks you
through an implementation." "From the very first chapter, you'll have a
working program you can run and play with. With each passing chapter, it
grows increasingly full-featured." Crafting Interpreters intro.

**Implementation and tutorial as one file (JONESFORTH).** A single
annotated assembly source that is simultaneously a working FORTH compiler
and a tutorial; chapter-like comment blocks (INTRODUCTION, THE DICTIONARY,
COMPILING) with ASCII diagrams precede the code they explain.
https://github.com/nornagon/jonesforth/blob/master/jonesforth.S

**Make hard detail optional.** "(You can just skip to the next section --
you don't need to be able to read assembler to follow this tutorial)."
Treats low-level literacy as optional, not a prerequisite. (JONESFORTH)

**Use first, understand later.** Readers get the `defword`/`defcode`
macros with usage shown while internals are deferred: "Don't worry too
much about the exact implementation details of this macro - it's
complicated!" (JONESFORTH)

**Learning by building / layered ascent (Nand to Tetris).** A "step-by-step
construction of a complete, general-purpose computer system" as "a layered
architecture, where each layer builds upon the previous one to create
increasingly sophisticated abstractions"; "understanding through
creation." Nisan & Schocken, CACM (2023),
https://cacm.acm.org/research/nand-to-tetris-building-a-modern-computer-system-from-first-principles/

## Failure modes (contrarian sources)

- Wall-of-code that is reference material masquerading as narrative; the
  reader drops out of narrative mode and never climbs back.
- Teaching two new things at once (high-level concept + low-level
  mechanics) — split them.
- Deferring the runnable payoff too long, turning chapters into a slog.
- Code that doesn't run or has drifted out of sync with the prose.
- Audience drift — writing for everyone, therefore for no one.

Sources: *How NOT to Write a Technical Book* (Coding Horror,
https://blog.codinghorror.com/how-not-to-write-a-technical-book/); Kartik
Agaram on literate-programming pitfalls
(http://akkartik.name/post/literate-programming); review of *Writing an
Interpreter in Go* (https://slar.se/book-review-writing-an-interpreter-in-go.html).

## Open questions the research did not settle

- Concrete, attributable guidance on **exercise design** in
  code-walkthrough books is thin; the Trace/Verify/Modify/Extend taxonomy
  in SKILL.md is proven practice (seed-forth book), not a cited standard.
- How to **fade worked examples** within a single book whose reader grows
  from novice to practitioner.
- Revision workflows beyond automate-and-proofread and live workshops
  (technical-reviewer cadence, beta programs, errata-driven iteration).
