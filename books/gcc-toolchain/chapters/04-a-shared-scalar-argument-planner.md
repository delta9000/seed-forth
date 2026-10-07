# A shared scalar argument planner

Seven scalar arguments need six argument registers and somewhere else to put the
seventh. How can the compiler construct that outgoing area without losing a
partially evaluated outer expression?

We will assign a small call on paper, then follow the planner's ownership
through nested calls, function entry and return. G01's no-argument call is the
smallest case of the same alignment obligation.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G03 supplies a checked signature;
[C18](../../c-compiler/chapters/18-functions-and-call-frame-accounting.md)
supplies frame and return concepts. A register is temporary CPU storage. RSP
points at the machine stack, which grows toward smaller addresses when pushed;
RBP is the function's fixed frame reference. Here INTEGER means the ABI class
used for admitted integers and pointers, rather than a claim that every C type
is an int.

## Assign seven inputs without changing their widths

Give a prototype seven long parameters and supply values 10, 20, 30, 40, 50, 60
and 70. The first six INTEGER arguments go to RDI, RSI, RDX, RCX, R8 and R9. The
seventh goes to the outgoing stack at offset zero from pre-call RSP. CALL then
adds its return-address cell, so that argument appears at callee-entry RSP+8.

After PUSH RBP and establishment of the frame, it appears at RBP+16. The two
coordinates describe the same stored argument at different moments. They must
not be added twice. An int argument uses a four-byte C type even when staging
uses an eight-byte slot; conversion to the declared parameter type happens
before transport.

A signature bounds the fixed arguments. Too many arguments to a nonvariadic
prototype and too few required arguments reject. An unspecified or variadic tail
uses default promotions instead of inventing fixed parameter types. Source
evaluation order here is an implementation choice, not a promise that all C
compilers evaluate arguments identically.

Sources: [scalar staging and
conversion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L995-L1027),
[register and outgoing-stack
placement](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1038-L1120).

## Keep a value before asking another function for one

Consider an outer call whose first argument has been evaluated, while its next
argument contains a nested call. The first value remains live. Merely aligning
RSP downward can overwrite that value or a saved switch register if the outgoing
block occupies the same storage.

The scalar provider tracks expression/argument pushes separately from switch
saves. Its call record stores the saved-RSP frame slot, surviving cell count and
staged cell count. Before changing the outgoing stack, it copies the surviving
span into frame slots. After return it restores RSP and the surviving values,
then discards only this call's staged arguments.

The final loaded direct profile installs `131` as the ordinary evaluated-call
provider. Its scalar cases use explicit argument-location records and frame
snapshots, while `121` remains the scalar/unevaluated fallback and supplies
shared save/restore helpers. Reading an earlier definition alone would miss the
selected provider. G15 opens the aggregate extensions; nothing in this scalar
story requires completing that chapter first.

Sources: [push tracking and live-span
save/restore](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1028-L1091),
[selected call preparation and
restoration](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L221-L327).

## Align at the moment the consumer requires

Supply saved RSP 0x8008 and one eight-byte outgoing stack argument. The planner
subtracts the outgoing size plus 15, then masks downward to a multiple of 16. In
this model, 0x8008−23 is 0x7FF1; masking yields 0x7FF0. It stores the seventh
argument at 0x7FF0. CALL stores the return address at 0x7FE8.

Callee entry is eight bytes below a multiple of sixteen, as required. Later
restoring the saved 0x8008 is correct for this supplied live-state model; it
does not mean that value was suitable as the pre-call pointer. Alignment and
balance concern different moments.

No-argument calls still reserve the slack needed to align. A fixed frame rounded
to sixteen cannot on its own account for all temporary pushes in a nested
expression. The call boundary must be derived from the current machine state and
restored ownership, not from a memorized function frame size.

Sources: [fresh aligned outgoing
block](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1092-L1128),
[selected aligned outgoing
block](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L221-L260).

## Move stack copies before register loads

Arguments are first materialized into owned temporary storage. Only then does
the planner place stack arguments and load the argument registers. This
sequencing is required because copying bytes may itself use GP registers.
Loading RDI and then running a copy that uses RDI as its destination would
destroy the intended first argument.

For a scalar indirect call, the target address also survives argument
evaluation. It is staged separately, then loaded into R10 when the call is
emitted. AL reports the number of vector argument registers used. In the
integer-only case that count is zero; writing it must not destroy the indirect
target. This is why RAX cannot simultaneously be the lasting target register.

A pending direct call reserves its relative field and records a symbol-owned
obligation. The ABI planner does not decide the final link address. Its success
establishes argument transport, while G02/G05 finish the symbol and relocation
contract.

Sources: [direct and indirect call
emission](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1129-L1171),
[selected target
preservation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L274-L327).

## Receive values in the matching entry plan

