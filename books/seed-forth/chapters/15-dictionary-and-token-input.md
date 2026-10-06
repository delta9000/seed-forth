# 15. Dictionary headers and token input

[Previous: Physical I/O and exit](14-physical-io-and-exit.md) · [Practice help](../practice/15-solutions.md) · [Next: Native colon compiler](16-native-colon-compiler.md)

Suppose a compiled word already calls `dup`, and we then define a new word
also named `dup`. Does the earlier caller change? The answer depends on a
distinction we can now inspect byte by byte: searching for a name chooses a
code address; executing a previously compiled call uses the address already
encoded in that call.

This chapter connects input bytes to those addresses. We will reconstruct
all 32 built-in headers, walk the search, trace the small storage and dispatch
words, and follow a token from `key` through whitespace, comments, lookup,
and error reporting. The destination is an ability to predict both a normal
lookup and its boundaries, including exactly which state survives a miss.

## Choose a stopping point and an evidence boundary

Bring [Chapter 8's header and phase model](08-defining-words-and-phases.md),
[Chapter 10's storage lifetime](10-storage-deferred-words-and-bytes.md), and
[Chapter 12's physical stack invariant](12-physical-stacks-and-memory.md).
[Chapter 14](14-physical-io-and-exit.md) supplies the `key` and syscall
contracts. Diagnose two prerequisites: does `latest` return an entry, and
does a processor ZF result have to survive an intervening ADD? No to both:
`latest` returns a system-cell address, and ADD replaces arithmetic flags.
Keep those distinctions nearby if either answer was uncertain.

There are three useful sittings: headers and `find`; storage and dispatch;
then character/token input and errors. Each has a stop/resume check. Readers
already comfortable with the mechanisms can start with S15-01, S15-02, and
S15-05, consulting the full byte listings as needed. No opcode memorization
or live seed session is required.

**Edition and method.** Every source link pins
[`000-seed.hex0` at 7d7e1996d1753118181d43e1a413960d3a1ec24b](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0).
The header fields and all eleven non-header listings were checked against
that source. Bounded GNU objdump 2.44 disassembly of the exact source-decoded,
nonexecutable inspection image agreed with the 114 instruction boundaries
and bytes. Traces below are manual derivations, not observed executions.
Nothing here claims a build, seed run, complete-system proof, or tested
recovery procedure.

Assume the pinned Linux/x86-64 layout, valid data and return stacks, readable
headers and token storage, and enough writable space wherever a store is
specified. All instruction ranges are **half-open hexadecimal file offsets**:
`[0303,0307)` includes four bytes. Add `0x400000` to obtain virtual addresses.
Branch targets in the listings are virtual addresses. Logical stack top is
at the right; cells and unqualified register-sized memory accesses are eight
bytes. Byte strings run from lower to higher addresses.

## Headers connect names to code

For an entry at virtual address `E`, the link occupies `E..E+7`, flags occupy
`E+8`, the unsigned one-byte name length `N` occupies `E+9`, and name bytes
occupy `E+10..E+9+N`. Code starts at `E+10+N`. There is no alignment padding,
NUL terminator, or separate code-pointer field. That code address is the
execution token, **xt**.

Here is the complete initial header ledger. Header and code offsets locate
bytes in the file; the final xt column is the virtual address `find` will
return. Link values are full
virtual addresses, stored as eight little-endian bytes. Flags and lengths
are hexadecimal byte values; parenthesized lengths are decimal. Each name
links to its exact source header.

| Header offset | Previous-link value | Flags | Length | Name bytes | Name | Code offset | Code start / xt |
|---|---|---|---|---|---|---|---|
| `00BA` | `0x000000` | `00` | `03` (3) | `64 75 70` | [`dup`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L76-L80) | `00C7` | `0x4000C7` |
| `00D0` | `0x4000BA` | `00` | `04` (4) | `64 72 6F 70` | [`drop`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L86-L90) | `00DE` | `0x4000DE` |
| `00E7` | `0x4000D0` | `00` | `04` (4) | `73 77 61 70` | [`swap`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L96-L100) | `00F5` | `0x4000F5` |
| `0101` | `0x4000E7` | `00` | `02` (2) | `3E 72` | [`>r`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L107-L111) | `010D` | `0x40010D` |
| `0119` | `0x400101` | `00` | `02` (2) | `72 3E` | [`r>`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L120-L124) | `0125` | `0x400125` |
| `0131` | `0x400119` | `00` | `02` (2) | `72 40` | [`r@`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L133-L137) | `013D` | `0x40013D` |
| `014E` | `0x400131` | `00` | `01` (1) | `40` | [`@`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L147-L151) | `0159` | `0x400159` |
| `015D` | `0x40014E` | `00` | `01` (1) | `21` | [`!`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L156-L160) | `0168` | `0x400168` |
| `017C` | `0x40015D` | `00` | `02` (2) | `63 40` | [`c@`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L169-L173) | `0188` | `0x400188` |
| `018D` | `0x40017C` | `00` | `02` (2) | `63 21` | [`c!`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L178-L182) | `0199` | `0x400199` |
| `01AC` | `0x40018D` | `00` | `01` (1) | `2B` | [`+`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L191-L195) | `01B7` | `0x4001B7` |
| `01C0` | `0x4001AC` | `00` | `04` (4) | `6E 61 6E 64` | [`nand`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L201-L205) | `01CE` | `0x4001CE` |
| `01DA` | `0x4001C0` | `00` | `02` (2) | `30 3D` | [`0=`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L212-L216) | `01E6` | `0x4001E6` |
| `01F5` | `0x4001DA` | `00` | `01` (1) | `2F` | [`/`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L224-L228) | `0200` | `0x400200` |
| `0212` | `0x4001F5` | `00` | `01` (1) | `2A` | [`*`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L239-L243) | `021D` | `0x40021D` |
| `022D` | `0x400212` | `00` | `03` (3) | `62 79 65` | [`bye`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L251-L255) | `023A` | `0x40023A` |
| `0246` | `0x40022D` | `00` | `04` (4) | `65 6D 69 74` | [`emit`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L261-L265) | `0254` | `0x400254` |
| `0282` | `0x400246` | `00` | `03` (3) | `6B 65 79` | [`key`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L278-L282) | `028F` | `0x40028F` |
| `02BE` | `0x400282` | `00` | `08` (8) | `73 79 73 63 61 6C 6C 36` | [`syscall6`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L300-L304) | `02D0` | `0x4002D0` |
| `02F5` | `0x4002BE` | `00` | `04` (4) | `66 69 6E 64` | [`find`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L320-L324) | `0303` | `0x400303` |
| `0359` | `0x4002F5` | `00` | `04` (4) | `68 65 72 65` | [`here`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L362-L366) | `0367` | `0x400367` |
| `0378` | `0x400359` | `00` | `01` (1) | `2C` | [`,`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L373-L377) | `0383` | `0x400383` |
| `03A3` | `0x400378` | `00` | `07` (7) | `65 78 65 63 75 74 65` | [`execute`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L387-L391) | `03B4` | `0x4003B4` |
| `0488` | `0x4003A3` | `00` | `05` (5) | `73 74 61 74 65` | [`state`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L484-L488) | `0497` | `0x400497` |
| `04AA` | `0x400488` | `00` | `06` (6) | `6C 61 74 65 73 74` | [`latest`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L495-L499) | `04BA` | `0x4004BA` |
| `04CD` | `0x4004AA` | `00` | `01` (1) | `27` | [`'`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L506-L510) | `04D8` | `0x4004D8` |
| `04E2` | `0x4004CD` | `00` | `01` (1) | `3A` | [`:`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L515-L519) | `04ED` | `0x4004ED` |
| `053F` | `0x4004E2` | `01` | `01` (1) | `3B` | [`;`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L538-L542) | `054A` | `0x40054A` |
| `0593` | `0x40053F` | `00` | `03` (3) | `6C 69 74` | [`lit`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L563-L567) | `05A0` | `0x4005A0` |
| `05B2` | `0x400593` | `01` | `05` (5) | `5B 6C 69 74 5D` | [`[lit]`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L577-L581) | `05C1` | `0x4005C1` |
| `0601` | `0x4005B2` | `00` | `06` (6) | `62 72 61 6E 63 68` | [`branch`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L602-L606) | `0611` | `0x400611` |
| `0617` | `0x400601` | `00` | `07` (7) | `30 62 72 61 6E 63 68` | [`0branch`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L613-L617) | `0628` | `0x400628` |

This table is a byte-reconstruction recipe, not merely an index of words.
For every row, serialize the link into eight little-endian bytes, append
the listed flag byte, length byte, and name bytes. For `drop`, that produces
all fourteen bytes in `[00D0,00DE)`:

```text
BA 00 40 00 00 00 00 00   00   04   64 72 6F 70
        link            flags len       name
```

For `[lit]`, all fifteen bytes in `[05B2,05C1)` are:

```text
93 05 40 00 00 00 00 00   01   05   5B 6C 69 74 5D
```

`dup` instead begins with eight zero bytes, followed by `00 03 64 75 70`.
Thus the headers account for `32 × 10 + 101 = 421` bytes: fixed fields plus
name bytes. Earlier body audits did not account for these bytes. Reconstruct
one header yourself before trusting that total.

Startup initializes the contents of LATEST's cell at `0x413008` to
[`0x400617`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L67-L72),
the `0branch` header. Walk the ledger upward from its last row: each link
names the preceding row's header. Eventually `drop` links to `dup`, whose
zero link terminates the walk. All 32 entries occur once. The four unnamed
helpers between `execute` and `state` have no headers; `state` links straight
to `execute`. Search follows links, not guesses about body lengths.

Only `;` and `[lit]` have flag byte `01`. Every other initial flag is `00`,
including `:` and `lit`. The interpreter later tests bit zero, while `find`
itself ignores flags. Being immediate changes what the outer loop does with
a hit; it does not change where the code starts.

Newest-first search gives redefinition its meaning. A new `dup` header links
back into the old chain and becomes LATEST. Future lookup finds the new
entry first. The original header and code remain at their previous addresses.
A previously compiled native CALL still targets its original xt unless some
separate operation rewrites that code. An explicitly retained old xt can
still select the old body. Do not turn “shadowed during name lookup” into
“unreachable by any means.”

## find: length first, then every byte

[`find_code`, 86 bytes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L325-L361),
has contract `( c-addr u -- xt-or-zero )`. Its caller supplies readable token
bytes and their length. The code neither scans for a terminator nor changes
case. The current header is kept separate from the two comparison pointers:

```text
offset range    bytes                           decoded instruction
[0303,0307)   48 8B 75 00                     mov rsi, [rbp]
[0307,030B)   48 83 C5 08                     add rbp, 8
[030B,0313)   48 8B 0C 25 08 30 41 00         mov rcx, [0x413008]
[0313,0316)   48 85 C9                        test rcx, rcx
[0316,0318)   74 3D                           jz 0x400355
[0318,031D)   48 0F B6 41 09                  movzx rax, byte [rcx+9]
[031D,0320)   48 39 F8                        cmp rax, rdi
[0320,0322)   75 2E                           jne 0x400350
[0322,0325)   48 89 FA                        mov rdx, rdi
[0325,0329)   4C 8D 41 0A                     lea r8, [rcx+10]
[0329,032C)   49 89 F1                        mov r9, rsi
[032C,032F)   48 85 D2                        test rdx, rdx
[032F,0331)   74 13                           jz 0x400344
[0331,0334)   41 8A 00                        mov al, [r8]
[0334,0337)   41 3A 01                        cmp al, [r9]
[0337,0339)   75 17                           jne 0x400350
[0339,033C)   49 FF C0                        inc r8
[033C,033F)   49 FF C1                        inc r9
[033F,0342)   48 FF CA                        dec rdx
[0342,0344)   EB E8                           jmp 0x40032C
[0344,034C)   48 89 0C 25 18 30 41 00         mov [0x413018], rcx
[034C,034F)   4C 89 C7                        mov rdi, r8
[034F,0350)   C3                              ret
[0350,0353)   48 8B 09                        mov rcx, [rcx]
[0353,0355)   EB BE                           jmp 0x400313
[0355,0358)   48 31 FF                        xor rdi, rdi
[0358,0359)   C3                              ret
```

The first load saves the token address in `rsi`; advancing `rbp` consumes
that address's memory-backed slot. `rdi` still holds `u`. RCX starts at the
newest header. A zero RCX reaches the miss return before any header access;
otherwise the byte at `RCX+9` is zero-extended and compared to the full input
length. Differing lengths jump to the link load at `0350` without comparing
any name bytes.

For equal lengths, `rdx=u` counts remaining comparisons, `r8=RCX+10` points
to the candidate name, and `r9=rsi` points to the token. On each equal byte,
both pointers advance and the count falls by one. RCX stays at the header.
A mismatch follows `[RCX]` and restarts the candidate test, resetting the
comparison pointers if another equal-length candidate appears. The original
token pointer in RSI and length in RDI are never consumed by that loop.

Trace token `here`, length four, at address `T`. Initially the logical stack
is `[99,T,4]`, with `rbp=P`, `[P]=T`, and `[P+8]=99`:

| Stage | Pointer/count state | Why control moves |
|---|---|---|
| `[0303,0313)` | `rsi=T`, `rbp=P+8`, `rdi=4`, `rcx=0x400617` | Consume the token address; load newest header |
| Candidate walk | Lengths 7, 6, 5, 3, 1, 1, 1, 6, 5, 7, 1 fail | These are `0branch` through comma, following links |
| Candidate `here` | `rcx=0x400359`; `r8=0x400363`, `r9=T`, `rdx=4` | Its length matches |
| Four equal iterations | Pairs `68`, `65`, `72`, `65`; pointers advance four times | Exact bytes, not a prefix test |
| Next loop test | `r8=0x400367`, `r9=T+4`, `rdx=0` | Zero remaining bytes reaches the hit block |
| `[0344,0350)` | `[0x413018]=0x400359`, `rdi=0x400367` | Save header identity; return code identity |

The result is `[99,0x400367]`. RBP remains `P+8`, so the original two inputs
became one result. In the candidate-walk row, `[lit]` is length five, `lit`
length three, and the later length-five entry is `state`; equal lengths alone
would still not be sufficient evidence of a matching name.

Now change the token to `herd`, still length four. The `here` candidate gets
through `h`, `e`, `r`; its final `e` differs from `d`. The branch at `0337`
skips before advancing either pointer for that unequal pair. Later candidates
of length four are tried from token position zero. In the initial dictionary
none matches, so the walk eventually follows `dup`'s zero link and returns
`rdi=0`, giving `[99,0]`. No error is printed by `find` itself.

The successful header is stored in **LAST_FOUND**, the cell at `0x413018`.
The miss block contains no such store. If a prior hit found `here`, a later
miss leaves LAST_FOUND holding `0x400359`; it does not clear it or make it a
valid description of the missing token. The normal
[REPL miss path](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L664-L689)
checks the returned xt first. Zero takes reporting and stack cleanup;
only the nonzero branch reads LAST_FOUND to inspect flags. That ordering is
why the stale value is harmless on this path, not a promise that stale state
is safe for arbitrary callers.

The public shape permits a caller to pass zero or more than 255 as `u`.
No initial header has zero length; none can have a one-byte length greater
than 255, so those inputs cannot hit the initial table. A constructed
zero-length header would reach the hit block without reading name bytes.
Do not infer an empty-name guard that this body does not contain.

**Stop/resume.** Save the hit pair: header `0x400359`, xt `0x400367`. On return,
explain which one LAST_FOUND stores, which one is returned, and why a later
miss must not make a caller consult the saved flags.

## Values, addresses, and the emission cursor

Three push-like words expose different contracts. The actual system cells
are STATE at `0x413000`, LATEST at `0x413008`, HERE at `0x413010`, and
LAST_FOUND at `0x413018`. The address of a cell and the value in that cell
remain different even when both values happen to look like addresses.

[`here_code`, 17 bytes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L367-L372),
pushes HERE's **contents**:

```text
offset range    bytes                           decoded instruction
[0367,036B)   48 83 ED 08                     sub rbp, 8
[036B,036F)   48 89 7D 00                     mov [rbp], rdi
[036F,0377)   48 8B 3C 25 10 30 41 00         mov rdi, [0x413010]
[0377,0378)   C3                              ret
```

[`state_code`, 19 bytes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L489-L494),
and [`latest_code`, 19 bytes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L500-L505),
push their cells' **addresses**:

```text
offset range    bytes                           decoded instruction
[0497,049B)   48 83 ED 08                     sub rbp, 8
[049B,049F)   48 89 7D 00                     mov [rbp], rdi
[049F,04A9)   48 BF 00 30 41 00 00 00 00 00   mov rdi, 0x413000
[04A9,04AA)   C3                              ret

offset range    bytes                           decoded instruction
[04BA,04BE)   48 83 ED 08                     sub rbp, 8
[04BE,04C2)   48 89 7D 00                     mov [rbp], rdi
[04C2,04CC)   48 BF 08 30 41 00 00 00 00 00   mov rdi, 0x413008
[04CC,04CD)   C3                              ret
```

In each separate trace, start with `rdi=99`, `rbp=P`. The first two
instructions move RBP to `P-8` and store 99 there. The load in `here` makes
the new top equal to `[0x413010]`, initially `0x401000`. The immediate loads
in `state` and `latest` instead make the new top `0x413000` and `0x413008`.
RET returns to the caller with one additional data item. Thus `state @`
reads the mode, `latest @` reads the newest header, but `here @` reads a
cell at the current emission cursor. It does not repeat HERE's fetch.

[`comma_code`, 32 bytes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L378-L386),
has contract `( v -- )` and writes a cell:

```text
offset range    bytes                           decoded instruction
[0383,038B)   48 8B 04 25 10 30 41 00         mov rax, [0x413010]
[038B,038E)   48 89 38                        mov [rax], rdi
[038E,0392)   48 83 C0 08                     add rax, 8
[0392,039A)   48 89 04 25 10 30 41 00         mov [0x413010], rax
[039A,039E)   48 8B 7D 00                     mov rdi, [rbp]
[039E,03A2)   48 83 C5 08                     add rbp, 8
[03A2,03A3)   C3                              ret
```

Let HERE contain a valid cursor `H`, with `rdi=0x1234`, `rbp=P`, `[P]=99`.
The first two instructions fetch `H` into RAX and store eight bytes there:
`34 12 00 00 00 00 00 00`. The next pair computes `H+8` and writes it back
into HERE's cell. The final load/add restores `rdi=99`, advances `rbp` to
`P+8`, and RET returns. The value was consumed only after its bytes were
stored; the cursor's cell itself did not move.

Comma neither allocates a mapping nor checks capacity, alignment, ownership,
or overlap. Its intended contract assumes the destination is safe. The
instructions perform a store and a cursor update, not an atomic transaction
with a rollback path. This is the physical basis of Chapter 10's variable
cell, and also why advancing HERE is not enough to prove an allocation safe.

## execute: restore the data top, then jump

[`execute_code`, 13 bytes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L392-L397),
consumes an xt before entering its target:

```text
offset range    bytes                           decoded instruction
[03B4,03B7)   48 89 F8                        mov rax, rdi
[03B7,03BB)   48 8B 7D 00                     mov rdi, [rbp]
[03BB,03BF)   48 83 C5 08                     add rbp, 8
[03BF,03C1)   FF E0                           jmp rax
```

For logical stack `[99,65,emit-xt]`, take `emit-xt=0x400254`, `rdi=emit-xt`,
`rbp=P`, `[P]=65`, `[P+8]=99`. RAX saves the target. The next two instructions
restore `rdi=65` and advance RBP to `P+8`. Consequently `emit` sees precisely
its expected `( c -- )` input, not its own address at the top.

Suppose execute's caller left return address `K` at `[rsp]`. `jmp rax` adds
no return destination. The target's eventual RET therefore returns directly
to `K`, which explains the term **tail jump**. Execute itself has no RET
instruction. For this example, `emit` attempts to write byte `41` and restores
99 according to Chapter 14's contract. This is a derived attempt, not a
guarantee that an output device accepts the byte.

There is no target validation. Executing zero after an unchecked failed
lookup is not a request to do nothing; it transfers control to address zero.
The target must be valid executable code with a stack contract the caller
satisfies. Saving an old xt and later using execute remains possible even
when a newer entry has the same name.

**Stop/resume.** From `[99,65,emit-xt]`, retain the state immediately before
JMP: `rdi=65`, `rbp=P+8`, `rax=emit-xt`, and `[rsp]=K`. Explain why another
CALL would have introduced a different return-stack obligation.

## read_char: preserve the stack, return a byte and ZF

Before following the larger token loop, isolate its 35-byte helper,
[`read_char`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L453-L467).
It has no net data-stack effect. Instead it returns the character in RDX and
sets ZF exactly when that character is one of four whitespace bytes:

```text
offset range    bytes                           decoded instruction
[0436,043B)   E8 54 FE FF FF                  call 0x40028F
[043B,043E)   48 89 FA                        mov rdx, rdi
[043E,0442)   48 8B 7D 00                     mov rdi, [rbp]
[0442,0446)   48 83 C5 08                     add rbp, 8
[0446,0449)   80 FA 20                        cmp dl, 0x20
[0449,044B)   74 0D                           je 0x400458
[044B,044E)   80 FA 09                        cmp dl, 0x09
[044E,0450)   74 08                           je 0x400458
[0450,0453)   80 FA 0A                        cmp dl, 0x0A
[0453,0455)   74 03                           je 0x400458
[0455,0458)   80 FA 0D                        cmp dl, 0x0D
[0458,0459)   C3                              ret
```

Start with `rdi=99`, `rbp=P`. The nested `key` call pushes its result: 99 is
stored at `P-8`, RBP is `P-8`, and RDI holds `c`. Copying RDI into RDX saves
the byte before the following load and ADD restore `rdi=99`, `rbp=P`.
These steps remove key's extra live stack item. They do not erase its old
slot. The ordinary nested call/return pair also balances its return address.

The ADD has changed flags, but every path then executes a comparison.
Space `20`, tab `09`, line feed `0A`, and carriage return `0D` are the exact
whitespace set. A successful early comparison takes JE to RET. Otherwise
the final comparison, against `0D`, determines ZF. RET does not change those
flags, so the caller may immediately use JE. In particular:

| RDX result | Last comparison executed | Returned ZF | Interpretation |
|---|---|---|---|
| `0x20` | Space equality | 1 | Whitespace |
| `0x0D` | Carriage-return equality | 1 | Whitespace |
| `0x0B` | Unequal to carriage return | 0 | Vertical tab is an ordinary byte here |
| `0` | Unequal to carriage return | 0 | EOF/NUL indication; caller must test separately |

This ZF is an internal interface, unlike arithmetic primitives whose later
pointer instructions overwrite their numeric-result flags. Insert flag-setting
work between this RET and the caller's JE, and you have changed the protocol.

Chapter 14's limitations propagate unchanged. A successful read of byte NUL
and a zero-byte EOF both produce zero. A negative read result takes key's
nonzero path and may load stale scratch; read_char has no independent errno
check. Therefore RDX and ZF do not prove a new input byte was delivered.
Normal traces below assume successful reads or stable EOF. This is a byte
reader, with no Unicode decoding or general Unicode whitespace rule.

## read_word: turn a stream into one borrowed token

[`read_word`, 117 bytes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L398-L452),
is an unnamed helper with contract `( -- c-addr u )`. It returns address
`T=0x412800`, the token input buffer, and a length. Zero length indicates no
ordinary token before the EOF indication. On a normal token, `1≤u≤255`.
RBX retains the length separately for error reporting.

The complete listing follows. Internal loop destinations are `03C3`
(skip whitespace), `03CE` (store), `03E9` (classify completed token), `03FD`
(parenthesis comment), `040D` (line comment), and `041D` (return pair):

```text
offset range    bytes                           decoded instruction
[03C1,03C3)   31 DB                           xor ebx, ebx
[03C3,03C8)   E8 6E 00 00 00                  call 0x400436
[03C8,03CA)   74 F9                           je 0x4003C3
[03CA,03CC)   85 D2                           test edx, edx
[03CC,03CE)   74 4F                           jz 0x40041D
[03CE,03D4)   88 93 00 28 41 00               mov [rbx+0x412800], dl
[03D4,03D6)   FF C3                           inc ebx
[03D6,03D8)   84 FF                           test bh, bh
[03D8,03DE)   0F 85 99 00 00 00               jnz 0x400477
[03DE,03E3)   E8 53 00 00 00                  call 0x400436
[03E3,03E5)   74 04                           je 0x4003E9
[03E5,03E7)   85 D2                           test edx, edx
[03E7,03E9)   75 E5                           jnz 0x4003CE
[03E9,03EC)   83 FB 01                        cmp ebx, 1
[03EC,03EE)   75 2F                           jne 0x40041D
[03EE,03F5)   8A 04 25 00 28 41 00            mov al, [0x412800]
[03F5,03F7)   3C 5C                           cmp al, 0x5C
[03F7,03F9)   74 14                           je 0x40040D
[03F9,03FB)   3C 28                           cmp al, 0x28
[03FB,03FD)   75 20                           jne 0x40041D
[03FD,0402)   E8 34 00 00 00                  call 0x400436
[0402,0404)   85 D2                           test edx, edx
[0404,0406)   74 BB                           jz 0x4003C1
[0406,0409)   80 FA 29                        cmp dl, 0x29
[0409,040B)   75 F2                           jne 0x4003FD
[040B,040D)   EB B4                           jmp 0x4003C1
[040D,0410)   80 FA 0A                        cmp dl, 0x0A
[0410,0412)   74 AF                           je 0x4003C1
[0412,0414)   85 D2                           test edx, edx
[0414,0416)   74 AB                           jz 0x4003C1
[0416,041B)   E8 1B 00 00 00                  call 0x400436
[041B,041D)   EB F0                           jmp 0x40040D
[041D,0421)   48 83 ED 08                     sub rbp, 8
[0421,0425)   48 89 7D 00                     mov [rbp], rdi
[0425,042A)   BF 00 28 41 00                  mov edi, 0x412800
[042A,042E)   48 83 ED 08                     sub rbp, 8
[042E,0432)   48 89 7D 00                     mov [rbp], rdi
[0432,0435)   48 89 DF                        mov rdi, rbx
[0435,0436)   C3                              ret
```

### Ordinary bytes: count, store, and return

The XOR initializes the whole RBX to zero through its 32-bit subregister.
Each `read_char` temporarily pushes and pops a data value, preserving the
caller's stack. At `03C8`, JE skips whitespace immediately, using the returned
ZF. For a non-whitespace result, TEST separately checks zero. This order
prevents EOF from being mistaken for whitespace and skipped forever under
the normal zero-return convention.

A nonzero ordinary byte is stored at `T+RBX`, then INC increments EBX. The
length counter is RBX rather than RCX because the input syscalls clobber RCX;
key and read_char leave RBX alone. Subsequent comparisons keep its value for
later reporting. After the limit test, another character either ends the
token or feeds the store loop. The whitespace delimiter is consumed but not
stored. A zero indication after some bytes likewise completes those bytes.

For input bytes space, `d`, `u`, `p`, line feed, take entry stack `[99]`,
`rdi=99`, `rbp=P`:

| Group | RBX and token bytes | Control/data consequence |
|---|---|---|
| Initialize and read space | `rbx=0`; TIB unchanged | ZF=1 repeats at `03C3` |
| Read/store `d` | `rbx=1`; `T[0]=64` | Limit test passes |
| Read/store `u` | `rbx=2`; `T[1]=75` | Continue token |
| Read/store `p` | `rbx=3`; `T[2]=70` | Continue token |
| Read line feed | `rbx=3`, `rdx=0x0A`, ZF=1 | Branch to completed-token classification |
| Length is not one | Same three bytes | Skip comment-marker tests |
| `[041D,0436)` | `rdi=3`, `rbp=P-16`; `[P-16]=T`, `[P-8]=99` | Return logical `[99,T,3]` |

The return block performs two pushes: preserve old top and install T, then
preserve T and install the length. It does not require the incoming stack
to be nonempty; Chapter 12's initialized dummy supports the same invariant.
There is no instruction that appends a zero byte. Bytes after the returned
length can be leftovers from a longer earlier token.

The address is **borrowed**: the producer owns and reuses TIB. A subsequent
read_word may overwrite its bytes even though an old address/length pair
still sits on the data stack. report_token also modifies this buffer. A
caller needing a durable name must copy exactly the returned bytes into
separate valid storage before the next such use. Chapter 16's header builder
will do that copying; keeping the numeric address alone does not preserve
the text.

### Comments require a complete one-byte marker

Only after an entire token ends does the code ask whether its length is
one, then compare its byte with backslash `5C` and left parenthesis `28`.
Thus `(foo`, `()`, `\\`, and `\comment` are ordinary tokens. A left
parenthesis embedded in a larger token has no special meaning. The reader
has already consumed one delimiter when it recognizes a marker.

For `( note ) dup`, token `(` ends at the following space. The loop at
`03FD` reads raw characters until `)` or zero. It does not seek a separate
`)` token, count nesting, or tokenize the comment. The closing parenthesis
is consumed; the jump to `03C1` resets length and begins the next ordinary
token. This call eventually returns the pair for `dup`, never a pair for
`(` or `note`. `)` can be adjacent to text inside the comment.

For `\ note` followed by line feed and `dup`, the one-byte marker's ending
space is still in DL. The line loop checks that already-read byte before
asking for another. After reading through `note` and the line feed, it
restarts at `03C1`. If the marker itself ended at line feed, the first check
restarts immediately, preserving the following line for tokenization.
A carriage return is whitespace for token termination but is not the line
comment's stopping byte: the loop seeks `0A` or zero.

These restarts are JMPs, not recursive CALLs, so skipping many comments does
not accumulate one return address per comment. Length resets on each
restart. For end-of-file inside a comment, zero triggers a restart, which
performs another read; with stable EOF it returns `[prefix,T,0]`. There is
no distinct “unterminated parenthesis” error. Nor should that extra read be
forgotten when considering streams whose zero/error behavior differs from
the normal assumption.

### EOF and the 256th stored byte

EOF before any token reaches `041D` with RBX zero and still pushes both T
and zero. EOF after `dup` first returns `[prefix,T,3]`; a later call returns
zero length under stable EOF. This makes an unterminated final ordinary
token usable. An input NUL is indistinguishable at these tests. In the normal
REPL, a NUL encountered before a token produces zero length and the loop exits;
the rest of that stream is not thereby certified absent.

The limit check is `test bh,bh`. BH is bits 8–15 of RBX, with no REX prefix
on this instruction. Starting from zero and increasing one at a time, lengths
1 through 255 keep BH zero. On the next iteration:

```text
Before store: rbx=255, dl=the 256th byte
03CE:         T[255] receives that byte
03D4:         ebx becomes 256 (0x00000100), so bh=1
03D6/03D8:    nonzero test branches to fatal_token at 0x400477
```

The accepted maximum is 255, but the rejected token's **256th byte is already
stored**. No further character or delimiter is read before failure. If the
input had 300 non-whitespace bytes, reporting uses the retained first 256,
not all 300. The buffer region extends to the sysvar page at `0x413000`,
providing 2048 bytes from T; the fatal report's 258-byte span fits there.
That local size fact is not a general bounds check for unrelated writes.

**Stop/resume.** Retain two independent results of reading `dup`: the returned
pair `[T,3]` and `rbx=3`. Explain why the address can become stale as text,
why EOF has ZF=0 in read_char, and why a 256-byte token never returns normally.

## Reporting is a write; fatal reporting exits

[`report_token`, 30 bytes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L468-L477),
uses RBX and the shared buffer, not a fresh stack pair:

```text
offset range    bytes                           decoded instruction
[0459,0462)   66 C7 83 00 28 41 00 3F 0A      mov word [rbx+0x412800], 0x0A3F
[0462,0465)   8D 53 02                        lea edx, [rbx+2]
[0465,046A)   BE 00 28 41 00                  mov esi, 0x412800
[046A,046F)   B8 01 00 00 00                  mov eax, 1
[046F,0474)   BF 01 00 00 00                  mov edi, 1
[0474,0476)   0F 05                           syscall
[0476,0477)   C3                              ret
```

For the missing token `herd`, RBX still holds four after find. The first
instruction writes little-endian word `0x0A3F` at `T+4`, placing question mark
`3F` followed by line feed `0A`. LEA sets EDX to six. The following moves
prepare `write(1,T,6)`, and SYSCALL attempts to write `herd?` plus newline to
**stdout**, not stderr. The syscall result in RAX is not checked or retried;
short writes and errors need not produce the complete intended message.

RDI now contains descriptor one, not the Forth value that was cached there.
RBP is unchanged, so this is not an ordinary stack-preserving `( -- )`
primitive despite the helper's convenient source comment. In the normal
REPL miss path, the returned zero from find is expendable: after reporting,
the caller loads the previous top from `[rbp]` and advances RBP. That explicit
cleanup repairs the cached-top invariant. Arbitrary callers must account
for the clobber rather than treating report_token as transparent.

[`fatal_token`, 17 bytes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L478-L483),
is a separate assigned region, including its own call and exit syscall:

```text
offset range    bytes                           decoded instruction
[0477,047C)   E8 DD FF FF FF                  call 0x400459
[047C,0481)   B8 3C 00 00 00                  mov eax, 60
[0481,0486)   BF 02 00 00 00                  mov edi, 2
[0486,0488)   0F 05                           syscall
```

Its CALL reports the retained token, then EAX becomes 60 and EDI becomes two.
The resulting raw Linux exit syscall terminates the calling thread; in this
single-thread seed it ends the process with status two under the ordinary
host contract. There is no RET. On an overlong token, reporting attempts 258
bytes, then termination proceeds even if the write failed. The invalid
literal path also uses this helper; its numeric parsing is opened later.

An ordinary dictionary miss in the REPL reports and reads on, including in
compile mode. That does not undo code already emitted, finish a partial
definition, or restore HERE, LATEST, or STATE to an earlier snapshot. Fatal
reporting supplies no rollback either. We have identified actual control
paths, not established safe recovery from arbitrary bad source.

## Tick joins reading to lookup

Finally, [`tick_code`, ten bytes](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L511-L514),
implements `'` by composing the helpers:

```text
offset range    bytes                           decoded instruction
[04D8,04DD)   E8 E4 FE FF FF                  call 0x4003C1
[04DD,04E2)   E9 21 FE FF FF                  jmp 0x400303
```

If the next ordinary token is `dup`, read_word leaves `[prefix,T,3]`, and
find replaces that pair with `0x4000C7` in the initial dictionary. Tick does
not execute dup. A miss leaves zero and does not itself report an error.
The last instruction is a tail JMP: find's RET uses tick's caller's return
address. At stable EOF the length-zero lookup misses this initial dictionary;
a caller that blindly executes its result is still responsible for that
invalid target. Tick adds no guard of its own.

## Practice: predict before consulting the checks

Use the [hints and checked solutions](../practice/15-solutions.md) one step
at a time. All problems are paper inspections under the chapter's normal
memory and input assumptions. Mark the step you can explain independently;
reading a correct trace beside yours is a different achievement.

1. **S15-01 — Rebuild identity.** Reconstruct `0branch`'s full header bytes,
   derive its xt, and follow two links. Then explain whether a newly defined
   `dup` redirects a CALL already targeting `0x4000C7`.
2. **S15-02 — Follow a partial match.** Use `[99,T,4]` with token `herd`.
   At the `here` candidate, complete the four-byte comparison trace. Predict
   RDI, RBP, and LAST_FOUND after the full miss, assuming a preceding hit
   stored `0x400359`. Identify the REPL branch that prevents stale flags use.
3. **S15-03 — Separate cell, cursor, and target.** Start with HERE=`0x401000`,
   stack `[99,0x1234]`. Trace comma, then here; separately trace latest and
   latest-fetch from `[99]`. From `[99,65,emit-xt]`, show execute's registers
   and return destination immediately before its jump.
4. **S15-04 — Preserve two input results.** Trace read_char for vertical tab
   `0B` with old top 99, including its temporary stack change. Then predict
   the first ordinary token returned from `( note ) dup`, from `() dup`,
   and from a lone backslash followed immediately by line feed and `dup`.
5. **S15-05 — Diagnose a boundary promise.** Someone claims: “A 256-byte token
   is truncated to 255, returned with a NUL terminator, and safely skipped if
   lookup fails.” Use the instructions to correct every part. Give the
   attempted report span, exit status, and buffer-lifetime restriction.

## What these 816 bytes establish

The [source ledger](../source-audit.csv) assigns this chapter 43 regions:
32 headers totaling 421 bytes; find/here/comma/execute/state/latest/tick
bodies totaling 196; and read_word/read_char/report_token/fatal_token totaling
199. Every header can be reconstructed from the ledger above, and all 395
non-header bytes appear in instruction listings. The total is 816, without
borrowing bytes already assigned to another chapter.

The main invariant crosses the interfaces: a reader supplies borrowed bytes
and a length; search turns them into header identity plus code identity;
execute consumes code identity after restoring the target's data top.
The flags, cursor addresses, stale lookup metadata, and input/error limits
are part of that explanation, not exceptions to hide.

Next, [the native colon compiler](16-native-colon-compiler.md) constructs
these same header fields and emits calls and literal data. We can now ask
exactly which bytes a definition appends, because we know what a valid name,
header, code address, and emission cursor mean in this seed.
