# 7. Linux I/O contracts

[Previous: Memory updates and writers](06-memory-updates-and-writers.md) · [Practice help](../practice/07-solutions.md) · [Next: Defining words and phases](08-defining-words-and-phases.md)

Three bytes in memory represent `ABC`. How do they reach a program's output? Storing them with `c!` or `c,` does not send them anywhere. We need a request to the operating system, and we need to distinguish the amount requested from the amount actually transferred.

By the end, you should be able to trace the library's Linux wrappers into `syscall6`, explain each argument's role, interpret a returned count or error, and describe what a caller must remember after a partial transfer. We will not implement a retry loop before learning control flow.

## Choose your route

Bring the address/value distinction from [Chapter 2](02-addresses-and-bytes.md), signed cell interpretation from [Chapter 3](03-bits-and-subtraction.md), call destinations from [Chapter 4](04-return-stack-and-shuffles.md), and `0<` from [Chapter 5](05-comparisons-and-characters.md). Stack tops remain at the right; cells are 64 bits; addresses and transfer counts measure bytes.

Check two prerequisites: does `[5000] c@` return an address or a byte value? What signed value does `2^64-9` represent? The answers are the byte at address 5000, and -9. If either distinction is uncertain, recover that earlier contract first. Otherwise, try S7-01 and S7-03 before choosing how much scaffolding to use.

**Evidence boundary.** This chapter describes revision `bbcc1732152af2d884737272eed870d2410ffe8e`. Definitions and primitive behavior are source-inspected; all examples are paper derivations. No syscall, seed program, file creation, or interactive-input experiment was executed for this chapter. Addresses below are invented model locations, not usable scratch addresses in a running seed.

## A running program already has a host

The seed runs as a **process**, a running program hosted by Linux. Linux has already loaded it and supplied an execution environment. This is not yet a program booting directly on an otherwise empty machine. The **kernel** is the operating-system component that handles requests such as reading from an open input or writing to an open output.

A **system call**, or syscall, crosses that process/kernel boundary. The seed issues Linux/x86-64 syscalls directly; these wrappers do not call a C library. Their numbers and register arrangement belong to this host interface, not to every operating system or processor.

A **file descriptor**, abbreviated `fd`, is a small nonnegative integer identifying an open entry in this process's descriptor table. It is not a memory address. By convention, descriptor 0 is **standard input**, or stdin, and descriptor 1 is **standard output**, or stdout. Either may refer to a terminal, file, or pipe connecting programs; either may also be closed. “Write to stdout” therefore does not guarantee “show text on a screen.” The [Linux `open(2)` documentation](https://man7.org/linux/man-pages/man2/open.2.html) describes the descriptor table and returned descriptor.

## A buffer needs an address and a length

A **buffer** is a region of memory used to hold bytes for a transfer. Our independent paper reset is:

| Address | 5000 | 5001 | 5002 |
|---|---:|---:|---:|
| Stored byte, decimal | 65 | 66 | 67 |
| ASCII interpretation | A | B | C |

Assume these three bytes belong to the caller, remain available throughout the call, and are disjoint from code, sysvars, and live stack storage. No address arithmetic wraps. For `write`, all requested bytes must be readable and contain the intended payload. For `read`, the whole requested destination must be writable and safe to overwrite. These words do not allocate a buffer or verify its ownership.

The pair `(5000, 3)` identifies the three-byte range. The address alone supplies no length; three cells would instead occupy 24 bytes. Nor does `write` search for a terminating zero: its count determines the requested extent. Printable `ABC` makes the example easy to inspect without hiding the byte-count rule.