The callee constructs its parameter locations from the same signature and
classifier. Register parameters are spilled into owned frame slots before stack
copying can clobber their registers. Stack parameters are copied from offsets
based on RBP+16. Source names are installed as local symbols referring to those
slots; the caller's temporary storage does not become the callee's local object.

Function generation preserves the used callee-saved registers, patches a
fixed-frame reservation after local demand is known and restores function/scope
bookkeeping on completion. A frame slot is compiler allocation metadata; its
byte address is relative to the eventual RBP. Fixed slots, outgoing stack space
and the return-address cell must be counted separately.

The scalar result crosses the boundary in RAX for integers/pointers. Generated
expression code then moves it to RDI and applies its declared type conversion.
This carrier switch does not widen an int object. A returned −1 int must be
treated as a signed 32-bit result before wider internal use.

Sources: [parameters, function frame and target
activation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1172-L1357),
[selected parameter plan and
spills](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L329-L376).

## Test the shared contract without pretending to execute

Our paper call now has an argument map, a stack coordinate map and an ownership
map. Together they explain why the callee can retrieve seventy and why the
caller can recover an older value after the nested call. No actual call
instruction has been executed for this chapter.

The argument-capacity and signature guards are intentionally bounded. Floating
scalars consume another register bank in G10/G12. Aggregate arguments can occupy
multiple registers or need complete stack copies in G15. Do not extrapolate the
seventh INTEGER argument's position to an arbitrary seventh C argument.

For a future execution record, retain both caller and callee compilation
profiles, the selected provider stream, emitted call sites, observed stack state
where available and result/status. A scalar arithmetic result alone cannot
expose every preservation or alignment error. A changed nested argument and a
live outer value provide more discriminating evidence.

Sources: [explicit argument records and
classification](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L96-L157).

## Give seven inputs distinct destinations

Supply a call with seven long arguments whose values are 10, 20, 30, 40, 50, 60
and 70. Keep these values in source order in a staging list. Assign the first
six integer-class positions to RDI, RSI, RDX, RCX, R8 and R9. Assign the seventh
to the overflow area. This assignment is a classification of destinations; it is
not permission to discard expression evaluation state as soon as a register
number becomes known.

At the callee's entry, CALL has placed an eight-byte return address at the
current stack pointer. The first overflow argument is beyond that return
address. It must not overwrite the return address and cannot be read from the
caller's pre-CALL stack coordinate without adjusting the viewpoint. Draw the
caller's stack before CALL and the callee's stack after CALL as two views of the
same memory. Mark which address belongs to each view.

Replace the third supplied argument with another function call. Its evaluation
can use the same volatile registers that the outer call will eventually need. If
the outer call's first two values lived only in their final registers throughout
that inner evaluation, those values could be lost. The planner's staged values
and protection of live expression state make the two calls composable. Argument
destination order does not, by itself, describe every evaluation step.

The callee then spills the incoming parameters into its own frame according to
their types. An int parameter has a narrower stored representation than a long
parameter. A register carrying a value is not automatically an eight-byte local
object. Read the spill operation together with the parameter metadata rather
than inferring storage width from the name RDI.

Sources: [scalar staging and
conversion](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L995-L1027),
[register and outgoing-stack
placement](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1038-L1120),
[parameters, function frame and target
activation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1172-L1357),
[selected parameter plan and
spills](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L329-L376).

## Derive the alignment, then restore ownership

Use the supplied stack pointer 0x8008 and a temporary demand of twenty-three
bytes. Subtracting gives 0x7FF1. Rounding downward to a multiple of sixteen
gives 0x7FF0, so the padding is one extra byte. The aligned pointer is the
pre-CALL state; CALL itself pushes the eight-byte return address and produces
the callee-entry pointer 0x7FE8.

These three addresses answer different questions. 0x8008 identifies the saved
caller state to restore. 0x7FF0 identifies the boundary at the instant the call
is issued. 0x7FE8 identifies the callee's entry stack. Replacing all three with
“the stack is aligned” hides the transition that determines where the overflow
argument and return address are found.

After the callee returns, restore the saved caller pointer rather than adding a
guessed constant derived from this one example. A nested expression, different
overflow extent or changed live-value count can change the subtraction and
padding. The saved pointer provides the completion contract across those
changes. Restoration is an ownership event: the outer expression regains the
temporary region that the call used.

Change the starting pointer to 0x8010 while retaining twenty-three demanded
bytes. Subtraction yields 0x7FF9; rounding yields 0x7FF0 again, now with nine
bytes of padding. The final aligned address happens to match the earlier
example. The restored caller state must still differ. Equal final alignment does
not mean the two calls owned identical starting stacks.

Sources: [fresh aligned outgoing
block](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1092-L1128),
[selected aligned outgoing
block](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L221-L260),
[direct and indirect call
emission](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1129-L1171),
[selected target
preservation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L274-L327).

## Keep the target alive until CALL consumes it

