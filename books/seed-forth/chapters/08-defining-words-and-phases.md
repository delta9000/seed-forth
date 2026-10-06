# 8. Defining words and keeping phases apart

[Previous: Linux I/O contracts](07-linux-io-contracts.md) · [Practice help](../practice/08-solutions.md) · [Next: Control flow by patching](09-control-flow-by-patching.md)

We can already write bytes and define a word. Now combine those abilities:

```forth
[lit] 7 constant seven
```

This creates a word named `seven`. Later, executing `seven` pushes seven.
The number has become part of executable code, rather than an extra value
that must remain on the data stack between those two moments.

There are actually **three phases** to explain: making the word `constant`,
using `constant` to make `seven`, and executing `seven`. Losing track of
which word is being built makes the source look self-contradictory. Keeping
the phases separate reveals a small, precise mechanism.

By the end, you should be able to trace all three phases, locate the emitted
value within the new word, explain when a token runs instead of compiling,
and calculate the relative address in a native call. We will then use those
same pieces to explain why `[char] ;` can compile a semicolon character
without ending a definition.

## Choose your route

Bring the stack notation and definition contract from [Chapter 1](01-values-and-words.md),
the address/value distinction from [Chapter 2](02-addresses-and-bytes.md),
modular subtraction from [Chapter 3](03-bits-and-subtraction.md), the call and
return destinations from [Chapter 4](04-return-stack-and-shuffles.md), and
the writers from [Chapter 6](06-memory-updates-and-writers.md). You do not
need to know an assembler, a branch compiler, or the operating-system loader.
We open only the machine-code contracts needed here.

Check two prerequisites: if HERE contains 1000, does `here-addr` push 1000?
Does `,8` with input seven execute an instruction that pushes seven? The
answers are no: `here-addr` returns the address of HERE's cell, while `,8`
writes eight bytes and consumes its input. If either distinction is shaky,
revisit the linked memory chapters before adding phases.

Experienced readers can attempt S8-01 and S8-04 first. Still inspect the
ordinary, non-immediate `:` and the whole-byte store in `immediate`; familiar
Forth spellings do not guarantee familiar implementation details.

