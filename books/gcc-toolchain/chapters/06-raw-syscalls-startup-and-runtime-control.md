# Raw syscalls, startup, and runtime control

A C function receives seven values through one convention; Linux receives a
syscall number and six values through another. Who moves them, and who turns a
kernel error into errno?

Start with a missing-file result, then follow the same boundary into process
startup, frame queries, signals and nonlocal return. These helpers are separate
objects with separate contracts.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G04 supplies System V arguments and G05 supplies linking. A **raw result** is
the kernel’s returned word before libc policy; errno is runtime state consulted
by C callers. [S07](../../seed-forth/chapters/07-linux-io-contracts.md)
refreshes request/result reasoning. The runtime here is explicitly
single-threaded.

## Move the seventh C input to the sixth kernel register

The signature of __seed_syscall6 has seven long inputs: number, then a1 through
a6. System V carries the first six in registers and a6 at entry RSP+8. The leaf
moves number from RDI to RAX, a1 from RSI to RDI, a2 from RDX to RSI, a3 from
RCX to RDX, a4 from R8 to R10, a5 from R9 to R8 and loads a6 into R9 from the
stack.

Linux’s fourth argument uses R10, while the C fourth input used RCX. SYSCALL
clobbers RCX and R11. The leaf has no frame, returns the raw result in RAX and
does not set errno. Its object contains 26 instruction bytes and an exported
function symbol. Loading the Forth builder itself emits nothing until its
object-building word is called.

For a supplied raw result −2, a public wrapper that recognizes −4095 through −1
stores positive errno 2 and returns its public failure value. A raw bridge
cannot choose that public value universally: mmap needs MAP_FAILED, while
descriptor functions commonly need −1.

