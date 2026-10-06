# Saved continuation drafts: C16–C18

These chapters are saved work in progress after the
[reviewed C01–C15 checkpoint](https://github.com/delta9000/seed-forth/commit/41f538d2da81f3831782d960a546c991244e2c83).
They are available to read and their technical/practice reviews have passed,
but the complete statement/function unit is not yet integrated. The described implementation remains pinned to
`7d7e1996d1753118181d43e1a413960d3a1ec24b`.

| Draft | Practice | Current review boundary |
|---|---|---|
| [C16 Conditions and loops](chapters/16-conditions-and-loops.md) | [Eight exercise sets](practice/16-solutions.md) | Technical/practice and continuous-story reviews passed; later unit integration remains pending |
| [C17 Switches, labels, and nonlocal control](chapters/17-switches-labels-and-nonlocal-control.md) | [Eight exercise sets](practice/17-solutions.md) | Technical/practice and continuous-story reviews passed; later unit integration remains pending |
| [C18 Functions and call-frame accounting](chapters/18-functions-and-call-frame-accounting.md) | [Nine exercise sets](practice/18-solutions.md) | Technical/practice review passed; the continuous first-reading story was checked for flow and technical consistency |

Each draft gives a bounded first reading session, later routes, worked traces,
graduated hints and changed-case practice. The practice adds 25 paired main
exercises. A checked reading route means that its named sections supply the
contracts needed by its assigned exercise parts; it is not a reader study.

Local links, exercise pairing and Markdown-to-HTML parseability were checked.
No rendered-layout, accessibility or real-reader validation is claimed. No
compiler, Forth, C example, generated program or bootstrap was executed for
these chapters. Numerical outcomes remain source-derived predictions.

## First-reading revisions

[C01](chapters/01-compiler-entry-and-profile.md) now starts with one small
`line(2, 3)` prediction before the complete triangle program. [C18](chapters/18-functions-and-call-frame-accounting.md)
keeps the copied-value puzzle, parameter slots, frame, return and complete call
in one continuous sequence. The alignment problem follows as a separate
question; compiler bookkeeping and provider details come afterward.

Independent review checked the changed explanations against the source and
previous worked results. Simulated reader checks sampled C1-01–C1-03 and the
C18 extra-local question, C18-04 and C18-07, looking for steps unsupported by the
supplied text. These are bounded model-assisted dependency checks, not human
learning, retention or transfer results.

C16 now follows the opening `continue` puzzle through `while`, `do` and `for`,
then explains why replay must save an already-read token. C17 follows one
switch through its case bodies, selector and cleanup before the byte-layout
and parser details. Their changed explanations received independent
source-consistency and simulated-reader checks, including loop destinations,
fallthrough, no-default behavior and saved-register cleanup. The source's
chosen layouts are distinguished from requirements imposed by C behavior.

The next integration includes C19's translation-unit/process-entry
account, complete source-map ownership and a mixed practice check. The [coverage map](../COVERAGE.md) still records
the reviewed C01–C15 scope rather than crediting these saved drafts as a
finished migration. Source and canonical literate-book files are unchanged.
