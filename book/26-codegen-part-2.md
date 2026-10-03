# Chapter 26 — Codegen, Part 2: Calls, Shims, and Globals

```text
Missing capability: emitted code cannot refer to unknown functions, globals, strings, or runtime services.
New pattern: emit placeholders, thread fixup lists, and finalize shims, strings, and globals later.
Artifact after this chapter: calls, libc shims, string storage, global storage, and wide-immediate fixups.
Proof link: Stage-A programs can use calls, file-scope data, and forward references without relocations.
```

Every encoder in Ch 25 takes operands that are known when it runs.
The first statement of `tri.c`'s `main`, `t.rows = ROWS;`, has no
such luck.  It must load the address of `t`, and `t` will live just
past the last byte of code, which the compiler reaches only after
writing the rest of `main`.  A compiler that writes machine code front
to back keeps meeting such numbers: a call to a function defined
further down, a file-scope global, a string literal the code must jump
over.  The compiled program also needs a C runtime (`tri.c` calls
`putchar`), and there is no libc to link against.

This chapter finishes `090-cc-emit.fth` (lines 434–1328) and answers
both problems.  Wide-immediate placeholders and fixup lists let
codegen reference forward-declared functions and not-yet-placed
globals.  Nineteen libc shims, emitted straight into the output as
machine code, stand in for the C runtime.  A separate globals buffer,
appended after the code at the end, holds file-scope data, and global
arrays get zeroed memory past the end of the file.  Every
deferred address is handled the same way: emit a placeholder, remember
where it is, patch it when the value is known.

The callers come later: string literals and global rvalues in Ch 28's
`cc-parse-primary`, prologue/epilogue use and fixup-list walking in
Ch 31's `cc-parse-function`.

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

\ cc-emit-mov-rdi-int ( v -- )  Load an integer literal into rdi using the
\ shortest correct encoding.  `mov rdi, imm32` (7 bytes) sign-extends its
\ 32-bit field, so it only represents values in signed-32 range; a wider
\ constant (e.g. 0x80000000 or 2^32) would be sign-extended or truncated.
\ For those, fall back to the 10-byte `movabs rdi, imm64`.  C literals are
\ always non-negative here (a leading `-` is unary minus, applied later), so
\ only the upper bound needs checking — which keeps every in-range constant
\ on the exact imm32 bytes it emitted before.
: cc-emit-mov-rdi-int                             ( v -- )
  cc-target-lp64 @ if,
    \ Unsigned magnitude also catches literals with bit 63 set.
    dup [lit] 2147483648 / if,
      cc-emit-movabs-rdi-imm64
    else, cc-emit-mov-rdi-imm32 then,
    exit,
  then,
  dup [lit] 2147483647 > if,
    cc-emit-movabs-rdi-imm64
  else,
    cc-emit-mov-rdi-imm32
  then, ;

\ cc-emit-movabs-rdi-imm64-placeholder ( -- patch-offset )
\ Emits `48 BF 00 00 00 00 00 00 00 00`; returns the imm64 file-offset.
\ Used when a forward-declared function's name is taken as an rvalue
\ (function-pointer load) before its definition is reached.  Caller threads
\ patch-offset onto the prototype symbol's cc-sym-addr-fixups list; the
\ list is walked and each 8-byte imm64 is patched to the function's real
\ vaddr when cc-parse-function processes its definition.
: cc-emit-movabs-rdi-imm64-placeholder
  [lit]  72 cc-emit-byte
  [lit] 191 cc-emit-byte
  cc-out-pos @
  [lit] 0 cc-emit-8le ;

```

`cc-emit-movabs-rdi-imm64` is the 10-byte encoder for `movabs rdi,
<imm64>`: `48 BF <8 bytes LE>`.  It is the only x86-64 instruction
that loads a full 64-bit immediate into a register.  The smaller `mov
rdi, imm32` (Ch 25 §3) sign-extends a 32-bit constant and can't reach
vaddrs above `0x7FFFFFFF`.  Every vaddr this compiler emits sits just
above `0x400000`, so the narrow form would reach them too; the wide
form is a simplicity choice.  One fixed 10-byte shape takes an
absolute vaddr as-is, needs no range check, and gives every
placeholder the same 8-byte slot to patch: string addresses here, and
forward function pointers and globals below.

`cc-emit-mov-rdi-int` picks between the two for an *integer literal*.
`int` is 64-bit here, but `mov rdi, imm32` sign-extends, so on its own
it would load `0x80000000` as a negative number and truncate `2^32` to
zero.  The helper keeps the compact 7-byte form for any value in
signed-32 range (every constant M2-Planet uses) and falls back to the
10-byte `movabs` only when the literal needs more than 32 bits.  C
negatives arrive as unary minus applied to a non-negative literal, so
a single upper-bound test suffices.

`cc-emit-movabs-rdi-imm64-placeholder` is the deferred variant.  It
writes the same 10 bytes with the imm64 zeroed and returns the offset
of those 8 zero bytes in `cc-out-buf` so the caller can patch them
later.

```forth file=090-cc-emit.fth
\ cc-add-fixup-to-list ( fixup-offset list-var -- )  Allocate a 16-byte node
\ and prepend it to the linked list rooted at list-var.  Defined here so
\ 100-cc-expr.fth (loaded before 112-cc-stmt.fth) can reference it from the
\ forward-function-rvalue path in cc-parse-primary.
: cc-add-fixup-to-list                            ( off var -- )
  [lit] 16 cc-alloc                               ( off var node )
  >r                                              ( off var ; R: node )
  swap r@ !                                       ( var ; R: node )
  dup @ r@ [lit] 8 + !                            ( var ; R: node )
  r> swap ! ;                                     ( -- )

