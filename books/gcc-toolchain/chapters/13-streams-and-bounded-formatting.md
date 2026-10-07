# Streams and bounded formatting

A read can transfer five bytes while returning only one complete four-byte
object. Where did the fifth byte go, and how should the caller distinguish end
of input from an error?

Follow one stream read, one pushed-back byte and one shortened formatting
buffer. These are contracts of the source-built runtime used by generators and
the first cc1, not host libc FILE objects.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G07 supplies memory and allocation; G12 supplies variadic retrieval. A
**stream** owns a descriptor plus logical state. size/count arguments describe
objects, while kernel read/write counts describe bytes. Assume valid supplied
buffers and streams. No file is opened or modified for these paper tasks.

## Buffer acceptance and descriptor progress

The five-byte fread trace below supplies unbuffered input (or equivalent
already-accounted buffer replies); extra read-ahead would change kernel position
without changing the complete-object count. For fully buffered output,
`fprintf` can accept bytes before any kernel write: a later fflush can fail.
For example the source account describes `/dev/full` accepting a formatted
length into the buffer, then fflush reporting ENOSPC. Keep acceptance, descriptor
progress and flush status separate. ftell subtracts all unread input and adds
pending output; the one-byte pushback exercise supplies no other pending state.
See [buffered stream contracts](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/STDIO-BUFFERING.md#L9-L99)
and [exact floating output](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/PRINTF-FLOAT.md#L1-L78).

## Give the descriptor an owned stream state

The private FILE record holds descriptor, access mode, sticky error/EOF state,
buffer mode, unread/pending extents, pushback and allocation state. Standard streams are initialized lazily
through accessors; their definitions are separate from the kernel’s descriptor
numbers. The public header now defines a complete FILE type with reserved members;
its layout is unrelated to host libc and callers still use the functions.

fopen validates its supported mode spelling, opens a descriptor and creates its
stream wrapper. fdopen transfers descriptor ownership only on success and does
not truncate merely because a w spelling was supplied. freopen has its own
replacement and failure path; it is not equivalent to closing an old stream and
assuming a new one exists.

fclose flushes pending output before closing and releasing owned storage.
Modes are selected on first I/O: terminal streams are line buffered, other
ordinary streams fully buffered, and stderr unbuffered. The default buffer is
BUFSIZ=8192; allocation failure falls back to unbuffered I/O. setvbuf accepts
full, line and unbuffered modes; setbuf with a non-NULL buffer requests full
buffering rather than failing. fflush writes pending output and reconciles
unread input on seekable descriptors.

Sources: [stream representation and
lifetime](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L1-L509),
[complete FILE and buffered
surface](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/include/stdio.h#L1-L120),
[buffering
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/setbuf.c#L1-L8).

## Count progress in bytes, return complete objects

Supply fread(buffer,4,2,stream), no pushed byte, and kernel replies of three
bytes, then two bytes, then zero. The requested total is eight; done progresses
0→3→5. Zero marks EOF and stops. The public return is floor(5/4)=1 complete
object. The fifth byte was written into the buffer even though it does not make
another complete object.

The loop retries EINTR and keeps positive partial progress. A negative non-EINTR
result sets errno and the sticky error flag. A zero result marks EOF without
converting it into a kernel error. Calling feof before a read therefore cannot
predict whether the next request will hit end of input.

fwrite also checks size*count overflow before multiplication and returns
completed object count from accumulated bytes. A write returning zero progress
becomes EIO and marks error. The API’s object count is not a guarantee that no
bytes of an incomplete final object reached the destination.

Sources: [read/write progress and partial
objects](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L510-L578).

## Reconcile one logical byte with kernel position

ungetc stores pushed bytes in buffer headroom (at least eight), clears EOF
and does not seek the descriptor backward. In this example assume no other
unread buffered bytes. Suppose the kernel position is ten and one byte is pushed. ftell
reports nine, subtracting the pending byte. The next fread consumes that byte
before another kernel request.

For a successful SEEK_CUR operation, fseek decreases the requested relative
offset by one while a push is pending, then clears push and EOF. A successful
seek is not clearerr: sticky error remains until its explicit clearing
operation. A failed seek preserves the relevant pending state and error
information.

rewind attempts absolute seek zero and clears indicators afterward, even if the
seek failed. A void return therefore does not establish successful
repositioning. These policies matter when a generator uses streams to reread
input or recover from an unmatched character.

Sources: [line reads, pushback and
positioning](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L629-L733).

## Separate formatted length from stored bytes

Supply snprintf into a four-byte buffer with text ABCDE and no conversions. Its
result is five, the would-have-written byte count. It stores ABC followed by
NUL. The full logical output length, stored non-NUL prefix and buffer capacity
are therefore five, three and four.

With capacity zero it stores no byte and can still compute length. This does not
make a NULL pointer valid for arbitrary nonzero-capacity output. The formatter
checks count overflow and reserves its closing terminator within supported
buffer operations.

A stream formatter writes through the progress-aware stream sink, while a buffer
formatter truncates storage without truncating its logical count. Both use the
same supported conversion parser. A successful bounded formatting count is not
proof that a stream write succeeded.

Sources: [format sinks and count
checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L744-L820),
[public formatting
wrappers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L1067-L1153).

## Retrieve the type the conversion actually requests

The supported formatter reads flags, width, precision and length before choosing
a variadic argument type. Signed decimal and unsigned decimal/octal/hexadecimal
use their promoted int or LP64 long/long-long interfaces. h/hh shorten the
fetched promoted value; z/t/j select the documented LP64-width path. Pointer,
narrow string/character, ASCII wide string/character, percent and %n have
explicit paths.

For a negative signed value the magnitude must be formed without overflowing
LONG_MIN. Prefix, precision zeroes and field padding have different positions: a
sign comes before zero padding. Negative star width requests left justification;
a negative precision is treated as unspecified. Width/precision overflow
rejects.

Floating e/E/f/F/g/G/a/A conversions now use the exact formatter, taking
double normally and long double for L (also ll). Positional conversions remain
unsupported and fail with EINVAL before consuming the argument. Wide conversion is ASCII-bounded; a code point
above 127 reports EILSEQ. Floating arithmetic and formatting are separate providers; this pin supplies
both.

Sources: [supported format grammar and
conversions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L872-L1066).

## Count bytes before counting complete objects

Supply an input request for two objects of four bytes each. The requested extent
is eight bytes. Suppose the underlying reads make three bytes of progress, then
two, then report end-of-file. The stream has received five bytes in total. The
object-count result is one, because only one four-byte object is complete.

The fifth byte has still been transferred into the destination. Returning one
object does not say that exactly four bytes were touched. Keep the destination's
eight-byte capacity, five-byte progress and one complete-object result in
separate columns. A caller that repeats the request must account for the API
contract rather than pretending the partial object never existed.

A zero result from the underlying read marks end-of-file in this supplied trace.
A negative error would set a different sticky state. Short progress alone need
not mean either event; another read may make more progress. The source's loop
and indicators let the operation preserve those distinctions.

For output, a partial underlying write also consumes only a prefix. Its retry
loop must continue at the next unwritten byte. Counting completed objects
belongs after tracking actual progress, not before the system call. This is the
runtime version of the publication concern in G02, with a different stream owner
and no implication that each write creates an atomic final file.

Sources: [read/write progress and partial
objects](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L510-L578).

## Keep a logical position when a byte is pushed back

A successful ungetc retains one byte to supply to the next input operation. The
underlying file descriptor may already be past that byte. Consequently, the
logical stream position must account for the pending pushed-back byte. Reading
the descriptor's offset alone would describe physical input progress, not the
stream view presented to the caller.

Supply a descriptor offset ten and one pending pushed-back byte. The logical
next-read position is one byte earlier under this contract. Consuming that byte
changes the stream state without another kernel read. A seek has to reconcile
this pending state with the requested positioning operation rather than silently
leaving both views active.

EOF and error indicators are sticky records. Clearing them changes the
indicators; it does not repair an invalid descriptor or manufacture missing
input. An eventual stream check should retain operation results and indicators
together. Looking only at errno after a successful operation would conflate the
wrapper's last error storage with this stream's current progress.

Sources: [line reads, pushback and
positioning](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L629-L733).

## Measure formatting independently of capacity

Supply five output characters A B C D E and a snprintf destination capacity of
four. The formatter's required length is five. The stored output is A B C
followed by a terminator. The count answers how much formatted text was
required, while capacity answers how much may be stored.

With zero capacity, no destination character can be stored, yet the length
calculation remains meaningful under the selected contract. With capacity one,
only the terminator fits. These changed cases reveal whether the formatter
counted conceptual output or merely successful stores. Preserve both counters
while following the source's output helper.

The supported formatting subset handles selected integer, string and pointer
cases with width, precision and padding behavior. It does not acquire floating
formatting because a later GCC-built musl provides it. Its wide-character
helpers retain their stated limited behavior rather than promising a complete
locale system. A future fixture should choose admitted conversions and record
both returned length and destination bytes; no new stream or formatting run
accompanies these paper traces.

Sources: [format sinks and count
checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L744-L820),
[public formatting
wrappers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L1067-L1153),
[supported format grammar and
conversions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L872-L1066).

## Follow a formatted character to its actual owner

The formatter can count a conceptual character before deciding whether a
destination has room to store it. For a bounded string destination, capacity
limits stores while the required-length count continues. For a stream
destination, the eventual write has its own progress and error state. One
formatter count therefore cannot stand in for every output observation.

Supply five formatted characters and a stream write that makes three bytes of
progress before failing. Retain the five-character logical count, three
delivered bytes and the error event separately. The surrounding program must see
the public formatting/write failure according to the selected API; the book's
evidence must also retain the partial physical progress.

The integer length modifiers belong to argument interpretation. An hh conversion
requests a promoted integer through varargs, then narrows it for the desired
formatting semantics. It does not mean the caller placed a one-byte slot in the
save area. G12's promotions remain part of the formatter's input contract.

| Output view | Quantity it reports | State it cannot replace |
|---|---|---|
| Conceptual formatter | Required character count | Destination capacity |
| Bounded destination | Stored prefix plus terminator when possible | Full required length |
| Stream transfer | Bytes actually progressed | Conceptual output alone |
| Public result | API success/failure or count | All underlying progress details |
| Sticky indicator | Retained stream error/EOF state | Current operation's complete result |

On input, pushback supplies a byte without another kernel read. A logical tell
operation therefore accounts for that pending byte, while the descriptor offset
records prior physical progress. Seeking and clearing state have specified
effects, so a reader should check them individually rather than assuming one
successful operation resets the whole FILE object.

Streams now have real buffering. Buffer acceptance can precede descriptor
progress, and a later flush can fail. The exact floating formatter supplies %f
and its related conversions; positional formats and non-ASCII wide output
remain outside the admitted surface.

A future fixture should record returned values, exact stored bytes, capacity and
indicators. This lets an empty destination, partial object or failed write be
interpreted under its actual rule. No target stream was opened or formatting
result observed for these new paper examples.

Sources: [stream representation and
lifetime](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L1-L509),
[complete FILE and buffered
surface](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/include/stdio.h#L1-L120),
[buffering
boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/setbuf.c#L1-L8),
[read/write progress and partial
objects](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L510-L578),
[format sinks and count
checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L744-L820),
[public formatting
wrappers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L1067-L1153),
[supported format grammar and
conversions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L872-L1066).

## A stream handle is an owned object, not just a descriptor number

The runtime's FILE representation includes descriptor and stream state. The
public header keeps it opaque so callers use operations rather than relying on
its private fields. A host FILE object has a different owner and cannot be
passed here because its pointer has the same machine width.

Mode parsing decides which access is allowed and how the underlying descriptor
is opened. A bounded accepted spelling is part of the contract. A plausible
filename or descriptor does not make every mode extension supported. Keep
opening result, owned descriptor and later stream allocation as separate events
when reading cleanup paths.

Operations then update explicit EOF, error and pushback state. clearerr clears
the indicators; ordinary successful I/O need not clear every earlier error. A
successful seek has its specified positioning and state effects. A future test
should ask about each operation rather than treating “stream worked once” as a
complete state reset.

Partial-object I/O makes these distinctions observable. Five bytes can enter a
destination while fread returns one complete four-byte object. A following
operation must interpret both object count and state under the API. Similarly, a
stream write can make physical progress before its public failure. Counting
conceptual formatted output cannot erase that partial transfer.

The bounded formatter uses a destination helper to keep logical count and actual
storage separate. Width, precision and padding are applied through its admitted
conversion paths. For integer length modifiers, the varargs type is promoted
before narrowing for output. Pointer and string cases have their own input
contracts; an invalid string pointer is not repaired by limiting destination
capacity.

Unsupported floating, positional and broader wide/locale formatting remains
explicit. Later GCC-built musl can support a larger set without changing the
seed formatter's source. This series changes producers at Stage C; a later
successful output is evidence about that later runtime and fixture.

For a later source-built stdio check, retain how the stream was created, its
descriptor ownership, exact operation inputs, returned counts, indicators and
actual bytes. A host-supported test can supply independent expectations, but
should not lend its FILE objects to the production runtime. Such a test belongs
to a separate graph with named host tools.

The chapter has derived its five-byte input and bounded ABCDE formatting states
on paper. It has not opened target files, induced descriptor failures, rendered
floating text through seed printf or validated every stdio behavior. Its
practical achievement is a state model that tells a later observer what to
retain.

Sources: [stream representation and lifetime](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L1-L509), [complete FILE and buffered surface](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/include/stdio.h#L1-L120), [buffering boundary](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/setbuf.c#L1-L8), [read/write progress and partial objects](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L510-L578), [line reads, pushback and positioning](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L629-L733), [format sinks and count checks](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L744-L820), [public formatting wrappers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L1067-L1153), [supported format grammar and conversions](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/runtime/gcc-seed/stdio.c#L872-L1066).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](12-variadic-cursors-and-argument-classes.md) remains
available for a specific missing contract; its entire implementation is not an
entrance examination. The first four problems below revisit concrete state
transitions. The later problems change a representation, ownership or evidence
boundary. They can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/13-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G13-01 — Count objects

Derive the fread result from replies 3,2,0 for size four/count two. Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G13-02 — Distinguish sticky flags

Does successful I/O automatically erase every prior error? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G13-03 — Account for pushback

Kernel position ten with one pushed byte: what does ftell report? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G13-04 — Separate count from storage

What follows from four-byte snprintf storage for ABCDE? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G13-05 — Use the promoted argument

Why does an hh integer conversion not fetch a one-byte variadic slot? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G13-06 — Reject unsupported formatting

May printf use %f merely because double arithmetic is implemented? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G13-07 — Report an observed write

The formatter counted five bytes, but its stream write failed after three. What
should a record preserve? Explain which supplied rule determines your answer.
Keep any prediction separate from a claim that the corresponding program or
build was run.

## What this mechanism makes available

You can now open the stream/format behavior used by a selected real program. Use
the state transitions above to justify that explanation, rather than treating a
source filename or a successful later milestone as a substitute for the
mechanism.

Continue to [G14: Bitfield layout and preserving
stores](14-bitfield-layout-and-preserving-stores.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
