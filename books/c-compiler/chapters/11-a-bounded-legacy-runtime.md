# 11. A bounded legacy runtime

`putchar('*')` looks like one operation. The generated program must turn its argument into a byte in readable memory, put a descriptor and byte count into Linux's registers, request a write, recover its stack, and return a result. The name alone does not tell us what that result means. In this runtime, a successful one-byte `putchar` returns **one**, not the star's value, 42.

This chapter opens those small runtime bodies. By the end, you should be able to predict each supported name's request and result, trace the inline heap state, and identify the assumptions that make a buffer or string operation meaningful. You should also be able to explain why sharing familiar C-library names does not establish a hosted C library.

**Edition and evidence.** The implementation is the default legacy direct-ELF profile at [`7d7e1996d1753118181d43e1a413960d3a1ec24b`](https://github.com/delta9000/seed-forth/tree/7d7e1996d1753118181d43e1a413960d3a1ec24b). Our primary bodies are [`090`, runtime emitters](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L535-L1003), with registration and entry code in [`116`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L585-L884). Results below are source-based paper derivations. No compiler, generated program, Forth example, build, or Linux bootstrap was executed to establish them. Kernel interface references specify the boundary; they do not demonstrate that an emitted executable reached it.

## Choose a useful route

For a short first pass, read **Two times, two register contracts**, **Follow one star**, **A partial transfer**, and **One mapping, a moving pointer**. Finish with C11-01, C11-04, and C11-05. The registration detail and compact reference cards remain available when you need another name.

The prerequisites are [C09's byte and address coordinates](09-instructions-inside-an-executable.md), [C10's calls and deferred addresses](10-calls-literals-and-deferred-addresses.md), and the distinction between a request and progress from [Linux I/O contracts](../../seed-forth/chapters/07-linux-io-contracts.md). Here is an entry check:

1. A `CALL` starts at file offset 700 and occupies five bytes. From which offset is its relative displacement measured?
2. A buffer has capacity 12; a read requests eight bytes and reports three. How many bytes are newly supplied input?
3. At a restricted generated-function boundary, where does argument four arrive? Does the Linux syscall interface use the same register?

The [entry-check feedback](../practice/11-solutions.md#entry-check) is separate. If these distinctions are secure, skip the refreshers and try the mixed exercises. If they blur together, keep two snapshots on paper: builder output coordinates and generated-machine state. They describe different times.

All offsets here count **bytes**, decimal unless prefixed by `0x`. Hexadecimal byte pairs such as `2A` represent stored bytes. Registers are 64-bit unless their name says otherwise: `eax` is the low 32 bits of `rax`, and writing `eax` clears the upper 32 bits. Memory spans `[A,A+n)` include A and exclude A+n. Assume valid stack storage, valid return addresses, and bounded, nonwrapping arithmetic for successful traces unless a limit is explicitly examined.

## Two times, two register contracts

A **shim** is a small adapter between interfaces. The Forth word `cc-emit-putchar-shim` runs in the builder and appends bytes. Those bytes later run in the generated process. Calling the emitter does not write a star to that process's stdout, and the generated shim does not call the builder's Forth `write` word.

The default function-call path puts up to six integer or pointer values in these registers:

| Position | Generated-function argument | Linux syscall argument |
|---:|---|---|
| 1 | `rdi` | `rdi` |
| 2 | `rsi` | `rsi` |
| 3 | `rdx` | `rdx` |
| 4 | `rcx` | `r10` |
| 5 | `r8` | `r8` |
| 6 | `r9` | `r9` |

Before `SYSCALL`, `rax` identifies the operation. On an ordinary return, `rax` contains its result. `SYSCALL` overwrites `rcx` and `r11`; it does not push a normal `CALL` return address onto the user stack. These Linux/x86-64 details are explicit in the [versioned kernel entry comments](https://github.com/torvalds/linux/blob/v6.12/arch/x86/entry/entry_64.S#L47-L75). Our small bodies arrange their own arguments before crossing that boundary.

An ordinary generated function returns a scalar in `rax`; the caller's `48 89 C7` then copies it to `rdi`, the expression-result register. That move does not reinterpret bytes as characters, convert counts to elements, or normalize an error. The called body decides what `rax` means.

A **file descriptor**, or fd, is a small integer identifying an open endpoint in this process. Descriptor 0 conventionally denotes stdin and 1 stdout; neither must be a terminal or even remain open. Here, the `fp` argument to `fputs` and its relatives is used as that integer. These bodies never dereference a hosted `FILE` structure. The legacy typedef registrations admit familiar spellings such as `FILE` and `size_t` by mapping them to the legacy integer type; that is no promise of hosted stream layout or standard fixed-width typedef sizes. See [`cc-emit-libc-typedefs`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L815-L846).

### The entry stub is the first caller

Linux starts at the executable's entry address, not at the C function named `main`. C09's 120-byte header places the 26-byte entry stub at file offset 120. Under the stated Linux initial-stack contract, the stub reads argc from `[rsp]`, forms argv as `rsp+8`, and calls the resolved `main`. On return it copies `rax` to `rdi`, puts 60 in `rax`, and issues the exit syscall. Those are the operations emitted by [`cc-emit-entry-stub`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L585-L622).

With an initially 16-aligned stack and no intervening stack change, that first `CALL` makes `main` enter with `rsp` eight bytes below the original value. This local fact is not a proof of every later nested call's alignment or of general ABI interoperability. The stub supplies no third `envp` argument and contains no hosted initialization, constructor walk, buffered-stream flush, or exit-handler mechanism. In C01's bounded, single-threaded triangle trace, a returned sixteen becomes the argument of exit. It does not print `16`.

## Which bodies are present, and who owns their bytes?

There are **sixteen emitter definitions** in the runtime region of `090`, supplying **nineteen callable names**. The difference comes from `cc-emit-syscall-shim`: four providers specialize the same shape for `open`, `read`, `write`, and `close`.

Eleven bodies are **eager**: [`cc-emit-shims`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L659-L740) registers each name with the current target address, then emits its body. The records use the legacy integer result type except for void `exit` and `free`; the eight-byte result can carry an address without supplying a hosted library signature. This happens before user functions are parsed. Even an unused eager name occupies bytes.

| Eager order | File start | Region length | Next file offset |
|---|---:|---:|---:|
| `putchar` | 146 | 29 | 175 |
| `exit` | 175 | 10 | 185 |
| `getchar` | 185 | 48 | 233 |
| `fputs` | 233 | 33 | 266 |
| `fputc` | 266 | 29 | 295 |
| `fopen` | 295 | 51 | 346 |
| `fclose` | 346 | 12 | 358 |
| `fwrite` | 358 | 20 | 378 |
| `fread` | 378 | 30 | 408 |
| `calloc` | 408 | 113 | 521 |
| `free` | 521 | 1 | 522 |

This is a derived layout: 120 header bytes + 26 entry bytes + 376 eager bytes = 522. `calloc`'s region includes sixteen data bytes, not 113 instruction bytes. There is no claimed compiled `tri.c` file size here. The stale comment naming `fputc` as thirty bytes is not the append count: its instructions occupy twenty-nine.

These bytes have several owners at different times:

- The builder owns `cc-out-buf`, where it appends and patches the image
- The output file contains shim instructions and the two initial heap-state cells
- After loading, the generated process reads the instructions and mutates its mapped heap-state cells; C09's single load segment has read, write, and execute flags
- A successful runtime `mmap` supplies a separate generated-process heap mapping. Its 256 MiB are not appended to the executable and are not the builder's arena or globals buffer

Writing a heap-state cell at runtime does not rewrite the stored executable file. Nor does a callable address identify a Forth execution token. C10's coordinate distinctions still apply.

### Late names wait for a call or an address

The eight remaining names are `malloc`, `open`, `read`, `write`, `close`, `strlen`, `memcpy`, and `strrchr`, in that table order. [`cc-late-shims`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L757-L804) has one 32-byte builder-side row per name:

| Row offset | Eight-byte field |
|---:|---|
| 0 | Pointer to raw name bytes |
| 8 | Name length |
| 16 | Forth emitter execution token |
| 24 | Symbol ID, filled during registration |

A zero name-pointer cell ends the table. The name bytes created by `cc-name-*` have no length prefix; registration passes their lengths separately. `cc-register-late-shims` installs function symbols with unresolved address zero and stores their IDs in the rows. The other row fields remain builder metadata, never generated heap data.

After user functions, the emission pass tests **both** pending-list heads:

```forth
    dup [lit] 24 + @                               ( row id )
    dup cc-sym-call-fixups @  over cc-sym-addr-fixups @  or if,
      cc-here-vaddr over cc-sym-val cell[] !
      dup cc-sym-call-fixups @ cc-here-vaddr cc-walk-and-patch-to-vaddr
      dup cc-sym-addr-fixups @ cc-here-vaddr cc-walk-and-patch-imm64-to-vaddr
      [lit] 0 over cc-sym-call-fixups !
      [lit] 0 over cc-sym-addr-fixups !
      over [lit] 16 + @ execute
    then,
```

The excerpt is the inner body of `cc-emit-late-shims`. If either head is nonzero, it assigns the current target address, patches relative calls and absolute address loads with their respective walkers, clears both heads, then executes the emitter token. Merely taking an unresolved function's address is enough. A user definition that already resolved both lists removes this need; a wholly unused prototype also has no waiting sites.

`cc-emit-open-shim`, `cc-emit-read-shim`, `cc-emit-write-shim`, and `cc-emit-close-shim` supply syscall numbers 2, 0, 1, and 3. `cc-emit-malloc-late` obtains the registered `calloc` target for its tail jump. The other rows name their direct emitters. A program with no pending use emits none of these late bodies.

One extra raw name, `cc-name-memset`, is only an external prototype on this path. It supplies no twentieth body. A remaining call **or address** fixup reaches error 206 in [`cc-check-fns-defined`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L812-L884); missing `main` reaches 207. Recognizing a spelling and supplying an implementation are different steps.

## Follow one star

Use C01's `putchar('*')`, with ASCII star value 42. Literal preparation emits:

```text
48 C7 C7 2A 00 00 00       mov rdi, 42
```

The eager layout gives `putchar` file offset 146, target address `0x400092`. For relative-call arithmetic, use a **separate paper callsite** at offset 1024, already holding `rdi=42`. This chosen location is beyond the eager block. It is a manually composed coordinate fixture, not a claim about the complete compiled triangle image.

The five-byte call ends at offset 1029. Its displacement is `146−1029 = −883`, whose low four little-endian bytes are `8D FC FF FF`. The call and result transfer are therefore:

```text
E8 8D FC FF FF             call putchar
48 89 C7                   mov rdi, rax
```

Changing the paper callsite changes the displacement. It does not change the shim's identity or make its target a builder-buffer address.

### The stack owns the temporary byte

Let the caller's `rsp` immediately before `CALL` be S, at a valid call boundary. `CALL` stores its return address at S−8 and enters the shim with `rsp=S−8`. The first instruction, `PUSH RDI`, stores the eight-byte value 42 at S−16. Little-endian storage makes its first byte `2A`; seven zero bytes follow. Only the first byte is requested for output.

These are the exact instruction bytes from [`cc-emit-putchar-shim`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L549-L571), decoded as data for this trace:

| Shim offset | Bytes | Instruction and newly established fact |
|---:|---|---|
| 0 | `57` | `push rdi`: scratch starts at S−16 |
| 1 | `48 C7 C0 01 00 00 00` | `mov rax,1`: request number is write |
| 8 | `48 C7 C7 01 00 00 00` | `mov rdi,1`: destination is fd 1 |
| 15 | `48 89 E6` | `mov rsi,rsp`: buffer is S−16 |
| 18 | `48 C7 C2 01 00 00 00` | `mov rdx,1`: request one byte |
| 25 | `0F 05` | `syscall`: returning result replaces `rax` |
| 27 | `5F` | `pop rdi`: recover saved 42; `rsp=S−8` |
| 28 | `C3` | `ret`: consume original return address; `rsp=S` |

The byte lengths add to 29. There are three distinct ones before the request: syscall number, descriptor, and count. None is the character value. The pushed eight-byte object supplies addressable storage for an interface that expects a buffer pointer rather than a byte in a register.

Assume the kernel reports one byte written. `rax=1` survives the `POP` and `RET`; the caller's result move then makes `rdi=1`. The temporary restoration of 42 inside the shim is not its returned result. The triangle ignores that result, which is sufficient for its paper drawing trace under successful writes.

If the returning kernel instead reports raw −9, that value likewise survives. Linux represents raw syscall errors as negative error numbers; there is no automatic user-space `errno` store. The [kernel result helpers](https://github.com/torvalds/linux/blob/v6.12/arch/x86/include/asm/syscall.h#L42-L71) distinguish those error patterns from ordinary results. Our chapter compares three different adapter policies:

| Supplied raw write result | `putchar('*')` returns | `fputc('*',fd)` returns | `write(fd,B,1)` returns |
|---:|---:|---:|---:|
| 1 | 1 | 42 | 1 |
| 0 | 0 | 42 | 0 |
| −9 | −9 | 42 | −1 |

For the last column, B contains `2A` and is readable. `fputc` reloads the saved low byte unconditionally; the generic `write` shim changes any negative result to −1. A name beginning with `f` does not predict either policy.

**Checkpoint.** Keep S and the two stack slots visible. Can you explain why popping the scratch does not consume the call's return address? If not, compare the two pushes rather than rereading the syscall numbers.

## Reading one character: zero is a separate branch

[`cc-emit-getchar-shim`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L584-L623) also pushes `rdi` for scratch, then requests `read(0,rsp,1)`. Afterward it executes `TEST RAX,RAX` and `JNZ`. The test asks whether the result is zero, **not whether it is positive**.

- A successful one-byte read follows the nonzero branch and zero-extends the scratch byte into `rax`. Input byte `FF` therefore yields 255
- A returned zero follows the other branch, loads −1, and skips the byte load. For this nonzero-count ordinary input request, that is the EOF path
- A negative result also follows the nonzero branch. The shim reads scratch instead of returning the error

For a precise failure fixture, supply incoming `rdi=42` and assume a raw −9 result with no scratch-byte change. The pushed low byte remains `2A`, so the shim returns 42. Without a supplied scratch value and memory effect, no particular returned byte follows. A no-argument source call does not establish that the incoming register or reserved byte is zero.

The byte load is `48 0F B6 04 24`. Its final `24` is a SIB addressing byte selecting `[rsp]`, not a displacement of 36. SIB means scale/index/base: x86 uses it here to express a stack-pointer base with no index. Chapter 9's instruction fields let us distinguish that address from the byte stored there.

Thus EOF and failure must be traced separately even though neither supplies a new character. This is a statement about the existing branch, not a request to redesign it. None of these paths appends a string terminator to a user buffer or maintains a stream error flag.

## A partial transfer keeps bytes and elements apart

Take a writable twelve-byte buffer B and an open descriptor 7. Supply the generated-function arguments for `fread(B,4,3,7)`:

```text
rdi = B        rsi = 4        rdx = 3        rcx = 7
```

The [`fread` body](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L778-L813) first pushes size 4. It multiplies size by count, moves twelve to `rdx`, B to `rsi`, and descriptor 7 to `rdi`. It clears `eax` for syscall zero. Before the request, the state is therefore `read(7,B,12)`.

Suppose that one read supplies ten bytes. A short successful read is permitted by the [Linux read contract](https://kernel.googlesource.com/pub/scm/docs/man-pages/man-pages/+/44930b7b8eacbfff12acd1dcfbb66dd818e35254/man/man2/read.2); twelve requested is not twelve obtained. The shim pops the saved size into `rcx`, replacing the syscall-clobbered register with a known divisor. Since `rax=10` is positive, it clears `edx` and performs unsigned `DIV RCX` on `rdx:rax`. The quotient is 2 and remainder 2. The function returns the quotient, two complete four-byte elements.

Ten bytes were nevertheless transferred into `[B,B+10)`. Eight of them form the two complete elements counted by the return value; two are a partial third element. Nothing in this body undoes that partial transfer or supplies the remaining two bytes. The region `[B+10,B+12)` has not gained valid new input from this request. There is also no trailing-NUL store. Do not hand B to a string scan merely because the read returned nonnegative.

Now change only the operation to `fwrite(B,4,3,7)` and require B's twelve bytes to be readable. The [`fwrite` body](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L758-L776) requests one twelve-byte write. A supplied raw result of ten is returned as **ten bytes**, with no division. Its return unit differs from `fread`'s positive-result unit.

For `fread`, zero and negative results bypass division and return unchanged. For `fwrite`, all returning raw results pass through. Both bodies multiply sizes without an overflow check and make one request, without a progress loop or interruption retry. Our successful example uses a positive size and an unoverflowed product fitting the actual buffer. A zero product still reaches a zero-count syscall; the body does not short-circuit before it. In `fread`, a zero or negative result skips division, so zero size alone is not evidence that division by zero executes.

### Reference cards: character, file, and process operations

These cards complete the contracts needed alongside the worked traces. Arguments are in the generated-function order; returned values are in `rax` unless the operation does not normally return. A raw negative result means the body preserves the kernel error pattern, not that it sets `errno`.

**`putchar(c)` — `cc-emit-putchar-shim`, 29 bytes.** Push c, write its low byte to fd 1, pop the scratch, return the raw write result. Stack storage must be valid. It makes no output-buffering or full-success promise beyond the supplied result.

**`getchar()` — `cc-emit-getchar-shim`, 48 bytes.** Read one byte from fd 0 into pushed scratch. Zero becomes −1; every nonzero result selects a zero-extended scratch byte. The error limitation is the nonzero test described above.

**`fputc(c,fp)` — `cc-emit-fputc-shim`, 29 bytes.** Push c, move the descriptor from `rsi` to `rdi`, use `rsp` as the one-byte buffer, and issue write. Then `0F B6 04 24` loads the saved byte into `eax`, clearing the high half of `rax`; `POP RCX` discards scratch. It returns c's low byte even when the supplied write result is negative. Count the emitted lengths `1+7+3+3+7+2+4+1+1=29`, despite the source's thirty-byte comment. See [the body](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L670-L695).

**`fputs(s,fp)` — `cc-emit-fputs-shim`, 33 bytes.** Save s and the descriptor, count bytes through the first NUL, then issue one write of the preceding bytes. The terminator is scanned but not written, and no newline is added. `rdx` counts the length; `0F B6 0C 17` reads `[rdi+rdx]`, with SIB `17` selecting an unscaled `rdx` index and `rdi` base. The descriptor is restored into `rdi`; the string pointer becomes `rsi`. Return the raw byte count or raw error. The entire scan through the terminator must be readable, and a positive result smaller than the length is partial progress. See [the body](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L631-L668).

**`fopen(path,mode)` — `cc-emit-fopen-shim`, 51 bytes.** Push the path in `rdi`, load only `mode[0]` into `eax`, and form flags in `esi`: `w` selects flags 577 (`0x241`, write/create/truncate); `a` selects 1089 (`0x441`, write/create/append); every other byte selects zero, read-only. It pops the saved path back into `rdi` and puts creation mode 420, octal `0644`, in `edx` for raw open syscall 2. A negative result becomes zero; nonnegative descriptors are unchanged. Therefore successful fd 0 and failure have the same returned representation. `r+` selects read-only because the plus is never read; `wb` takes the same branch as `w`. The path must be readable through its NUL; mode must at least have a readable first byte. There is no validation of the remainder, stream object allocation, or buffering. See [the body](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L697-L743).

**`fclose(fp)` — `cc-emit-fclose-shim`, 12 bytes.** With the descriptor already in `rdi`, issue close syscall 3, clear `eax`, return zero. The zero does not certify a successful close; any returning error was overwritten. Closing is meaningful only for a descriptor the caller is responsible for releasing. See [the body](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L745-L756).

**`fwrite(ptr,size,n,fp)` / `fread(ptr,size,n,fp)` — `cc-emit-fwrite-shim` / `cc-emit-fread-shim`, 20 / 30 bytes.** Both move argument four out of `rcx` before the syscall and request `size*n` bytes. Write requires a readable source and returns raw bytes/error; read requires a writable destination and divides only a positive result by the saved size. Neither checks capacity or arithmetic overflow. The preceding trace supplies the intermediate states rather than a libc equivalence.

**`open(path,flags,mode)`, `read(fd,buf,count)`, `write(fd,buf,count)`, `close(fd)` — `cc-emit-syscall-shim`, 20 bytes each.** The first three arguments already occupy the needed syscall registers. The providers set numbers 2, 0, 1, and 3. The shared body loads `eax`, requests the operation, tests the sign of `rax`, changes any negative result to −1, and returns. It does not store an error number, retry, or process a stream object. Read and write counts remain bytes; zero read with positive requested count is the ordinary EOF case, while a zero-count request establishes no new input. Open uses the caller's flags and mode rather than `fopen`'s first-byte translation. The length is `5+2+3+2+7+1=20`, not the stale twenty-two-byte comment. See [the shared body](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L907-L927).

**`exit(n)` — `cc-emit-exit-shim`, 10 bytes.** Put 60 in `rax`, leave n in `rdi`, issue the syscall. Its final `RET` is not the expected successful path. There is no stdio flush or `atexit` walk. Our process-ending description assumes this single-threaded program; raw syscall 60 terminates the calling thread, and Linux exposes the low eight status bits to the waiting parent. See [the shim](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L573-L582) and [the versioned exit implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/exit.c#L988-L1002).

## One mapping, a moving pointer

The runtime `calloc` owns a **bump allocator**: return the current position, then advance that position by a rounded size. It is separate from C02's builder arena. The body contains 97 instruction bytes followed immediately by two eight-byte cells. Initially both contain zero because the emitter appends explicit zeros:

```forth
  [lit] 195 cc-emit-byte                          \ ret
  [lit]   0 cc-emit-8le                           \ heap_base = 0
  [lit]   0 cc-emit-8le ;                         \ heap_pos  = 0
```

This is the end of [`cc-emit-calloc-shim`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L815-L896). `heap_base` is at offset 97 within the region and `heap_pos` at 105. In the eager layout, their file offsets are 505 and 513, hence target addresses `0x4001F9` and `0x400201`. These cells are file-backed runtime state; the heap payload they will point to is elsewhere. There is no extra alignment padding before the cells.

### First establish a usable heap

At entry, `calloc(n,size)` saves both arguments with `PUSH RDI` and `PUSH RSI`. It loads `heap_base` and tests it. A nonzero value skips mapping. On the zero path, the body supplies this Linux request:

| Register | Value | Role |
|---|---:|---|
| `rax` | 9 | mmap syscall number |
| `rdi` | 0 | Let the kernel choose an address |
| `rsi` | 268,435,456 | Length: 256 MiB |
| `rdx` | 3 | Read/write protection |
| `r10` | 34 (`0x22`) | Private, anonymous mapping |
| `r8` | `0x00000000FFFFFFFF` | fd field, unused for this anonymous mapping |
| `r9` | 0 | Offset |

The `r8` value deserves precision. `41 B8 FF FF FF FF` writes **R8D**, so it clears the upper half. It does not independently establish a 64-bit all-ones register. The anonymous mapping contract is the relevant reason no backing fd is used. Linux's versioned [`mmap` manual](https://github.com/mkerrisk/man-pages/blob/man-pages-5.13/man2/mmap.2) documents the anonymous zero initialization and ignored fd; the shim's constants describe this Linux-specific case, not a portable mapping API.

Assume this request succeeds at nonzero address H and the resulting mapping remains accessible. The body stores H into both inline cells. It then restores size into `rsi` and n into `rdi`. Later calls see nonzero `heap_base` and reuse that same mapping; there is no per-allocation mapping or automatic extension.

### Then claim a bounded slice

With `heap_pos=H`, trace `calloc(3,5)` under these additional premises: product, rounding addition, and pointer advance do not overflow; at least sixteen mapped bytes remain; allocations are serialized; and previous callers have respected their bounds.

| Transition | State after it | Reason |
|---|---|---|
| `imul rdi,rsi` | `rdi=15` | Requested bytes are 3×5 |
| `add rdi,7` | `rdi=22` | Prepare upward eight-byte rounding |
| `and rdi,-8` | `rdi=16` | Clear the lowest three bits |
| Load `heap_pos` | `rax=H` | Preserve the address to return |
| Copy to `rcx`; add `rdi` | `rcx=H+16` | Compute next position |
| Store `rcx` in `heap_pos` | State cell contains H+16 | Claim the rounded interval |
| `ret` | Return H | `rax` still contains the old position |

Fifteen bytes were requested; sixteen bytes were consumed from the allocator's interval. Starting from an aligned mapping and advancing by multiples of eight preserves eight-byte alignment. It does not establish every stronger alignment a different ABI or object type might require.

Where do zeros come from? A successful anonymous mapping starts zero-filled. The allocator's monotonic, non-overlapping slices have not yet been handed to earlier callers, so valid earlier writes cannot have changed them. There is no clearing loop on each `calloc` call. That explanation depends on fresh slices, bounded writes, and no pointer wrap; changing any of them breaks the argument.

The source's short “zeroed memory or NULL” comment is not a sufficient failure contract. This body does not test the mmap result for error before storing it, check multiplication or rounding overflow, compare the next position to the mapping end, or synchronize concurrent calls. A negative mmap result is saved as nonzero heap state and used by the subsequent arithmetic; there is no guaranteed NULL conversion or remapping recovery. We therefore make no valid-allocation prediction outside the successful, in-range premises above.

A zero product rounds to zero and leaves the position unchanged. Even if the first such request causes mapping, repeated zero-size calls need not return distinct addresses. `free` cannot improve the available-space story because it does not reclaim anything.

### Optional depth: RIP-relative fields keep code and state together

A RIP-relative address adds a signed displacement to the address **after** the instruction. If C is the target address of the first `calloc` byte, its first state load begins at C+2 and occupies seven bytes. Displacement 88 therefore selects `C+2+7+88 = C+97`, the base cell.

The full local calculation is short enough to inspect:

| Instruction starts at region offset | Length | Displacement | Target offset | Operation |
|---:|---:|---:|---:|---|
| 2 | 7 | 88 | 97 | Load base |
| 48 | 7 | 42 | 97 | Store mapping result as base |
| 55 | 7 | 43 | 105 | Store mapping result as position |
| 76 | 7 | 22 | 105 | Load current position |
| 89 | 7 | 9 | 105 | Store next position |

For example, `48 89 0D 09 00 00 00` at offset 89 stores `rcx` at `C+96+9`, not `C+89+9`. The `RET` occupies offset 96, and the data begins at 97. The conditional `JNZ` at 12 ends at 14; its displacement 48 reaches 62, the argument-restoration path after the mapping stores.

Moving the whole 113-byte region intact leaves these internal distances unchanged. Inserting bytes inside it can change them. The entry address and external calls still require their own correct coordinates; local position-relative addressing does not make the entire executable position-independent.

### Allocation reference cards

**`calloc(n,size)` — `cc-emit-calloc-shim`, 113-byte region.** Save two arguments, initialize one 256 MiB anonymous mapping when the saved base is zero, restore arguments, round the product to eight bytes, return old position, store the advanced position. Ninety-seven code bytes and sixteen inline data bytes form one closed region. The safe success domain and missing checks are stated above.

**`malloc(n)` — `cc-emit-malloc-shim`, 12 bytes.** Set `rsi=1`, then `JMP rel32` to the selected `calloc` target. This is a **tail jump**: it adds no return address. `calloc` eventually returns directly to the original caller using the address already on the stack. Its relative field uses the same next-instruction rule as C10. It inherits the same bounded heap behavior; there is no separate malloc arena. See [the emitter](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L929-L937).

**`free(p)` — `cc-emit-free-shim`, one byte `C3`.** Return without examining p or touching heap state. It has no specified useful result value, deallocation, clearing, or reuse mechanism. Calling `free(H)` after the trace cannot move `heap_pos` back from H+16. See [the entire body](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L898-L900).

**Pause point.** Save `heap_base=H`, `heap_pos=H+16`, and “one successful 256 MiB mapping.” On returning, predict the next position after `malloc(9)` before looking at the solution for C11-05. You do not need to reconstruct mmap's six arguments to resume the bump calculation.

## Three routines stay inside memory

The remaining string and memory bodies make no syscall. Their names do not remove the need to establish readable and writable spans.

Supply a readable region A holding these bytes:

```text
address       A    A+1  A+2  A+3
byte          2A   61   2A   00
meaning       *    a    *    terminator
```

### Count to the first zero

[`cc-emit-strlen-shim`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L939-L957), fourteen bytes, clears `eax` to start a count. `80 3C 07 00` compares `[rdi+rax]` with zero: SIB `07` selects `rax` as unscaled index and `rdi` as base. It increments `rax` only for a nonzero byte.

The comparisons at counts 0, 1, and 2 find nonzero bytes; count 3 finds NUL and returns three. Four bytes had to be readable, although the returned length is three. No maximum length travels with the pointer and no bound check stops an unterminated scan. This is why read capacity alone cannot justify a call to `strlen`.

### Remember the last match, including the terminator

[`cc-emit-strrchr-shim`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L973-L1003), twenty-three bytes, clears `eax` for a no-match result and scans with `rdi` as its cursor. It loads one byte into `ecx`, compares `cl` with `sil`, records `rdi` in `rax` on equality, then tests whether the loaded byte is zero.

For `strrchr(A,'*')`, the remembered pointer changes from zero to A at the first byte, remains A at `a`, then becomes A+2 at the second star. The terminator ends the scan; A+2 is returned. Searching for absent `b` returns zero. Searching for byte zero records A+3 **before** the end test and therefore returns the terminator's address. Only the low byte of the second argument participates in the comparison.

The instruction `40 38 F1` includes a REX prefix so its byte-register operand is `sil`. It does not compare the entire 64-bit character argument. As with `strlen`, the complete scan through NUL must be readable; zero as the initial result does not provide a safe response to an invalid pointer.

### Copy an explicit count, with the direction stated

[`cc-emit-memcpy-shim`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L959-L971) is nine bytes:

```text
48 89 F8       mov rax,rdi
48 89 D1       mov rcx,rdx
F3 A4          rep movsb
C3             ret
```

Take a disjoint writable four-byte destination D and `memcpy(D,A,4)`. The first move saves the original D as the result. The second puts four in the repetition counter. With the processor's **direction flag**, DF, clear, each `MOVSB` copies `[rsi]` to `[rdi]` and increments both pointers. Repetition stops when `rcx` reaches zero.

After four iterations D contains `2A 61 2A 00`, `rsi=A+4`, `rdi=D+4`, and `rax=D`. The shim returns the original destination rather than the advanced cursor. It copied the terminator because the supplied count included it, not because `MOVSB` recognizes strings. A count of three would leave D's fourth byte unchanged.

DF clear is a real premise: this body contains no `CLD` instruction. With DF set, the pointers decrement instead. Require readable source extent, writable destination extent, and non-overlapping regions for the intended `memcpy` contract. This is not a `memmove` implementation; overlapping forward writes can change bytes that later iterations will read. There is no sanitizer or friendly failure branch if an access faults.

## What the small runtime establishes

We can now distinguish three questions for every name: **what bytes are requested or touched, what value is returned, and what makes those accesses valid?** Matching a familiar name answers none of those automatically.

The runtime has one-request I/O adapters, a small monotonic heap, and three direct memory routines. It has no general hosted stream state, uniform error convention, retry layer, allocator reclamation, or checked string bounds. Even a returned nonnegative value needs its unit: byte value, byte count, element quotient, descriptor, pointer, or forced zero.

The [native runtime](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/119-cc-native-runtime.fth) and [explicit System V runtime](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/122-cc-sysv-runtime.fth) belong to later profile interfaces. They are not interchangeable implementations silently selected by these names. Loading their provider layers is not permission to transfer their call, storage, or library promises to this default path.

Nor does knowing these bytes establish that the builder wrote the whole file, Linux loaded it, or the program performed a particular I/O operation. C02's output writer discards write and close results. A source-derived request trace, a completed output file, a reached entry point, and observed application behavior remain different evidence.

## Practice

Use paper states only. Do not run allocation-exhaustion experiments, execute an emitted image, or modify source for these questions. Record a value **with its role or unit**. [Hints and checked manual solutions](../practice/11-solutions.md) are available without a required waiting period.

### C11-01 — Keep the character, request, and result separate

Start from the star trace with `rsp=S` before the call. List both stack slots, the four relevant registers immediately before the write, and `rsp`, `rax`, and `rdi` after the shim returns but before the caller's result move. Do this for supplied raw results 1 and −9. Then complete the corresponding returned-value rows for `fputc('*',1)` and `write(1,B,1)`, where B contains `2A`. Explain why changing the raw result never changes the requested count.

### C11-02 — Follow the input branch

Supply incoming `rdi=0x63`. In three separate calls, read returns (a) 1 after storing byte `FF`, (b) 0 without changing scratch, or (c) −9 without changing scratch. Derive `getchar`'s result and identify the branch for each. Which results establish a newly read character? Explain why a claim that all nonpositive returns become −1 does not match the instructions.

### C11-03 — Read the mode policy literally

For separate `fopen` calls, give flags and creation-mode argument for mode strings `r+`, `w+`, and `ab`. Then compare supplied open results 0 and −13. Can the caller distinguish them from the returned value? Finally, if raw close returns −9, compare `fclose` and the late `close` wrapper. No filesystem operation is performed here.

### C11-04 — Complete the transfer accounting

Let B have a writable fifteen-byte extent and call `fread(B,3,5,7)`. A supplied read transfers eleven bytes. Finish the register preparation, division, returned value, and newly written span. Which bytes form a partial element? For a readable fifteen-byte source and the same supplied progress, what does `fwrite(B,3,5,7)` return? Repeat the return calculation for raw zero and −5, identifying which path performs division.

### C11-05 — Keep heap storage and heap payload apart

A successful existing mapping has base H and position H+24, with ample capacity. Trace `calloc(3,5)`, `free` of that returned pointer, and `malloc(9)`. Give both returned pointers and every position change. Then derive the target of the seven-byte RIP-relative load at region offset 76 with displacement 22. If the region begins at file offset 408, give the position cell's file offset and target virtual address. Explain why these are not the pointer returned by `calloc`.

### C11-06 — Transfer a string with an explicit boundary

A contains `2A 61 2A 00`; D is disjoint writable storage initially containing four `7F` bytes. With DF clear, trace `memcpy(D,A,3)`, including returned pointer and final cursors. Is `strlen(D)` justified from the resulting four known bytes? Independently derive `strrchr(A,'*')` and `strrchr(A,0)`. Name the additional premise lost if DF is set.

### C11-07 — Demand a body without calling it

After parsing, a late `strlen` symbol has call-list head zero and address-list head N. No user definition resolved it. The other late symbols have no pending sites. Describe exactly which body is emitted, which list walker matters, which heads are cleared, and the number of appended bytes. Contrast an unused `memset` prototype with a pending address use of `memset`. Why is the table's emitter token unsuitable as a generated function address?

### C11-08 — Separate three claims of success

A reader says: “The builder exited zero; `fclose` returns zero; and the allocator returned a nonzero number. Therefore the generated program was fully written, its file operation succeeded, and its allocation is valid.” For each implication, identify the missing evidence using this chapter and C02. Then explain why replacing the chapter's default-profile label with “System V libc” would not repair any implication. This is a contract diagnosis, not a request for implementation changes.

### Changed cases: fresh prompts, no answers here

After feedback, choose a case that changes the distinction you missed. These are new attempts, not instructions to copy a nearby solution.

1. **C11-01R:** Use byte value 255 and supplied raw write result zero. Predict the three adapter results and the eight scratch bytes
2. **C11-02R:** A successful read stores NUL. Compare its returned value with EOF, and say which one establishes a new byte
3. **C11-03R:** The mode's first byte is `x`; the supplied open result is 4. Derive flags and return without assuming mode validation
4. **C11-04R:** Use separate `fread(B,1,10,7)` and `fwrite(B,1,10,7)` cases with a valid ten-byte buffer and supplied positive transfer of seven bytes. What distinction between the two positive return conventions becomes numerically hidden? Then consider a zero-count read returning zero
5. **C11-05R:** Starting from position H+80, take a zero-size allocation, then `malloc(1)`. Separately move the entire calloc region twenty bytes later without changing its interior; which address calculations change?
6. **C11-06R:** Copy all four A bytes, then search the copied string for a character argument whose low byte is zero but whose full value is 256
7. **C11-07R:** A user definition has already patched and cleared both lists for `strlen`. `memcpy` has one waiting call and one waiting address. Identify emission and patching work
8. **C11-08R:** Someone supplies an observed one-byte star write from one earlier executable. State what that observation supports, and what it cannot establish about this pinned source's allocation, failure handling, or full bootstrap

## Stop with a recoverable state

A useful stopping result is the ability to trace one call through a shim without confusing its argument with its return. Save one example's registers, valid memory extent, and supplied kernel result. On a later return, reconstruct the next transition before reopening the answer. If the arithmetic is right but the meaning is wrong, write the units beside every number; if the wrong address is used, label builder pointer, file offset, and target address separately.

This chapter established bounded source-derived contracts, not measured learner mastery or executed runtime correctness. The next compiler mechanisms can now call these names under explicit assumptions rather than treating “libc” as an unexplained promise.
