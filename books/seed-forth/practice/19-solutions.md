# Audit synthesis and capstone: hints and solutions

Return to [Chapter 19](../chapters/19-audit-synthesis-and-capstone.md).
These answers are independently recalculated static derivations for the
pinned Linux/x86-64 seed, not observed runs. Addresses and byte strings
are hexadecimal; ordinary input values are decimal. Cells are eight
bytes, storage is little-endian, and logical stack tops appear at the
right. The chapter's capacity, input, and calling preconditions apply.

Use the first hint to find a starting point, the second for a concrete
step. After feedback, close the answer and attempt the changed case.
Recording whether you used help distinguishes supported performance from
an independent result; neither alone establishes later retention.

## S19-01 — Derive the whole fresh entry

**Hint 1.** Separate fixed header fields, variable-length name, and body.
The code address is not the address stored in LATEST.

**Hint 2.** Thirteen header bytes put code at `0x40100D`. Add five for
the first CALL's origin, then eight for the next instruction's start.

**Checked solution.** Header length is `8+1+1+3=13`; body length is
`5+8+5+1=19`. Total length is 32 bytes. The link is the old LATEST,
`0x400617`; flags zero make `inc` ordinary, length three accounts for
`69 6E 63`. No padding or terminator belongs between name and code.

The two distances are calculated from the instruction ends:

```text
lit: 0x4005A0 - (0x40100D+5) = -0xA72 = -2674
 + : 0x4001B7 - (0x40101A+5) = -0xE68 = -3688
```

As four-byte little-endian two's-complement patterns these are
`8E F5 FF FF` and `98 F1 FF FF`. The complete entry is:

```text
17 06 40 00 00 00 00 00 00 03 69 6E 63 E8 8E F5
FF FF 01 00 00 00 00 00 00 00 E8 98 F1 FF FF C3
```

The inverse additions recover `0x4005A0` and `0x4001B7`. HERE advances
to `0x401020`; LATEST becomes `0x401000`; STATE returns to zero.
Colon removes its name-reading temporaries. Compile-mode `[lit]` consumes
the parsed value through its emission path. Compiling `+` consumes the
lookup's xt rather than executing addition. Semicolon emits RET without
requiring a data operand. Thus the compiling stack remains empty at each
completed source-word boundary.

**Common error.** Writing `0x40100D` into LATEST makes it point at code
rather than the new header. Lookup would then interpret instruction bytes
as link/flags/length fields. A plausible code address does not satisfy a
header-address contract.

**Changed case.** On a fresh reset, derive `: up [lit] 2 + ;`. There are
two name bytes, so xt=`0x40100C`, literal cell=`0x401011`, addition call=
`0x401019`, RET=`0x40101E`, and final HERE=`0x40101F`. The distances are
-2673 and -3687. Check your result against this 31-byte string:

```text
17 06 40 00 00 00 00 00 00 02 75 70 E8 8F F5 FF FF
02 00 00 00 00 00 00 00 E8 99 F1 FF FF C3
```

LATEST is still `0x401000`, STATE zero; `[99,5]` would become `[99,7]`.
Changing a name's length moves both CALL origins even though their targets
remain fixed.

## S19-02 — Shift a layout and extend the chain

**Hint 1.** Distinguish moving HERE in an independent model from making
another definition in an existing chain. Only the second necessarily
changes which header was previously newest.

**Hint 2.** With shifted HERE, every generated address moves by `0x80`;
primitive targets do not. Each required signed distance therefore decreases
by `0x80`.

**Checked solution: shifted reset.** The initial link remains `0x400617`.
The new header starts at `0x401080`, xt at `0x40108D`, literal cell at
`0x401092`, addition call at `0x40109A`, and RET at `0x40109F`.

```text
lit: 0x4005A0 - 0x401092 = -0xAF2 = -2802
 + : 0x4001B7 - 0x40109F = -0xEE8 = -3816
```

The complete 32-byte entry is:

```text
17 06 40 00 00 00 00 00 00 03 69 6E 63 E8 0E F5
FF FF 01 00 00 00 00 00 00 00 E8 18 F1 FF FF C3
```

Only displacement bytes differ from the unshifted entry. Its link does
not point at its own new address, and there are no absolute self-addresses
in this body. Final HERE=`0x4010A0`, LATEST=`0x401080`, STATE=0.
The shifted initial HERE is a stipulated paper variation, not what the
seed's startup actually stores.

