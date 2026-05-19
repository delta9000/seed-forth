# Chapter 26 — Codegen, Part 2: Calls, Shims, and Globals

> **Status:** ✅ complete.  Contributes the second half of
> `090-cc-emit.fth` (lines 412–1027); together with Ch 25 the file
> tangles byte-identically.

## Goal

By the end of this chapter the reader can:

- read the forward-call infrastructure (`movabs rdi, imm64`
  placeholder + `cc-add-fixup-to-list`) and explain how a
  forward-declared function's address gets patched in after the
  fact;
- read the eleven libc shims emitted at the start of the code
  segment (`putchar`, `exit`, `getchar`, `fputs`, `fputc`,
  `fopen`, `fclose`, `fwrite`, `fread`, `calloc`, `free`) and
  trace each one's syscall sequence;
- read the file-scope-globals machinery (`cc-globals-buf`,
  `cc-gfixup-*`, `cc-emit-global-ref`) and explain how a global
  reference becomes a back-patched `movabs rdi, imm64`.

## Source coverage

`090-cc-emit.fth` lines 412–1027.  Ch 25 covered lines 1–411.

## Concepts introduced

- **`movabs rdi, imm64` + forward-call fixup lists.**  When a
  function is referenced before it is defined, the codegen emits
  a placeholder `movabs rdi, <imm64=0>` and threads the patch
  offset onto a linked list rooted in `cc-sym-extra2` (Ch 24).
  Ch 31's `cc-parse-function` walks the list when the definition
  arrives.
- **`cc-emit-string-bytes`.**  Decodes the seven C escapes the
  lexer kept literal — `\n`, `\t`, `\r`, `\\`, `\'`, `\"`, `\0` —
  and emits a NUL-terminated copy of the string into the output
  buffer.
- **Libc shims as inline machine code.**  Eleven small functions
  (`putchar` through `free`) are emitted at the start of the
  code segment.  Each is direct Linux syscall code; no
  `dlsym`, no `PLT`, no libc.
- **`calloc` as a bump allocator over a one-shot `mmap`.**  A
  single 256 MiB mmap holds the entire heap; `calloc` is bump
  allocation plus zero-fill (handed by Linux on first touch).
  `free` is a no-op.
- **File-scope globals + deferred vaddr fixups.**  Globals
  accumulate in `cc-globals-buf` during parsing and are appended
  to the output ELF *after* the code.  Each `IDENT` reference
  emits a placeholder `movabs rdi, imm64` and records the patch
  site; `cc-finalize-globals` later resolves everything.

## Concepts carried in

- Every instruction encoder from Ch 25 (push/pop, mov,
  prologue/epilogue, idiv, cmp/set, rel32 placeholders).
- `cc-emit-byte`, `cc-emit-8le`, `cc-out-pos`, `cc-out-patch-4le`,
  `cc-out-patch-8le` (Ch 21).
- `cc-alloc` (Ch 21), `cc-sym-extra2` (Ch 24).

## Concepts deferred

- Where `cc-emit-string-bytes` and `cc-emit-global-ref` are
  *called* from — Chs 27–28 (string literals, global identifier
  rvalues).
- Where the prologue/epilogue from Ch 25 are *called* from —
  Ch 31 (function definitions).
- Where the forward-call fixup list is *walked* — Ch 31
  (`cc-parse-function`).

---

Ch 25 covered the per-instruction encoders.  This chapter is
about everything that sits above them — the machinery that lets
the compiler reference things it hasn't emitted yet, the
self-contained libc replacement that lets compiled programs run
without dynamic linking, and the data segment that holds
file-scope variables.

The narrative thread is *deferred resolution*.  A compiler that
emits ELF bytes linearly will repeatedly encounter symbols whose
addresses it doesn't yet know: forward-declared functions,
file-scope globals declared after they are first used, string
literals whose pool location is fixed later.  Each is handled
the same way — emit a placeholder, remember where, patch it when
the truth arrives.

## 1. `movabs rdi, imm64` and the forward-call fixup list

```forth file=090-cc-emit.fth
\ ===========================================================================
\ movabs rdi, imm64 — used for loading string-literal addresses.
\ ===========================================================================
\ Encoding: 48 BF <imm64-LE>  (10 bytes total).

: cc-emit-movabs-rdi-imm64                        ( v -- )
  [lit]  72 cc-emit-byte                          \ REX.W
  [lit] 191 cc-emit-byte                          \ B7 + rdi (7) = BF
  cc-emit-8le ;

\ cc-emit-movabs-rdi-imm64-placeholder ( -- patch-offset )
\ Emits `48 BF 00 00 00 00 00 00 00 00`; returns the imm64 file-offset.
\ Used when a forward-declared function's name is taken as an rvalue
\ (function-pointer load) before its definition is reached.  Caller threads
\ patch-offset onto cc-sym-extra2 of the function's prototype symbol; the
\ list is walked and each 8-byte imm64 is patched to the function's real
\ vaddr when cc-parse-function processes its definition.
: cc-emit-movabs-rdi-imm64-placeholder
  [lit]  72 cc-emit-byte
  [lit] 191 cc-emit-byte
  cc-out-pos @
  [lit] 0 cc-emit-8le ;

\ cc-add-fixup-to-list ( fixup-offset list-var -- )  Allocate a 16-byte node
\ and prepend it to the linked list rooted at list-var.  Defined here so
\ 100-cc-expr.fth (loaded before 110-cc-decl.fth) can reference it from the
\ forward-function-rvalue path in cc-parse-primary.
: cc-add-fixup-to-list                            ( off var -- )
  [lit] 16 cc-alloc                               ( off var node )
  >r                                              ( off var ; R: node )
  swap r@ !                                       ( var ; R: node )
  dup @ r@ [lit] 8 + !                            ( var ; R: node )
  r> swap ! ;                                     ( -- )

```

`cc-emit-movabs-rdi-imm64` is the 10-byte encoder for `movabs rdi,
<imm64>`: `48 BF <8 bytes LE>`.  This is the only x86-64
instruction that loads a full 64-bit immediate into a register;
the smaller `mov rdi, imm32` (Ch 25 §3) sign-extends a 32-bit
constant and can't reach vaddrs above `0x7FFFFFFF`.  Since our
output binaries live at `0x400000` and may grow past 4 GiB of
addressable space (heap), we need the wide form.

