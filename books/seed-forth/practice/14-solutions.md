# Physical I/O and exit: hints and solutions

Return to [Chapter 14](../chapters/14-physical-io-and-exit.md).
These are checked manual derivations for the pinned Linux/x86-64 seed, not
observed I/O. P and S denote the entry values of `rbp` and `rsp` for each
independent case; `[S]=K` is the valid Forth return destination. Offsets are
hexadecimal, cells occupy eight bytes, and logical stack tops are at the
right. `M=2^64`; a signed -9 is the cell pattern `M-9`.

Use the first hint to orient your attempt and the second for a specific
step. Compare your trace with the solution, identify the first mismatch,
then close the feedback before trying the changed case. These checks can
show where a derivation went wrong; they are not a measured learning study.

## S14-01 — Rebuild the seven-to-one bridge

**Hint 1.** The number is cached; all six arguments are stored. Write the
stored cells in increasing-address order before assigning registers.

**Hint 2.** `[P]=f`, `[P+40]=a`, and `[P+48]=99`. Advancing by 48 makes 99
the next-deeper value, not the cached result.

**Worked solution.** Entry `rdi=n`, and memory is
`f,e,d,c,b,a,99,77` at successive cells P through P+56. The instructions
establish:

| Instruction offset | Result of that instruction |
|---|---|
| `02D0` | `rax=n` |
| `02D3` | `r9=f` from P |
| `02D7` | `r8=e` from P+8 |
| `02DB` | `r10=d` from P+16 |
| `02DF` | `rdx=c` from P+24 |
| `02E3` | `rsi=b` from P+32 |
| `02E7` | `rdi=a` from P+40 |
| `02EB` | Ordinary return supplies `rax=result`; old `rcx` and `r11` are not preserved |
| `02ED` | `rbp=P+48`; six input slots cease to be live |
| `02F1` | `rdi=result`; 99 remains at `[rbp]`, 77 at `[rbp+8]` |
| `02F4` | Resume K with `rsp=S+8` and D=`[77,99,result]` |

No argument-memory bytes are erased. The cached number is replaced, so
seven inputs become one output through a net removal of six stack cells.

Loading a into `rdi` before saving n makes the later move put a into `rax`.
The intended syscall number has been lost, and the request can select the
wrong operation. An accidental equality `a=n` would hide the defect in
one example. It does not establish a correct bridge.

With the separate cleanup edit, `rbp=P+56`, so the next-deeper value becomes
77 and the final logical stack is `[77,result]`. The bits of 99 still exist
at P+48, but they are outside the live stack. This is loss of a logical
value, not memory erasure.

**Wrong path to diagnose.** Keeping 99 in `rdi` discards the returned result.
Moving P by seven cells confuses the number's register residence with a
memory-backed argument. Both errors can coexist with correct syscall
argument registers, so audit setup and cleanup separately.

**Changed case.** Use an older prefix `[11,22,33]`, arbitrary six arguments,
and an assumed raw result -9. What is the result stack and where is 33?

**Check.** The stack is `[11,22,33,M-9]`; final `rdi=M-9`, `rbp=P+48`, and
`[P+48]=33`. Cells at P+56 and P+64 hold 22 and 11. The error changes the
meaning of the result, not the cleanup size.

## S14-02 — Separate an output byte from an output result

**Hint 1.** Locate the only store before SYSCALL. Its width tells you which
bits of the input become payload.

**Hint 2.** `0x141 modulo 256 = 0x41`. The instruction after SYSCALL reads
P, not `rax`.

**Worked solution.** At entry `rdi=0x141`, `[P]=99`, `[P+8]=77`:

| Offset | Established effect |
|---|---|
| `0254` | `rax=0x412000` |
| `025B` | Byte at `0x412000` becomes `0x41`; later bytes are not written by this instruction |
| `025E` | `rax=1`, replacing the temporary scratch address |
| `0263` | `rdi=1`, replacing the consumed Forth input with descriptor 1 |
| `0268` | `rsi=0x412000` |
| `0272` | `rdx=1` |
| `0277` | Request `write(1,0x412000,1)`; assume an ordinary return for this exercise |
| `0279` | `rdi=99` from `[P]` |
| `027D` | `rbp=P+8`, leaving 77 at `[rbp]` |
| `0281` | `rsp=S+8`; resume K with D=`[77,99]` |