```

`cc-add-fixup-to-list` builds the linked list of patch sites.  It
allocates a 16-byte node with `cc-alloc` (Ch 21), stores the patch
offset at `[0]` and the old head at `[8]`, and points the list root
variable at the new node: an ordinary linked-list prepend.  Each node
looks like this:

```
+0:  patch-offset (into cc-out-buf)
+8:  next pointer (0 = end)
```

This is the emit-remember-patch pattern again, with "remember" grown
from one stack cell to a list of output offsets.  A forward-declared
function's prototype carries two such lists (Ch 24 §3):
`cc-sym-call-fixups` collects its `call rel32` sites, and
`cc-sym-addr-fixups` collects `movabs` sites that take its address as
a value.  When Ch 31's `cc-parse-function`
reaches the definition, it walks both and patches each recorded site
with the resolved address.  Ch 30's `break` and `continue` lists use
the same word.

The word lives here rather than in `112-cc-stmt.fth` because Ch 28's
`cc-parse-primary` needs it for the forward-function-rvalue path, and
`100-cc-expr.fth` loads before `112-cc-stmt.fth`.

## 2. String-literal bytes with C-escape decoding

```forth file=090-cc-emit.fth
\ ===========================================================================
\ String-literal byte emission with C-escape decoding.
\ ===========================================================================
\ Walks ( src-addr src-len ) and copies bytes into cc-out-buf, decoding each
\ escape with cc-decode-escape (050), the same table character literals
\ use.  Appends a trailing NUL byte.
\
\ Stack convention inside the loop: ( src len ).

: cc-emit-string-bytes                            ( src-addr src-len -- )
  begin,
    dup [lit] 0 >
  while,
    over c@ backslash = if,
      dup [lit] 2 >= if,
        \ Have at least one more byte for the escape.
        over 1+ cc-decode-escape                  ( src len byte n )
        swap cc-emit-byte 1+                      ( src len k )
        \ Advance src by k (the backslash and the escape), len by -k.
        >r swap r@ + swap r> -
      else,
        \ Trailing backslash with no follow-up char: emit literally.
        over c@ cc-emit-byte
        swap 1+ swap 1-
      then,
    else,
      over c@ cc-emit-byte
      swap 1+ swap 1-
    then,
  repeat,
  drop drop
  [lit] 0 cc-emit-byte ;                          \ trailing NUL terminator

```

The lexer (Ch 23) keeps backslash escapes as literal byte pairs inside
string-literal slices.  This is where they are decoded.

The walk is a `begin, while, repeat,` over `(src-addr, len)`: if the
current byte is a backslash and at least one more byte follows,
decode the pair with `cc-decode-escape` (Ch 23 §4), the table
character literals use; otherwise copy the byte verbatim.  Any
escaped character the table doesn't name passes through unchanged,
which is more permissive than ANSI C.

A trailing NUL is appended so string literals work with C's
`printf` / `puts`-style functions.

## 3. The libc shims: write/read/open/close/mmap

The nineteen shims in this section are the entire libc the compiled
programs see.
There is no `printf`, no `free` that frees, no `strcmp`, no
`errno`: just write, read, open/close, mmap-backed allocation, three
string functions and `exit`.  Ch 31's `cc-emit-shims` emits the first
eleven into the code segment at startup and registers each vaddr in
the symbol table, so a call to `putchar(c)` in user code is an
ordinary `call rel32` into the shim.  The last eight are emitted only
when called (end of this section).

All but `free` share one shape: marshal the arguments, load the
syscall number into `rax`, `syscall`, fix up the result, `ret`.  The
marshalling exists because the two conventions differ: Linux syscalls
take arguments in `rdi/rsi/rdx/r10/r8/r9`, while SYS-V function calls
use `rdi/rsi/rdx/rcx/r8/r9`.  No shim has a frame.  There is no `push
rbp` and no prologue; a shim uses a `push` only where it needs a
scratch byte or a saved register, then the matching `pop` and `ret`.

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

```

`putchar` (29 bytes) takes its byte in `rdi`, pushes it to get a
1-byte buffer on the stack, points `rsi` at it, sets fd 1, and calls
syscall 1 (write).  Pushing to make a buffer recurs in the shims that
need one byte of memory, and it saves carrying a global scratch byte.

`exit` (10 bytes) is the simplest: `mov rax, 60 ; syscall`.  The `ret`
is unreachable, since the kernel never returns from `exit`, but keeps
the shim well-formed.

```forth file=090-cc-emit.fth
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

```

`getchar` (48 bytes) uses the same push-a-buffer trick with syscall 0
(read).  `read` returns 0 at EOF, but C's `getchar` returns -1
(`EOF`), so the shim branches on `rax == 0`.  The two short jumps
(`75 09` and `EB 05`) skip exactly the right number of bytes; their
displacements are counted by hand against the shim's layout.

```forth file=090-cc-emit.fth
\ ===========================================================================
\ Libc shims: fputs, fputc, fopen, fclose, fwrite, fread, calloc,
\ free.  All follow SYS-V x86-64 ABI.  Symbol registration and
\ vaddr assignment happen in cc-emit-shims (116-cc-prog.fth).
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

```

`fputs` counts the string's length itself before calling write.
`fputc` pushes the character as a buffer, like `putchar`, but takes
the fd from its second argument and returns the character.

```forth file=090-cc-emit.fth
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
  [char] w  cc-emit-byte                          \ cmp eax, 'w'
  [lit] 117 cc-emit-byte [lit]   7 cc-emit-byte   \ jne +7
  [lit] 190 cc-emit-byte [lit] 577 cc-emit-4le    \ mov esi, 0x241
  [lit] 235 cc-emit-byte [lit]  10 cc-emit-byte   \ jmp +10
  [lit] 131 cc-emit-byte [lit] 248 cc-emit-byte
  [char] a  cc-emit-byte                          \ cmp eax, 'a'
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

```

`fopen` (51 bytes) is the most involved of these.  It turns the mode
string's first byte into open flags with `cmp eax, 'w'` and `cmp eax,
'a'`: `'w'` gives `O_WRONLY|O_CREAT|O_TRUNC`, `'a'` gives
`O_WRONLY|O_CREAT|O_APPEND`, and anything else `O_RDONLY`.  On failure
it returns 0 (NULL) instead of a negative errno.  `fclose` is syscall 3
followed by a zeroed return value.

```forth file=090-cc-emit.fth
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