A read uses the same address-and-count shape in the opposite direction. A returned count of one means only one byte was newly read; it does not make the other two bytes valid new input. Keep **capacity**, **requested count**, and **actual count** separate. The [read contract](https://man7.org/linux/man-pages/man2/read.2.html) allows a successful transfer smaller than the request.

## One bridge, seven input cells

The primitive's Forth contract is:

```text
syscall6 ( a b c d e f n -- result )
```

There are six argument cells plus the syscall number `n`. The number is the topmost of all seven inputs; `f` is the topmost argument. A returning call consumes those seven cells and leaves one result. Older stack values remain below it.

An **application binary interface**, or ABI, specifies the machine-level agreement for passing values and continuing execution. Registers are named storage locations in the processor. The Linux/x86-64 syscall agreement is:

| Forth input | Meaning | Register at kernel entry |
|---|---|---|
| `n` | Syscall number | `rax` |
| `a` | Argument 1 | `rdi` |
| `b` | Argument 2 | `rsi` |
| `c` | Argument 3 | `rdx` |
| `d` | Argument 4 | `r10` |
| `e` | Argument 5 | `r8` |
| `f` | Argument 6 | `r9` |
| Returned value | Replaces the number | `rax` on return |

The seed subsequently moves returned `rax` into `rdi`, its data-stack top register. This complete mapping appears in [`syscall6_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L300-L318).

Do not treat this as an ordinary C function call. The usual x86-64 System V integer-argument convention uses `rcx` for argument four; Linux syscalls use `r10`. The `SYSCALL` instruction puts the user continuation address in `rcx` and saved processor flags in `r11`, overwriting their earlier contents. It does not push a `CALL`-style return destination on the user's stack. Linux's [versioned entry-source comments](https://github.com/torvalds/linux/blob/v6.12/arch/x86/entry/entry_64.S#L47-L75) document that distinction.

There are two boundaries: the Forth caller calls the `syscall6` word using the seed's own `rdi`/`rbp` data-stack and `rsp` return-stack convention; that word then enters the kernel using `SYSCALL`. After the kernel returns, the word's final `RET` uses its existing Forth-call destination. The seed does not rely on `rcx` or `r11` retaining a value across this kernel call. None of this makes seed words automatically callable as standard C functions.

## Five wrappers specialize the bridge

A **wrapper** adapts one interface to a more specific use. These are the actual library definitions, with their source comments omitted:

```forth
: open   [lit] 0 [lit] 0 [lit] 0 [lit]  2 syscall6 ;
: read   [lit] 0 [lit] 0 [lit] 0 [lit]  0 syscall6 ;
: write  [lit] 0 [lit] 0 [lit] 0 [lit]  1 syscall6 ;
: close  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit]  3 syscall6 ;
: die  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 60 syscall6 ;
```

Their numbers and padding are pinned in [`010-lib.fth`, Linux wrappers](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L47-L69).

| Word | Caller supplies | Number | Normal successful outcome |
|---|---|---:|---|
| `open` | `path flags mode` | 2 | New nonnegative descriptor |
| `read` | `fd buf count` | 0 | Actual number of bytes read |
| `write` | `fd buf count` | 1 | Actual number of bytes written |
| `close` | `fd` | 3 | Zero |
| `die` | `status` | 60 | Does not return |

For three-argument calls, the three zeros fill `d`, `e`, and `f`. For one-argument calls, five zeros fill `b` through `f`. These are complete stack entries even though the selected syscall ignores those argument slots. Omitting padding would make `syscall6` take other stack values as arguments.

The wrappers do not add checking, retries, formatting, or allocation. In particular, `write` means one write request, not “write everything.” Their colon definitions are studied as existing words; loading the library and executing external I/O belong to the later execution route.

## Trace the request for ABC

Start with `[99, 1, 5000, 3]`: older value 99, descriptor 1, buffer address 5000, and requested count three. Predict the full stack immediately before `syscall6`.

| After operation in `write` | Data stack |
|---|---|
| Start | `[99, 1, 5000, 3]` |
| First `[lit] 0` | `[99, 1, 5000, 3, 0]` |
| Second `[lit] 0` | `[99, 1, 5000, 3, 0, 0]` |
| Third `[lit] 0` | `[99, 1, 5000, 3, 0, 0, 0]` |
| `[lit] 1` | `[99, 1, 5000, 3, 0, 0, 0, 1]` |
| `syscall6`, assuming result 3 | `[99, 3]` |

The two ones have different jobs: the deeper one identifies stdout; the top one selects the write syscall. Neither is an ASCII byte from the payload.

We can check the primitive's internal transitions without decoding instruction bytes. Let `P` label its entry value of `rbp`, the pointer to the stack portion below register-held top `n=1`. Its stored cells are:

| Location | `P` | `P+8` | `P+16` | `P+24` | `P+32` | `P+40` | `P+48` |
|---|---:|---:|---:|---:|---:|---:|---:|
| Value | 0 | 0 | 0 | 3 | 5000 | 1 | 99 |
| Role | f | e | d | c | b | a | older value |

Each following row shows the state newly established; registers already loaded retain their listed values until the kernel call:

| Source action | Established value or state |
|---|---|
| Copy entry `rdi` into `rax` | `rax=1`, saving the syscall number |
| Load cell at `P` | `r9=0` |
| Load cell at `P+8` | `r8=0` |
| Load cell at `P+16` | `r10=0` |
| Load cell at `P+24` | `rdx=3` |
| Load cell at `P+32` | `rsi=5000` |
| Load cell at `P+40` | `rdi=1`, now the descriptor |
| Execute `SYSCALL` | Request `write(1, 5000, 3)`; assume returned `rax=3` |
| Advance `rbp` by 48 | `rbp=P+48`, discarding six stored argument cells |
| Copy `rax` into `rdi` | New top is 3, with older 99 below |
| `RET` | Resume the Forth caller with `[99, 3]` |

The number is saved before `rdi` takes argument `a`; equal numeric values in this example must not obscure that role change. Six stored cells occupy 48 bytes. The seventh input was already in the top register, so replacing it with the result completes the seven-to-one effect.

Under the assumed result three, Linux reports accepting all three bytes for this request. Our memory still contains `65 66 67`; writing does not consume or erase it. We have derived a request and a conditional outcome, not observed screen output or durable file storage.

## Read the result before reusing it

For the same request, interpret possible returned cells separately:

| Signed result | Stack afterward | What the caller knows |
|---:|---|---|
| 3 | `[99, 3]` | All three requested bytes were accepted |
| 1 | `[99, 1]` | Only the first byte, A, was accepted |
| 0 | `[99, 0]` | No progress reported; the request is not complete |
| -9 | `[99, M-9]` | Raw error `EBADF`; not a transferred count |

Here `M=2^64`. Linux's error number nine names an invalid descriptor or one unsuitable for that operation. The last row represents a separate failure case, for example stdout being closed; it is not the promised result for every stdout request. `M-9` is decimal 18446744073709551607. The bits encode signed -9, not an enormous successful transfer.

The seed exposes the kernel's **negative errno** directly: `errno` is an error number, and a raw error result contains its negative. There is no C-library step converting every failure to -1 and setting a separate variable. See Linux's [x86 syscall result handling](https://github.com/torvalds/linux/blob/v6.12/arch/x86/include/asm/syscall.h#L42-L71) and [error-number definitions](https://github.com/torvalds/linux/blob/v6.12/include/uapi/asm-generic/errno-base.h#L5-L14). The raw error range is signed -4095 through -1, using the kernel's [`MAX_ERRNO` bound](https://github.com/torvalds/linux/blob/v6.12/include/linux/err.h#L18-L27); an arbitrary negative cell is not automatically a valid errno result.

For these `open`, `read`, `write`, and `close` result contracts, Chapter 5's `0<` distinguishes a raw error from a nonnegative success. `dup 0<` preserves the result while adding a flag. This is a classification step, not an error handler. Do not feed an error cell into buffer arithmetic, unsigned division as a signed magnitude, or a later count argument. Nor should a rule for these results replace checking another syscall's own contract.

Negative values in tables are interpretations. `[lit] -9` is not valid seed syntax; a paper test can construct the pattern with `[lit] 0 [lit] 9 -`. That arithmetic does not cause an operating-system error.

## Partial transfer changes the next request

A short successful transfer is an ordinary possibility, not proof of a broken wrapper. Linux documents both [short writes](https://man7.org/linux/man-pages/man2/write.2.html) and [short reads](https://man7.org/linux/man-pages/man2/read.2.html). The caller must inspect the result and decide what its larger task requires.

After the modeled write returns one, the untransferred suffix is `BC`:

```text
original start = 5000       original count = 3
accepted count = 1
next start     = 5000+1 = 5001
remaining      = 3-1    = 2
next request   = write(1, 5001, 2)
```

Repeating `(1, 5000, 3)` would resend A. Advancing by three would skip B and C. Retain the descriptor, current address, and remaining count somewhere under an explicit caller contract; `write` itself consumes its inputs and returns only the result.

A caller aiming to finish the buffer can repeat after positive progress, stop when none remain, and report or otherwise handle an error. A zero-progress result needs a policy too; blindly repeating forever is not completion. Some errors may permit a retry after suitable handling, but not every error means “try again.” This is an English design outline, not an untaught Forth loop.

For a positive-count read from an ordinary file or byte-stream pipe, zero means **end of file** (EOF), with no new bytes. A short positive read need not mean EOF; another read may obtain more. A zero-count request can return zero without testing the end of input. These distinctions prevent a count from being mistaken for a character.

## Opening, closing, and leaving

`open` supplies a path address, flags describing the requested operation, and a mode for creation cases that use it. The path is zero-terminated: readable pathname bytes followed by a zero byte. Unlike `write`, this interface does not take a path length. We do not construct a live filename or select file-creation flags here. A successful descriptor must be distinguished from an error before being passed onward; do not assume its value must be three.

`close` takes the descriptor, appends five padding zeros and number three, then makes one call. Zero reports success. Close only a descriptor whose lifetime the caller is responsible for ending. Closing releases the descriptor for reuse. Check failures, but do not blindly retry a failed Linux close: the descriptor may already have been released. The [close documentation](https://man7.org/linux/man-pages/man2/close.2.html) explains that hazard.

`die ( status -- )` uses syscall 60 with the caller's status. The seed's [`bye_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L251-L259) directly issues the same syscall with status zero. Successful termination supplies no return-stack or data-stack result to inspect afterward.

