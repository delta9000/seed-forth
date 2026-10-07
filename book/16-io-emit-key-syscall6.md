# Chapter 16 — I/O: `emit`, `key`, `syscall6`

```text
Missing capability: emit, key, and syscall6 were black boxes.
New pattern: syscall6 loads rax, rdi, rsi, rdx, r10, r8, r9 from the data stack and traps.
Artifact after this chapter: the four primitives that connect the seed to Linux, in machine code.
Proof link: every byte the seed reads or writes goes through these; Ch 5's wrappers sit directly on top.
```

The seed contains six `syscall` instructions (`0F 05`).  That is
its entire interface to Linux, and it is small enough to audit in
one sitting.  Four of them are in this chapter's four primitives;
the other two belong to the token reader's error path, which writes
an unknown or malformed token back out and, if it is fatal, exits
(Ch 17).  Everything the seed ever reads arrives one byte per system
call: feeding it the library and the C compiler, 527,619 bytes of
Forth (`010-lib.fth` through `120-cc-main.fth`, comments and all),
costs one `read` call per byte, plus one that returns EOF
(`strace -c` will count them for
you).

The four primitives are lines 251–318 of `000-seed.hex0`: `bye`,
`emit`, `key` and `syscall6`, each a header followed by its code.
`emit` and `key` move one byte each through a shared scratch byte at
`0x412000`, which keeps them under 50 bytes and leaves buffering to
the Forth layers above.  `syscall6` is the general hatch that Ch 5 wrapped `open`,
`read`, `write`, `close` and `die` around: it loads a syscall number
and six arguments from the data stack into the registers the kernel
expects.  The token reader `read_word`, which calls `key` in a
loop, is Ch 17.

## 1. `bye_code` in 12 bytes

`bye_code` is the simplest syscall in the seed: `exit(0)`.

```hex0 chunk=bye
;; --- bye @ 0x22D --- header
12 02 40 00 00 00 00 00                   ; link  = 0x400212 (*)
00                                        ; flags = 0
03                                        ; nlen  = 3
62 79 65                                  ; name  = "bye"
;; ----- bye_code @ 0x23A  ( -- ) exit(0); never returns -----
B8 3C 00 00 00                            ; mov eax, 60        ; SYS_exit
BF 00 00 00 00                            ; mov edi, 0         ; status 0
0F 05                                     ; syscall

```

Three instructions: syscall number 60 in `eax`, exit status 0 in
`edi`, `syscall`.  No `ret`, because the kernel terminates the
process and never returns to userspace.  The body lives at `0x23A`
and is also the REPL's EOF path: when `read_word` returns length
zero, the REPL executes `jz bye_code` and the kernel takes over.

## 2. `emit_code` in 46 bytes

`emit` takes a byte off the data stack and writes it to fd 1
(stdout) via `write(2)`.

```hex0 chunk=emit
;; --- emit @ 0x246 --- header
2D 02 40 00 00 00 00 00                   ; link  = 0x40022D (bye)
00                                        ; flags = 0
04                                        ; nlen  = 4
65 6D 69 74                               ; name  = "emit"
;; ----- emit_code @ 0x254  ( c -- ) write one byte to stdout -----
48 C7 C0 00 20 41 00                      ; mov rax, 0x412000  ; scratch byte
40 88 38                                  ; mov [rax], dil     ; store TOS's low byte there
B8 01 00 00 00                            ; mov eax, 1         ; SYS_write
BF 01 00 00 00                            ; mov edi, 1         ; fd 1 (stdout)
48 BE 00 20 41 00 00 00 00 00             ; mov rsi, 0x412000  ; buf (movabs)
BA 01 00 00 00                            ; mov edx, 1         ; count 1
0F 05                                     ; syscall            ; clobbers rcx, r11
48 8B 7D 00                               ; mov rdi, [rbp]
48 83 C5 08                               ; add rbp, 8
C3                                        ; ret

```

The body stores, calls, then pops: the low 8 bits of TOS (`dil`) go
into the scratch byte, `write(1, 0x412000, 1)` traps to the kernel,
and the next cell becomes TOS.

Two details stand out.

**The scratch byte is global.**  Every `emit` writes to the same
address, which is safe only because the seed is single-threaded;
it saves the bytes a per-call buffer would cost.

**`mov eax, 1` not `mov rax, 1`.**  The 32-bit form (`B8 imm32`,
5 bytes) is two bytes shorter than `mov rax, 1` (`48 C7 C0 imm32`,
7 bytes) and zero-extends to 64 bits, which is exactly what we want
when the value fits in 32 bits.  Most of the constants in this
primitive are loaded with 32-bit moves.  The buffer address is the
odd one out: it uses the 10-byte `movabs` form, even though
`0x412000` fits comfortably in 32 bits (the first instruction loads
the same address into `rax` with a 7-byte move, and `key` below does
the same for `rsi`).  That `movabs` is three bytes the seed could
have saved, not a requirement.