```

`fwrite` and `fread` multiply `sz * n` into a byte count and move the
fd from the fourth argument register.  `fwrite` returns the raw byte
count from write; `fread` divides the bytes read by `sz` to return an
element count, as C requires.

```forth file=090-cc-emit.fth
\ -- calloc(size_t n, size_t sz) -> zeroed memory or NULL.  113 bytes.
\
\ Bump allocator backed by a single 256 MB mmap.  heap_base and heap_pos
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
\   mov esi, 0x10000000         BE 00 00 00 10
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

```

`calloc` (113 bytes) is the heart of the runtime.  On the first call
it mmaps a 256 MiB anonymous private region via syscall 9 and stores
the base in an inline data slot just past its own `ret`.  Every call
then bumps a position pointer forward by the rounded-up size.
Zero-fill costs nothing because Linux zero-fills anonymous mappings.

The inline `heap_base` and `heap_pos` slots are reached through
RIP-relative `mov` instructions whose displacements are counted by
hand and baked into the source.  `heap_pos` alone is touched at three
sites with three different displacements: the first-call setup stores
to it (`+0x2B`), the bump reads it (`+0x16`) and stores the new
position (`+0x09`).  None is derived from a label.  Each displacement
is the distance from the end of its instruction to the slot, so bytes
added at the top of the shim move the access and the data together
and change nothing.  Bytes added *between* an access and the slots
(anywhere in the body) shift every displacement ahead of the
insertion.  That makes this the fragile shim of the set.

```forth file=090-cc-emit.fth
\ -- free(void *p) -> void.  1 byte.  No-op: bump allocator never frees.
: cc-emit-free-shim
  [lit] 195 cc-emit-byte ;                        \ ret

```

`free` is 1 byte, just `ret`.  The bump allocator never reclaims
memory, and with a 256 MiB heap and M2-Planet's small working set,
that is fine for the duration of one compilation.

The last eight shims are for programs written against POSIX and
`<string.h>` rather than M2-Planet's small set: pnut calls `open`,
`read`, `write` and `close` on file descriptors, allocates with
`malloc`, and uses `strlen`, `memcpy` and `strrchr`.  Unlike the
eleven above, which every program carries, these are emitted only
into a program that calls them (Ch 31's late shims), so a program that
uses none is not a byte longer.

```forth file=090-cc-emit.fth
\ ===========================================================================
\ Libc shims: the POSIX calls open, read, write, close; malloc, and the
\ string functions strlen, memcpy, strrchr.
\ ===========================================================================

