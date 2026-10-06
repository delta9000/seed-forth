# Return check: source, storage, and two executions

Try these after intervening material or at a later session, with the worked
answers closed. Use the chapter contracts or reference links if a convention
is missing. The aim is to choose the relevant mechanism, not to memorize an
address. These are paper cases under the pinned legacy profile unless a
question changes one choice.

## Questions

### CR1-01

A root byte file contains `#include "part.h"\nX\n`; the successfully opened
header contains `Y\n`. Assume both files are read completely and successfully.
Each displayed `\n` is one newline byte. Neither X nor
Y is a macro. Predict the flattened bytes, source length, line counter just
after scanning, and line counter at lexer entry. Does this establish the
length of a generated executable or what a running C program prints?

### CR1-02

A newest-first name table stores a four-byte name span into a completed
root-level include's slot. The root then reads another header into that same
slot. The table index and pointer value are unchanged. Can a later lookup be
assumed to find the original name? Identify the storage that must be
preserved, and contrast this with a still-live parent while its nested child
is being scanned.

### CR1-03

Use a paper capacity of six bytes. An output emitter has already appended six
valid bytes. Separately, an input reader's first read returns six. Which
operation has met its local capacity contract, and which exits? If a later
file-output attempt returns four from `write`, does the current writer try
again? Distinguish source acceptance, buffer contents, file delivery and
program behavior in your explanation.

### CR1-04

A driver selects the 3/7/4-MiB I/O workspace but leaves the target-selection
flags unchanged at their legacy defaults. What are the three selected bases
relative to mapping base M? Has `int` become four bytes? Has a stored output
position been reset? Has System V calling convention been selected? State
which facts follow from the selector and which need a different operation.

## Before revealing the answers

For each case, write one sentence naming the decisive contract. If you have
only a final number, add the state change that produced it. If you cannot
begin, choose one of these cues:

- CR1-01: the include shares its parent's output sink but leaves the parent's
  directive newline for later consumption
- CR1-02: copying a pointer and copying pointed-to bytes are different actions
- CR1-03: the reader tests accumulated length plus one; the emitter tests its
  prospective emitted length
- CR1-04: changing selected storage is not changing target semantics or
  initializing per-compilation state

## Worked answers

### CR1-01

The header contributes `Y\n`, then the parent's retained directive newline is
emitted, then `X\n`. The predicted source is `Y\n\nX\n`, five bytes with three
newlines. The output-progress line is four after scanning. Completion
publishes source length five and rewinds the next reader to position zero,
line one. The include's input cursor and the shared output cursor have
different owners.

This fixture is preprocessor-only text, not a complete C program. It supplies
no executable-size or running-program observation. Even for valid C input,
source length, emitted image size and program output are different quantities.

Changed case: remove only the header's final newline. The source becomes
`Y\nX\n`, four bytes, with output-progress line three and next-reader line
one. The parent still contributes its own retained newline.

### CR1-02

No. The table retains the same numeric address, but the second header may
replace the four bytes at that address. The old span can also exceed the new
header's meaningful length. Newest-first lookup decides which record to
inspect first; it does not preserve the record's referenced text.

Before the include slot is reused, copy the required name bytes into owned
storage whose lifetime covers later lookups, and store the resulting span.
The macro pool later provides that role. A nested child instead occupies a
different live slot from its parent, so the parent's input bytes are preserved
until its own scan finishes. These are lifetime rules, not properties of the
word “header.”

Changed case: in a packed pool, popping the top permits reuse of the child's
span. It still does not move or invalidate the still-live parent's lower span.
The preservation argument should name intervals rather than rely on a fixed
slot number.

### CR1-03

The emitter may fill six-byte storage exactly: its last prospective length
was six, so the last byte was stored at offset five. Another append would fail
with output code 21. The input reader adds the returned six and tests
`6+1 <= 6`; that fails with its supplied code, such as 20 for stdin. It does
not perform a further EOF probe or append a zero terminator.

For a separate successful path reaching the file writer, a four-byte return
from a six-byte request leaves two bytes undelivered by that request. The
legacy writer drops the result and calls `close`; it has no retry loop. A
populated output buffer therefore does not establish complete file delivery.
A delivered file still needs loading and execution before its behavior is an
observation. A source-capacity failure never reaches those later stages
through normal return.

Changed case: reads of two, three, then zero accept five bytes and return
that count. The next destination offsets are 0, 2 and 5; request sizes are
6, 4 and 1. A negative result in place of zero also ends this reader and
returns five, rather than diagnosing the read error.

### CR1-04

Raw input uses M with capacity 3 MiB; expanded source uses M+3 MiB with
capacity 7 MiB; output uses M+10 MiB with capacity 4 MiB. The first successful
selection maps 14 MiB and caches M; another selection reuses it.

None of the other conclusions follows. The legacy target still gives `int`
eight-byte storage, and its call contract remains the legacy one. The selector
changes buffer pointers and limits, copies no existing payload and resets no
length or cursor. A fresh compilation must initialize its input/source/output
state through the appropriate driver operations. A different target requires
explicit target selection, not merely more workspace.

Changed case: selecting the default workspace again changes the three
address/limit pairs back. It does not free the cached mapping, recover earlier
logical lengths, or make stale cursor values valid for a new compilation.

## Use the result

If a number is wrong, locate the first transition where your state differs.
If a number is right but its evidence claim is too strong, name the unobserved
boundary. Reattempt one changed case without the answer open; later return to
a different question. A successful paper explanation is useful evidence of
that explanation, not a compiler execution or a general learning study.

[Back to the volume](../README.md)