## 3. `key_code` in 47 bytes

`key` reads one byte from fd 0 (stdin) and pushes its value, or
pushes `0` on EOF.

```hex0 chunk=key
;; --- key @ 0x282 --- header
46 02 40 00 00 00 00 00                   ; link  = 0x400246 (emit)
00                                        ; flags = 0
03                                        ; nlen  = 3
6B 65 79                                  ; name  = "key"
;; ----- key_code @ 0x28F  ( -- c ) read one byte from stdin; 0 at EOF -----
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi
B8 00 00 00 00                            ; mov eax, 0         ; SYS_read
BF 00 00 00 00                            ; mov edi, 0         ; fd 0 (stdin)
48 C7 C6 00 20 41 00                      ; mov rsi, 0x412000  ; buf = scratch byte
BA 01 00 00 00                            ; mov edx, 1         ; count 1
0F 05                                     ; syscall
48 85 C0                                  ; test rax, rax      ; 0 bytes read = EOF
74 06                                     ; jz .eof  (rel8 = 0x2BA - 0x2B4)
48 0F B6 3E                               ; movzx rdi, byte [rsi] ; TOS = the byte
EB 03                                     ; jmp .done  (rel8 = 0x2BD - 0x2BA)
;; .eof:
48 31 FF                                  ; xor rdi, rdi       ; TOS = 0
;; .done:
C3                                        ; ret

```

The push happens *first*: `sub rbp, 8; mov [rbp], rdi` spills the
old TOS to make room.  Then we read.  Then `rdi` becomes either
the byte we read (zero-extended to a cell) or `0` if `read` returned
zero (which on a pipe or redirected file means EOF).

The EOF sentinel matters.  `read_word` (Ch 17) calls `key` in a
loop and passes the `0` outward as "no token," and the REPL (Ch 20)
answers that with the `jz bye_code` from §1.  The seed's entire shutdown path
starts at this one `xor rdi, rdi`.

`mov rsi, 0x412000` here uses the *32-bit-immediate* form (`48 C7
C6 ...`), not the 10-byte `movabs` form.  The CPU sign-extends
that immediate to 64 bits, and since the sign bit of `0x412000` is
clear, sign-extension gives the same result as zero-extension.

## 4. `syscall6_code` in 37 bytes

```hex0 chunk=syscall6
;; --- syscall6 @ 0x2BE --- header
82 02 40 00 00 00 00 00                   ; link  = 0x400282 (key)
00                                        ; flags = 0
08                                        ; nlen  = 8
73 79 73 63 61 6C 6C 36                   ; name  = "syscall6"
;; ----- syscall6_code @ 0x2D0  ( a b c d e f n -- rax ) -----
;; Linux x86-64: rax=n, rdi=a, rsi=b, rdx=c, r10=d, r8=e, r9=f.
;; Pops the six arguments; the new TOS is the syscall's return value.
48 89 F8                                  ; mov rax, rdi       ; rax = n (syscall number)
4C 8B 4D 00                               ; mov r9, [rbp]      ; f
4C 8B 45 08                               ; mov r8, [rbp+8]    ; e
4C 8B 55 10                               ; mov r10, [rbp+16]  ; d
48 8B 55 18                               ; mov rdx, [rbp+24]  ; c
48 8B 75 20                               ; mov rsi, [rbp+32]  ; b
48 8B 7D 28                               ; mov rdi, [rbp+40]  ; a
0F 05                                     ; syscall            ; clobbers rcx, r11 (unused)
48 83 C5 30                               ; add rbp, 48        ; pop the 6 argument cells
48 89 C7                                  ; mov rdi, rax       ; TOS = result
C3                                        ; ret

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
order from shallowest (`f → r9`) to deepest (`a → rdi`).  Any order
would work, because each read targets a different register and no
slot is overwritten before it is read.

After `syscall`, the return value is in `rax`.  We free the six
argument slots in one `add rbp, 48` (six cells × 8 bytes) and
move `rax` to `rdi` to become the new TOS.

## 5. Why six args and not seven?

Linux syscalls take up to six arguments.  The seventh value on the
data stack (popped first, in `rax`) is the syscall *number*.
There's no need for a seven-argument variant because the kernel
doesn't have one.

A call with fewer arguments pushes zeros for the unused ones, so one
primitive covers every syscall the Forth code makes.

## 6. The Ch 5 wrappers, revisited

In Ch 5 we built `open`, `read`, `write`, `close`, and `die` as
short Forth definitions, each ending in a call to `syscall6`.  The
compile-mode REPL turns `: write  ... [lit] 1 syscall6 ;` into a
sequence of `CALL` instructions ending in `CALL syscall6`
(`E8 xx xx xx xx`).  At runtime `syscall6_code` pulls its registers
from the stack, executes `0F 05`, and the kernel does the work.

`emit_code` and `key_code` skip `syscall6` and issue `0F 05`
themselves; `B8 01 00 00 00` in `emit_code` is what a Forth wrapper
would spell `[lit] 1 syscall6`.

## Try it

```sh
./build.sh
echo "[lit] 72 emit [lit] 105 emit bye" | ./seed-forth
# prints "Hi"

