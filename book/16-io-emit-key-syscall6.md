# Chapter 16 — I/O: `emit`, `key`, `syscall6`

> **Status:** ✅ complete.  Defines chunks `<<syscall6-code>>` and
> `<<syscall6-dict>>`; bodies for `<<bye-code>>`, `<<emit-code>>`,
> `<<key-code>>` live in Ch 14 (to keep the master root contiguous)
> but are *explained* here.

## Goal

By the end of this chapter the reader can:

- read `emit_code` and `key_code` byte for byte, including their
  `write(2)` and `read(2)` syscalls;
- read `syscall6_code` and explain how it marshals seven data-stack
  cells into the x86-64 syscall ABI;
- explain the single-byte I/O scratch at `0x412000` and why the seed
  uses one shared buffer instead of per-call allocation.

## Source coverage

`000-seed.hex0` lines 65–96 (`bye_code`, `emit_code`, `key_code`)
and lines 627–648 (`syscall6_code` plus the `syscall6` dictionary
entry).

## Concepts introduced

- **The single-byte I/O scratch at `0x412000`.**  `emit` writes one
  byte there before calling `write(1, scratch, 1)`; `key` reads one
  byte into it via `read(0, scratch, 1)`.  One global byte covers
  all character I/O at the seed layer.
- **EOF handling in `key`.**  When `read` returns `0`, `key` pushes
  the cell value `0` — a sentinel the REPL uses to detect end of
  input.  Otherwise `key` pushes the byte read.
- **The x86-64 syscall ABI.**  `rax = syscall number`; arguments in
  `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`; the `syscall` instruction
  traps to the kernel; result returned in `rax`; `rcx` and `r11` are
  clobbered.
- **`syscall6_code`'s seven-cell marshalling.**  Pops six argument
  cells off the data stack into the ABI registers, then uses the old
  TOS (already in `rdi` at entry) as the syscall number.

## Concepts carried in

- The data-stack convention from Ch 14 (`rdi` = TOS, `[rbp]` =
  under-TOS).
- The Forth-level `syscall6` wrappers (`open`, `read`, `write`,
  `close`, `die`) from Ch 5.

## Concepts deferred

- The token reader `read_word` (which calls `key` in a loop) — Ch 17.

---

I/O at the seed layer is one byte at a time.  Higher layers
(`010-lib.fth`, `030-cc-io.fth`) build buffered I/O on top, but the
seed itself reads a byte and writes a byte and nothing else.  That
restriction shrinks `emit` and `key` to roughly 45 bytes each, and
it lets the seed get away with a *single byte* of scratch buffer at
`0x412000`.

The general-purpose hatch is `syscall6`: pop seven cells, hit the
kernel, push the result.  Every Forth-level wrapper in Ch 5 ends in
a call to it.

## 1. `bye_code` in 11 bytes

`bye_code` is the smallest, simplest syscall in the seed: `exit(0)`.

```
B8 3C 00 00 00          mov eax, 60        ; syscall number for exit
BF 00 00 00 00          mov edi, 0         ; exit code 0
0F 05                   syscall            ; never returns
```

Three instructions.  No `ret`, because the kernel terminates the
process and never returns to userspace.  The body lives at `0x0D2`
and is referenced from the REPL's EOF path: when `read_word` returns
length zero, the REPL emits `jmp bye_code` and the kernel takes over.

(The chunk body itself was defined in Ch 14 as `<<bye-code>>` so the
source from `<<jmp-to-repl>>` flows continuously into `<<bye-code>>`
without a gap.  The bytes are listed in the master root block in
the order shown above.)

## 2. `emit_code` in 42 bytes

`emit` takes a byte off the data stack and writes it to fd 1
(stdout) via `write(2)`.

```
;; @0x0DE
48 C7 C0 00 20 41 00    mov rax, 0x412000  ; scratch-byte address
40 88 38                mov [rax], dil     ; store TOS's low byte there
B8 01 00 00 00          mov eax, 1         ; syscall number for write
BF 01 00 00 00          mov edi, 1         ; fd = 1 (stdout)
48 BE 00 20 41 00 00 00 00 00
                        mov rsi, 0x412000  ; buffer address
BA 01 00 00 00          mov edx, 1         ; count = 1
0F 05                   syscall            ; rcx, r11 clobbered
48 8B 7D 00             mov rdi, [rbp]     ; pop new TOS from data stack
48 83 C5 08             add rbp, 8
C3                      ret
```

The control flow is: store-then-syscall-then-pop.  The byte to emit
is in `rdi` (TOS) at entry; we copy its low 8 bits (`dil`) into the
scratch byte at `0x412000`; we load the `write(1, 0x412000, 1)`
arguments into the right registers; we trap to the kernel; we pop
the data stack to make the *next* cell the new TOS.