For this single-threaded seed, that ends the process. The raw Linux exit syscall terminates the calling thread, so this account must not silently become a multi-thread shutdown promise. The status reported to the parent uses the low eight bits: status 259 yields three, since `259 = 256+3`. This is a derived example, not an observed shell status. See the [Linux exit interface](https://man7.org/linux/man-pages/man2/exit.2.html), the [status rule](https://man7.org/linux/man-pages/man2/_exit.2.html), and the [versioned kernel mask](https://github.com/torvalds/linux/blob/v6.12/kernel/exit.c#L992-L995).

## Two small I/O words have narrower guarantees

The seed also has direct `emit` and `key` primitives. We defer their instruction-by-instruction treatment to the later physical-I/O unit, but their limits matter now:

- `emit ( c -- )` stores the low byte of `c` in shared scratch storage and requests a one-byte write to descriptor 1. It ignores the returned write result. Its empty output stack does not certify successful output
- `key ( -- c )` requests one byte from descriptor 0 into that same scratch location. It returns zero if the read result equals zero. Otherwise it loads the scratch byte, without checking for a negative error result

Consequently, a successfully read NUL byte, whose value is zero, collides with `key`'s EOF sentinel. A negative read error takes the nonzero-result path and can expose a stale scratch byte; it is not reliably reported as an error or EOF. These are conclusions from [`emit_code` and `key_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L266-L298), not proposed improvements or executed failures. No dynamic-input experiment is needed to establish the branch distinction.

## Practice

Use fresh paper resets and the [hints, solutions, and changed cases](../practice/07-solutions.md).

### S7-01 — Complete the bridge

Starting with `[99, 1, 5000, 3]`, expand `write` through every literal. Label all seven inputs and give all seven kernel-entry registers. Assuming result one, give the final stack and unchanged buffer. Why is the descriptor's one unrelated to the syscall number's one?

### S7-02 — Repair missing padding

A proposed `demo-close` appends only four zeros and number three before `syscall6`. Starting with `[99, 7]`, which value becomes argument `a`, and what happens to the promised older value? Repair the wrapper. Then explain why `open` needs three padding zeros, rather than five, with inputs `[99, PATH, FLAGS, MODE]`.

### S7-03 — Interpret an error cell

A write returns decimal 18446744073709551607. Give its signed interpretation and error number; trace `dup 0<`. Explain why using that result as a byte count violates the contract. Separately compare a zero result from a positive-count file read with a zero result from a zero-count read.

### S7-04 — Finish a partial transfer on paper

Design English steps or pseudocode for finishing `ABC`, with successive write results one and two. Track descriptor, next address, remaining count, and accepted prefix. Include separate decisions for a negative result and zero progress. Do not implement a Forth loop. Explain what resending the original request after the first result would duplicate.

### S7-05 — Keep status, count, and byte distinct

For separate paper cases, determine: the parent-visible status from `die` supplied 259; the status from `bye`; `key`'s result for a successful NUL read; and `key`'s path after a negative read result when scratch still contains 65. Can completion of `emit` establish that one byte was written? Give the source-level reason for each answer.

## Stop and return

If a trace differs, label roles before changing numbers: descriptor, address, count, syscall number, result. For a pause, save “one byte accepted; next address 5001; two remain.” On return, rebuild that state without the table. After intervening material, retry S7-03 and S7-04 with their solutions closed.

You can now account for the boundary between byte storage and an external transfer, including the obligations the tiny wrappers leave to their callers. Next, [Defining words and phases](08-defining-words-and-phases.md) returns to how the system constructs new words. The [edition record](../../EDITION.md) retains the source and execution limits; external Linux documentation was checked on 2026-10-06.