`cc-emit-movabs-rdi-imm64-placeholder` is the deferred variant.
It writes the same 10 bytes but with the imm64 zeroed, and returns
the byte offset of those 8 zero bytes inside `cc-out-buf` so the
caller can patch them later.

`cc-add-fixup-to-list` builds the linked list of patch sites.  It
allocates a 16-byte node via `cc-alloc` (Ch 21), writes the new
node's `[0]` = patch-offset and `[8]` = old-head, and updates the
list root variable to point at the new node.  Standard intrusive
linked-list prepend, written in nine words of Forth.

The shape of a list node is:

```
+0:  patch-offset (into cc-out-buf)
+8:  next pointer (0 = end)
```

When Ch 31's `cc-parse-function` reaches the definition of a
previously-forward-declared function, it walks `cc-sym-extra2`
for that symbol and for each node patches `cc-out-buf[off ..
off+7]` to the resolved 64-bit vaddr.

The comment on `cc-add-fixup-to-list` mentions it's defined here
specifically so Ch 27's `cc-parse-primary` can reach it from the
forward-function-rvalue path — `100-cc-expr.fth` loads *before*
`110-cc-decl.fth`, so anything Ch 27 needs has to come from this
file or earlier.

## 2. String-literal bytes with C-escape decoding

```forth file=090-cc-emit.fth
\ ===========================================================================
\ String-literal byte emission with C-escape decoding.
\ ===========================================================================
\ Walks ( src-addr src-len ) and copies bytes into cc-out-buf, decoding
\ \n, \t, \r, \\, \', \", and \0.  Other escape characters pass through
\ literally (matches cc-lex-char behaviour).  Appends a trailing NUL byte.
\
\ Stack convention inside the loop: ( src len ).

: cc-emit-string-bytes                            ( src-addr src-len -- )
  begin,
    dup [lit] 0 >
  while,
    over c@ [lit] 92 = if,                        \ '\\' (backslash)
      dup [lit] 2 >= if,
        \ Have at least one more byte for the escape.
        over [lit] 1 + c@                         ( src len escaped )
        dup [lit] 110 = if, drop [lit] 10 else,   \ \n
        dup [lit] 116 = if, drop [lit]  9 else,   \ \t
        dup [lit] 114 = if, drop [lit] 13 else,   \ \r
        dup [lit]  92 = if, drop [lit] 92 else,   \ \\
        dup [lit]  39 = if, drop [lit] 39 else,   \ \'
        dup [lit]  34 = if, drop [lit] 34 else,   \ \"
        dup [lit]  48 = if, drop [lit]  0 else,   \ \0
          \ Default: pass the escaped char through unchanged.
        then, then, then, then, then, then, then,
        cc-emit-byte
        \ Advance src by 2, decrement len by 2.
        swap [lit] 2 + swap [lit] 2 -
      else,
        \ Trailing backslash with no follow-up char: emit literally.
        over c@ cc-emit-byte
        swap [lit] 1 + swap [lit] 1 -
      then,
    else,
      over c@ cc-emit-byte
      swap [lit] 1 + swap [lit] 1 -
    then,
  repeat,
  drop drop
  [lit] 0 cc-emit-byte ;                          \ trailing NUL terminator

```

The lexer (Ch 23) preserves backslash escapes as literal byte
pairs inside string-literal slices, leaving decoding to codegen.
This is that decoding.

The walk is a `begin, while, repeat,` over `(src-addr, len)`:
read the current byte, if it's a backslash and there's at least
one more byte available, decode the next byte; otherwise copy
verbatim.  The seven recognised escapes are exactly those
`cc-lex-char` decodes (Ch 23 §4) plus `\r` — the only printable C
escape that has no `'…'` form in the M2-Planet sources.

Any escaped character that *isn't* in the recognised set passes
through unchanged.  This is more permissive than ANSI C requires
but matches `cc-lex-char` — and crucially doesn't reject M2-Planet
sources that use only the seven supported escapes.

A trailing NUL byte is appended so string literals can be used
with C's `printf` / `puts`-style functions out of the box.

## 3. The libc shims: write/read/open/close/mmap