Two details are worth flagging.

**The scratch byte is global.**  Every call to `emit` writes to the
same address.  That's fine because the seed is single-threaded and
the syscall returns before the next `emit` can run.  In a threaded
world this would be a race; in this codebase it is one of the moves
that lets the seed fit in 2,040 bytes.

**`mov eax, 1` not `mov rax, 1`.**  The 32-bit form is one byte
shorter and zero-extends to 64 bits, which is exactly what we want
when the value fits in 32 bits.  Most of the constants in this
primitive are loaded with 32-bit moves; only the buffer address
(which doesn't fit in 32 bits unless you sign-extend, and we don't
want to) uses the 10-byte `movabs` form.

## 3. `key_code` in 30 bytes

`key` reads one byte from fd 0 (stdin) and pushes its value, or
pushes `0` on EOF.

```
;; @0x10C
48 83 ED 08             sub rbp, 8         ; make data-stack room
48 89 7D 00             mov [rbp], rdi     ; spill old TOS
B8 00 00 00 00          mov eax, 0         ; syscall number for read
BF 00 00 00 00          mov edi, 0         ; fd = 0 (stdin)
48 C7 C6 00 20 41 00    mov rsi, 0x412000  ; buffer address
BA 01 00 00 00          mov edx, 1         ; count = 1
0F 05                   syscall
48 85 C0                test rax, rax      ; did read return 0?
74 06                   jz .eof
48 0F B6 3E             movzx rdi, byte [rsi]  ; rdi = the byte
EB 03                   jmp .done
48 31 FF                xor rdi, rdi       ; .eof: rdi = 0
                        ; .done:
C3                      ret
```

The push happens *first*: `sub rbp, 8; mov [rbp], rdi` spills the
old TOS to make room.  Then we read.  Then `rdi` becomes either
the byte we read (zero-extended to a cell) or `0` if `read` returned
zero (which on a pipe or redirected file means EOF).

The EOF sentinel is important.  Higher up, `read_word` (Ch 17) uses
`key` in a loop; it propagates the `0` outward as "no token,
exiting." The REPL (Ch 20) translates that into `jmp bye_code`.  The
entire shutdown path of the seed pivots on this one `xor rdi, rdi`.

`mov rsi, 0x412000` here uses the *32-bit-immediate* form (`48 C7
C6 ...`), not the 10-byte `movabs` form.  That works because
`0x412000` fits in 32 bits and the assembler sign-extends — but the
sign bit is clear, so sign-extension is identical to zero-extension.

## 4. `syscall6_code` in 39 bytes

```hex0 chunk=syscall6-code
;; ----- syscall6_code @ 0x6D4 ( a b c d e f n -- rax ) -----
;; Linux x86-64: rax=n, rdi=a, rsi=b, rdx=c, r10=d, r8=e, r9=f
;; Pops 6 args; new TOS = syscall return.
48 89 F8                                  ; mov rax, rdi
4C 8B 4D 00                               ; mov r9, [rbp]      ; f
4C 8B 45 08                               ; mov r8, [rbp+8]    ; e
4C 8B 55 10                               ; mov r10, [rbp+16]  ; d
48 8B 55 18                               ; mov rdx, [rbp+24]  ; c
48 8B 75 20                               ; mov rsi, [rbp+32]  ; b
48 8B 7D 28                               ; mov rdi, [rbp+40]  ; a
0F 05                                     ; syscall  (rcx,r11 clobbered; unused)
48 83 C5 30                               ; add rbp, 48        ; pop 6 args
48 89 C7                                  ; mov rdi, rax       ; new TOS = result
C3

```

This is the generic kernel-call bridge.  Forth-level callers push
six argument cells and then the syscall number; `syscall6_code`
moves everything into the ABI-required registers, traps, and pushes
the kernel's return value.

The order of `mov`s matters.  At entry, the syscall number is in
`rdi` (TOS); the *deepest* argument (`a`) is at `[rbp+40]` and the
*shallowest* argument (`f`) is at `[rbp+0]`.  We have to grab the
syscall number first (it's in `rdi`, which we'll overwrite shortly):

```
mov rax, rdi    ; rax = syscall number; rdi will hold arg `a`
```

Then we read each argument from its slot into its register, in
order from shallowest (`f → r9`) to deepest (`a → rdi`).  The
order doesn't really matter as long as we don't overwrite a slot
before reading it — and we don't, because each read targets a
different register.

After `syscall`, the return value is in `rax`.  We free the six
argument slots in one `add rbp, 48` (six cells × 8 bytes) and
move `rax` to `rdi` to become the new TOS.