**Checked solution: reader-built `bump`.** Return to the original completed
`inc`, where HERE=`0x401020` and LATEST=`0x401000`. Define:

```forth
: bump [lit] 7 + ;
```

Its four-byte name gives a fourteen-byte header. The new entry starts at
`0x401020`, its xt is `0x40102E`, its literal cell starts at `0x401033`,
its addition call starts at `0x40103B`, and RET is at `0x401040`.

```text
lit: 0x4005A0 - 0x401033 = -0xA93 = -2707
 + : 0x4001B7 - 0x401040 = -0xE89 = -3721
```

The full 33-byte entry is:

```text
00 10 40 00 00 00 00 00 00 04 62 75 6D 70
E8 6D F5 FF FF 07 00 00 00 00 00 00 00 E8 77 F1 FF FF C3
```

Final HERE=`0x401041`, LATEST=`0x401020`, STATE=0. The new link leads
to `inc` at `0x401000`; `inc` still links to `0x400617`. Later execution
on `[99,5]` gives `[99,5,7]`, then `[99,12]`, without changing those
links. The older prefix is not part of the addition's operands.

**Common error.** Reusing the shifted-reset link for `bump` skips `inc`
in the search chain. Reusing `inc`'s three-byte header length puts `bump`'s
body one byte too early. Check chain identity and name size separately.

**Changed case.** Shift the independent `inc` reset by another `0x100`,
so initial HERE=`0x401180`, with the same initial LATEST. The xt becomes
`0x40118D`; CALL bytes become `E8 0E F4 FF FF` and `E8 18 F0 FF FF`.
Their origins are `0x401192` and `0x40119F`; the distances are -3058 and
-4072. Final HERE=`0x4011A0`. Explain the extra `-0x100` in each distance
before checking the bytes.

## S19-03 — Track width and overflow

**Hint 1.** The addition instruction does not allocate an extra bit for
a carry. A signed interpretation changes how a pattern is read, not how
many bits are stored.

**Hint 2.** `256 = 0x100`, so its low two bytes are `00 01`. The literal
slot is always eight bytes. The parser's success flag checks syntax,
not whether the mathematical integer fits.

**Checked solution.** The unsigned maximum is `2^64-1`, represented by
eight FF bytes. Adding one leaves the low 64 bits zero. Thus
`[99,18446744073709551615]` becomes `[99,0]`.

Signed maximum is `2^63-1`. Incrementing produces pattern
`0x8000000000000000`, unsigned `9223372036854775808`, or signed
`-9223372036854775808`. These are two interpretations of one result.
The word does not test processor overflow flags or signal a signed-range
error.

Changing the definition's literal to 256 replaces the inline bytes at
`[0x401012,0x40101A)` with `00 01 00 00 00 00 00 00`. Header length,
CALL locations, displacements, RET, and final HERE remain unchanged. The
changed word adds 256 modulo `2^64` rather than one.

The token `18446744073709551616` equals `2^64`. Each byte is a valid
decimal digit, so the parser reports success with value zero after
64-bit wraparound. In interpret mode `[lit]` leaves zero. In compile mode
it emits eight zero bytes after CALL `lit`. Neither route rejects the
token for overflow. Compare an empty token or `-1`, which fails the
nonempty unsigned-digit syntax contract.

A cell's 64-bit value, an eight-byte inline cell, and a four-byte signed
CALL displacement are different roles. Making a literal small does not
shrink its slot; storing a target distance's low 32 bits does not prove
that the requested target is reachable. For example, a desired positive
distance `0x80000000` would decode as a negative distance instead.

**Common error.** Interpreting a zero result as failed parsing loses the
separate success flag. Claiming that signed overflow traps adds a check
that this addition primitive does not perform.

**Changed case.** Use `: inc [lit] 18446744073709551615 + ;` in the same
fresh layout. The inline cell becomes eight FF bytes; all addresses and
CALL bytes remain the same. Input `[99,0]` produces `[99,18446744073709551615]`;
input `[99,1]` produces `[99,0]`. The bit-pattern effect is decrement by
one modulo `2^64`, despite the chosen name `inc`.

## S19-04 — Diagnose phase and target mistakes

**Hint 1.** The ordinary REPL looks up names. Decimal parsing is reached
when `[lit]` explicitly consumes its next token.

**Hint 2.** Decode `81 F5 FF FF` as a signed little-endian distance and
add it to `0x401012`. Compare the resulting address with the source's
separate `lit` header and code addresses.