```forth file=090-cc-emit.fth
\ ===========================================================================
\ Built-in libc shims (putchar, exit, getchar) emitted at the start of
\ the code segment so user code can call them via the standard call path.
\ ===========================================================================
\
\ All three shims follow SYS-V x86-64 calling convention: the first arg is in
\ rdi, the return value comes back in rax, and the call site converts rax to
\ rdi via cc-emit-mov-rdi-rax (already done by cc-parse-call).
\
\ NOTE on stack: each shim is entered with rsp ≡ 8 mod 16 (caller pushed the
\ return address from a 16-aligned base).  putchar and getchar each do one
\ `push` before the syscall, restoring rsp ≡ 0 mod 16.  Linux syscalls don't
\ care about ABI alignment, so this keeps the shim prologues uniform.

\ -- putchar(int c): write the low byte of rdi to fd 1.  29 bytes.
\
\   push rdi             57
\   mov rax, 1           48 C7 C0 01 00 00 00     (write syscall #)
\   mov rdi, 1           48 C7 C7 01 00 00 00     (fd = stdout)
\   mov rsi, rsp         48 89 E6                 (buffer = pushed qword's first byte)
\   mov rdx, 1           48 C7 C2 01 00 00 00     (count = 1)
\   syscall              0F 05
\   pop rdi              5F                       (restore rsp)
\   ret                  C3
: cc-emit-putchar-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 192 cc-emit-byte
  [lit]   1 cc-emit-4le                           \ mov rax, 1
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 199 cc-emit-byte
  [lit]   1 cc-emit-4le                           \ mov rdi, 1
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 230 cc-emit-byte
                                                  \ mov rsi, rsp
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 194 cc-emit-byte
  [lit]   1 cc-emit-4le                           \ mov rdx, 1
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  95 cc-emit-byte                          \ pop rdi
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- exit(int n): syscall 60 with rdi = n.  10 bytes.
\
\   mov rax, 60          48 C7 C0 3C 00 00 00
\   syscall              0F 05
\   ret                  C3                        (unreachable but tidy)
: cc-emit-exit-shim
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 192 cc-emit-byte
  [lit]  60 cc-emit-4le                           \ mov rax, 60
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- getchar(void): read 1 byte from fd 0; return -1 on EOF.  48 bytes.
\
\   push rdi             57                          (reserve 8B scratch on stack)
\   mov rax, 0           48 C7 C0 00 00 00 00        (read syscall #)
\   mov rdi, 0           48 C7 C7 00 00 00 00        (fd = stdin)
\   mov rsi, rsp         48 89 E6
\   mov rdx, 1           48 C7 C2 01 00 00 00
\   syscall              0F 05
\   test rax, rax        48 85 C0
\   jnz .have            75 09                       (skip 9 bytes -> movzx)
\   mov rax, -1          48 C7 C0 FF FF FF FF
\   jmp .done            EB 05                       (skip 5 bytes -> pop rdi)
\ .have:
\   movzx rax, byte [rsp] 48 0F B6 04 24
\ .done:
\   pop rdi              5F
\   ret                  C3
: cc-emit-getchar-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 192 cc-emit-byte
  [lit]   0 cc-emit-4le                           \ mov rax, 0
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 199 cc-emit-byte
  [lit]   0 cc-emit-4le                           \ mov rdi, 0
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 230 cc-emit-byte
                                                  \ mov rsi, rsp
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 194 cc-emit-byte
  [lit]   1 cc-emit-4le                           \ mov rdx, 1
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  72 cc-emit-byte [lit] 133 cc-emit-byte [lit] 192 cc-emit-byte
                                                  \ test rax, rax
  [lit] 117 cc-emit-byte [lit]   9 cc-emit-byte   \ jnz +9 (skip mov+jmp)
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 192 cc-emit-byte
  [lit] 255 cc-emit-byte [lit] 255 cc-emit-byte
  [lit] 255 cc-emit-byte [lit] 255 cc-emit-byte   \ mov rax, -1 (sign-extended imm32 = FFFFFFFF)
  [lit] 235 cc-emit-byte [lit]   5 cc-emit-byte   \ jmp +5 (skip movzx)
  [lit]  72 cc-emit-byte [lit]  15 cc-emit-byte
  [lit] 182 cc-emit-byte [lit]   4 cc-emit-byte
  [lit]  36 cc-emit-byte                          \ movzx rax, byte [rsp]
  [lit]  95 cc-emit-byte                          \ pop rdi
  [lit] 195 cc-emit-byte ;                        \ ret

\ ===========================================================================
\ Libc shims: fputs, fputc, fopen, fclose, fwrite, fread, calloc,
\ free.  All follow SYS-V x86-64 ABI.  Symbol registration and
\ vaddr assignment happen in cc-emit-shims (110-cc-decl.fth).
\ ===========================================================================

\ -- fputs(char *s, FILE *fp) -> non-negative on success.  33 bytes.
\
\   push rdi           57                    (save str)
\   push rsi           56                    (save fd)
\   xor rdx, rdx       48 31 D2              (length counter)
\ .loop:
\   movzx ecx, [rdi+rdx]  0F B6 0C 17       SIB: idx=rdx(2) base=rdi(7)
\   test cl, cl            84 C9
\   jz +5  (.done)         74 05
\   inc rdx                48 FF C2
\   jmp .loop              EB F3             (disp = -13)
\ .done:
\   mov rax, 1         48 C7 C0 01 00 00 00  (write)
\   mov rsi, rdi       48 89 FE              (buf = str)
\   pop rdi            5F                    (fd = saved rsi slot)
\   pop rcx            59                    (discard saved str)
\   syscall            0F 05
\   ret                C3
: cc-emit-fputs-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  86 cc-emit-byte                          \ push rsi
  [lit]  72 cc-emit-byte [lit]  49 cc-emit-byte
  [lit] 210 cc-emit-byte                          \ xor rdx, rdx
  [lit]  15 cc-emit-byte [lit] 182 cc-emit-byte
  [lit]  12 cc-emit-byte [lit]  23 cc-emit-byte   \ movzx ecx, [rdi+rdx]
  [lit] 132 cc-emit-byte [lit] 201 cc-emit-byte   \ test cl, cl
  [lit] 116 cc-emit-byte [lit]   5 cc-emit-byte   \ jz +5
  [lit]  72 cc-emit-byte [lit] 255 cc-emit-byte
  [lit] 194 cc-emit-byte                          \ inc rdx
  [lit] 235 cc-emit-byte [lit] 243 cc-emit-byte   \ jmp .loop  (disp = -13)
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte [lit]   1 cc-emit-4le    \ mov rax, 1
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 254 cc-emit-byte                          \ mov rsi, rdi  (buf)
  [lit]  95 cc-emit-byte                          \ pop rdi  (fd)
  [lit]  89 cc-emit-byte                          \ pop rcx  (discard str)
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- fputc(int c, FILE *fp) -> c on success.  30 bytes.
\
\   push rdi           57                    (char onto stack = write buffer)
\   mov rax, 1         48 C7 C0 01 00 00 00
\   mov rdi, rsi       48 89 F7              (fd = arg2)
\   mov rsi, rsp       48 89 E6              (buf = stack)
\   mov rdx, 1         48 C7 C2 01 00 00 00
\   syscall            0F 05
\   movzx eax, [rsp]   0F B6 04 24           (return char)
\   pop rcx            59
\   ret                C3
: cc-emit-fputc-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte [lit]   1 cc-emit-4le    \ mov rax, 1
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 247 cc-emit-byte                          \ mov rdi, rsi  (fd)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 230 cc-emit-byte                          \ mov rsi, rsp  (buf)
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 194 cc-emit-byte [lit]   1 cc-emit-4le    \ mov rdx, 1
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  15 cc-emit-byte [lit] 182 cc-emit-byte
  [lit]   4 cc-emit-byte [lit]  36 cc-emit-byte   \ movzx eax, [rsp]
  [lit]  89 cc-emit-byte                          \ pop rcx
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- fopen(char *path, char *mode) -> fd on success, 0 on error.  51 bytes.
\
\   push rdi           57
\   movzx eax, [rsi]   0F B6 06              (first char of mode)
\   xor esi, esi       31 F6                 (flags = O_RDONLY = 0)
\   cmp eax, 119       83 F8 77              ('w')
\   jne +7  (.try_a)   75 07
\   mov esi, 0x241     BE 41 02 00 00        (O_WRONLY|O_CREAT|O_TRUNC)
\   jmp +10  (.open)   EB 0A
\ .try_a:
\   cmp eax, 97        83 F8 61              ('a')
\   jne +5  (.open)    75 05
\   mov esi, 0x441     BE 41 04 00 00        (O_WRONLY|O_CREAT|O_APPEND)
\ .open:
\   pop rdi            5F
\   mov rax, 2         48 C7 C0 02 00 00 00  (open syscall)
\   mov edx, 420       BA A4 01 00 00        (mode 0644)
\   syscall            0F 05
\   test rax, rax      48 85 C0
\   jns +2  (.ok)      79 02
\   xor eax, eax       31 C0                 (return NULL on error)
\ .ok:
\   ret                C3
: cc-emit-fopen-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  15 cc-emit-byte [lit] 182 cc-emit-byte
  [lit]   6 cc-emit-byte                          \ movzx eax, [rsi]
  [lit]  49 cc-emit-byte [lit] 246 cc-emit-byte   \ xor esi, esi
  [lit] 131 cc-emit-byte [lit] 248 cc-emit-byte
  [lit] 119 cc-emit-byte                          \ cmp eax, 'w'
  [lit] 117 cc-emit-byte [lit]   7 cc-emit-byte   \ jne +7
  [lit] 190 cc-emit-byte [lit] 577 cc-emit-4le    \ mov esi, 0x241
  [lit] 235 cc-emit-byte [lit]  10 cc-emit-byte   \ jmp +10
  [lit] 131 cc-emit-byte [lit] 248 cc-emit-byte
  [lit]  97 cc-emit-byte                          \ cmp eax, 'a'
  [lit] 117 cc-emit-byte [lit]   5 cc-emit-byte   \ jne +5
  [lit] 190 cc-emit-byte [lit] 1089 cc-emit-4le   \ mov esi, 0x441
  [lit]  95 cc-emit-byte                          \ pop rdi
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte [lit]   2 cc-emit-4le    \ mov rax, 2
  [lit] 186 cc-emit-byte [lit] 420 cc-emit-4le    \ mov edx, 0644
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  72 cc-emit-byte [lit] 133 cc-emit-byte
  [lit] 192 cc-emit-byte                          \ test rax, rax
  [lit] 121 cc-emit-byte [lit]   2 cc-emit-byte   \ jns +2
  [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte   \ xor eax, eax
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- fclose(FILE *fp) -> 0.  12 bytes.
\
\   mov rax, 3    48 C7 C0 03 00 00 00  (close syscall)
\   syscall       0F 05
\   xor eax, eax  31 C0
\   ret           C3
: cc-emit-fclose-shim
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte [lit]   3 cc-emit-4le    \ mov rax, 3
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte   \ xor eax, eax
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- fwrite(void *ptr, size_t sz, size_t n, FILE *fp) -> bytes written.  20 bytes.
\
\   imul rdx, rsi  48 0F AF D6   (total = n * sz;  rdx=n, rsi=sz)
\   mov rsi, rdi   48 89 FE      (buf = ptr)
\   mov rdi, rcx   48 89 CF      (fd = arg4)
\   mov rax, 1     48 C7 C0 01 00 00 00
\   syscall        0F 05
\   ret            C3
: cc-emit-fwrite-shim
  [lit]  72 cc-emit-byte [lit]  15 cc-emit-byte
  [lit] 175 cc-emit-byte [lit] 214 cc-emit-byte   \ imul rdx, rsi
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 254 cc-emit-byte                          \ mov rsi, rdi  (buf)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 207 cc-emit-byte                          \ mov rdi, rcx  (fd)
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte [lit]   1 cc-emit-4le    \ mov rax, 1
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- fread(void *ptr, size_t sz, size_t n, FILE *fp) -> elements read.  30 bytes.
\
\   push rsi         56               (save sz)
\   imul rsi, rdx    48 0F AF F2      (total = sz * n)
\   mov rdx, rsi     48 89 F2         (count)
\   mov rsi, rdi     48 89 FE         (buf = ptr)
\   mov rdi, rcx     48 89 CF         (fd = arg4)
\   xor eax, eax     31 C0            (read = 0)
\   syscall          0F 05
\   pop rcx          59               (restore sz)
\   test rax, rax    48 85 C0
\   jle +5  (.done)  7E 05
\   xor edx, edx     31 D2            (clear for div)
\   div rcx          48 F7 F1         (rax = bytes_read / sz)
\ .done:
\   ret              C3
: cc-emit-fread-shim
  [lit]  86 cc-emit-byte                          \ push rsi
  [lit]  72 cc-emit-byte [lit]  15 cc-emit-byte
  [lit] 175 cc-emit-byte [lit] 242 cc-emit-byte   \ imul rsi, rdx
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 242 cc-emit-byte                          \ mov rdx, rsi  (count)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 254 cc-emit-byte                          \ mov rsi, rdi  (buf)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 207 cc-emit-byte                          \ mov rdi, rcx  (fd)
  [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte   \ xor eax, eax
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  89 cc-emit-byte                          \ pop rcx  (sz)
  [lit]  72 cc-emit-byte [lit] 133 cc-emit-byte
  [lit] 192 cc-emit-byte                          \ test rax, rax
  [lit] 126 cc-emit-byte [lit]   5 cc-emit-byte   \ jle +5
  [lit]  49 cc-emit-byte [lit] 210 cc-emit-byte   \ xor edx, edx
  [lit]  72 cc-emit-byte [lit] 247 cc-emit-byte
  [lit] 241 cc-emit-byte                          \ div rcx
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- calloc(size_t n, size_t sz) -> zeroed memory or NULL.  113 bytes.
\
\ Bump allocator backed by a single 16 MB mmap.  heap_base and heap_pos
\ are stored as inline 8-byte data slots immediately after the ret.
\ All RIP-relative displacements are fixed because the shim is a closed
\ region; the offsets below are exact (verified by hand):
\
\   heap_base @ shim_offset 97  (rip+0x58 from @2, rip+0x2A from @48)
\   heap_pos  @ shim_offset 105 (rip+0x2B from @55, rip+0x16 from @76,
\                                 rip+0x09 from @89)
\
\   push rdi                    57
\   push rsi                    56
\   mov rax, [rip+0x58]         48 8B 05 58 00 00 00  (heap_base)
\   test rax, rax               48 85 C0
\   jnz +48  (.have_heap)       75 30
\   xor edi, edi                31 FF
\   mov esi, 0x1000000          BE 00 00 00 01
\   mov edx, 3                  BA 03 00 00 00   (PROT_READ|PROT_WRITE)
\   mov r10d, 0x22              41 BA 22 00 00 00  (MAP_PRIVATE|MAP_ANONYMOUS)
\   mov r8d, -1                 41 B8 FF FF FF FF  (no fd)
\   xor r9d, r9d                45 31 C9           (offset=0)
\   mov eax, 9                  B8 09 00 00 00     (mmap)
\   syscall                     0F 05
\   mov [rip+0x2A], rax         48 89 05 2A 00 00 00  (heap_base)
\   mov [rip+0x2B], rax         48 89 05 2B 00 00 00  (heap_pos)
\ .have_heap:
\   pop rsi                     5E
\   pop rdi                     5F
\   imul rdi, rsi               48 0F AF FE   (total = n*sz)
\   add rdi, 7                  48 83 C7 07   (align8)
\   and rdi, -8                 48 83 E7 F8
\   mov rax, [rip+0x16]         48 8B 05 16 00 00 00  (heap_pos = cur)
\   mov rcx, rax                48 89 C1
\   add rcx, rdi                48 01 F9      (new_pos = cur + size)
\   mov [rip+0x09], rcx         48 89 0D 09 00 00 00  (heap_pos = new_pos)
\   ret                         C3
\   heap_base: 8 zero bytes     (mmap is zero-filled by Linux)
\   heap_pos:  8 zero bytes
: cc-emit-calloc-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  86 cc-emit-byte                          \ push rsi
  [lit]  72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit]   5 cc-emit-byte [lit]  88 cc-emit-4le    \ mov rax, [rip+0x58]
  [lit]  72 cc-emit-byte [lit] 133 cc-emit-byte
  [lit] 192 cc-emit-byte                          \ test rax, rax
  [lit] 117 cc-emit-byte [lit]  48 cc-emit-byte   \ jnz +48 (.have_heap)
  [lit]  49 cc-emit-byte [lit] 255 cc-emit-byte   \ xor edi, edi
  [lit] 190 cc-emit-byte [lit] 268435456 cc-emit-4le  \ mov esi, 0x10000000 (256 MB heap)
  [lit] 186 cc-emit-byte [lit]   3 cc-emit-4le    \ mov edx, 3
  [lit]  65 cc-emit-byte [lit] 186 cc-emit-byte
  [lit]  34 cc-emit-4le                           \ mov r10d, 0x22
  [lit]  65 cc-emit-byte [lit] 184 cc-emit-byte
  [lit] 255 cc-emit-byte [lit] 255 cc-emit-byte
  [lit] 255 cc-emit-byte [lit] 255 cc-emit-byte   \ mov r8d, -1  (4 explicit bytes)
  [lit]  69 cc-emit-byte [lit]  49 cc-emit-byte
  [lit] 201 cc-emit-byte                          \ xor r9d, r9d
  [lit] 184 cc-emit-byte [lit]   9 cc-emit-4le    \ mov eax, 9
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit]   5 cc-emit-byte [lit]  42 cc-emit-4le    \ mov [rip+0x2A], rax (heap_base)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit]   5 cc-emit-byte [lit]  43 cc-emit-4le    \ mov [rip+0x2B], rax (heap_pos)
  [lit]  94 cc-emit-byte                          \ pop rsi
  [lit]  95 cc-emit-byte                          \ pop rdi
  [lit]  72 cc-emit-byte [lit]  15 cc-emit-byte
  [lit] 175 cc-emit-byte [lit] 254 cc-emit-byte   \ imul rdi, rsi
  [lit]  72 cc-emit-byte [lit] 131 cc-emit-byte
  [lit] 199 cc-emit-byte [lit]   7 cc-emit-byte   \ add rdi, 7
  [lit]  72 cc-emit-byte [lit] 131 cc-emit-byte
  [lit] 231 cc-emit-byte [lit] 248 cc-emit-byte   \ and rdi, -8
  [lit]  72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit]   5 cc-emit-byte [lit]  22 cc-emit-4le    \ mov rax, [rip+0x16] (heap_pos)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 193 cc-emit-byte                          \ mov rcx, rax
  [lit]  72 cc-emit-byte [lit]   1 cc-emit-byte
  [lit] 249 cc-emit-byte                          \ add rcx, rdi
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit]  13 cc-emit-byte [lit]   9 cc-emit-4le    \ mov [rip+0x09], rcx (heap_pos)
  [lit] 195 cc-emit-byte                          \ ret
  [lit]   0 cc-emit-8le                           \ heap_base = 0
  [lit]   0 cc-emit-8le ;                         \ heap_pos  = 0

\ -- free(void *p) -> void.  1 byte.  No-op: bump allocator never frees.
: cc-emit-free-shim
  [lit] 195 cc-emit-byte ;                        \ ret

```

