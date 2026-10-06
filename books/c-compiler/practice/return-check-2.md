# Return check: macros, decisions, and source identity

Use these paper cases after the macro and conditional chapters, with their
worked tables closed. Bring the exact profile named in each question. If an
interface is missing, reopen its contract; this is not a memory test of
function names. All results remain manual derivations.

## Questions

### CR2-01

Direct preprocessing is enabled. Define `HEADER` as `"a.h"` and preprocess
`#include HEADER`, with no trailing space before its LF. The include handler
skips blanks before borrowing its operand. How many bytes are in the expanded
temporary operand, including separator spaces? Which storage must stay alive
until its header operand has been parsed and the included bytes scanned? Does returning from that
file also reclaim the outer operand temporary?

### CR2-02

In the legacy profile, define `GATE` first as `1` and then as `0`. Before any
undefinition, compare `#ifdef GATE` with `#if GATE`. Then process `#undef GATE`.
Does the older definition become visible? Has its pool space or record count
been reclaimed? Explain why using an empty replacement body instead of `0`
would still make the name present.

### CR2-03

Use the legacy profile, C05's supplied evaluator, an initially empty
conditional stack, and no definition of `NEVER_EVALUATED`. An active file
opens `#if 0`. Inside that skipped group it contains another
`#if NEVER_EVALUATED`, an `#error`, and the nested `#endif`. The outer group
then reaches `#else`, followed by `kept` and its closing `#endif`. Track the
conditional states and say which condition reaches the expression evaluator.
Is the nested suppression the same mechanism as evaluating a logical
expression's dead right-hand operand?

### CR2-04

Use a source-location-enabled direct profile. The physical main file is
`/project/src/main.c`. Its first line is `#line 40 "virtual.c"`; line two
contains `__LINE__`, and line three contains `__FILE__`. What do those two
macros contribute, in normalized token spelling? If a later relative quoted
include names `detail.h`, which directory is searched first? Does `cc-die`
therefore print the presumed filename and line forty?

## Hints

- CR2-01: the borrowed spelling starts after the separator; two different
  scans each add an edge space
- CR2-02: newest-first lookup, all-matches undefinition, and storage reclamation
  are three different operations
- CR2-03: an inactive parent makes a newly opened child `done`; closing the
  child exposes the parent's earlier state
- CR2-04: retain physical path, logical offset/name and flattened diagnostic
  progress as separate records

## Worked answers

### CR2-01

The borrowed slice is `HEADER`, not a leading space plus HEADER. Its object
replacement contains the five bytes `"a.h"`. Scanning the operand region adds
one space at each edge, and scanning the object replacement adds another
pair. The exact temporary is two spaces, `"a.h"`, two spaces: **nine bytes**.
These are temporary preprocessing bytes, not an executable or file-size
measurement.

The handler retains the temporary while it installs that span as an
operand-reading region, validates the single header operand, resolves the
physical path and descends into the included file. The include has its own
input-region/depth/pool-top restoration. On its return, the outer handler still
must restore the original directive region and finally the saved scratch top.
Popping one nested lifetime does not automatically end every enclosing one.

Changed case: add another space between `include` and `HEADER`. Both separator
spaces are skipped before borrowing, so the nine-byte result is unchanged.
Do not transfer that answer to `cc-pp-if-value` without checking its entry
position: the conditional-expression path borrows its remaining line before
such an include-specific blank skip.

### CR2-02

Newest-first lookup finds the second GATE record. `#ifdef` asks whether that
record exists, so it selects its first group. `#if` expands ordinary GATE to
zero and sends the resulting expression to the evaluator, so that condition
is false. Presence and value answer different questions.

The undefinition handler repeatedly finds matches and clears each matching
name length. Both GATE records become unavailable to lookup; the older `1`
does not reappear. The record count and text-pool position are not reduced.
The records and their copied bytes still occupy storage for the pass, even
though lookup no longer treats their names as live.

Changed case: an empty GATE body still belongs to a record with a live
nonempty name, so `#ifdef GATE` remains true. Do not invent a numerical value
for an empty expanded expression; presence alone does not supply one.

### CR2-03

The outer `#if 0` is active when encountered, so its zero expression reaches
the evaluator and pushes `seek`. The nested opener finds its parent already
skipping and pushes `done` without evaluating `NEVER_EVALUATED`. The hidden
`#error` is not dispatched as an active error. The nested closer pops `done`,
leaving the outer `seek`. The outer `#else` changes it to `take`; `kept` is
retained, and the final closer returns to depth zero.

Ordinary retained newline handling is separate from whether a line's other
bytes survive. No full byte-output claim is made without specifying the exact
line endings and input bytes.

The later expression evaluator's short-circuit machinery can parse a dead
arm while suppressing its evaluation. Here the conditional-group dispatcher
does not send the inactive nested expression to that evaluator at all. Both
avoid evaluation, but their state owners and parsing work differ.

Changed case: use outer `#if 1`. It pushes `take`, so the nested expression
now reaches the evaluator. The bare remaining identifier has value zero under
the named evaluator contract and pushes `seek`; the nested error remains
hidden. After its closer, outer `#else` changes `take` to `done`, so `kept`
is not retained.

### CR2-04

The directive sets the logical offset to `40−(1+1)=38`. At physical line two,
`__LINE__` therefore contributes decimal token `40`. At physical line three,
`__FILE__` contributes the string token `"virtual.c"`; a `__LINE__` invocation
there would contribute `41`. Those are normalized token spellings, not a
claim about all surrounding output spaces or newlines.

The physical file identity remains `/project/src/main.c`. A later quoted
`detail.h` first tries `/project/src/detail.h`, then the configured include
directories if needed. The presumed display name does not redirect that
search.

`cc-die` uses its separate flattened source-progress counter and fixed
`cc: line N: error CODE` form. It does not automatically print the virtual
filename or use the location macro's value. A trace of `__LINE__` is not a
trace of the diagnostic formatter.

Changed case: an empty presumed filename is a real zero-length logical name,
not the sentinel meaning “use the physical path.” It still does not change
include search. Omitting the filename operand, in contrast, preserves the
previous presumed name.

## Check the reason, then change the situation

If you mixed presence with value, use CR2-02 with an empty body. If you mixed
nested lifetimes, draw one interval for the operand and one inside it for the
include. If you mixed location meanings, keep three named columns rather than
repairing a number by guesswork. Return later to another changed case without
its answer open. Correct performance on these cases does not establish full
C preprocessing conformance or learner transfer to an unrelated system.

[Back to the volume](../README.md)