Sources: [raw register
bridge](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L1-L33),
[public error
translation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/mapping.c#L6-L38).

## Give errno its own storage

A separate object reserves four aligned BSS bytes for local __seed_errno.
__errno_location uses a RIP-relative address and returns its pointer. Its
relocation’s addend −4 has the same field-end reason as G01’s call, although the
instruction computes a data address.

This isolation means the raw syscall object has no libc state dependency. errno
is an int object, not an eight-byte copy of the raw result. Successful wrappers
generally preserve it; a success value alone does not require clearing a
previous error. Single-threaded storage is not thread-local storage and must not
be presented as a multithreaded runtime guarantee.

Sources: [errno object and address
relocation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L35-L54).

## Make the first call before there is a C caller

The runtime-aware start.o exports _start and contains two unresolved calls, to
__seed_init_runtime and main. It reads argc and the argv address from the
initial Linux stack before alignment. It aligns RSP and pushes those two inputs
so initialization cannot destroy them, calls the initializer, restores them,
sets the vector count to zero and calls main.

The initializer’s ordinary C source sets the program basename and environment
pointer. Its archive member is startup.o, distinct from the Forth-built start.o.
Default linking supplies start.o eagerly and selects startup.o when its
initializer is demanded. main’s return passes to RDI and syscall 60; this path
does not call the C exit wrapper.

The smaller raw startup object calls main directly and is 32 bytes, while the
runtime-aware one is 41. Choosing the smaller builder changes the startup
contract. Matching the exported name _start cannot establish that both perform
initialization.

Sources: [raw
startup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L56-L81),
[runtime-aware
startup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L103-L133),
[C
initializer](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/startup.c#L1-L25).

## Ask for a frame, not an arbitrary backtrace

__seed_parent_frame is a five-byte leaf that reads [RBP]. It relies on the
calling C function and its parent maintaining the seed System V RBP frame chain.
Because temporary argument pushes change RSP without changing RBP, the saved
parent frame supplies a stable depth metric for the documented C_alloca adapter.

An optimizer may omit frames in arbitrary host code. This helper is therefore a
private ABI interface, not a portable frame-query service. The adapter in
libiberty is applied in a private verified source view under __SEED_FORTH__; it
does not replace allocation or grant unknown frame layouts this contract.

A reported early C_alloca failure from changing temporary stack depth remains an
attributed historical observation. The new paper example has no actual
allocation or callback execution. Preserve both the target-specific repair and
that evidence boundary.

Sources: [parent-frame
leaf](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L83-L93),
[C_alloca adapter and recorded
failure](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L320-L350).

## Return through the owner of the saved state

Signal return uses syscall 15, rt_sigreturn, with the kernel-owned signal frame
at the current RSP. The leaf cannot add a normal C frame first. If the syscall
unexpectedly returns, UD2 traps. Signal-mask and handler installation policy
live in the C signal runtime; this leaf supplies only the return boundary.

setjmp saves RBX, RBP, R12–R15, the caller’s post-return RSP and the return
instruction address into eight words. Its ordinary return is zero. longjmp
restores those words and jumps to the saved instruction, supplying the low C-int
result: zero becomes one, and nonzero values are normalized from ESI rather than
assuming meaningful upper bits.

This is a nonlocal return into a still-live invocation, not a replay of every
instruction since setjmp. The helper saves no signal mask or floating
environment. A frame that has already returned is not a valid destination;
changing register bytes does not recreate its lifetime.

Sources: [signal-return
leaf](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L95-L101),
[setjmp and longjmp
state](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L135-L181).

## Keep termination policies visible

The C exit function repeatedly requests syscall 60 with the low status byte and
cannot turn a denied request into an ordinary return. abort first tries SIGABRT
with the installed disposition, then resets it and retries, falling back to
exit(134) if delivery fails. These are C runtime policies above the raw bridge.

The runtime documents unbuffered stream writes and no atexit callbacks for this
exit contract. Do not import a full hosted exit-handler sequence into G01’s
direct startup syscall. Signal termination, ordinary exit status and printed
bytes remain different outputs.

The support objects provide syscall, errno, startup, frame, signal-return and
nonlocal-return services. Their production by Forth is independent from their
later target execution. Future evidence must identify the selected object and
the actual live-stack/signal assumptions, rather than count matching exported
names.

Sources: [exit and abort
policy](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/process.c#L5-L42).

## Translate an interface rather than copying registers

Supply a C call to the raw syscall helper with a syscall number followed by six
arguments. C places its first six integer-class inputs in RDI, RSI, RDX, RCX, R8
and R9; the seventh C input is on the stack. The kernel expects the number in
RAX and the six arguments in RDI, RSI, RDX, R10, R8 and R9. Even with all inputs
integer-valued, these are different interfaces.

Write the input meanings beside their initial destinations before moving them.
The C value in RDI is the number, not kernel argument one. The value in RSI must
become argument one. The kernel's fourth argument must reach R10 rather than
RCX. The final C input must be read from its stack position and reach the
kernel's sixth argument register. Thinking “both use six registers” would miss
the extra number and the special fourth register.

SYSCALL also has clobbers. A wrapper cannot promise the caller that every
incoming temporary register survives merely because the kernel's result is a
single number. The helper's generated body implements the bridge; a C
declaration lets the selected call planner supply its inputs. Those two sides
are jointly necessary, just as the independent caller and callee were in G04.

Now supply a raw return of −2. The syscall convention's error range makes that
an error result. A libc-style wrapper records positive errno 2 and returns −1.
These are two changes at two destinations: a mutable errno object and the
function result. A successful return does not establish that errno was cleared,
so a program must use the operation's result to decide whether errno is
relevant.

Sources: [raw register
bridge](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L1-L33),
[public error
translation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/mapping.c#L6-L38),
[errno object and address
relocation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L35-L54).

## Read the first stack before main's frame exists

At process entry, the kernel has prepared the initial stack of argc, argument
pointers and environment pointers. It has not called main using the C call
convention. The source-built startup derives the C inputs from that stack,
aligns for the call and then invokes main. Its environment handling belongs to
this startup sequence, before an ordinary main frame exists.

When main returns, startup receives the scalar result and requests process exit.
Returning seven is therefore observable as process status in the planned
fixture. It remains distinct from writing the character `7`. The runtime's exit
path and its output wrapper have different operations and consumers. Draw them
as separate arrows even if a hosted program eventually uses both.

Compare this entry with the raw executable's shorter startup. Both reach a
main-like entry and exit, but their supported inputs and setup differ. Counting
their bytes does not make one a general replacement for the other. A runtime
providing argc, argv, environment and errno has obligations that the no-libc
example intentionally avoids.

Sources: [raw
startup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L56-L81),
[runtime-aware
startup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L103-L133),
[C
initializer](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/startup.c#L1-L25).

## Resume a continuation with an explicit contract

A saved nonlocal-return buffer stores the selected callee-saved register state,
stack position and continuation needed by its helper. It is not a snapshot of
every object in the process. Heap contents, global variables and arbitrary
volatile-register values are not restored merely because execution resumes at
the earlier setjmp boundary.

On the first return, setjmp yields zero. A later longjmp supplies the resumed
result, with zero changed to one. That rule lets the receiving code distinguish
initial execution from resumption even when the caller requested zero. It does
not repair an expired stack frame: the saved continuation still requires a valid
lifetime.

The parent-frame helper has its own fixed-RBP contract. It does not imply
unrestricted stack walking through every optimized or foreign frame. Signal
return likewise serves a specified kernel boundary, not an ordinary C RET. Keep
each helper's precondition beside its small machine body. A later runtime check
should exercise each contract separately; successful startup alone would not
validate nonlocal control or signal restoration.

Sources: [parent-frame
leaf](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L83-L93),
[C_alloca adapter and recorded
failure](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L320-L350),
[signal-return
leaf](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L95-L101),
[setjmp and longjmp
state](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L135-L181).

## Keep a runtime object census beside the first call

The runtime support builders each create an object with a small, named
responsibility. The syscall leaf translates registers and returns a raw value.
The errno object owns four bytes and an accessor. The startup object establishes
entry. The parent-frame leaf reads the admitted frame chain. Signal return and
nonlocal return each restore state owned under a different contract.

| Support object role | State it relies on | Completion event |
|---|---|---|
| Raw syscall bridge | Prepared C inputs and kernel interface | Raw kernel result returned |
| errno accessor | Its own aligned BSS storage | Pointer to that int supplied |
| Runtime-aware entry | Initial stack and initializer provider | main result passed to exit syscall |
| Parent-frame leaf | Fixed RBP frame chain | Saved parent frame read |
| Signal return | Kernel-owned signal frame | Kernel resumes interrupted state |
| Nonlocal return | Still-live saved continuation | setjmp site resumes with normalized result |

The table also shows why one happy startup run would be an incomplete runtime
test. It exercises entry and perhaps the syscall exit boundary. It may never
query a parent frame, restore a signal frame or resume a saved continuation. A
complete exported-name list is similarly insufficient: each name needs its
admitted state before execution can demonstrate its behavior.

Source loading is earlier than object production. Loading 122 creates builder
definitions and quoted byte arrays; calling its object-building word asks 081 to
record the selected bytes and symbols. Writing that object is a later event
again. Keep these events separate when explaining what the Forth code does at
load time.

The source comments explicitly specify that the raw syscall leaf does not set
errno and that the nonlocal buffer does not save masks or floating state. These
negative contracts are useful because they prevent a familiar function name from
importing a larger hosted runtime. A wrapper above the raw leaf must choose its
own public failure result; a signal-aware jump would require a different
state-saving contract.

A future observation should identify the exact support object selected and the
caller that establishes its preconditions. Passing a host-created buffer or
walking a foreign frame cannot be justified solely by equal pointer width. This
series concerns the selected single-threaded seed runtime and its documented
ABI. Its numerical examples and saved-state descriptions were inspected and
derived, not run as new runtime tests.

Sources: [raw register
bridge](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L1-L33),
[public error
translation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/mapping.c#L6-L38),
[errno object and address
relocation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L35-L54),
[parent-frame
leaf](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L83-L93),
[C_alloca adapter and recorded
failure](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L320-L350),
[signal-return
leaf](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L95-L101),
[setjmp and longjmp
state](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L135-L181).

## Let one initialized global connect startup and archives

The C initializer provides the environment pointer and program basename before
main. The Forth-built runtime-aware entry supplies its unresolved call. That
call causes the archive member containing the initializer to be selected. The
selected member can introduce another runtime obligation, which G16's rescan
later follows. An initial stack layout has therefore become both a
running-program input and a link-time dependency story.

Supply argc equal to two. The argv sequence contains two argument pointers
followed by its null terminator. The environment pointer is derived beyond that
argument-pointer sequence. No assumption about the lengths of the argument
strings is needed for this pointer-array step. Those strings live elsewhere;
their byte lengths are not the number of argv pointer slots.

Before calling initialization, entry has prepared argc and argv in the C input
registers. The initializer may use those volatile registers. Two saved
eight-byte words preserve the values while retaining the chosen pre-call
alignment. Entry restores the pair before main. The startup therefore has a
local preservation problem resembling G04's nested-call problem, even though it
has no ordinary source-level C caller.

A program can resolve main without selecting this initializer if a different raw
startup was chosen. It can also select the correct initializer while main itself
does not use environment state. A successful integer-only main result would
leave that initialization largely untested. Choosing a future fixture that reads
its prepared argument/environment state would make the startup distinction
observable.

The runtime also retains a separately owned errno object. Neither successful
initialization nor successful main exit proves that errno conversion was
exercised. Likewise, the parent-frame leaf and nonlocal-return helpers require
different callers. Separate object construction makes these responsibilities
easy to list, but their exported names do not supply execution evidence.

The chapter's startup trace is inspected source and supplied state. It gives a
reader enough to identify the real first caller and its inputs while leaving
actual process capture and failure checks open.

Sources: [raw startup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L56-L81), [runtime-aware startup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L103-L133), [C initializer](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/startup.c#L1-L25), [parent-frame leaf](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth#L83-L93), [C_alloca adapter and recorded failure](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L320-L350).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](05-linking-independently-built-objects.md) remains available
for a specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/06-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G6-01 — Map the bridge

Where does C input a6 arrive, and where must Linux receive it? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G6-02 — Translate an error

A wrapper receives raw −2. What does the raw leaf do to errno? What may the
wrapper do? Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G6-03 — Keep startups separate

Name the producer and role of start.o and startup.o. Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G6-04 — Preserve arguments

Why push argc and argv after aligning in the runtime-aware startup? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G6-05 — Query a stable frame

Why can a parent-frame metric survive temporary argument pushes? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G6-06 — Normalize nonlocal return

What does longjmp(buffer,0) make the saved setjmp return? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G6-07 — State what is saved

Does the eight-word buffer restore signal masks or revive returned frames?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

## What this mechanism makes available

You can now identify actual startup and linux exit inputs for the linked
fixture. Use the state transitions above to justify that explanation, rather
than treating a source filename or a successful later milestone as a substitute
for the mechanism.

Continue to [G07: Source-built allocation and byte
operations](07-source-built-allocation-and-byte-operations.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