These eleven shims are the entire libc the compiled programs see.
No `printf`, no `malloc` with `free`, no `strcmp`, no `errno` —
just write, read, open/close, mmap-backed allocation, and `exit`.

The shape of each shim is the same: load syscall number into
`rax`, move/preserve SYS-V arg registers into the right syscall
registers (which are *different* — Linux uses `rdi/rsi/rdx/r10/
r8/r9` for syscalls, while SYS-V uses `rdi/rsi/rdx/rcx/r8/r9` for
function calls), `syscall`, fix up the return value if needed,
`ret`.

`putchar` (29 bytes) takes its byte in `rdi`, pushes it onto the
stack, points `rsi` at the stack to get a 1-byte buffer, sets fd
to 1, syscall 1 (write), pops, returns.  The "push to make a
buffer" idiom is recurring — it's how the shims that need a
1-byte buffer in memory avoid carrying around a global scratch
byte.

`exit` (10 bytes) is the simplest: `mov rax, 60 ; syscall`.  The
`ret` is unreachable (the kernel never returns from `exit`) but
keeps the shim well-formed.

`getchar` (48 bytes) is the most intricate of the trio: the
`read` syscall returns 0 at EOF, but C's `getchar` returns -1
(`EOF`).  The shim branches on `rax == 0`, returns `-1` on EOF or
the byte read otherwise.  Two near jumps (`75 09` and `EB 05`)
skip exactly the right number of bytes; the displacements are
hand-calculated against the shim's internal layout.