For returned `rax=1`, Linux reports one accepted byte. For zero, it reports
no progress. For signed -9, it reports an error. All three cases finish
with the same D, pointer, and restored older prefix. None puts that count
or error onto the Forth data stack. A later word cannot retrieve it through
an `emit` result that does not exist.

A reported one is not proof that a terminal showed a glyph: stdout may be
a file or pipe. Nor does it establish durable storage. The return path
itself is an assumption; a signal or nonreturning host condition would
invalidate the successful-return portion of the table.

The `40` REX prefix makes register code 111 denote `dil` for this byte
store. Without it, that code selects the legacy byte register `bh`, so the
store would not take the intended low byte of `rdi`. Bit eight of `0x141`
is outside `dil`; it is discarded, not serialized into a second byte.

**Wrong path to diagnose.** A final stack `[77,99,1]` silently gives `emit`
the result behavior of `syscall6`. The raw kernel register is not itself a
Forth stack item. A final `[77]` advances the data pointer one cell too far.

**Changed case.** Independently call `emit` with the one-value logical
stack `[0x100]`. Assume the write reports one. What payload and returned
representation result?

**Check.** Payload is the NUL byte `0x00`. `[P]` holds the saved dummy; it
is reloaded into `rdi`, and `rbp=P+8=B=0x411000`. D is empty. The reported
transfer does not imply visible text. A zero-valued dummy is not an older
user-supplied zero.

## S14-03 — Audit every `key` outcome

**Hint 1.** Trace pointer reservation and old-top saving before interpreting
the read. Neither branch later undoes that reservation.

**Hint 2.** TEST of a negative nonzero value clears ZF. JZ tests zero, not
whether the signed result is nonpositive.

**Worked solution.** The common setup is:

| Offset | Established effect |
|---|---|
| `028F` | `rbp=P-8` reserves one cell |
| `0293` | `[P-8]=99`; `[P]=77` remains unchanged |
| `0297` | `rax=0`, read number |
| `029C` | `rdi=0`, stdin descriptor |
| `02A1` | `rsi=0x412000` |
| `02A8` | `rdx=1`, requested bytes |
| `02AD` | Request `read(0,0x412000,1)` |

At `02AF`, TEST sets ZF according to the returned 64-bit `rax`. The four
independent outcomes then follow:

| Outcome | `02AF` | `02B2` | Remaining path | D after RET |
|---|---|---|---|---|
| `rax=1`, scratch now `FF` | ZF=0 | Fall through | `02B4` gives `rdi=255`; `02B8` jumps to `02BD` | `[77,99,255]` |
| `rax=0` | ZF=1 | Jump to `02BA` | XOR gives `rdi=0`; fall through to `02BD` | `[77,99,0]` |
| `rax=M-9`, scratch still `41` | ZF=0 | Fall through | `02B4` gives `rdi=65`; `02B8` jumps to `02BD` | `[77,99,65]` |
| `rax=1`, scratch now `00` | ZF=0 | Fall through | `02B4` gives `rdi=0`; `02B8` jumps to `02BD` | `[77,99,0]` |

In all four cases, final `rbp=P-8`, `[rbp]=99`, and `[rbp+8]=77`.
RET consumes K, leaving `rsp=S+8`. On the EOF path the old scratch is not
read, so its value is irrelevant to the returned zero.

The first branch computes `0x2B4+6=0x2BA`; the second computes
`0x2BA+3=0x2BD`. Add the mapping base for virtual targets `0x4002BA` and
`0x4002BD`. Counting from each instruction's start instead of its end gives
the wrong target.

EOF and a successfully transferred NUL yield identical Forth results.
The specified error yields the same result as a successful A byte would.
If scratch had instead been zero, that error could also look like EOF.
Neither an error nor the unchanged byte establishes a new transfer.

**Wrong path to diagnose.** Returning `M-9` gives `key` an error channel its
bytes do not implement. Returning zero for every negative result assumes
a branch condition that is absent. Advancing P after RET incorrectly
removes the slot that preserves 99.

**Changed case.** Begin with the empty logical stack: `rbp=B`, `rdi=0`
as dummy. Assume scratch contains `FF` and read returns a negative error
without changing it. Is there an underflow? What is the returned stack?

**Check.** `key` requires no data input, so it saves the dummy at B-8 and
returns D=`[255]`, with `rbp=B-8` and `rdi=255`. This is physically a valid
one-value representation containing misleading input data. A correct stack
shape does not establish a successful read.