```hex0 chunk=syscall6-dict
;; --- syscall6 @ 0x6F9 (xt = 0x70B) ---
C0 06 40 00 00 00 00 00                     ; link = 0x4006C0 ([lit])
00
08                                        ; nlen = 8
73 79 73 63 61 6C 6C 36                   ; "syscall6"
E9 C4 FF FF FF                              ; jmp syscall6_code (rel = 0x6D4 - 0x710 = -60)

```

The dictionary entry is the usual `link / flags / nlen / name /
jmp` shape.  Its link chains back to `[lit]`'s entry — the previous
word defined in the seed at that point in source.

## 5. Why six args and not seven?

Linux syscalls take up to six arguments.  The seventh value on the
data stack (popped first, in `rax`) is the syscall *number*.
There's no need for a seven-argument variant because the kernel
doesn't have one.

If a future syscall needed more than six arguments — none do — you
would have to spill them through a memory buffer, the way the
syscall number does in shorter wrappers (e.g., `key_code` doesn't
use `syscall6`; it loads its three registers directly).  But the
common pattern is "wrap a kernel call with N arguments where N ≤
6," which `syscall6` covers exactly.

## 6. The Ch 5 wrappers, revisited

In Ch 5 we built `open`, `read`, `write`, `close`, and `die` as
five-line Forth definitions, each ending in a call to `syscall6`.
Now you can see what those compile to.  `: write  ... [lit] 1
syscall6 ;` — at the seed's compile-mode emitter — turns into a
sequence of `CALL` instructions that ends with `CALL syscall6` (a
`E8 xx xx xx xx` instruction).  At runtime, `syscall6_code` pulls
its registers from the stack, hits `0F 05`, and the kernel does the
work.

The seed-level `emit_code` and `key_code` don't *use* `syscall6` —
they emit the `0F 05` directly because they pre-date the
syscall6-as-Forth-primitive design.  You'll notice this when you
read the bytes: `emit_code` loads `rax = 1` directly with `B8 01
00 00 00`, while a Forth-level write wrapper would do `[lit] 1
syscall6`.  Two paths, same syscall — the seed picks the cheaper
one for the two byte-at-a-time primitives it always needs, and
defers to `syscall6` for everything else.

## Try it

```sh
./build.sh
echo "[lit] 72 emit [lit] 105 emit bye" | ./seed-forth
# prints "Hi"

# Read a byte and echo it back:
printf 'A' | ./seed-forth -e 'key emit bye' 2>/dev/null || \
  echo "(seed-forth has no -e; pipe stdin instead)"

# Demonstrate EOF:
printf '' | ./seed-forth
# exits cleanly via the REPL's EOF path

# Use the Forth-level wrappers from 010-lib.fth (which call syscall6
# internally) — this requires loading the library first:
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo '[lit] 1 [lit] 65 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 1 syscall6 drop bye'
} | grep -v '^[[:space:]]*$' | ./seed-forth
# write(1, 0x41, 0, 0, 0, 0) — well, the 2nd arg is treated as buffer
# address, so this writes whatever bytes happen to live at 0x41.
# A real test would put a real address in there.
```

## Exercises

1. `emit` writes to fd `1` (stdout) hard-coded.  Sketch the changes
   needed to make `emit-to-fd ( c fd -- )` that takes the file
   descriptor from the stack.  How many extra bytes?

2. The scratch byte at `0x412000` is shared between `emit` and `key`.
   In what scenario could this corrupt something?  (Hint: signal
   handlers running during a syscall — not possible in this seed,
   but worth thinking about.)

3. `key`'s push-shape is `sub rbp, 8; mov [rbp], rdi; ...; mov rdi,
   X`.  Why doesn't it use the Ch 14 "push" pattern of `48 83 ED
   08; 48 89 7D 00; 48 89 C7` (which would require loading `X` into
   a temp first)?  Compare the byte counts.

4. Implement a `keys ( c-addr u -- u-actually-read )` primitive in
   hex that calls `read(0, c-addr, u)` directly.  Why doesn't the
   seed expose it, given that bulk reads are obviously cheaper than
   N calls to `key`?  (Hint: who would call it?)

5. `syscall6_code` clobbers `rcx` and `r11` but the seed doesn't
   save them.  Why is that safe in this calling convention?  (Hint:
   none of the Forth primitives use `rcx` or `r11` across calls.)

## Takeaways

- I/O at the seed level is one byte at a time, via a single shared
  scratch byte at `0x412000`.  Higher layers buffer.
- `bye_code`, `emit_code`, and `key_code` emit their `syscall`
  instruction directly — they don't go through `syscall6_code`.
  Inlining the three syscalls used at boot is cheaper than the
  argument-marshalling cost.
- `syscall6_code` is the universal kernel-call bridge for everything
  else.  Every wrapper in Ch 5 ends in a call to it.

Next: Chapter 17 — The Dictionary.