`fputs`, `fputc`, `fopen`, `fclose`, `fwrite`, `fread` follow the
same pattern with their own argument shuffles.  `fopen` is the
most involved (51 bytes) because it has to parse the mode-string
character to pick between `O_RDONLY`, `O_WRONLY|O_CREAT|O_TRUNC`,
and `O_WRONLY|O_CREAT|O_APPEND` — `cmp eax, 'w'` and `cmp eax,
'a'` against the first byte of the mode string.

`calloc` (113 bytes) is the heart of the runtime.  On first call,
it mmaps a 256 MiB anonymous private region via syscall 9 and
stashes the base address into an inline data slot just past its
own `ret`.  On every call thereafter it bumps a position pointer
forward by the rounded-up size.  Zero-fill is free because Linux
zero-fills anonymous mmaps.

The inline `heap_base` and `heap_pos` slots are accessed via
RIP-relative `mov` instructions whose displacements are computed
*by hand* and baked into the source.  Three call sites read
`heap_pos` at three different RIP-relative offsets (`+0x16`,
`+0x09`, `-0x2B`) — none of them is mechanically derived from a
label; all three are the result of counting bytes.  This is the
fragile shim of the bunch: any change to the prologue's
byte count shifts every RIP-relative displacement.

`free` (1 byte: just `ret`) is the punchline.  The bump allocator
never reclaims memory.  In a 256 MiB heap with M2-Planet's small
working set, that's fine for the duration of one compilation.

