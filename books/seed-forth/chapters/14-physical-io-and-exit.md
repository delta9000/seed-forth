# 14. Physical I/O and exit

[Previous: Arithmetic in instruction bytes](13-arithmetic-in-instruction-bytes.md) · [Practice help](../practice/14-solutions.md) · [Next: Dictionary and token input](15-dictionary-and-token-input.md)

Start with `[77,99,65]` and call `emit`. The top value, 65, lives in `rdi`.
But Linux wants the output descriptor, 1, in that same register. Where does
65 go before the register changes roles? Where do 77 and 99 survive?

This chapter follows four bodies across that boundary. We will account for
142 instruction bytes, derive the returned stack when a call returns, and
separate that stack result from evidence that I/O succeeded. The distinction
matters most for `key`: its byte-shaped answer can hide a failed read.

## Choose your route and establish the boundary

Bring [Chapter 7's Linux contracts](07-linux-io-contracts.md), Chapter 11's
file offsets and mapped addresses, Chapter 12's cached top and saved dummy,
and Chapter 13's register widths, zero-extension, and zero flag. Quick check:
with `[77,99,65]`, `rdi=65` and `[rbp]=99`. After a valid `drop`, `rdi=99`
and `rbp` has advanced eight. Also, a raw read result of -9 is an error,
not a byte count. Revisit the relevant trace if either answer is uncertain.
Otherwise, try S14-01 and S14-03 before reading the worked cases.

**Evidence boundary.** The primary source is [`000-seed.hex0` at revision
7d7e1996d1753118181d43e1a413960d3a1ec24b](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L251-L318).
GNU objdump 2.44 independently decoded the four exact body ranges from the
nonexecutable, source-decoded image. Listings are source-checked; state
traces are manual derivations. No seed execution, syscall experiment,
compilation, or observed output is claimed.

Assume the Linux/x86-64 profile, enough operands, valid stack storage, and
intact return destinations. Buffers must satisfy the chosen operation's
access requirements and not overwrite live seed state. For a returning
primitive, let entry `rbp=P`, entry `rsp=S`, and `[S]=K`, its caller's return
destination. Each independent example resets P. Stack tops are at the right;
cells occupy eight bytes. Addresses here are virtual, not physical RAM.

Every listing uses half-open hexadecimal **file-offset** ranges. Add
`0x400000` to obtain a virtual address. Thus `[0254,025B)` begins at
`0x400254` and contains seven bytes. Instruction operands use decimal
small constants or explicit `0x` notation; bytes are hexadecimal.

## One register has two jobs at different times

At a Forth word boundary, `rdi` holds the cached data-stack top and `rbp`
points to the next-deeper stored cell. At a Linux syscall boundary, the
argument registers follow a different agreement:

| Role at kernel entry | Register |
|---|---|
| Syscall number | `rax` |
| Arguments 1, 2, 3 | `rdi`, `rsi`, `rdx` |
| Arguments 4, 5, 6 | `r10`, `r8`, `r9` |
| Raw result on ordinary return | `rax` |

This is an ABI, an agreement between machine-code participants.
The seed must arrange it explicitly; the kernel does not know about its
cached-top convention. Linux's [versioned entry comments](https://github.com/torvalds/linux/blob/v6.12/arch/x86/entry/entry_64.S#L47-L75)
document these register roles.

An ordinary System V function call uses `rcx` for its fourth integer
argument. `SYSCALL` instead puts its continuation address into `rcx` and
saved flags into `r11`, destroying their previous contents. Linux therefore
uses `r10` for argument four. `SYSCALL` does not push a Forth-call return
address or change the user stack pointer as `CALL` does. The later `RET`
still needs the original K at `[S]`. The [AMD64 ABI, §§3.2.3 and A.2.1](https://refspecs.linuxfoundation.org/elf/x86_64-abi-0.99.pdf#page=124)
contrasts the function and kernel conventions.

These bodies keep no needed value in `rcx` or `r11` across the syscall.
That makes their clobber harmless here; it does not promise either register
is preserved for some future caller. Nor does using Linux's argument
registers make a Forth word a standard C function. We cross two interfaces:
a seed call enters the word, and a syscall enters Linux.

## `syscall6`: seven inputs become one raw result

Start with the general bridge, whose contract Chapter 7 used:

```text
syscall6 ( a b c d e f n -- result )
```

The six arguments are distinct from the seventh cell, the syscall number.
For `[77,99,a,b,c,d,e,f,n]`, entry `rdi=n`. The stored part is:

| Address | P | P+8 | P+16 | P+24 | P+32 | P+40 | P+48 | P+56 |
|---|---|---|---|---|---|---|---|---|
| Cell | f | e | d | c | b | a | 99 | 77 |

The usual dummy and any further older cells are omitted. Predict which
instruction must preserve n before `rdi` becomes a.

The [37-byte `syscall6_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L305-L318)
answers with its first move:

```text
offset range    bytes             decoded instruction
[02D0,02D3)   48 89 F8          mov rax, rdi
[02D3,02D7)   4C 8B 4D 00       mov r9, qword [rbp]
[02D7,02DB)   4C 8B 45 08       mov r8, qword [rbp+8]
[02DB,02DF)   4C 8B 55 10       mov r10, qword [rbp+16]
[02DF,02E3)   48 8B 55 18       mov rdx, qword [rbp+24]
[02E3,02E7)   48 8B 75 20       mov rsi, qword [rbp+32]
[02E7,02EB)   48 8B 7D 28       mov rdi, qword [rbp+40]
[02EB,02ED)   0F 05             syscall
[02ED,02F1)   48 83 C5 30       add rbp, 48
[02F1,02F4)   48 89 C7          mov rdi, rax
[02F4,02F5)   C3                ret
```

The `4C` prefixes select 64-bit operands and extend the destination-register
field, allowing `r9`, `r8`, and `r10`. The displacement bytes `10`, `18`,
`20`, and `28` are hexadecimal 16, 24, 32, and 40. The final `30` is an
immediate hexadecimal 48, not thirty cells. No argument load changes P or
writes to those stored cells.

| After instruction at | Newly established state | Why it matters |
|---|---|---|
| `02D0` | `rax=n` | Preserve number before reusing cached-top register |
| `02D3` | `r9=f` | Sixth argument is nearest the cached top |
| `02D7` | `r8=e` | Load fifth argument from P+8 |
| `02DB` | `r10=d` | Load fourth argument into syscall-specific register |
| `02DF` | `rdx=c` | Load third argument from P+24 |
| `02E3` | `rsi=b` | Load second argument from P+32 |
| `02E7` | `rdi=a` | Replace n only after it is safe in `rax` |
| `02EB` | On an ordinary return, `rax=result` | Kernel result replaces number; `rcx`/`r11` are clobbered |
| `02ED` | `rbp=P+48` | Six stored input cells leave the live stack |
| `02F1` | `rdi=result` | Restore cached-top representation |
| `02F4` | Resume K; `rsp=S+8` | Return with `[77,99,result]` |

Seven inputs were consumed, yet the pointer moved by six cells. The number
was in the register, so replacing it with the result needs no seventh
memory removal. Moving P by 56 would discard 99. Reloading 99 as the top
would also be wrong: this word returns a result above the older prefix.
The six old argument cells retain their bytes outside the live range.

The loads could be reordered if their dependencies remain satisfied:
P must stay fixed, and n must be saved before loading a into `rdi`.
“Any order” without those qualifications would lose data. This is the
same preserve-before-overwrite discipline as Chapter 12's `swap`.

### Reconnect the bridge to an actual request

Use Chapter 7's paper buffer A containing `65 66 67`, the bytes of `ABC`,
and assume it is suitably readable. From
`[77,99,1,A,3,0,0,0,1]`, the bridge establishes:

```text
rax=1     rdi=1     rsi=A     rdx=3
r10=0     r8=0      r9=0
request: write(1, A, 3)
```

The two ones have different roles: syscall number and descriptor. Linux's
[x86-64 number table](https://github.com/torvalds/linux/blob/v6.12/arch/x86/entry/syscalls/syscall_64.tbl#L11-L73)
assigns read 0, write 1, and exit 60. Unused argument slots still occupy real
Forth cells because this bridge always loads all six.

If the returning kernel reports three, the final stack is `[77,99,3]`.
If it reports one, the final stack is `[77,99,1]`: only the first requested
byte was accepted. If it reports zero, no progress is established. A raw
-9 gives `[77,99,M-9]`, where `M=2^64`; it is an error pattern, not a huge
count. Linux's [result handling](https://github.com/torvalds/linux/blob/v6.12/arch/x86/include/asm/syscall.h#L42-L71)
keeps the raw result in the accumulator. No C-library translation to -1
and a separate `errno` variable occurs in this body.

Every returning case performs the same stack cleanup. Cleanup establishes
the Forth representation, not successful external work. The bridge does
not retry, retain a remaining-byte count, validate addresses, or impose a
meaning on every possible syscall's result. Syscalls that terminate or
replace execution do not satisfy this ordinary-return trace.

## `emit`: save one byte, then recover the older top

The [46-byte `emit_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L266-L276)
issues its own syscall rather than calling `syscall6`:

```text
offset range    bytes                            decoded instruction
[0254,025B)   48 C7 C0 00 20 41 00             mov rax, 0x412000
[025B,025E)   40 88 38                         mov byte [rax], dil
[025E,0263)   B8 01 00 00 00                   mov eax, 1
[0263,0268)   BF 01 00 00 00                   mov edi, 1
[0268,0272)   48 BE 00 20 41 00 00 00 00 00    movabs rsi, 0x412000
[0272,0277)   BA 01 00 00 00                   mov edx, 1
[0277,0279)   0F 05                            syscall
[0279,027D)   48 8B 7D 00                      mov rdi, qword [rbp]
[027D,0281)   48 83 C5 08                      add rbp, 8
[0281,0282)   C3                               ret
```

`dil` is `rdi`'s low byte. The `40` prefix makes that byte-register name
available, as in Chapter 13's SETE. Storing this byte preserves the intended
payload before the descriptor replaces the whole cache. It does not store
a 64-bit cell or encode a character into several bytes.

The writes to `eax`, `edi`, and `edx` each clear the high half of the
corresponding 64-bit register. Thus they establish complete values 1 in
`rax`, `rdi`, and `rdx`, regardless of previous high bits. The first address
load sign-extends its 32-bit immediate to 64 bits; its sign bit is clear.
The ten-byte `movabs` instead contains a full eight-byte immediate for the
same address. We audit the encoding present, without assuming it is the
shortest possible choice.

Follow the opening example with `rdi=65`, `[P]=99`, and `[P+8]=77`:

| After instruction at | Established state or action |
|---|---|
| `0254` | `rax=0x412000`, address of shared scratch byte |
| `025B` | Scratch byte becomes `0x41`, decimal 65 |
| `025E` | `rax=1`, selecting write rather than holding an address |
| `0263` | `rdi=1`, now stdout's descriptor rather than the input cell |
| `0268` | `rsi=0x412000`, pointer to the byte already stored |
| `0272` | `rdx=1`, a one-byte request |
| `0277` | Request `write(1,0x412000,1)`; any returned count/error is in `rax` |
| `0279` | `rdi=99`, recovered from P, regardless of that result |
| `027D` | `rbp=P+8`; 77 is again immediately below the cache |
| `0281` | Return to K with `[77,99]` |

The result in `rax` is ignored. A returned count of one establishes that
one byte was accepted; it does not prove screen display or durable storage.
A zero-progress return or negative error establishes no successful byte
transfer, yet the same data item is consumed. There is no positive partial
count smaller than one: a one-byte request makes the interesting count
boundary zero versus one. Chapter 7's multi-byte request can also return a
short positive count. The [write contract](https://man7.org/linux/man-pages/man2/write.2.html)
explains why requesting output and completing it are different claims.

This trace assumes control returns. For example, a broken pipe can cause a
signal rather than an ordinary continuation; the primitive installs no
recovery path. Calling `emit` does not guarantee it reaches its final RET.

Changing the input to `0x141` still stores `0x41`. High bits disappear at
the byte store. With no older logical value, the post-call load would
restore the dummy instead of 99, producing the empty representation.
With an older prefix, its top becomes cached and the rest remains in memory.

## `key`: reserve a result slot before borrowing the cache

The [47-byte `key_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L283-L298)
must preserve the old cache before putting descriptor zero into `rdi`:

```text
offset range    bytes                   decoded instruction
[028F,0293)   48 83 ED 08             sub rbp, 8
[0293,0297)   48 89 7D 00             mov qword [rbp], rdi
[0297,029C)   B8 00 00 00 00          mov eax, 0
[029C,02A1)   BF 00 00 00 00          mov edi, 0
[02A1,02A8)   48 C7 C6 00 20 41 00    mov rsi, 0x412000
[02A8,02AD)   BA 01 00 00 00          mov edx, 1
[02AD,02AF)   0F 05                   syscall
[02AF,02B2)   48 85 C0                test rax, rax
[02B2,02B4)   74 06                   jz 0x4002BA
[02B4,02B8)   48 0F B6 3E             movzx rdi, byte [rsi]
[02B8,02BA)   EB 03                   jmp 0x4002BD
[02BA,02BD)   48 31 FF                xor rdi, rdi
[02BD,02BE)   C3                      ret
```

Reset to `[77,99]`: `rdi=99`, `[P]=77`. At `028F`, `rbp=P-8` reserves a
cell. At `0293`, `[P-8]=99` saves the old top. This temporary reservation
during setup is not released on return: it supports the new logical value
that `key` leaves above 99. Undoing it would lose the old cached value from
the live stack.

At `0297`, `rax=0` selects read. At `029C`, `rdi=0` selects stdin. At
`02A1`, `rsi=0x412000` selects the shared scratch address, using the
sign-extended immediate form. At `02A8`, `rdx=1` supplies the requested
count. `02AD` requests `read(0,0x412000,1)`. The old 99 is safe in its
reserved slot throughout; 77 remains at P.

After an ordinary return, `TEST` at `02AF` sets ZF exactly when the whole
returned `rax` is zero. It does not classify all failures. JZ at `02B2`
uses that one flag. Both branch displacements count from the next instruction:

```text
JZ:   next offset 0x2B4 + 0x06 = 0x2BA, the XOR
JMP:  next offset 0x2BA + 0x03 = 0x2BD, the RET
```

### Three raw outcomes, only two paths

For the ordinary file or byte-stream input model from Chapter 7, distinguish:

| Assumed raw read outcome | Branch and cache action | Final logical stack |
|---|---|---|
| Positive count, necessarily 1 here; new byte `0x41` | ZF=0; load and zero-extend scratch; jump past XOR | `[77,99,65]` |
| Zero count, EOF for this model | ZF=1; jump to XOR, setting `rdi=0` | `[77,99,0]` |
| Negative error, such as -9 | ZF=0; take the same scratch-load path as success | `[77,99,scratch-byte-value]` |

The [read contract](https://man7.org/linux/man-pages/man2/read.2.html)
distinguishes transferred bytes, zero at EOF, and failure. The raw negative
error encoding comes from the syscall ABI, rather than the C wrapper's
-1 return described in that manual's interface.

On the positive path, MOVZX at `02B4` reads exactly one byte and clears the
high 56 bits of `rdi`; even byte `FF` becomes 255. JMP at `02B8` skips the
XOR so that value survives. On the zero path, XOR at `02BA` makes the entire
cache zero without reading scratch. Both paths reach RET at `02BD`, with
`rbp=P-8` and the original return destination intact.

The negative path is the dangerous one. Suppose an earlier `emit` left
`0x41` in scratch and a subsequent read returns an error without replacing
it. TEST sees a nonzero pattern, so `key` returns 65 again. This is a
conditional stale-data trace, not evidence that another A arrived. There
is no sign test, retry, error result, or rollback of the reserved slot.

Even successful input is ambiguous: a transferred NUL byte, value zero,
passes through MOVZX and gives the same Forth result as EOF. The caller
cannot distinguish those cases from that result alone. An unchanged scratch
byte of zero on an error could produce zero too. This is a compact token-input
primitive with limitations, not a robust binary-input API.

The shared address is also state: `emit` overwrites it, and successful
`key` overwrites it through the kernel. These traces assume no concurrent
or reentrant use changes that byte during a request. A different threading
or signal-handler design would need to revisit that assumption.

**Stop/resume.** Save the sentence “nonzero count is not the same test as
positive count.” On return, derive both branch targets and trace a negative
result before rereading the successful path.

## `bye`: leave execution, rather than restore a stack

The [12-byte `bye_code`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L256-L259)
is shorter because it has no normal return contract:

```text
offset range    bytes             decoded instruction
[023A,023F)   B8 3C 00 00 00    mov eax, 60
[023F,0244)   BF 00 00 00 00    mov edi, 0
[0244,0246)   0F 05             syscall
```

The first move establishes `rax=60`; the second establishes `rdi=0`, the
exit status. The third requests raw Linux `exit(0)`. It does not take the
old cached top as a status. No data-memory load, pointer adjustment, or
RET follows. Once the normal exit takes effect, there is no returned Forth
stack to inspect and no need to recover its older prefix.

More precisely, raw Linux exit terminates the calling thread. For this
single-thread seed that ends its process. It is not the C-library
`exit` function or an `exit_group` request; see the [kernel/C-library
distinction](https://man7.org/linux/man-pages/man2/_exit.2.html#NOTES).
We assume the normal exit contract, not a host interceptor that forces it
to return. The bytes after this body are a dictionary header, not a fallback
continuation if that assumption fails.

Chapter 7's library `die` is different at the Forth boundary. Its
[pinned definition](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/010-lib.fth#L65-L69)
takes a status, appends five unused argument zeros and number 60, then uses
`syscall6`. `bye` hard-codes status zero and issues SYSCALL directly.
Neither successful exit reaches a subsequent RET. A generic bridge's
seven-to-one notation cannot manufacture a return from a nonreturning call.

## Practice

These are paper audits. Do not run, patch, or compile the seed. The
[feedback companion](../practice/14-solutions.md) gives graduated hints,
checked solutions, and changed cases.

### S14-01 — Rebuild the seven-to-one bridge

From `[77,99,a,b,c,d,e,f,n]`, fill every register at `02EB` and trace all
three instructions after a returning syscall. Give final `rbp`, `rdi`, D,
and `rsp`. Diagnose two separate proposed edits: loading `rdi` before
saving n, and changing cleanup to `add rbp,56`. What does each lose?

### S14-02 — Separate an output byte from an output result

Reset to `[77,99,0x141]`. Trace all ten `emit` instructions, identifying
scratch, descriptor, address, count, old-prefix recovery, and return.
Compare assumed raw results 1, 0, and -9. What final data state is identical?
Which claim about external output differs? Explain the `40` prefix and
why the input's bit eight never becomes a second byte.

### S14-03 — Audit every `key` outcome

Reset to `[77,99]` with scratch `0x41`. Trace setup and both branches for
three independent outcomes: read returns 1 after storing `0xFF`; read
returns 0; read returns -9 without changing scratch. Include ZF, branch
targets, final pointer, and stack. Add a successful read of NUL. Which
outcomes become indistinguishable to the caller, and why?

### S14-04 — Preserve information in a changed interface

A hypothetical replacement returns `( -- byte status )`, where status is
1 for a transferred byte, 0 for EOF, and the raw negative error otherwise.
Specify the pair for byte NUL, byte `FF`, EOF, and -9; use byte zero when no
byte was received. Derive final registers and live stack storage from entry
`[77,99]`. Explain why replacing JZ with a sign-aware branch alone cannot
implement this two-result contract. No machine-code patch is required.

### S14-05 — Compare the two exits and the two ABIs

From `[99,7]`, compare direct `bye` with library `die`: give the exit-number
and status registers each establishes, and explain why neither has a
successful-return stack. Then assess a proposal to move syscall argument
four into `rcx` and save the Forth return destination in `r11`. Identify
both independent conflicts with SYSCALL and where the real return
destination remains during `emit`, `key`, and a returning `syscall6`.

## Check the boundary, then continue

If an older value disappears, reconstruct the memory-backed cells before
changing the arithmetic. If an error becomes a character, inspect the
branch condition before the byte load. If a trace says “printed A,” replace
that claim with the actual assumed result and what it establishes.
Close the hints and attempt one changed case; following a worked trace and
reconstructing it independently are different evidence.

The body ledger is `bye` 12, `emit` 46, `key` 47, and `syscall6` 37 bytes:
`12+46+47+37=142`. Ranges are `[0x23A,0x246)`, `[0x254,0x282)`,
`[0x28F,0x2BE)`, and `[0x2D0,0x2F5)`. The intervening dictionary headers
belong to Chapter 15 and are excluded. Static checking used binary input,
x86-64 mode, Intel syntax, base `0x400000`, and separate start/stop bounds
for each body. No execution evidence is substituted for those checks.

We have connected private stack state to kernel requests, including paths
that cannot establish successful input or output. [Chapter 15](15-dictionary-and-token-input.md)
follows how dictionary names and token input use these mechanisms. It must
inherit `key`'s actual limits rather than assume a stronger input contract.