**Edition and evidence.** We describe the Linux/x86-64 seed at
[`7d7e1996d1753118181d43e1a413960d3a1ec24b`](https://github.com/delta9000/seed-forth/tree/7d7e1996d1753118181d43e1a413960d3a1ec24b).
Every trace is manually derived from inspected source, not an executed
observation. Code excerpts explain existing definitions; assume their stated
dependencies are available. Model addresses are not usable scratch locations
in a running seed. Assume sufficient writable dictionary space, executable
completed bodies, valid stacks, no overlap with reserved state, and no
address wrap. No build or live memory-writing exercise is required.

## The outer loop makes a decision about each token

The **outer loop** reads an input token, finds its dictionary entry, and
decides what to do with the word. This is different from a compiled body
executing instructions that were already placed in memory.

The cell **STATE** records the input-processing mode. The word `state`
pushes the address of that cell, so `state @` fetches its contents. Interpret
mode uses zero. The normal compile mode established by `:` uses one; the
outer loop actually tests zero versus nonzero. STATE is not the data-stack
depth and does not hold the address of the definition under construction.

Each word also has an **immediate flag**, bit zero in a header byte. For a
successfully found token, the decision is:

| Immediate bit | STATE contents | Outer-loop action |
|---|---|---|
| Set | Either mode | Execute the word now |
| Clear | Zero | Execute the word now |
| Clear | Nonzero | Append a native call to the word's code |

“Compile a word” here usually means emit an instruction that will call it
later. It does not mean run that word on the current stack. The immediate
bit is the exception that lets selected words do work during compilation.

The primitive `:` is **not immediate**. When executed, it reads the next
token as a name, creates that word's header, and sets STATE to one. The
primitive `;` **is immediate**: it appends one native return instruction and
sets STATE to zero. This is how the outer loop can stop compiling without
first compiling a call to the stopping operation.

`[lit]` is also immediate, but its own implementation inspects STATE:

| Input handled | When it runs | Work done now | Effect when compiled code later runs |
|---|---|---|---|
| `[lit] 7` | Interpret mode | Read decimal token `7`; push 7 | No compiled code was made |
| `[lit] 7` | Compile mode | Read `7`; emit a five-byte call to `lit` and an eight-byte cell | Push the stored 7 and continue after the cell |

The second row emits **13 bytes**. It does not leave seven on the compiling
data stack. We will open `lit`'s return-address mechanism below. For now this
is the precise implementation contract behind Chapter 1's deferred literal.
There is still no ordinary bare-number fallback in the outer loop.

These decisions are visible in the pinned
[`repl`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L664-L689),
[`colon_code` and `semicolon_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L515-L549),
and [`bracket_lit_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L577-L600).

## Give the name, header, and code different addresses

A **dictionary entry** connects a name to its executable body. If an entry
starts at address `E` and its name contains `N` bytes, its layout is:

| Location | Width | Contents |
|---|---:|---|
| `E+0` | 8 bytes | Link: address of the previous entry, or zero at the chain's end |
| `E+8` | 1 byte | Flags; bit zero means immediate |
| `E+9` | 1 byte | Name length `N` |
| `E+10` | `N` bytes | Name, without a terminating zero |
| `E+10+N` | Depends on word | First byte of executable body |

The header occupies `10+N` bytes, with no automatic padding. The body's
start is the **execution token**, abbreviated **xt**. In this seed an xt
is a code address, not the header's address and not the name's address.

LATEST's cell holds `E` for the newest entry. Recall the asymmetry:
`latest` pushes the **address of LATEST's cell**, while `latest @` pushes
the **entry address stored there**. In contrast, `here` already fetches
HERE's contents. The primitive `state` behaves like `latest`, returning its
cell's address. These three distinctions remain true during compilation.

The primitive `'`, called **tick**, reads the next token and looks it up.
Its data-stack effect is `( -- xt-or-zero )`; separately, its **input
effect** is to consume one token. A quoted name in notation such as
`( "name" -- xt )` is not a string already on the data stack. For example,
`' seven` reads the characters `seven` from input and pushes that word's
code address, assuming the word exists. A missing name produces zero.

`execute` consumes an xt and transfers control to that code. Its useful
combined contract is `( inputs xt -- outputs )`, where inputs and outputs
are the chosen word's contract. The xt must identify suitable executable
code, and the word's own stack and calling preconditions must hold. It
does not validate zero or manufacture a safe result for a bad address.
Its implementation tail-jumps after removing the xt, so the called body's
return goes back to `execute`'s caller.

Thus, after defining `seven`, `' seven execute` has the same data effect
as executing `seven`. Tick obtains the address; `execute` uses it. Passing
a header address or a failed lookup's zero to `execute` violates the
contract. Lookup and these primitives are in
[`find_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L320-L360),
[`execute_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L387-L396),
and [`tick_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L506-L513).

## Change the newest word's flag

The library definition is:

```forth
: immediate  latest @ [lit] 8 + [lit] 1 swap c! ;
```

Suppose LATEST holds entry address `E`. A later call to `immediate` has this
derived trace; older data remains below the displayed portion:

```text
latest @       [E]
[lit] 8 +      [E+8]       address of the flags byte
[lit] 1        [E+8, 1]
swap           [1, E+8]    value below, destination on top
c!             []         store byte 1 at E+8
```

Using `c!` matters: an eight-byte store would overwrite the length and name
too. Using `@` after `latest` matters: without it, the offset would refer
to the system-variable area rather than the newest header.

The store writes the **entire flags byte** to one. Despite the source's
section label “toggle,” it neither toggles bit zero nor ORs one into the
previous flags. Calling it twice leaves the same byte, one. Other bits
would be cleared; the inspected dispatcher only uses bit zero.

In `: helper ... ; immediate`, the final `immediate` runs after `;` restores
interpret mode, and marks the newest word, `helper`. `immediate` itself is
ordinary, not immediate. The
[source definition](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L180-L189)
changes metadata that the outer loop will consult on later tokens.

## Emit a body that will push one value

The seed keeps the data-stack top in register `rdi`; deeper values live in
memory addressed by `rbp`. To push a new value, the emitted code must make
room, save the old top, then load the new top. This table is the actual
x86-64 template; byte displays are hexadecimal and offsets count bytes:

| Body offset | Bytes | Instruction | Effect when this code executes |
|---|---|---|---|
| 0–3 | `48 83 ED 08` | `sub rbp, 8` | Make one cell of data-stack room |
| 4–7 | `48 89 7D 00` | `mov [rbp+0], rdi` | Save the old top in that room |
| 8–9 | `48 BF` | Start of `movabs rdi, V` | Introduce an embedded 64-bit value |
| 10–17 | Eight little-endian bytes | Value field of that instruction | Load `V` as the new top |
| 18 | `C3` | `ret` | Resume the caller |

`movabs` is the instruction spelling for loading the full eight-byte value
here. You need not derive its opcode; this edition's template supplies it.
The count is eight bytes for room-and-save, two opcode bytes, eight value
bytes, and one return: **19 bytes total, including the value**.

These are the actual library definitions:

```forth
: ret,  [lit] 195 c, ;

: push-imm64,
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,
  [lit] 72 c, [lit] 191 c,
  ,8 ;

: push-body,  push-imm64, ret, ;

: constant  : push-body, [lit] 0 state ! ;
```

`push-imm64, ( v -- )` emits the first **18 bytes**. Each temporary literal
supplies one fixed byte to `c,`, leaving `v` underneath until the final
`,8` consumes it. `ret, ( -- )` emits decimal 195, hexadecimal `C3`.
`push-body, ( v -- )` combines them.

The trailing commas are part of the word names. They suggest emission,
but are not special syntax. Executing `ret,` writes a return opcode at
HERE; that store does not itself return from the newly generated word.
Executing `push-body,` consumes `v` while arranging a future push of `v`.
These are different actions at different times. The
[template and definitions](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L191-L222)
are the evidence for the count and behavior.

## Phase 1: make `constant` itself

Read the last definition carefully:

```forth
: constant  : push-body, [lit] 0 state ! ;
```

Which colon reads a name now? Predict before following this table. The
outer loop is initially interpreting, and the helper words already exist.

| Input handled | Outer-loop action | Result being prepared |
|---|---|---|
| First `:` and name `constant` | Execute `:`; it consumes the name | Header for `constant`; STATE becomes 1 |
| Second `:` | Ordinary word in compile mode: emit a call to `:` | A future invocation will read a new name |
| `push-body,` | Emit a call | A future invocation will emit a push body |
| `[lit] 0` | Execute immediate `[lit]` | Emit the 13-byte sequence that later pushes zero |
| `state` | Emit a call | Later obtain STATE's cell address |
| `!` | Emit a call | Later store the zero at that address |
| `;` | Execute immediate `;` | Append `C3`; restore STATE to 0 |

The second `:` does **not** consume `push-body,` as a name during this
phase. Its immediate bit is clear, so the outer loop compiles its call.
Likewise, `push-body,` does not generate seven's body yet. No seven has
even been supplied.

The final source semicolon ends `constant`'s definition now. Inserting an
earlier semicolon to “finish the inner word” would finish `constant` at
that earlier point. There is no nested source-definition parser waiting
to pair two colons with two semicolons.

The new flags byte for `constant` is zero, and no `immediate` follows its
definition. Thus `constant` itself is ordinary; the use we trace next
starts in interpret mode so that the outer loop executes it.

Save the result as a sequence of future actions: read a name and build its
header; emit a push body using the supplied value; push zero; get STATE's
address; store zero; return. This sequence, not the original source tokens,
is what a later call to `constant` executes.

## Phase 2: use `constant` to make `seven`

Now consider `[lit] 7 constant seven` in interpret mode. The literal pushes
seven, and the outer loop executes `constant`. That compiled body's first
call executes `:`. **Now** the colon reads `seven` from the remaining input.

Use a fresh paper model. Let `H` mean the invented address where the new
entry begins, and `P` the old newest entry. These letters are address labels,
not seed input or the half-range notation from Chapter 5. Initially HERE
holds `H`, LATEST holds `P`, and the data stack is `[99, 7]`.

The name `seven` contains five bytes, so its header occupies **15 bytes**:

| New entry locations | Contents |
|---|---|
| `H` through `H+7` | Old entry pointer `P`, little-endian |
| `H+8` | Flags byte `00` |
| `H+9` | Name-length byte `05` |
| `H+10` through `H+14` | Name bytes `73 65 76 65 6E`, spelling `seven` |

Colon updates LATEST to `H`, HERE to `H+15`, and STATE to one. Its internal
name-reading values are consumed; the data stack returns to `[99, 7]`.
The next code writes already start **after the header**.

| Completed action in `constant` | Data stack | HERE contents | STATE |
|---|---|---|---:|
| Enter with value seven | `[99, 7]` | `H` | 0 |
| Call `:`; consume name `seven` | `[99, 7]` | `H+15` | 1 |
| Emit fixed ten-byte prefix | `[99, 7]` | `H+25` | 1 |
| `,8` inside `push-imm64,` | `[99]` | `H+33` | 1 |
| `ret,` completes `push-body,` | `[99]` | `H+34` | 1 |
| Compiled literal pushes zero | `[99, 0]` | `H+34` | 1 |
| `state` | `[99, 0, address-of-STATE]` | `H+34` | 1 |
| `!` | `[99]` | `H+34` | 0 |

The value bytes at `H+25` through `H+32` are
`07 00 00 00 00 00 00 00`. The return byte is at `H+33`.
The finished word therefore occupies 15 header bytes plus 19 body bytes,
34 altogether, and its xt is `H+15`.

Why do the already-compiled calls to writers execute while STATE is one?
Because **STATE guides outer-loop token dispatch, not every machine
instruction**. `constant` is currently executing compiled code. It calls
`push-body,` directly; no outer-loop decision recompiles that call.
The writers themselves write bytes without consulting STATE.

The zero is also already compiled. There is no fresh execution of the
input-reading `[lit]` word at this moment. After zero and `state` supply
the store's inputs, `!` restores interpret mode. Finally, `constant`'s
own compiled return resumes its caller. That return is separate from the
return byte it just wrote into `seven`.

## Phase 3: execute the created word

Later, the outer loop finds `seven` and executes its body. Starting with
`[99]`, the body saves the old top, loads its embedded value seven, and
returns, leaving `[99, 7]`. It does not read another input token, create
another header, or advance HERE. Its generated instructions do the work.

A constant captures the **value supplied when it is made**. It does not
automatically repeat the calculation that produced that value. For example,
if HERE currently contains 1000, `here constant saved-here` captures 1000.
Later `saved-here` still pushes 1000 after HERE advances. It neither asks
for the new cursor nor yields the address of HERE's cell.

To capture that cell's address, the supplied value would instead come from
`here-addr`. A word made with `here-addr constant saved-here-cell` pushes
the cell address, and a later `saved-here-cell @` fetches the then-current
cursor. These are paper comparisons of value capture, not instructions to
reset a live cursor. The address/value distinction survives all three phases.

**Pause here if needed.** Save the row just after the inner colon:
`[99, 7]`, HERE=`H+15`, LATEST=`H`, STATE=1. On returning, explain who
executes next and why STATE does not prevent that execution.

## A call stores a distance from its end

We need one more writer before character literals. A native x86-64
`CALL rel32` consists of byte `E8` followed by a four-byte signed
displacement. It saves the address after these five bytes on the return
stack, then transfers control to that address plus the displacement.

If the instruction starts at `A` and its target is `T`, the required value
is `T-(A+5)`. The origin is the **end of the whole instruction**. The
library expresses this as:

```forth
: call,
  [lit] 232 c,
  here [lit] 4 + - ,4 ;
```

After writing decimal 232 (`E8`), HERE is already `A+1`. Adding four
therefore gives `A+5`. The subtraction has target below origin, matching
Chapter 3's `( a b -- a-b )` contract.

For invented addresses `A=1000`, `T=900`, the complete grouped trace is:

| After operation | Stack | HERE |
|---|---|---:|
| Start | `[99, 900]` | 1000 |
| `[lit] 232 c,` | `[99, 900]` | 1001 |
| `here` | `[99, 900, 1001]` | 1001 |
| `[lit] 4 +` | `[99, 900, 1005]` | 1001 |
| `-` | `[99, 2^64-105]` | 1001 |
| `,4` | `[99]` | 1005 |

The low 32 bits represent signed -105. Emitted bytes, in increasing address
order, are `E8 97 FF FF FF`. The runtime calculation is `1005-105=900`.
Using five after emitting `E8` would subtract 1006, encode -106, and land
at 899. Correct subtraction alone cannot rescue the wrong origin.

The exact mathematical displacement must fit signed 32 bits:
`-2147483648` through `2147483647`. `,4` writes low bits; it does not check
that range. A farther target can silently encode the wrong destination.
Assume a suitable executable target and a valid return-stack contract too.
The library's [`call,`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L224-L234)
and the seed's internal [`compile_call`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L551-L561)
implement the same five-byte layout.

## Put a literal cell after a call, then skip it

The seed primitive `,` has contract `( v -- )`: store one full eight-byte
cell at HERE and advance HERE by eight. Its final payload and cursor effect
match `,8` in this profile; it is a direct cell store rather than the
library's sequence of byte stores. It differs from `c,`, which writes one
byte. The punctuation names `,`, `,8`, and `c,` designate separate words.
See [`comma_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L373-L385).

Suppose a call to `lit` starts at model address `A`:

```text
A through A+4       CALL lit
A+5 through A+12    inline eight-byte value
A+13               next instruction
```

The call puts `A+5` on the return stack. The specialized `lit` routine
removes that return address, reads the cell at `A+5`, pushes its value on
the data stack, and substitutes `A+13` as the return destination. Its
return therefore skips the data bytes instead of trying to execute them.
Older return-stack entries remain underneath this temporary destination.

This is a calling-layout contract, not permission to call `lit` arbitrarily:
the caller must provide the eight-byte cell immediately after the call.
An ordinary `execute` of its xt does not supply that layout. The inspected
[`lit_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L563-L575)
rewrites exactly this return destination. `[lit]`'s 13-byte compile-time
product now has a fully stated runtime explanation.

## Let a word consume a token before the outer loop sees it

The library obtains the needed xt through the mechanisms already taught:

```forth
' lit constant lit-xt

: tib  state [lit] 2048 - ;
: char  ' drop tib c@ ;

: [char]  char lit-xt call, , ;
immediate
```

Tick reads `lit` and pushes its xt. `constant` captures that address under
the new name `lit-xt`. Executing `lit-xt` later pushes the saved address;
it does not execute `lit`.

The **token input buffer**, or TIB, holds the last token read. In this
pinned layout it begins 2048 bytes below STATE's cell. Thus `tib` obtains
its address from `state`, not from `state @`. Actual source addresses are
`0x413000` for STATE and `0x412800` for TIB; these are edition facts, not
the invented addresses used in our traces.

`char` uses tick as a token reader. Tick leaves an xt or zero; `drop`
discards that lookup result. `tib c@` reads the first byte of the token
still in the buffer. In interpret mode, `char A` consequently pushes 65
whether or not a word named `A` exists. Its input effect consumes `A`;
its data effect is `( -- 65 )`. Require a next nonempty token; this helper
does not establish a useful character result for exhausted input.

`char` is ordinary. `[char]` is immediate because the following
`immediate` marks its just-created header. Used during compilation,
`[char] ;` runs these steps now:

| Action | Compiling data stack | Emission |
|---|---|---|
| `char` consumes the next token `;` | `[59]` | None |
| `lit-xt` | `[59, xt-of-lit]` | None |
| `call,` | `[59]` | Five-byte call to `lit` |
| `,` | `[]` | Eight-byte cell containing 59 |

Older stack entries, omitted here, survive. The result is the same 13-byte
literal sequence as `[lit] 59`. `[char]` has no mode test of its own, so
this is a compile-time usage contract; do not assume it behaves like
`char` merely because STATE is zero.

For the paper definition `: semi [char] ; ;`, the first semicolon is
consumed by `char` through tick. Although its lookup finds the semicolon
word, `drop` discards the xt without executing it. The outer loop never
dispatches that consumed token. The second semicolon reaches the outer
loop and ends `semi`. Its derived body is 13 literal bytes followed by
one return; a later execution pushes 59. No execution is claimed here.

## The reader limits which characters can be quoted

The input reader separates tokens on space, tab, line feed, and carriage
return. It does not return those separators as tokens. A token **exactly**
`\` starts a line comment; one **exactly** `(` starts a parenthesized
comment. The reader skips the comment and resumes token reading before
tick gets a result. `char` cannot bypass that reader policy.

The library therefore supplies names for selected awkward characters:

```forth
[lit]  9 constant tab
[lit] 10 constant nl
[lit] 32 constant bl
[lit] 40 constant lparen
[lit] 92 constant backslash
```

`bl` means blank, a space. These declarations put the constant mechanism
to work without asking the reader to return whitespace or a one-token
comment marker. The word “exactly” matters: `char (x` can obtain the first
byte 40 because `(x` is not the single-token comment marker `(`. That
does not make whitespace into a token. The helper definitions and named
constants are at
[`010-lib.fth`, lines 236–263](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L236-L263);
the reader's exact-marker rules are in
[`read_word`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L398-L451).

## Practice

Use independent paper models. Hints, solutions, and changed cases are in
the [feedback companion](../practice/08-solutions.md).

### S8-01 — Separate the three phases

Make a three-row timeline for defining `constant`, processing
`[lit] 7 constant seven`, and executing `seven`. Identify which word's
header or body is written in each phase, which input token the inner
colon consumes, and when seven leaves or enters the data stack. Explain
why the second colon does not read `push-body,` as a name in phase 1,
and why `push-body,` executes despite STATE=1 in phase 2.

### S8-02 — Locate the metadata and body

Set model LATEST's cell address to 2000, containing `H=1000` after `seven`
is made. Give the results of `latest`, `latest @`, and `' seven`.
Locate the flags, name length, name, embedded value, return byte, and next
HERE. Trace `immediate` with older stack value 99. If the flags initially
contained 128, what byte would this actual definition leave? Explain why
using `!` instead of `c!` is an error.

### S8-03 — Capture the right kind of address

HERE's cell is at model address 2008 and initially contains 1000. Compare
the values captured by `here constant saved-here` and, in a separate reset,
`here-addr constant saved-here-cell`. At a later point HERE contains 1200.
What does each created word push? Which word followed by `@` fetches 1200?
Explain why the first word is not a live alias for the cursor.

### S8-04 — Repair the displacement origin

A call begins at model address 1000 and targets 1100. Derive the five
bytes emitted by the actual `call,`. Someone changes its four to five
because “calls are five bytes long.” Derive the wrong displacement and
destination. Finally, would a mathematical displacement of 2147483648 be
valid merely because `,4` can emit its low four bytes?

### S8-05 — Follow a consumed semicolon

Trace the compilation of `: semi [char] ; ;` using a model body start `B`.
Give the offsets of the call, literal cell, return, and next HERE. Explain
which semicolon ends the definition and how runtime `lit` avoids executing
the cell. Then explain the difference between `char A`, `' A`, and
`' A execute` if no word named `A` exists. Stop the last trace at its failed
precondition rather than predicting a crash.

## Check, pause, and continue

If the phases blur, label every action with both **who is executing** and
**whose bytes are being written**. If an address is wrong, distinguish the
system cell, header start, body start, and current cursor before recalculating.
If a call misses, recompute its origin after counting bytes already emitted.

You can stop with the three-phase timeline. On a later return, reconstruct
the seven body and try S8-03 without the solution: retrieving a stored
address is different from retrieving the changing value at that address.

We now have enough machinery to explain generated control flow: immediate
words can emit calls during compilation, and a runtime helper can interpret
data placed after its call. [The next chapter](09-control-flow-by-patching.md)
uses those contracts for branch destinations, including destinations whose
addresses are not known until later. This chapter establishes the phase,
layout, and call boundaries; it does not claim a build or a learner study.