These shims are *emitted into the code segment* at compile-time
startup — Ch 31's `cc-emit-shims` calls each `cc-emit-X-shim`
in sequence and registers the resulting vaddr in the symbol
table.  User code calling `putchar(c)` then resolves to a normal
`call rel32` into the emitted shim.

## 4. Bitwise, shifts, inc/dec, and unary `!`

```forth file=090-cc-emit.fth
\ ===========================================================================
\ Shifts, bitwise ops, inc/dec/neg/not on rdi
\ ===========================================================================
\ Variable-count shifts use rcx (specifically CL).  The binary-op pattern
\ leaves rdi=left and rcx=right (already in rcx because of mov rcx,rdi+pop).
\
\ shl rdi, cl: 48 D3 E7   (D3 /4, mod=11 rm=rdi=7 -> 11_100_111=0xE7)
: cc-emit-shl-rdi-cl
  [lit]  72 cc-emit-byte
  [lit] 211 cc-emit-byte
  [lit] 231 cc-emit-byte ;

\ sar rdi, cl (arithmetic right shift, signed): 48 D3 FF  (D3 /7 -> 11_111_111=0xFF)
: cc-emit-sar-rdi-cl
  [lit]  72 cc-emit-byte
  [lit] 211 cc-emit-byte
  [lit] 255 cc-emit-byte ;

\ and rdi, rcx: 48 21 CF  (21 /r, mod=11 reg=rcx=1 rm=rdi=7 -> 11_001_111=0xCF)
: cc-emit-and-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]  33 cc-emit-byte
  [lit] 207 cc-emit-byte ;

\ or rdi, rcx: 48 09 CF
: cc-emit-or-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]   9 cc-emit-byte
  [lit] 207 cc-emit-byte ;

\ xor rdi, rcx: 48 31 CF
: cc-emit-xor-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]  49 cc-emit-byte
  [lit] 207 cc-emit-byte ;

\ not rdi: 48 F7 D7  (F7 /2 = NOT, mod=11 rm=rdi=7 -> 11_010_111=0xD7)
: cc-emit-not-rdi
  [lit]  72 cc-emit-byte
  [lit] 247 cc-emit-byte
  [lit] 215 cc-emit-byte ;

\ neg rdi: 48 F7 DF  (F7 /3 = NEG, mod=11 rm=rdi=7 -> 11_011_111=0xDF)
: cc-emit-neg-rdi
  [lit]  72 cc-emit-byte
  [lit] 247 cc-emit-byte
  [lit] 223 cc-emit-byte ;

\ inc qword [rbp + disp8]: 48 FF 45 <disp8>
\ ModR/M(mod=01, reg=/0=INC, rm=rbp=5) = 01_000_101 = 0x45.  Increments the
\ local slot in place without disturbing rdi/rcx (used by post-increment).
: cc-emit-inc-mem-local                           ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 255 cc-emit-byte
  [lit]  69 cc-emit-byte
  cc-disp8-from-slot cc-emit-byte ;

\ dec qword [rbp + disp8]: 48 FF 4D <disp8>
\ ModR/M(mod=01, reg=/1=DEC, rm=rbp=5) = 01_001_101 = 0x4D.
: cc-emit-dec-mem-local                           ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 255 cc-emit-byte
  [lit]  77 cc-emit-byte
  cc-disp8-from-slot cc-emit-byte ;

\ cc-emit-not-zero-flag.  Canonicalize rdi to 0/1 = (rdi == 0).
\ Pattern: xor rax,rax; test rdi,rdi; sete al; mov rdi,rax.  Used by unary '!'.
: cc-emit-not-zero-flag
  [lit]  72 cc-emit-byte [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte
                                                  \ xor rax,rax
  [lit]  72 cc-emit-byte [lit] 133 cc-emit-byte [lit] 255 cc-emit-byte
                                                  \ test rdi,rdi
  [lit]  15 cc-emit-byte [lit] 148 cc-emit-byte [lit] 192 cc-emit-byte
                                                  \ sete al
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 199 cc-emit-byte ;
                                                  \ mov rdi,rax

```