**Checked solution: missing literal introducer.** In `: inc 1 + ;`,
colon still creates the same thirteen-byte header. The absent name `1`
causes a lookup miss. The REPL requests output of `1?` followed by a
newline, removes the failed-lookup result, and continues; it does not
parse one, emit a literal, reset STATE, or undo the header.

It then compiles `+` at `0x40100D`, whose instruction end is `0x401012`.
The distance is `0x4001B7-0x401012 = -0xE5B = -3675`, giving
`E8 A5 F1 FF FF`. Semicolon writes C3 at `0x401012`. The resulting entry
has nineteen bytes, final HERE=`0x401013`, LATEST=`0x401000`, STATE=0.
A status or mode value does not certify the intended stack effect.

Calling this mistaken word on `[5]` violates addition's two-operand
contract. The saved dummy is not a real second value. Do not accept a
plausible register result as valid Forth behavior after that violation.
On `[99,5]`, both operands really exist, so it returns `[104]`: it consumes
the supposed older prefix rather than preserving `[99,6]`.

**Checked solution: header as target.** `0xFFFFF581` represents -2687,
or `-0xA7F`. Therefore `0x401012-0xA7F = 0x400593`, the **header** of
`lit`, thirteen bytes before its xt. These bytes are intended as link,
flags, length, and name, not as entry instructions for the primitive.
Calling them violates the executable-target contract. No specific crash,
output, or safe recovery follows from this static diagnosis.

**Common error.** Saying “the assembler fixes a named target” invents a
later assembler pass. The native emitter stores the supplied displacement;
the CPU adds it to the actual instruction-end address.

**Changed case.** In a separate hypothetical source variant, clear the
immediate bit on semicolon's header. In the otherwise correct capstone,
STATE remains nonzero when `;` is read, so the loop compiles a CALL to
semicolon instead of executing it. HERE advances from `0x40101F` to
`0x401024`, STATE remains one, and no final C3 is emitted. A later EOF
would take the interpreter's exit-zero path without repairing the word.
This is a diagnosis of a stipulated variant, not an edit to the pinned seed.

## S19-05 — Write an honest audit conclusion

**Hint 1.** Give every evidence claim a noun: source inspection,
calculation, execution, comparison, proof, or learning observation.

**Hint 2.** Name one exact positive result, then name the environment and
preconditions on which its predicted behavior depends.

**Checked example.** A defensible four-sentence answer is:

1. I inspected the Linux/x86-64 seed at revision
   `bbcc1732152af2d884737272eed870d2410ffe8e` and its 76-region,
   1,772-file-byte ledger
2. From the source-defined initial state I derived the complete 32-byte
   `inc` entry, checked both CALL targets, and traced its predicted effect
   `[99,5] -> [99,6]`
3. This work did not execute the seed, regenerate a bootstrap chain,
   prove every permitted program correct, or measure novice learning
4. The argument depends on the stated CPU/Linux contracts, accurate source
   decoding and inspection, valid input and storage, and correct stack and
   call-site conditions

The proposed security claim does not follow. A matching rebuild would
establish a specified byte comparison under its recorded method; it could
reproduce a defect. Security additionally requires a threat model and
appropriate evidence about attacks, malformed inputs, authority, and
failure behavior. File coverage is valuable because it exposes the whole
artifact to inspection, not because it changes those requirements.

Useful next evidence could include an authorized, recorded run on a named
profile; checks that compare generated memory to this prediction; explicit
boundary/error cases; and a precisely scoped correctness or security
argument. A reproducibility claim would need its own inputs, toolchain,
commands, environment, and comparison rule. These are proposed evidence,
not completed activities. Linux/toolchain implementation review belongs
to later scoped work, not an implied achievement of this volume.

**Evaluation criteria.** Accept other wording when it identifies the pin,
states a checked positive result, labels prediction correctly, and names
remaining assumptions. Reject an answer that treats a file hash as a
safety certificate, quietly calls a derivation a run, or claims all later
volumes are finished. “Nothing was proved, therefore nothing was learned”
also misses the inspectable positive result.

**Changed case.** Suppose a future authorized test captures the exact
32 memory bytes and stdout byte `41`, with a recorded environment and
input. You may then report those as observed results of that test. You
still cannot generalize them to all inputs, another platform, a matching
rebuild, arbitrary-program correctness, or security. Change only the
claims for which that new evidence actually supplies support.