## S14-04 — Preserve information in a changed interface

**Hint 1.** Decide what each result means before arranging its storage. A
NUL byte is valid data; status must carry the distinction from EOF.

**Hint 2.** Two pushed values mean two net eight-byte reservations. The
last result, status, is the new cache; the byte is directly below it.

**Worked solution.** Under the proposed contract, the pairs are:

| Outcome | `(byte,status)` |
|---|---|
| Successfully transferred NUL | `(0,1)` |
| Successfully transferred `FF` | `(255,1)` |
| EOF | `(0,0)` |
| Raw error -9 | `(0,M-9)`, interpreting the second cell as signed -9 |

From entry `[77,99]`, the desired result is `[77,99,byte,status]`.
Final `rbp=P-16`, `rdi=status`, `[P-16]=byte`, `[P-8]=99`, and `[P]=77`.
The earlier dummy and older storage retain their roles. A valid
implementation must preserve the old cache, distinguish positive, zero,
and negative raw results, and install both output cells. It should read
scratch as new data only when the count establishes a transferred byte.

A sign-aware branch can distinguish failure, but it does not reserve the
second output slot, store the byte below status, or arrange two results.
The real one-result `key` ends at P-8. Merely changing its condition leaves
a mismatch between advertised and implemented stack effects.

**Wrong path to diagnose.** Returning a negative error in a single byte
slot can still encode all 256 byte values differently from some errors,
but that is a different contract from the requested two-cell interface.
Evaluate a design against the stated result shape rather than moving the
goalposts to fit a convenient implementation.

**Changed case.** Change the hypothetical interface again to
`( -- status byte )`. Where do the two new values live, and which property
still distinguishes EOF from a real NUL?

**Check.** Final `rbp=P-16`, `rdi=byte`, `[P-16]=status`, `[P-8]=99`, and
`[P]=77`. The status remains zero for EOF and one for a transferred NUL;
only its stack position changed. A caller must inspect the agreed position.
This is a paper design, not a patched or tested replacement.

## S14-05 — Compare the two exits and the two ABIs

**Hint 1.** `bye` never loads a status from the Forth data stack. `die`
starts with that caller-supplied status and builds the seven-cell request.

**Hint 2.** SYSCALL itself assigns `rcx` and `r11`. The Forth CALL's return
destination was already stored through `rsp` before that happened.

**Worked solution.** For direct `bye` from `[99,7]`, the moves establish
`rax=60`, `rdi=0`. Old top 7 is overwritten, not used as status. Normal
raw exit ends this single-thread seed with status zero; no returned stack
exists.

For `die`, the wrapper appends five zero arguments and syscall number 60:

```text
[99,7,0,0,0,0,0,60]
     a b c d e f  n
```

The bridge puts 60 into `rax` and 7 into `rdi`; other argument registers
receive zeros. Normal exit uses status 7 and does not return. `syscall6`'s
pointer cleanup and RET are not reached. Although 99 survives in memory
up to the syscall, that is not a promise of a returned `[99,result]`.

The proposal's `rcx` argument is lost when SYSCALL installs its continuation
address there, and Linux expects argument four in `r10` anyway. Its saved
Forth destination in `r11` is lost when SYSCALL installs saved flags.
These are separate failures: correcting the fourth argument still would
not preserve the destination in `r11`.

In each actual returning body, K remains at `[S]` on the user return stack.
No body instruction moves `rsp` before RET. SYSCALL is a different control
transfer; its clobbers do not remove K from that stack. RET finally reads
K and changes `rsp` to S+8. This reasoning assumes an ordinary syscall
return and intact user storage, as the chapter states.

**Wrong path to diagnose.** Saying “`bye` returns an empty stack” confuses
no return with a returning word that leaves no values. Saying “`die`
returns status” confuses an input to a terminating request with an output.

**Changed case.** A proposed caller needs a value currently in `rcx`
after `emit`. Is the original value preserved just because `emit` contains
no explicit MOV to `rcx`? Where could a design preserve it?

**Check.** No: SYSCALL is itself a clobber. A compatible design must save
and restore the value in storage whose lifetime and non-overlap are
established, such as an owned stack slot, rather than assume an unused
explicit operand implies preservation. Any return-stack reservation must
also leave the real return destination at the location RET will use.