\ -- open / read / write / close: the arguments are already where the
\ syscall wants them (rdi, rsi, rdx), so each is the syscall plus C's
\ error convention: a negative result (Linux's -errno) becomes -1.  22 bytes.
\
\   mov eax, N          B8 <N>
\   syscall             0F 05
\   test rax, rax       48 85 C0
\   jns +7  (.ok)       79 07
\   mov rax, -1         48 C7 C0 FF FF FF FF
\ .ok:
\   ret                 C3
: cc-emit-syscall-shim                            ( n -- )
  [lit] 184 cc-emit-byte cc-emit-4le              \ mov eax, n
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  72 cc-emit-byte [lit] 133 cc-emit-byte
  [lit] 192 cc-emit-byte                          \ test rax, rax
  [lit] 121 cc-emit-byte [lit]   7 cc-emit-byte   \ jns +7
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 192 cc-emit-byte
  [lit] 255 cc-emit-byte [lit] 255 cc-emit-byte
  [lit] 255 cc-emit-byte [lit] 255 cc-emit-byte   \ mov rax, -1
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- malloc(size_t n) -> calloc(n, 1).  12 bytes.
\
\   mov rsi, 1          48 C7 C6 01 00 00 00
\   jmp calloc          E9 <rel32>
: cc-emit-malloc-shim                             ( calloc-vaddr -- )
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 198 cc-emit-byte [lit]   1 cc-emit-4le    \ mov rsi, 1
  [lit] 233 cc-emit-byte
  cc-here-vaddr [lit] 4 + - cc-emit-4le ;         \ jmp calloc

\ -- strlen(char *s) -> length.  14 bytes.
\
\   xor eax, eax             31 C0
\ .loop:
\   cmp byte [rdi+rax], 0    80 3C 07 00
\   je +5  (.done)           74 05
\   inc rax                  48 FF C0
\   jmp .loop                EB F5
\ .done:
\   ret                      C3
: cc-emit-strlen-shim
  [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte   \ xor eax, eax
  [lit] 128 cc-emit-byte [lit]  60 cc-emit-byte
  [lit]   7 cc-emit-byte [lit]   0 cc-emit-byte   \ cmp byte [rdi+rax], 0
  [lit] 116 cc-emit-byte [lit]   5 cc-emit-byte   \ je +5
  [lit]  72 cc-emit-byte [lit] 255 cc-emit-byte
  [lit] 192 cc-emit-byte                          \ inc rax
  [lit] 235 cc-emit-byte [lit] 245 cc-emit-byte   \ jmp .loop  (disp = -11)
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- memcpy(void *d, void *s, size_t n) -> d.  9 bytes.
\
\   mov rax, rdi     48 89 F8
\   mov rcx, rdx     48 89 D1
\   rep movsb        F3 A4           (rdi = d, rsi = s already)
\   ret              C3
: cc-emit-memcpy-shim
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 248 cc-emit-byte                          \ mov rax, rdi
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 209 cc-emit-byte                          \ mov rcx, rdx
  [lit] 243 cc-emit-byte [lit] 164 cc-emit-byte   \ rep movsb
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- strrchr(char *s, int c) -> pointer to the last c in s (the NUL
\ counts, so c = 0 finds the end), or NULL.  23 bytes.
\
\   xor eax, eax               31 C0
\ .loop:
\   movzx ecx, byte [rdi]      0F B6 0F
\   cmp cl, sil                40 38 F1
\   jne +3  (.skip)            75 03
\   mov rax, rdi               48 89 F8
\ .skip:
\   test cl, cl                84 C9
\   je +5  (.done)             74 05
\   inc rdi                    48 FF C7
\   jmp .loop                  EB EC
\ .done:
\   ret                        C3
: cc-emit-strrchr-shim
  [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte   \ xor eax, eax
  [lit]  15 cc-emit-byte [lit] 182 cc-emit-byte
  [lit]  15 cc-emit-byte                          \ movzx ecx, byte [rdi]
  [lit]  64 cc-emit-byte [lit]  56 cc-emit-byte
  [lit] 241 cc-emit-byte                          \ cmp cl, sil
  [lit] 117 cc-emit-byte [lit]   3 cc-emit-byte   \ jne +3
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 248 cc-emit-byte                          \ mov rax, rdi
  [lit] 132 cc-emit-byte [lit] 201 cc-emit-byte   \ test cl, cl
  [lit] 116 cc-emit-byte [lit]   5 cc-emit-byte   \ je +5
  [lit]  72 cc-emit-byte [lit] 255 cc-emit-byte
  [lit] 199 cc-emit-byte                          \ inc rdi
  [lit] 235 cc-emit-byte [lit] 236 cc-emit-byte   \ jmp .loop  (disp = -20)
  [lit] 195 cc-emit-byte ;                        \ ret

```

The four system calls share one body, `cc-emit-syscall-shim`: the C
arguments are already in `rdi`, `rsi` and `rdx`, where Linux wants
them, so the shim loads the call number and adds C's convention on
top: Linux answers `-errno`, C answers -1.  `malloc(n)` is
`calloc(n, 1)`: it sets the second argument and jumps into the calloc
shim, whose bump allocator already hands out zeroed memory.  The three
string functions are the obvious loops, each a few bytes.  `memcpy`
is the x86 string instruction `rep movsb`, which copies `rcx` bytes
from `[rsi]` to `[rdi]`.  `strrchr` keeps the last match in `rax` and
counts the terminating NUL as part of the string, as C does, so
`strrchr(s, 0)` finds the end.  Their short jumps are counted by hand,
like `getchar`'s; `tests/cc/P8-libc-shims.c` calls each of them.

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

\ inc qword [rbp + disp]: 48 FF 45 <disp8>  (or 48 FF 85 <disp32>)
\ ModR/M(mod=01, reg=/0=INC, rm=rbp=5) = 01_000_101 = 0x45.  Increments the
\ local slot in place without disturbing rdi/rcx (used by post-increment).
: cc-emit-inc-mem-local                           ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 255 cc-emit-byte
  [lit]  69 cc-emit-local-ea ;

\ dec qword [rbp + disp]: 48 FF 4D <disp8>  (or 48 FF 8D <disp32>)
\ ModR/M(mod=01, reg=/1=DEC, rm=rbp=5) = 01_001_101 = 0x4D.
: cc-emit-dec-mem-local                           ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 255 cc-emit-byte
  [lit]  77 cc-emit-local-ea ;

\ The same through the address in rcx, for a ++ / -- whose operand is a
\ pointer target, an element or a field (rcx holds its address).
\ byte? picks the one-byte form (a char).
\   inc qword [rcx]  48 FF 01      inc byte [rcx]  FE 01
\   dec qword [rcx]  48 FF 09      dec byte [rcx]  FE 09
: cc-emit-inc-via-rcx                             ( byte? -- )
  0= if, [lit] 72 cc-emit-byte [lit] 255 else, [lit] 254 then,
  cc-emit-byte  [lit] 1 cc-emit-byte ;
: cc-emit-dec-via-rcx                             ( byte? -- )
  0= if, [lit] 72 cc-emit-byte [lit] 255 else, [lit] 254 then,
  cc-emit-byte  [lit] 9 cc-emit-byte ;

\ mov rdi, [rcx]  48 8B 39   /  movzx rdi, byte [rcx]  48 0F B6 39
: cc-emit-load-via-rcx                            ( byte? -- )
  [lit] 72 cc-emit-byte
  if, [lit] 15 cc-emit-byte [lit] 182 else, [lit] 139 then,
  cc-emit-byte  [lit] 57 cc-emit-byte ;

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

The variable-count shifts `shl rdi, cl` and `sar rdi, cl` use `cl`
(the low byte of `rcx`) because x86 hard-codes `cl` as the shift-count
register.  The binary-op pattern already leaves the right operand in
`rcx`, so no extra move is needed.

`sar` is *arithmetic* right shift, which copies the sign bit.  That
matches C's right shift for signed `int` (implementation-defined, but
arithmetic on every x86 compiler).  An unsigned shift would need
`shr`, but this compiler only supports signed `int`.

`inc qword [rbp + disp]` and `dec qword [rbp + disp]` bump a local
slot in place (disp8 or disp32 per slot, via Ch 25's
`cc-emit-local-ea`).  They bypass `rdi` entirely, which is what
post-increment (`i++`) needs: `rdi` keeps the *old* value of `i`
while the slot is incremented.  `cc-emit-inc-via-rcx` and
`cc-emit-dec-via-rcx` do the same to memory whose address is in `rcx`,
a byte or a qword, and `cc-emit-load-via-rcx` reads it first: that is
`g++`, `a[i]--` and `++p->n` (Ch 28).

`cc-emit-not-zero-flag` is C's unary `!`: 12 bytes that compute `rdi
:= (rdi == 0) ? 1 : 0`, the comparison pattern from Ch 25 §6 with
`test rdi, rdi` in place of `cmp rdi, rcx`.

## 5. File-scope globals and deferred vaddr fixups

File-scope variables live immediately after the code, in the same
PT_LOAD segment: scalars in a *data* area that is part of the file,
arrays in a *bss* past the end of the file, which the kernel
zero-fills (Ch 25 §1).  The code's length isn't known until parsing
ends, so neither are the globals' addresses.

```forth file=090-cc-emit.fth
\ ===========================================================================
\ File-scope global variables.
\ ===========================================================================
\ Globals live in two areas placed after the code, in the same PT_LOAD
\ segment:
\   data  scalars, and whatever has an initializer.  Built in
\         cc-globals-buf during parsing (initializer bytes are written
\         straight in; the rest stays zero) and appended to the output
\         file.
\   bss   arrays.  They start zeroed, so they take no room in the file:
\         the segment's p_memsz simply extends past its p_filesz, and
\         the kernel zero-fills the difference.
\ Each global gets a SLOT: its offset in the data area, or cc-bss-flag
\ plus its offset in the bss.
\
\ At codegen time, an IDENT referring to a sk-global emits
\     movabs rdi, <imm64 placeholder = 0>          ; 10 bytes
\ and records (patch-offset-in-cc-out-buf, slot) into the cc-gfixup arrays.
\
\ At cc-finalize-globals (called after parsing, before cc-finalize-elf):
\   1. cc-globals-base-vaddr := cc-here-vaddr (080); the bss starts at
\      the first 8-aligned address after the data.
\   2. Append cc-globals-buf bytes to cc-out-buf.
\   3. For each fixup, compute the slot's vaddr and patch the placeholder
\      imm64 in cc-out-buf at the recorded patch-offset.

[lit] 65536 constant cc-globals-cap                \ data area: 64 KiB
create cc-globals-buf  cc-globals-cap allot
variable cc-globals-pos

[lit] 268435456 constant cc-bss-cap                \ bss: 256 MiB
variable cc-bss-pos
[lit] 1099511627776 constant cc-bss-flag           \ 2^40: "this slot is in the bss"

\ Capacity for deferred global-vaddr fixups (each use of a global's name
\ is one).  M2-Planet's source has about 1,600, and so has pnut's.
[lit] 16384 constant cc-gfixup-cap
create cc-gfixup-out-pos  cc-gfixup-cap [lit] 8 * allot
create cc-gfixup-slot     cc-gfixup-cap [lit] 8 * allot
variable cc-gfixup-count

variable cc-globals-base-vaddr                   \ set by cc-finalize-globals
variable cc-bss-base-vaddr                       \ set by cc-finalize-globals

```

`cc-globals-buf` is a 64 KiB area that accumulates the data area,
initialisers included, during parsing; M2-Planet needs 488 bytes of
it and pnut 848, because their arrays go to the bss.  The bss is only
a size, `cc-bss-pos`, capped at 256 MiB (code 82): pnut's global
arrays add up to 4.6 MB, which would not fit in any buffer of the
compiler, and need not, since the bss has no bytes in the file.  A
slot in the bss is marked by adding `cc-bss-flag`, 2^40, far above
any data offset, so one cell tells the two areas apart.  The
16,384-entry fixup cap is ten times what M2-Planet (about 1,600
references to globals) or pnut (about the same) needs.  Capacities
throughout the compiler follow the same rule: what the programs it
builds need, plus a comfort factor.

```forth file=090-cc-emit.fth
\ cc-globals-init ( -- )  Reset globals + fixup state at the start of compile.
: cc-globals-init
  [lit] 0 cc-globals-pos !
  [lit] 0 cc-bss-pos !
  [lit] 0 cc-gfixup-count !
  [lit] 0 cc-globals-base-vaddr !
  \ Zero the globals buffer so uninitialized globals are guaranteed zero
  \ even if a previous run left bytes in there.  Loop walks i = 0..cap-1.
  [lit] 0
  begin, dup cc-globals-cap < while,
    [lit] 0 over cc-globals-buf + c!
    1+
  repeat, drop ;

\ cc-globals-alloc ( bytes -- slot )  Reserve `bytes` bytes of the data
\ area; return the offset of the first reserved byte.  Dies with 80 if
\ cc-globals-buf would overflow.
: cc-globals-alloc                                 ( bytes -- slot )
  dup cc-globals-pos @ + cc-globals-cap [lit] 80 cc-check-cap
  cc-globals-pos @                                 ( bytes slot )
  swap                                              ( slot bytes )
  cc-globals-pos +! ;

\ cc-bss-alloc ( bytes -- slot )  Reserve `bytes` zeroed bytes in the bss;
\ return the slot (cc-bss-flag + offset).  Dies with 82 past cc-bss-cap.
: cc-bss-alloc                                     ( bytes -- slot )
  dup cc-bss-pos @ + cc-bss-cap [lit] 82 cc-check-cap
  cc-bss-pos @ cc-bss-flag +                       ( bytes slot )
  swap cc-bss-pos +! ;

\ cc-globals-store-8le ( v slot -- )  Write `v` as 8-byte LE into globals-buf
\ at the given slot offset.
: cc-globals-store-8le                             ( v slot -- )
  cc-globals-buf +                                 ( v addr )
  >r                                                ( v ; R: addr )
  dup r@                       c!
  [lit] 256 / dup r@ 1+ c!
  [lit] 256 / dup r@ [lit] 2 + c!
  [lit] 256 / dup r@ [lit] 3 + c!
  [lit] 256 / dup r@ [lit] 4 + c!
  [lit] 256 / dup r@ [lit] 5 + c!
  [lit] 256 / dup r@ [lit] 6 + c!
  [lit] 256 /     r> [lit] 7 + c! ;

\ cc-gfixup-add ( patch-offset slot -- )  Record a deferred global-vaddr fixup.
\ Indexes its two parallel arrays with cell[] (030-cc-io.fth).
: cc-gfixup-add                                    ( patch-off slot -- )
  cc-gfixup-count @ 1+ cc-gfixup-cap [lit] 81 cc-check-cap
  cc-gfixup-count @                                 ( patch-off slot i )
  >r                                                \ park i on rstack
  r@ cc-gfixup-slot     cell[] !                   \ store slot
  r@ cc-gfixup-out-pos  cell[] !                   \ store patch-off
  r> drop
  [lit] 1 cc-gfixup-count +! ;

\ cc-emit-global-ref ( slot -- )  Emit `movabs rdi, <vaddr placeholder>` and
\ record a deferred fixup so the imm64 will be patched to the slot's
\ address once globals are placed.  Used by the sk-global IDENT path in
\ cc-parse-primary.
: cc-emit-global-ref                                ( slot -- )
  [lit]  72 cc-emit-byte                            \ REX.W (0x48)
  [lit] 191 cc-emit-byte                            \ B7 + 7 = BF (movabs rdi)
  cc-out-pos @                                      ( slot patch-off )
  [lit] 0 cc-emit-8le                               \ imm64 placeholder
  swap cc-gfixup-add ;
```

## LP64 integer encoders

The direct target opts in with `cc-target-lp64`.  Its integer loads,
stores, and register conversions distinguish signed and unsigned
1-, 2-, 4-, and 8-byte values.  The wrappers leave the pinned target's
original encodings intact.  Conversion is separate from storing so
an assignment can both write the proper width and retain the converted
value.  Unsigned division, comparison, and right shift use the CPU's
unsigned forms after the parser converts both operands.

`tests/cc/lp64-encoders-check.py` asks the seed to emit each routine,
then runs it from private memory.  It checks narrowing boundaries,
neighboring-byte preservation, both local-displacement encodings,
full-width literals, and legacy opcode bytes without a host C compiler.

```forth file=090-cc-emit.fth

\ ===========================================================================
\ Opt-in LP64 integer encoders.
\ ===========================================================================
\ The original words above stay byte-identical.  The typed wrappers retain
\ their legacy encodings while cc-target-lp64 is 0.  Scalar floating types
\ have storage sizes in 060, but these words implement integer operations.
\ A typed store writes only the destination width; use convert-rdi first
\ when the assignment expression must retain a correctly converted result.

\ cc-emit-load-typed-via-rdi ( ty -- )  rdi := *(T *)rdi.
: cc-emit-type-check-noop ;
defer cc-emit-type-check-fwd
' cc-emit-type-check-noop is cc-emit-type-check-fwd

: cc-emit-load-typed-via-rdi
  cc-emit-type-check-fwd
  dup ty-size [lit] 1 = if,
    ty-unsigned? if, cc-emit-load-byte-via-rdi else,
      [lit] 72 cc-emit-byte [lit] 15 cc-emit-byte
      [lit] 190 cc-emit-byte [lit] 63 cc-emit-byte  \ movsx rdi, byte [rdi]
    then, exit,
  then,
  dup ty-size [lit] 2 = if,
    [lit] 72 cc-emit-byte [lit] 15 cc-emit-byte
    ty-unsigned? if, [lit] 183 else, [lit] 191 then, cc-emit-byte
    [lit] 63 cc-emit-byte exit,                    \ movzx/movsx rdi, word [rdi]
  then,
  dup ty-size [lit] 4 = if,
    ty-unsigned? if,
      [lit] 139 cc-emit-byte [lit] 63 cc-emit-byte  \ mov edi, [rdi]
    else,
      [lit] 72 cc-emit-byte [lit] 99 cc-emit-byte
      [lit] 63 cc-emit-byte                       \ movsxd rdi, dword [rdi]
    then, exit,
  then,
  drop cc-emit-load-via-rdi ;

\ cc-emit-store-typed-via-rcx ( ty -- )  *(T *)rcx := rdi.
: cc-emit-store-typed-via-rcx
  cc-emit-type-check-fwd
  ty-size
  dup [lit] 1 = if, drop cc-emit-store-byte-via-rcx exit, then,
  dup [lit] 2 = if,
    drop [lit] 102 cc-emit-byte [lit] 137 cc-emit-byte
    [lit] 57 cc-emit-byte exit,                    \ mov word [rcx], di
  then,
  [lit] 4 = if,
    [lit] 137 cc-emit-byte [lit] 57 cc-emit-byte    \ mov dword [rcx], edi
  else, cc-emit-store-via-rcx then, ;

\ cc-emit-convert-rdi ( ty -- )  Truncate/sign-extend the integer in rdi.
: cc-emit-convert-rdi
  cc-emit-type-check-fwd
  dup ty-size [lit] 1 = if,
    ty-unsigned? if, cc-emit-zx-byte-rdi else,
      [lit] 72 cc-emit-byte [lit] 15 cc-emit-byte
      [lit] 190 cc-emit-byte [lit] 255 cc-emit-byte \ movsx rdi, dil
    then, exit,
  then,
  dup ty-size [lit] 2 = if,
    [lit] 72 cc-emit-byte [lit] 15 cc-emit-byte
    ty-unsigned? if, [lit] 183 else, [lit] 191 then, cc-emit-byte
    [lit] 255 cc-emit-byte exit,                   \ movzx/movsx rdi, di
  then,
  dup ty-size [lit] 4 = if,
    ty-unsigned? if,
      [lit] 137 cc-emit-byte [lit] 255 cc-emit-byte \ mov edi, edi
    else,
      [lit] 72 cc-emit-byte [lit] 99 cc-emit-byte
      [lit] 255 cc-emit-byte                      \ movsxd rdi, edi
    then, exit,
  then,
  drop ;

\ Conversions with source type preserve the integer emitter by default.
: cc-emit-convert-value-default ( source destination -- ) nip cc-emit-convert-rdi ;
defer cc-emit-convert-value
' cc-emit-convert-value-default is cc-emit-convert-value

\ cc-emit-convert-rcx ( ty -- )  Same conversion for the right operand.
: cc-emit-convert-rcx
  cc-emit-type-check-fwd
  dup ty-size [lit] 1 = if,
    [lit] 72 cc-emit-byte [lit] 15 cc-emit-byte
    ty-unsigned? if, [lit] 182 else, [lit] 190 then, cc-emit-byte
    [lit] 201 cc-emit-byte exit,                   \ movzx/movsx rcx, cl
  then,
  dup ty-size [lit] 2 = if,
    [lit] 72 cc-emit-byte [lit] 15 cc-emit-byte
    ty-unsigned? if, [lit] 183 else, [lit] 191 then, cc-emit-byte
    [lit] 201 cc-emit-byte exit,                   \ movzx/movsx rcx, cx
  then,
  dup ty-size [lit] 4 = if,
    ty-unsigned? if,
      [lit] 137 cc-emit-byte [lit] 201 cc-emit-byte \ mov ecx, ecx
    else,
      [lit] 72 cc-emit-byte [lit] 99 cc-emit-byte
      [lit] 201 cc-emit-byte                      \ movsxd rcx, ecx
    then, exit,
  then,
  drop ;

: cc-emit-convert-right-default ( source destination -- ) nip cc-emit-convert-rcx ;
defer cc-emit-convert-right
' cc-emit-convert-right-default is cc-emit-convert-right

\ cc-emit-load-local-typed ( slot ty -- )  LP64 memory width, legacy qword.
: cc-emit-load-local-typed
  cc-target-lp64 @ if,
    swap cc-emit-lea-rdi-local cc-emit-load-typed-via-rdi
  else, drop cc-emit-load-local then, ;

\ cc-emit-store-local-typed ( slot ty -- )  rdi is preserved.
: cc-emit-store-local-typed
  cc-emit-type-check-fwd
  cc-target-lp64 @ 0= if, drop cc-emit-store-local exit, then,
  ty-size
  dup [lit] 1 = if,
    drop [lit] 64 cc-emit-byte [lit] 136 cc-emit-byte
    [lit] 125 cc-emit-local-ea exit,               \ mov byte [rbp+disp], dil
  then,
  dup [lit] 2 = if,
    drop [lit] 102 cc-emit-byte [lit] 137 cc-emit-byte
    [lit] 125 cc-emit-local-ea exit,               \ mov word [rbp+disp], di
  then,
  [lit] 4 = if,
    [lit] 137 cc-emit-byte [lit] 125 cc-emit-local-ea
  else, cc-emit-store-local then, ;

\ Unsigned division clears rdx, then DIV rcx uses the full rdx:rax dividend.
\ Both operands must already have been converted to the common C type.
: cc-emit-udiv-quotient
  cc-emit-mov-rax-rdi
  [lit] 49 cc-emit-byte [lit] 210 cc-emit-byte      \ xor edx, edx
  [lit] 72 cc-emit-byte [lit] 247 cc-emit-byte [lit] 241 cc-emit-byte
  cc-emit-mov-rdi-rax ;                            \ div rcx; mov rdi, rax

: cc-emit-udiv-remainder
  cc-emit-mov-rax-rdi
  [lit] 49 cc-emit-byte [lit] 210 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 247 cc-emit-byte [lit] 241 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 215 cc-emit-byte ;

: cc-emit-cmp-ult [lit] 146 cc-emit-cmp-set ;       \ setB
: cc-emit-cmp-uge [lit] 147 cc-emit-cmp-set ;       \ setAE
: cc-emit-cmp-ule [lit] 150 cc-emit-cmp-set ;       \ setBE
: cc-emit-cmp-ugt [lit] 151 cc-emit-cmp-set ;       \ setA

\ Logical (unsigned) right shift: shr rdi, cl = 48 D3 EF.
: cc-emit-shr-rdi-cl
  [lit] 72 cc-emit-byte [lit] 211 cc-emit-byte [lit] 239 cc-emit-byte ;
```

Each scalar's declaration calls `cc-globals-alloc <bytes>` to reserve
a slot, and possibly `cc-globals-store-8le` to write its initialiser;
an array's calls `cc-bss-alloc`.
A *reference* to a global from compiled code is a 10-byte `movabs rdi,
imm64` whose imm64 starts as 0.  `cc-emit-global-ref` emits the
placeholder and records `(patch-offset, slot)` in the parallel arrays
`cc-gfixup-out-pos[]` and `cc-gfixup-slot[]`, indexed with Ch 21's
`cell[]` like every other table.

At the end of compilation, Ch 32's driver calls `cc-finalize-globals`
(defined in Ch 31's `116-cc-prog.fth`):

1. Set `cc-globals-base-vaddr` to `cc-here-vaddr` (`cc-base-vaddr +
   cc-out-pos`).
2. Append the `cc-globals-buf` bytes to `cc-out-buf`, advancing
   `cc-out-pos` past the global data.
3. If there is a bss, pad the file to an 8-byte boundary; the bss
   starts there (`cc-bss-base-vaddr`), and its size goes to Ch 25's
   `cc-bss-size`.
4. For every recorded fixup, compute the vaddr (`cc-globals-base-vaddr
   + slot` for a data slot, `cc-bss-base-vaddr + slot - cc-bss-flag`
   for a bss one) and patch the placeholder imm64 in `cc-out-buf` at
   the recorded `patch-offset`.

After that, `cc-finalize-elf` (Ch 25 §1) patches the program header's
`p_filesz` and `p_memsz`, and `cc-write-output` (Ch 21 §2) writes the
buffer.

Machine code and string bytes go straight into `cc-out-buf`: a string
literal sits inline behind a `jmp`, so its address is known the moment
it's emitted.  Global bytes wait in `cc-globals-buf` until the end of
the code fixes their address.  This is Ch 21's one-buffer-per-
responsibility pattern at codegen scale, with `cc-globals-buf` and the
`cc-gfixup` arrays each owning one kind of deferred data.

## 6. The path back together

`090-cc-emit.fth` is 1349 lines of compiler-side machine-code
emission, used three ways:

- **Per-instruction encoders** (Ch 25 §3–§7 and §4 here) write the
  bytes of one x86-64 instruction at a time.  Expression codegen
  (Chs 27–28) composes them into operators and assignments, and
  statement codegen (Ch 30) into the bodies of `if` / `while` / `for` /
  `return`.
- **Prologue/epilogue, locals and param-spills** (Ch 25 §4–§5) are the
  ingredients of function definitions.  Ch 31's `cc-parse-function`
  calls each in sequence.
- **Shims, globals and forward-call fixups** (this chapter) are the
  scaffolding the compiled program needs to run.  Ch 31 emits the
  shims at startup, Ch 28's `cc-parse-primary` walks the call and
  global paths, and Ch 32 wires the whole thing together.

## Try it

**Small check:** the one-line program below calls `putchar`, forcing
the shim path to exist in the output.

**Layer check:** there is no standalone root-level codegen unit
test; the focused C fixtures under `tests/cc/G*.c` are the layer
tests for these paths.

**Bootstrap relevance:** calls, shims, strings, globals, and
wide-immediate fixups all participate in the Stage-A gate.  The
width choice in `cc-emit-mov-rdi-int` is the exception:
`tests/cc/F-wide-const.c` gates it with a literal above the
signed-32 range, which an `imm32` load would sign-extend to a
negative value.  Stage-A never compiles such a literal, so the gate
is the only check on the `movabs` fallback.

```sh
./build.sh
tests/cc/stage-a-check.sh        # full bootstrap-gate
```

To run the small check, compile the one-line program directly.
Seed-forth has no `-e` flag or `include` word, so we feed the fifteen
numbered `.fth` files, comments and all, followed by the C source on
a single stdin.  The last file
(`120-cc-main.fth`) ends by invoking `cc-main`, which reads the
remaining stdin as the C input, compiles, writes `/tmp/cc-out`,
and exits:

```sh
./build.sh
{
  cat 010-lib.fth $(tools/compiler-layers.sh)
  cat <<'C'
int main(void) { putchar(42); return 0; }
C
} | ./seed-forth
chmod +x /tmp/cc-out && /tmp/cc-out         # prints '*'
```

`tests/cc/build-m2planet-monolith.sh` runs the same pattern at full
scale, building M2-Planet itself with this pipe.

**tri.c at this stage:** stop the compiler between parsing and
`cc-finalize-globals` and look at the placeholder for `t`.  The probe
loads every file except `120-cc-main.fth`, runs `cc-main`'s first
steps, and prints in hex the fixup count and the imm64 at the first
fixup, before and after the patch:

```sh
./build.sh
{
  cat 010-lib.fth 0[2-9]0-cc-*.fth 1[01][0-9]-cc-*.fth
  cat <<'FORTH'
    : .h  dup [lit] 15 > if, dup [lit] 16 / .h then,
          [lit] 15 and dup [lit] 9 > if, [lit] 39 + then, [lit] 48 + emit ;
    : site  cc-gfixup-out-pos @ cc-out-buf + @ .h ;
    : probe
      cc-load-stdin cc-preprocess cc-out-init cc-globals-init
      cc-emit-elf-header cc-parse-program
      cc-gfixup-count @ .h [lit] 32 emit  site [lit] 32 emit
      cc-finalize-globals  site  bye ;
    probe
FORTH
  cat <<'C'
#define ROWS 4
struct tri { int rows; int stars; };
struct tri t;

void line(int pad, int n) {
    while (pad > 0) { putchar(' '); pad = pad - 1; }
    while (n > 0) { putchar('*'); n = n - 1; }
    putchar('\n');
}

int main() {
    int w[ROWS];
    int r;
    t.rows = ROWS;
    for (r = 0; r < t.rows; r = r + 1) {
        w[r] = 1 + r * 2;
        line(t.rows - 1 - r, w[r]);
        t.stars = t.stars + w[r];
    }
    if (t.stars == ROWS * ROWS) return t.stars;
    return 1;
}
C
} | ./seed-forth                   # prints "7 0 4004c9"
```

Seven `movabs rdi` sites refer to `t`, one for each `t.rows` or
`t.stars` in the source.  The first, for `t.rows = ROWS;`, holds 0
until `cc-finalize-globals` writes `0x4004c9`: `cc-base-vaddr` plus
the 1,225 bytes of header and code that Ch 21's probe counted, so `t`
starts on the byte after `main`'s last `ret`.  In `line`, all three
`putchar` calls are `call 0x400092`, the 29-byte shim of §3; the ten
shims `tri.c` never calls are emitted anyway.

## Exercises

1. **★★★ Modify.** The `calloc` shim is 113 bytes and uses hand-counted RIP-
   relative offsets.  Insert four `nop`s (`90`) first at the very
   top of the shim, then just before `.have_heap`.  For each
   placement, which displacements (and which `jnz`) need to
   change, and why does the first placement change none of the
   RIP-relative ones?

2. **★★★ Extend.** `free` is a 1-byte `ret`.  Construct a test program that
   relies on `free` reclaiming memory; observe how the bump
   allocator handles it.  Could a free-list be retrofitted?

3. **★★ Trace.** `fopen` recognises only `r`, `w`, `a` as the first byte of the
   mode string.  What does it do with `rb` or `r+`?  Trace one
   case.

4. **★★ Extend.** The fixup-list mechanism in `cc-add-fixup-to-list` is the
   same shape as a Lisp cons-cell.  Could the compiler reuse a
   single generic list type for both forward-call fixups and
   global fixups?  What would the consolidation save?

5. **★★★ Extend.** `cc-decode-escape` names four escapes and passes the
   rest through.  Add `\xNN` (two-hex-digit escape).  Why can't it go
   in `cc-decode-escape` alone, and what must `cc-emit-string-bytes`
   and `cc-lex-char` each change?

## After this chapter

The compiler can emit code that talks to the rest of itself: function
calls with fixup lists for targets not yet defined, libc shims,
inline string literals, and global-address placeholders patched once
layout is known.  Calls and global accesses are where Stage-A parity
first depends on exact layout, since both encode addresses and offsets
that shift if any earlier byte changes.  What the encoders cannot do
is choose their own order.  In `1 + r * 2` on line 16 of `tri.c`,
the `+` arrives first, one token at a time, yet the `imul` must be
emitted before the `add`.  Ch 27 gets that order right without an
expression tree.

## Takeaways

- Deferred resolution runs the codegen: placeholders go in, fixup metadata is stashed, and a final sweep patches forward function references (`cc-sym-call-fixups`/`cc-sym-addr-fixups`), global vaddrs (`cc-gfixup-*`) and ELF sizes (`cc-out-patch-4le`) independently.
- Libc is not a dependency but emitted code: eleven shims give compiled programs `putchar`, `exit`, file I/O and a 256 MiB bump-allocated heap.
- Globals share the single R-W-X PT_LOAD segment with the code, appended after the last function, so there is no `.data` phdr, relocation table or dynamic linker.

Next: Chapter 27 — Expressions, Part 1: The Precedence Cascade.