# Read a byte and echo it back.  seed-forth has no -e flag; we put
# both the program and its input on stdin.  Defining the work in a
# colon definition ensures the REPL has finished parsing tokens
# before `key` reads, so the byte `key` consumes is the 'A' that
# follows the program, not part of the program itself:
{ echo ': read-one key emit bye ;'; echo 'read-one'; printf 'A'; } | ./seed-forth
# prints "A".

# Demonstrate EOF:
printf '' | ./seed-forth
# exits cleanly via the REPL's EOF path

# Drive syscall6 directly to call write(fd=1, buf, count=1).  The
# buffer must be a real address; we get one by writing 'A' (65) into
# scratch space at the current HERE, capturing that address first.
# The library's `c,` writes the byte and advances HERE by 1.
{ cat 010-lib.fth
  echo 'here [lit] 65 c, [lit] 1 swap [lit] 1 [lit] 0 [lit] 0 [lit] 0 [lit] 1 syscall6 drop bye'
} | ./seed-forth
# Stack going into syscall6: ( 1 buf 1 0 0 0 1 )
#                              ^ ^   ^ ^ ^ ^ ^---- syscall number (write)
#                              | |   | d e f
#                              | |   `--- count
#                              | `------- buf
#                              `--------- fd=1 (stdout)
# Prints "A".
```

That last command made a Linux system call by pushing seven numbers
and naming one word.  Part III's C compiler reads its C source and
writes its executable through exactly this path, in 4 KiB reads and
one `write` of the whole output rather than a byte at a time.

## Exercises

1. **★★ Extend.** `emit` writes to fd `1` (stdout) hard-coded.  Sketch the changes
   needed to make `emit-to-fd ( c fd -- )` that takes the file
   descriptor from the stack.  How many extra bytes?

2. **★ Trace.** The scratch byte at `0x412000` is shared between `emit` and `key`.
   In what scenario could this corrupt something?  (Hint: signal
   handlers running during a syscall.  The seed has none, but the
   question is still worth answering.)

3. **★★ Trace.** `key`'s push-shape is `sub rbp, 8; mov [rbp], rdi; ...; mov rdi,
   X`.  Why doesn't it use the Ch 14 "push" pattern of `48 83 ED
   08; 48 89 7D 00; 48 89 C7` (which would require loading `X` into
   a temp first)?  Compare the byte counts.

4. **★★★ Extend.** Implement a `keys ( c-addr u -- u-actually-read )` primitive in
   hex that calls `read(0, c-addr, u)` directly.  Why doesn't the
   seed expose it, given that bulk reads are obviously cheaper than
   N calls to `key`?  (Hint: who would call it?)

5. **★ Trace.** `syscall6_code` clobbers `rcx` and `r11` but the seed doesn't
   save them.  Why is that safe in this calling convention?  (Hint:
   none of the Forth primitives use `rcx` or `r11` across calls.)

## Takeaways

- The seed does I/O one byte at a time through a single shared
  scratch byte at `0x412000`, and higher layers add buffering.
- `bye_code`, `emit_code` and `key_code` issue `syscall` directly,
  which for three fixed calls is cheaper than marshalling arguments
  through `syscall6_code`.
- `syscall6_code` is the kernel bridge for everything else, and
  every Ch 5 wrapper ends in a call to it.

**Running count: 757 of 1,772 bytes read (43%).**  This chapter
added 200: 142 bytes of code (`bye` 12, `emit` 46, `key` 47,
`syscall6` 37) and 58 of headers.

The seed can now compute and talk to the kernel, but every piece
so far is known only by its address.  Somehow the three characters
`dup` arriving on stdin have to become a call to `0x4000C7`.
Ch 17 shows how, and what the reader does with the tokens it cannot
use.

Next: Chapter 17 — The Dictionary.