The variable-count shifts `shl rdi, cl` and `sar rdi, cl` use
`cl` (the low byte of `rcx`) because x86 hard-codes `cl` as the
shift-count register.  The binary-op pattern leaves the right
operand in `rcx`, which is `cl`-prefix-compatible — no extra
move is needed.

`sar` is *arithmetic* right shift, which sign-extends the
top bit.  That matches C's right-shift semantics for signed `int`
(implementation-defined but universally arithmetic on x86); for
unsigned shifts a `shr rdi, cl` would replace `sar`.  This
compiler only supports signed `int`, so `sar` is sufficient.

`inc qword [rbp + disp8]` and `dec qword [rbp + disp8]` are the
in-place increment/decrement of local slots.  They bypass `rdi`
entirely — the binary-op pattern doesn't apply because there's no
"right operand"; you just bump the memory and move on.  Used by
post-increment (`i++`), which needs the *old* value of `i` and
then the increment, but the increment doesn't perturb `rdi`'s
current contents.

`cc-emit-not-zero-flag` is C's unary `!`: 12 bytes that compute
`rdi := (rdi == 0) ? 1 : 0`.  The pattern is identical to the
comparison helpers from Ch 25 §6, swapping `cmp rdi, rcx` for
`test rdi, rdi`.

## 5. File-scope globals and deferred vaddr fixups

```forth file=090-cc-emit.fth
\ ===========================================================================
\ File-scope global variables.
\ ===========================================================================
\ Globals are accumulated in a parallel buffer (cc-globals-buf) during
\ parsing.  Each global gets a SLOT offset into that buffer (0 for the first
\ one, +8 for each subsequent qword, +N*8 for arrays).  Initializer bytes
\ are written directly into cc-globals-buf at the slot offset; uninitialized
\ globals stay zero (Forth `allot` zeroes the memory).
\
\ At codegen time, an IDENT referring to a sk-global emits
\     movabs rdi, <imm64 placeholder = 0>          ; 10 bytes
\ and records (patch-offset-in-cc-out-buf, slot) into the cc-gfixup arrays.
\
\ At cc-finalize-globals (called after parsing, before cc-finalize-elf):
\   1. cc-globals-base-vaddr := cc-base-vaddr + cc-out-pos@.
\   2. Append cc-globals-buf bytes to cc-out-buf.
\   3. For each fixup, compute vaddr = cc-globals-base-vaddr + slot, then
\      patch the placeholder imm64 in cc-out-buf at the recorded patch-offset.
\
\ This places the globals immediately after the code in the same PT_LOAD
\ segment — no holes, no extra phdr.

[lit] 4096 constant cc-globals-cap
create cc-globals-buf  cc-globals-cap allot
variable cc-globals-pos

\ Capacity for deferred global-vaddr fixups.  M2-Planet's cc_core.c emits
\ ~891 global references — 256 is far too low; 4096 gives healthy headroom.
[lit] 4096 constant cc-gfixup-cap
create cc-gfixup-out-pos  cc-gfixup-cap [lit] 8 * allot
create cc-gfixup-slot     cc-gfixup-cap [lit] 8 * allot
variable cc-gfixup-count

variable cc-globals-base-vaddr                   \ set by cc-finalize-globals

\ cc-globals-init ( -- )  Reset globals + fixup state at the start of compile.
: cc-globals-init
  [lit] 0 cc-globals-pos !
  [lit] 0 cc-gfixup-count !
  [lit] 0 cc-globals-base-vaddr !
  \ Zero the globals buffer so uninitialized globals are guaranteed zero
  \ even if a previous run left bytes in there.  Loop walks i = 0..cap-1.
  [lit] 0
  begin, dup cc-globals-cap < while,
    [lit] 0 over cc-globals-buf + c!
    [lit] 1 +
  repeat, drop ;

\ cc-globals-alloc ( bytes -- slot )  Reserve `bytes` bytes; return the offset
\ of the first reserved byte.  Aborts if cc-globals-buf would overflow.
: cc-globals-alloc                                 ( bytes -- slot )
  cc-globals-pos @                                 ( bytes slot )
  swap                                              ( slot bytes )
  cc-globals-pos +!
  cc-globals-pos @ cc-globals-cap > if,
    [lit] 70 die
  then, ;

\ cc-globals-store-8le ( v slot -- )  Write `v` as 8-byte LE into globals-buf
\ at the given slot offset.
: cc-globals-store-8le                             ( v slot -- )
  cc-globals-buf +                                 ( v addr )
  >r                                                ( v ; R: addr )
  dup r@                       c!
  [lit] 256 / dup r@ [lit] 1 + c!
  [lit] 256 / dup r@ [lit] 2 + c!
  [lit] 256 / dup r@ [lit] 3 + c!
  [lit] 256 / dup r@ [lit] 4 + c!
  [lit] 256 / dup r@ [lit] 5 + c!
  [lit] 256 / dup r@ [lit] 6 + c!
  [lit] 256 /     r> [lit] 7 + c! ;

\ cc-gfixup-add ( patch-offset slot -- )  Record a deferred global-vaddr fixup.
\ Uses sym-slot (from 070-cc-sym.fth, signature `( id arr -- addr )`) since it's a
\ generic helper that just computes arr + 8*id.
: cc-gfixup-add                                    ( patch-off slot -- )
  cc-gfixup-count @ dup cc-gfixup-cap >= if,
    [lit] 71 die
  then,
  ( patch-off slot i )
  >r                                                \ park i on rstack
  r@ cc-gfixup-slot     sym-slot !                 \ store slot
  r@ cc-gfixup-out-pos  sym-slot !                 \ store patch-off
  r> drop
  [lit] 1 cc-gfixup-count +! ;

\ cc-emit-global-ref ( slot -- )  Emit `movabs rdi, <vaddr placeholder>` and
\ record a deferred fixup so the imm64 will be patched to cc-globals-base-
\ vaddr + slot once globals are placed.  Used by the sk-global IDENT path in
\ cc-parse-primary.
: cc-emit-global-ref                                ( slot -- )
  [lit]  72 cc-emit-byte                            \ REX.W (0x48)
  [lit] 191 cc-emit-byte                            \ B7 + 7 = BF (movabs rdi)
  cc-out-pos @                                      ( slot patch-off )
  [lit] 0 cc-emit-8le                               \ imm64 placeholder
  swap cc-gfixup-add ;
```