An indirect call has one more value than a direct named call: the address of the
function to invoke. That address can initially be held in a register that
argument assignment or expression evaluation will overwrite. The selected call
path protects it and uses R10 at the final indirect call boundary. Treat it as a
value with a lifetime, not merely syntax attached to the parentheses.

There is also a small piece of call metadata in AL: the selected
floating-register count. Zero integer-only floating arguments gives zero; later
floating lessons change that count. Preparing AL can change the low byte of RAX,
so it belongs in the same interference analysis as target preservation. A plan
that remembers every argument but destroys its indirect target is still an
invalid call plan.

G15 will extend classification to records and hidden returns. Do not project
those rules backward onto this scalar lesson. The integer-only trace has one
slot per supplied long, a specified alignment transition and a scalar result.
Its purpose is to let a reader explain where each value survives before the
broader argument classes arrive. A later disassembly can check the predicted
transfers, but no new scalar fixture has been executed here.

Sources: [direct and indirect call
emission](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1129-L1171),
[selected target
preservation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L274-L327),
[parameters, function frame and target
activation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1172-L1357),
[selected parameter plan and
spills](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L329-L376).

## Locate a call error before looking at its result

Supply the seven-long call again, with values ten through seventy in steps of
ten. If the seventh argument appears in R9 alongside the sixth, the
classification is wrong before CALL. If it appears at outgoing offset zero but
the callee reads entry RSP instead of RSP+8, classification can be correct while
the callee's coordinate is wrong. If both are correct but an inner call replaced
an earlier staged value, the lifetime contract failed before either transfer.

Give each failure a first boundary:

| Supplied failure | State to inspect first | Repair sought |
|---|---|---|
| Seventh value competes for R9 | Argument locations | Overflow after six general positions |
| Callee reads return address as argument | Entry-stack view | Offset beyond CALL's pushed word |
| Early value changes during nested call | Protected live span | Preserve outer evaluation state |
| Caller resumes with rounded RSP | Saved caller state | Restore its original pointer |
| Indirect target changes with AL | Final target carrier | Keep address independent of count byte |

None of these diagnoses needs the called function to perform a complex
calculation. A callee that returns one selected input would be enough for a
future fixture to expose some of them. But one selected input cannot expose
every transfer, so retaining actual placement evidence is useful when designing
the observation.

There are three representations of a returned int worth retaining. Its C object
storage uses four bytes. Its integer ABI result crosses through the integer
return register. The selected expression machinery then adapts it into its
internal carrier and signed-int representation. A wrong internal result can
therefore occur after an otherwise correct machine return. Do not repair the
caller's storage width by changing the callee's register convention.

The final direct profile installs the evaluated-call provider from 131 after the
earlier 121 helpers. Read that hook installation before using a nearby earlier
definition as the whole account. The earlier scalar code still explains shared
conventions, but the selected planner owns the full explicit-location and
snapshot path. Load order here decides executable behavior; source order in a
teaching chapter decides which contract a learner can already explain.

For a later inspection, preserve both declaration metadata and machine
transfers. A register-only listing cannot verify that the declared result was
normalized correctly; a final numerical result cannot show which temporary
protection made nested evaluation safe. The chapter's placement and alignment
predictions remain supplied states rather than new execution evidence.

Sources: [direct and indirect call
emission](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1129-L1171),
[selected target
preservation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L274-L327),
[parameters, function frame and target
activation](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/121-cc-sysv.fth#L1172-L1357),
[selected parameter plan and
spills](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/131-cc-aggregate-abi.fth#L329-L376).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](03-signatures-declarators-and-ranked-arrays.md) remains
available for a specific missing contract; its entire implementation is not an
entrance examination. The first four problems below revisit concrete state
transitions. The later problems change a representation, ownership or evidence
boundary. They can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/04-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G4-01 — Assign registers

Place the seven supplied long arguments. Where is argument seven before CALL?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G4-02 — Change coordinates

Locate argument seven at callee entry and after the RBP prologue. Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G4-03 — Derive alignment

Reconstruct the supplied 0x8008 one-stack-argument model. Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G4-04 — Protect an outer argument

Why must the planner preserve a live first argument during a nested
second-argument call? Explain which supplied rule determines your answer. Keep
any prediction separate from a claim that the corresponding program or build was
run.

### G4-05 — Stage an indirect target

Why does the target survive in R10 rather than depending on AL? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G4-06 — Receive the result

Explain int storage, integer ABI return and internal expression carrier. Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

### G4-07 — Identify the selected provider

Why is 121’s scalar call definition insufficient as the full direct-profile
account? Explain which supplied rule determines your answer. Keep any prediction
separate from a claim that the corresponding program or build was run.

## What this mechanism makes available

You can now teach scalar calls/results and alignment for the two-object story.
Use the state transitions above to justify that explanation, rather than
treating a source filename or a successful later milestone as a substitute for
the mechanism.

Continue to [G05: Linking independently built
objects](05-linking-independently-built-objects.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