The globals machinery answers the question: *where do file-scope
variables live in the output?*  The answer is "immediately after
the code, in the same PT_LOAD segment."

`cc-globals-buf` is a 4 KiB scratch area that accumulates global
initialisers during parsing.  Each global's declaration calls
`cc-globals-alloc <bytes>` to reserve a slot, and possibly
`cc-globals-store-8le` to write its initialiser.

A *reference* to a global from compiled code is a 10-byte `movabs
rdi, imm64` whose imm64 is initially 0.  `cc-emit-global-ref`
emits the placeholder and records `(patch-offset, slot)` in the
parallel arrays `cc-gfixup-out-pos[]` and `cc-gfixup-slot[]`.

At the end of compilation, Ch 32's driver calls
`cc-finalize-globals` (defined in Ch 31's `110-cc-decl.fth`):

1. Note `cc-out-pos` and set `cc-globals-base-vaddr = cc-base-vaddr +
   cc-out-pos`.
2. Append `cc-globals-buf` bytes to `cc-out-buf`, advancing
   `cc-out-pos` past the global data.
3. For every recorded fixup, compute the actual vaddr
   `cc-globals-base-vaddr + slot` and patch the placeholder imm64
   in `cc-out-buf` at the recorded `patch-offset`.

After that, `cc-finalize-elf` (Ch 25 §1) patches the program
header's `p_filesz`, and `cc-write-output` (Ch 21 §2) writes the
buffer.

The 4096-entry fixup cap matters: M2-Planet's `cc_core.c` emits
about 891 references to globals.  256 would overflow; 4096 leaves
healthy headroom.  The capacity numbers throughout the compiler
are all sized for M2-Planet plus a comfort factor.

`sym-slot` (from Ch 24, `070-cc-sym.fth`) is reused here because
it's just `arr + 8*id` — it doesn't care that this isn't the
symbol table.  The same one-cell-per-slot discipline gives us
`cc-gfixup-slot[i]` for free.

## 6. The path back together

`090-cc-emit.fth` is now 1027 lines of compiler-side machine-code
emission.  The compiler uses it three ways:

- **Per-instruction encoders** (Chs 25 §3–§7) write the bytes of
  one x86-64 instruction at a time.  Expression codegen (Ch 27)
  composes these into right-hand sides of `=`, while statement
  codegen (Ch 30) composes them into the bodies of `if` /
  `while` / `for` / `return`.
- **Prologue/epilogue + locals + param-spills** (Ch 25 §4–§5) are
  the codegen ingredients of function definitions.  Ch 31's
  `cc-parse-function` calls each in sequence.
- **Shims + globals + forward-call fixups** (this chapter) are the
  scaffolding the compiled program needs to run.  Ch 31 emits the
  shims at startup; Ch 27's `cc-parse-primary` walks the call /
  global paths; Ch 32 wires the whole thing together.

If you read `cc-emit-byte` as "primitive output" and follow each
of the named encoders one rung higher, you have the full
output-side picture of the compiler.

## Try it

```sh
./build.sh
tests/cc/stage-a-check.sh        # full bootstrap-gate
```

To exercise just the shim emission, compile a one-line program:

```sh
./build.sh
echo 'int main(void) { putchar(42); return 0; }' \
  | ./seed-forth -e 'include 010-lib.fth  include 020-cc-arena.fth
                     include 030-cc-io.fth  include 040-cc-prep.fth
                     include 050-cc-lex.fth  include 060-cc-types.fth
                     include 070-cc-sym.fth  include 080-cc-elf.fth
                     include 090-cc-emit.fth  include 100-cc-expr.fth
                     include 110-cc-decl.fth  include 120-cc-main.fth
                     cc-compile  bye'
chmod +x a.out && ./a.out         # prints '*'
```

(The wiring command depends on which top-level driver your build
calls; the stage-A check is easier and tests everything.)

## Exercises

1. The `calloc` shim is 113 bytes and uses hand-counted RIP-
   relative offsets.  Add a 16-byte alignment padding to the
   prologue and confirm which displacements need to change.

2. `free` is a 1-byte `ret`.  Construct a test program that
   relies on `free` reclaiming memory; observe how the bump
   allocator handles it.  Could a free-list be retrofitted?

3. `fopen` recognises only `r`, `w`, `a` as the first byte of the
   mode string.  What does it do with `rb` or `r+`?  Trace one
   case.

4. The fixup-list mechanism in `cc-add-fixup-to-list` is the
   same shape as a Lisp cons-cell.  Could the compiler reuse a
   single generic list type for both forward-call fixups and
   global fixups?  What would the consolidation save?

5. The string-bytes decoder handles seven escapes.  Add `\xNN`
   (two-hex-digit escape).  Where in the codegen does the new
   case go?

## Takeaways

- Deferred resolution is the dominant pattern of the codegen.
  Placeholders go in, fixup metadata is stashed, and a sweep
  at the end patches everything.  Three independent fixup
  systems (forward calls via `cc-sym-extra2`, global vaddrs
  via `cc-gfixup-*`, ELF segment sizes via `cc-out-patch-4le`)
  coexist without interference.
- Libc is not a dependency; it's emitted inline.  Eleven shims
  amounting to ~400 bytes give the compiled programs `putchar`,
  `exit`, file I/O, and a 256 MiB bump-allocated heap.
- Globals share the single R-W-X PT_LOAD segment with code,
  appended after the last byte of the last function.  No
  separate `.data` phdr, no relocation table, no dynamic linker.

Next: Chapter 27 — Expressions, Part 1: Precedence Climbing.
