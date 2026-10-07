# Chapter 21 — Arena and I/O Buffers

```text
Missing capability: the compiler has nowhere to keep input bytes or emitted output.
New pattern: fixed buffers plus a tiny arena separate owned memory by responsibility.
Artifact after this chapter: a source reader, an output writer, and a bump allocator.
Proof link: later stages can assemble /tmp/cc-out deterministically for Stage-A checks.
```

Here is a 22-line C program, `tri.c`:

```c
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
```

The compiler Part III builds turns these 484 bytes into a
1,241-byte x86-64 executable that prints

```text
   *
  ***
 *****
*******
```

and exits with status 16, the number of stars.  No assembler, linker
or libc takes part: every one of the 1,241 bytes is written by Forth
words loaded on top of the 1,772-byte seed.  How do 22 lines become
those bytes?  `tri.c` is Part III's running example, and every
chapter from here to Ch 32 shows it at that chapter's stage.  This
chapter's Try it compiles it.

The first answer is plain bookkeeping.  The 484 bytes need somewhere
to land, and the 1,241 need somewhere to accumulate before they reach
disk.  Part III uses the seed's Forth to host a compiler for a small
subset of C: enough to rebuild M2-Planet, whose binary is the next
link in the Guix Full Source Bootstrap chain.  The compiler is split
across eighteen files (`020-cc-arena.fth` through `120-cc-main.fth`),
loaded in numerical order on top of `010-lib.fth`.  This chapter
covers the first two: the compiler's ground floor (the lexer's state
block, failure reporting and a bump allocator), and the source reader
and output writer.

## The main byte path

Ch 20 closed by naming Part III's three recurring motifs: emit,
remember, patch; small tables with newest-wins lookup; one buffer per
responsibility.  The first and third show up in this chapter's two
files.  Before reading them, here is the whole compiler at a glance,
as `cc-main` in `120-cc-main.fth` drives it:

```text
  stdin (C source)
    |  cc-load-stdin (030)
    v
  cc-in-buf
    |
    v
  preprocessor (040) ------------------> macro table (040)
    |  splices #include "..." files,        #define NAME N
    |  drops other directive lines
    v
  cc-src-buf
    |
    v
  lexer (050) <------------------------- macro table lookup
    |  one token at a time into the tok-* cells; an identifier
    |  that names a macro becomes a number token
    v
  parser + codegen: 100 (expressions), 110 (declarations,
    |  statements, functions); x86-64 encoders in 090
    v
  cc-out-buf
    |  [ELF header, 080: emitted before parsing starts]
    |  [entry stub, libc shims, function bodies]
    |  [globals, appended by cc-finalize-globals]
    |  cc-finalize-elf (080) patches p_filesz / p_memsz
    v
  cc-write-output (030) ---> /tmp/cc-out (ELF executable)

  shared state across the stages:
    020 lexer-state block, cc-die, arena    060 type words
    070 symbol table + scope stack
```

The ELF writer is not a stage at the end of the line.  Ch 25's
`cc-emit-elf-header` writes the 120-byte header into `cc-out-buf`
before the parser runs, with the size fields left at zero, and
`cc-finalize-elf` patches them once the last byte is known.

## 1. The ground floor: `020-cc-arena.fth`

The 448-line file `020-cc-arena.fth` first gives the arithmetic words
machine-code bodies, then holds the three things every later compiler
file leans on: one block of memory holding the lexer's
state, the word every failure ends in, and an allocator for data with
no fixed size.

### Arithmetic, input and a light optimizing compile

Part I built `-` from `nand` and `+`, and the sign test `0<` from the
unsigned `/`: every comparison is a 64-bit divide.  That was the point
there, since 32 primitives were enough.  But the compiler runs these
words hundreds of millions of times when it builds GCC, and the seed's
way of compiling, a CALL for every word, costs more than the words.  A
profile of seed-cc compiling GCC's `combine.c` showed where the time
went, and this section is the answer to it.  It changes no answer the
compiler gives: every object it writes is byte for byte what it was.

`code:` makes a header whose body `c,` then lays down; it is
`constant`'s trick (Ch 10) without the push body.  `native!` writes a
5-byte `JMP` over the start of an old definition, so every word
compiled earlier, in `010-lib.fth` included, runs the new code without
being compiled again.  It works the jump out before writing it,
because the first word it patches is `-`, which it also uses.  The
registers are the seed's: the top of stack is in `rdi`, the rest of
the data stack grows down from `rbp` (Ch 15's `+`).

Four things follow.  `-`, `0<`, `<`, `=`, `1+`, `1-`, `and`, `or` and
the character tests get x86 bodies with the same answers (`<` is still
the sign of `a - b`, wrapping exactly as Ch 7's does).  `key` gets a
4 KiB buffer, because the seed reads its input one byte per `read`
call and the compiler arrives as about 500 KB of source on every run;
`key-drain` hands the C source that follows to `cc-read-all` (§2).
`find` gets a hash table, kept up to date from `LATEST`, because the
seed walks every header for every token it reads.  And from here on
compiling is lightly optimized: `[lit]` lays an inline push instead of
a CALL to `lit`, the control-flow words lay `test`/`jz`/`jmp`
instructions instead of CALLs to `branch` and `0branch` (which rewrite
their own return address, so the processor mispredicts every one of
them), the commonest primitives are copied in place of their CALL, and
words made by `constant`, `create` and `variable` compile as an inline
push of their value.  Each such word is immediate and acts only while
compiling; interpreted, it does what the old word did.  One trap: a
word can see its own name while it is being defined, so the new `@`
reads `state` through `compiling?`, compiled before `@` changed.
Together these took `combine.c` from 6.9 to 1.0 seconds.

```forth file=020-cc-arena.fth
\ 020-cc-arena.fth — the compiler's ground floor: the lexer's state block,
\ how the compiler fails (cc-die, cc-check-cap), and a bump allocator for
\ variable-size data (struct descriptors, call/goto fixup lists, switch-case
\ lists — anything that doesn't fit a fixed slot in a parallel array).  Most
\ compiler state lives in fixed-size buffers (parallel arrays declared with
\ `create NAME N allot`); this arena handles the rest.
\
\ Depends on 010-lib.fth: constant, variable, create, allot, s,, char, [lit],
\ if,/then,, begin,/until,, swap, dup, over, nip, drop, >r, r>, +, -, /, *,
\ >, !, @, c!, c,, write, die.

\ ----- The compiler's arithmetic in machine code -----
\ 010-lib.fth builds - from nand and +, and the sign test 0< from the
\ unsigned / (a 64-bit divide per comparison).  The compiler runs them
\ hundreds of millions of times, so here they become x86 code with the
\ same answers: < is still (a - b)'s sign bit, wrapping as before.  Each
\ native word gets a fresh header (code:), and native! turns the first
\ definition into a jump to it, so every word compiled earlier, in
\ 010-lib.fth too, runs the new code.  TOS is in rdi and the data stack
\ grows down from rbp, as in the seed's + (Ch 15).
: code:  : [lit] 0 state ! ;             \ header only; c, lays the body
: native!  ( old new -- )                \ old's first bytes: JMP rel32 new
  over [lit] 5 + -  swap                 \ rel32 first: old may be - itself
  here >r  here-addr !  [lit] 233 c, ,4
  r> here-addr ! ;
variable code-start
: mov-rax-[rbp],  [lit] 72 c, [lit] 139 c, [lit] 69 c, [lit] 0 c, ;
: add-rbp-8,      [lit] 72 c, [lit] 131 c, [lit] 197 c, [lit] 8 c, ;
: sub-rax-rdi,    [lit] 72 c, [lit] 41 c, [lit] 248 c, ;
: mov-rdi-rax,    [lit] 72 c, [lit] 137 c, [lit] 199 c, ;
: sar63,  ( modrm -- )  [lit] 72 c, [lit] 193 c, c, [lit] 63 c, ;
' - code: -  here code-start !            \ ( a b -- a-b )
  mov-rax-[rbp], add-rbp-8, sub-rax-rdi, mov-rdi-rax, ret,
  code-start @ native!
' 0< code: 0<  here code-start !          \ ( n -- f )  sar rdi, 63
  [lit] 255 sar63, ret,
  code-start @ native!
' < code: <  here code-start !            \ ( a b -- f )  sign of a - b
  mov-rax-[rbp], add-rbp-8, sub-rax-rdi, [lit] 248 sar63, mov-rdi-rax, ret,
  code-start @ native!
' = code: =  here code-start !            \ ( a b -- f )  a - b = 0
  mov-rax-[rbp], add-rbp-8, sub-rax-rdi,
  [lit] 15 c, [lit] 148 c, [lit] 192 c,   \ sete al
  [lit] 72 c, [lit] 15 c, [lit] 182 c, [lit] 248 c,   \ movzx rdi, al
  [lit] 72 c, [lit] 247 c, [lit] 223 c,   \ neg rdi
  ret,
  code-start @ native!
' 1+ code: 1+  here code-start !          \ add rdi, 1
  [lit] 72 c, [lit] 131 c, [lit] 199 c, [lit] 1 c, ret,
  code-start @ native!
' 1- code: 1-  here code-start !          \ sub rdi, 1
  [lit] 72 c, [lit] 131 c, [lit] 239 c, [lit] 1 c, ret,
  code-start @ native!

\ The seed's key reads stdin one byte per read syscall, and the compiler
\ arrives through key: about 500 KB of Forth source on every run.  key-fill
\ below is key with a 64 KiB buffer; native! sends the seed's key, which its
\ reader calls directly, there too.  The C source that follows the Forth
\ text on stdin is then partly in the buffer: key-drain hands it over to
\ cc-read-all (030).
[lit] 4096 constant key-buffer-size
create key-buffer key-buffer-size allot
variable key-pos
variable key-len
: movabs-rsi,  [lit] 72 c, [lit] 190 c, ,8 ;
: movabs-rdx,  [lit] 72 c, [lit] 186 c, ,8 ;
' key code: key-fill  here code-start !   \ ( -- c ), 0 at end of input
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,     \ sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,     \ mov [rbp], rdi
  key-pos movabs-rsi,  [lit] 72 c, [lit] 139 c, [lit] 6 c,   \ mov rax, [rsi]
  key-len movabs-rdx,  [lit] 72 c, [lit] 59 c, [lit] 2 c,    \ cmp rax, [rdx]
  [lit] 114 c, [lit] 41 c,                             \ jb .have
  [lit] 49 c, [lit] 192 c,  [lit] 49 c, [lit] 255 c,   \ xor eax,eax  xor edi,edi
  key-buffer movabs-rsi,                               \ read(0, buffer,
  [lit] 186 c, key-buffer-size ,4  [lit] 15 c, [lit] 5 c,   \ size): syscall
  [lit] 72 c, [lit] 133 c, [lit] 192 c,                \ test rax, rax
  [lit] 126 c, [lit] 46 c,                             \ jle .eof
  key-len movabs-rdx,  [lit] 72 c, [lit] 137 c, [lit] 2 c,   \ mov [rdx], rax
  [lit] 49 c, [lit] 192 c,                             \ xor eax, eax
  key-buffer movabs-rsi,                               \ .have:
  [lit] 15 c, [lit] 182 c, [lit] 60 c, [lit] 6 c,      \ movzx edi, byte [rsi+rax]
  [lit] 72 c, [lit] 255 c, [lit] 192 c,                \ inc rax
  key-pos movabs-rdx,  [lit] 72 c, [lit] 137 c, [lit] 2 c,   \ mov [rdx], rax
  ret,
  [lit] 49 c, [lit] 255 c, ret,                        \ .eof: xor edi,edi
  code-start @ native!
\ key-drain ( buf cap -- n )  Move up to cap bytes that key-fill has read
\ but not handed out to buf; answer how many.
variable kd-buf
variable kd-cap
variable kd-n
: key-drain
  kd-cap ! kd-buf !  [lit] 0 kd-n !
  begin, kd-n @ kd-cap @ <  key-pos @ key-len @ <  and while,
    key-buffer key-pos @ + c@  kd-buf @ kd-n @ + c!
    [lit] 1 key-pos +!  [lit] 1 kd-n +!
  repeat,
  kd-n @ ;

\ ----- A light optimizing compile -----
\ The seed compiles every word as a CALL.  For literals and branches that
\ CALL goes to lit, branch or 0branch, which pop and rewrite their own
\ return address, so the processor mispredicts the return each time.  From
\ here on [lit] lays an inline push, the control-flow words lay test and
\ jump instructions, and the commonest primitives are copied in place of
\ the CALL.  Each new word acts only while compiling (state @); run from
\ the interpreter it does what the old one did.  Words already compiled,
\ 010-lib.fth's included, keep their CALLs.
\ [lit] first: the seed's [lit] compiles CALL lit and the value's cell (13
\ bytes); take the value back out and lay the 18-byte push instead.
' [lit] constant seed-lit
: here-8   here [lit] 8 - ;
: here-13  here [lit] 13 - ;
: [lit]
  seed-lit execute
  state @ if,
    here-8 @  here-13 here-addr !  push-imm64,
  then, ;
immediate
\ Branches: if, while, and until, pop the flag and jz rel32; else, repeat,
\ and again, jmp rel32.  A forward fixup is the address of the rel32 field.
: rel32!  ( target fixup -- )
  dup [lit] 4 + rot swap -  swap
  here >r  here-addr ! ,4  r> here-addr ! ;
: flag-test,                                  \ rax = flag, popped; test it
  [lit] 72 c, [lit] 137 c, [lit] 248 c,                     \ mov rax, rdi
  [lit] 72 c, [lit] 139 c, [lit] 125 c, [lit] 0 c,          \ mov rdi, [rbp]
  add-rbp-8,  [lit] 72 c, [lit] 133 c, [lit] 192 c, ;       \ test rax, rax
: jz-fwd,    flag-test, [lit] 15 c, [lit] 132 c, here [lit] 0 ,4 ;
: jmp-fwd,   [lit] 233 c, here [lit] 0 ,4 ;
: jz-back,   flag-test, [lit] 15 c, [lit] 132 c, here [lit] 4 + - ,4 ;
: jmp-back,  [lit] 233 c, here [lit] 4 + - ,4 ;
: if,      jz-fwd, ;                        immediate
: then,    here swap rel32! ;               immediate
: else,    jmp-fwd, swap here swap rel32! ; immediate
: begin,   here ;                           immediate
: while,   jz-fwd, ;                        immediate
: repeat,  swap jmp-back, here swap rel32! ; immediate
: until,   jz-back, ;                       immediate
: again,   jmp-back, ;                      immediate
\ Primitives copied in place of the CALL: the seed's bodies without their
\ ret (Chs 14-15), with the return-stack words' own return address left out.
: push-tos,  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,      \ sub rbp, 8
             [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c, ;    \ mov [rbp], rdi
: pop-tos,   [lit] 72 c, [lit] 139 c, [lit] 125 c, [lit] 0 c, add-rbp-8, ;
\ A word can see its own name while it is being defined, so the new @ must
\ not read state with @: compiling? was compiled with the seed's.
: compiling?  state @ ;
' dup constant seed-dup     : dup   compiling? if, push-tos, else, seed-dup execute then, ; immediate
' drop constant seed-drop   : drop  compiling? if, pop-tos, else, seed-drop execute then, ; immediate
' swap constant seed-swap
: swap  compiling? if,
    [lit] 72 c, [lit] 135 c, [lit] 125 c, [lit] 0 c,      \ xchg rdi, [rbp]
  else, seed-swap execute then, ; immediate
' over constant seed-over
: over  compiling? if,
    push-tos, [lit] 72 c, [lit] 139 c, [lit] 125 c, [lit] 8 c,   \ mov rdi, [rbp+8]
  else, seed-over execute then, ; immediate
' @ constant seed-fetch
: @  compiling? if, [lit] 72 c, [lit] 139 c, [lit] 63 c,    \ mov rdi, [rdi]
  else, seed-fetch execute then, ; immediate
' c@ constant seed-cfetch
: c@  compiling? if, [lit] 72 c, [lit] 15 c, [lit] 182 c, [lit] 63 c,   \ movzx rdi, byte [rdi]
  else, seed-cfetch execute then, ; immediate
' ! constant seed-store
: !  compiling? if,
    mov-rax-[rbp], [lit] 72 c, [lit] 137 c, [lit] 7 c,    \ mov [rdi], rax
    add-rbp-8, pop-tos,
  else, seed-store execute then, ; immediate
' c! constant seed-cstore
: c!  compiling? if,
    mov-rax-[rbp], [lit] 136 c, [lit] 7 c,                \ mov [rdi], al
    add-rbp-8, pop-tos,
  else, seed-cstore execute then, ; immediate
' + constant seed-plus
: +  compiling? if,
    [lit] 72 c, [lit] 3 c, [lit] 125 c, [lit] 0 c, add-rbp-8,   \ add rdi, [rbp]
  else, seed-plus execute then, ; immediate
' - constant native-minus
: -  compiling? if,
    mov-rax-[rbp], add-rbp-8, sub-rax-rdi, mov-rdi-rax,
  else, native-minus execute then, ; immediate
' 1+ constant native-1+
: 1+  compiling? if, [lit] 72 c, [lit] 131 c, [lit] 199 c, [lit] 1 c,
  else, native-1+ execute then, ; immediate
' 1- constant native-1-
: 1-  compiling? if, [lit] 72 c, [lit] 131 c, [lit] 239 c, [lit] 1 c,
  else, native-1- execute then, ; immediate
\ The return stack is the x86 stack, so inline >r, r> and r@ are push,
\ pop and a load from [rsp].  They are compile-only, as in any Forth.
: >r  [lit] 87 c, pop-tos, ; immediate                   \ push rdi
: r>  push-tos, [lit] 95 c, ; immediate                  \ pop rdi
: r@  push-tos, [lit] 72 c, [lit] 139 c, [lit] 60 c, [lit] 36 c, ; immediate  \ mov rdi, [rsp]

\ More primitives copied in: *, /, 0=, nand, and, or.
' * constant seed-star
: *  compiling? if,
    [lit] 72 c, [lit] 137 c, [lit] 248 c,                          \ mov rax, rdi
    [lit] 72 c, [lit] 15 c, [lit] 175 c, [lit] 69 c, [lit] 0 c,    \ imul rax, [rbp]
    add-rbp-8, mov-rdi-rax,
  else, seed-star execute then, ; immediate
' / constant seed-slash
: /  compiling? if,
    mov-rax-[rbp], [lit] 72 c, [lit] 49 c, [lit] 210 c,           \ xor rdx, rdx
    [lit] 72 c, [lit] 247 c, [lit] 247 c,                          \ div rdi
    add-rbp-8, mov-rdi-rax,
  else, seed-slash execute then, ; immediate
: 0=,  [lit] 72 c, [lit] 133 c, [lit] 255 c,                      \ test rdi, rdi
       [lit] 64 c, [lit] 15 c, [lit] 148 c, [lit] 199 c,          \ sete dil
       [lit] 72 c, [lit] 15 c, [lit] 182 c, [lit] 255 c,          \ movzx rdi, dil
       [lit] 72 c, [lit] 247 c, [lit] 223 c, ;                    \ neg rdi
' 0= constant seed-0=
: 0=  compiling? if, 0=, else, seed-0= execute then, ; immediate
: and,  [lit] 72 c, [lit] 35 c, [lit] 125 c, [lit] 0 c, add-rbp-8, ;   \ and rdi, [rbp]
: or,   [lit] 72 c, [lit] 11 c, [lit] 125 c, [lit] 0 c, add-rbp-8, ;   \ or rdi, [rbp]
' nand constant seed-nand
: nand  compiling? if, and, [lit] 72 c, [lit] 247 c, [lit] 215 c,      \ not rdi
  else, seed-nand execute then, ; immediate
' and code: and  here code-start !  and, ret,  code-start @ native!
' and constant native-and
: and  compiling? if, and, else, native-and execute then, ; immediate
' or code: or  here code-start !  or, ret,  code-start @ native!
' or constant native-or
: or  compiling? if, or, else, native-or execute then, ; immediate
\ 010-lib.fth's character tests subtract and divide; as x86 they are an
\ unsigned compare: sub rdi, low; cmp rdi, count; sbb rdi, rdi (-1 below).
: in-range,  ( low count -- )
  [lit] 72 c, [lit] 131 c, [lit] 239 c, swap c,                  \ sub rdi, low
  [lit] 72 c, [lit] 131 c, [lit] 255 c, c,                       \ cmp rdi, count
  [lit] 72 c, [lit] 25 c, [lit] 255 c, ret, ;                    \ sbb rdi, rdi
' digit? code: digit?  here code-start !  [lit] 48 [lit] 10 in-range,  code-start @ native!
' alpha-lower? code: alpha-lower?  here code-start !  [lit] 97 [lit] 26 in-range,  code-start @ native!
' alpha-upper? code: alpha-upper?  here code-start !  [lit] 65 [lit] 26 in-range,  code-start @ native!
\ The rest of 010-lib.fth's hot words, compiled again from the same text
\ so the copies above take effect, and the old bodies sent to the new ones.
' over code: over  here code-start !
  push-tos, [lit] 72 c, [lit] 139 c, [lit] 125 c, [lit] 8 c, ret,  code-start @ native!
' over constant native-over
: over  compiling? if, push-tos, [lit] 72 c, [lit] 139 c, [lit] 125 c, [lit] 8 c,
  else, native-over execute then, ; immediate
' alpha? : alpha?  dup alpha-lower? swap alpha-upper? or ;  ' alpha? native!
' space? : space?  dup [lit] 32 - 0= over [lit]  9 - 0= or
          over [lit] 10 - 0= or  swap [lit] 13 - 0= or ;  ' space? native!
' true : true  [lit] 0 0= ;  ' true native!
' <> : <>  = 0= ;  ' <> native!
' > : >   swap < ;  ' > native!
' <= : <=  > 0= ;  ' <= native!
' >= : >=  < 0= ;  ' >= native!
' nip : nip   swap drop ;  ' nip native!
' rot : rot   >r swap r> swap ;  ' rot native!
' 2dup : 2dup  over over ;  ' 2dup native!
' 2drop : 2drop drop drop ;  ' 2drop native!
' +! : +!  swap over @ + swap ! ;  ' +! native!
' -! : -!  swap over @ swap - swap ! ;  ' -! native!
' bytes-eq : bytes-eq
  begin,
    dup [lit] 0 >
  while,
    >r
    over c@ over c@ <> if,
      r> drop 2drop [lit] 0 exit,
    then,
    1+ swap 1+ swap
    r> 1-
  repeat,
  drop 2drop true ;  ' bytes-eq native!

\ Comparisons copied in place (same answers as 010-lib.fth's).
: pop-sub,  mov-rax-[rbp], add-rbp-8, sub-rax-rdi, ;          \ rax = a - b
: flag-al,  [lit] 72 c, [lit] 15 c, [lit] 182 c, [lit] 248 c, \ movzx rdi, al
            [lit] 72 c, [lit] 247 c, [lit] 223 c, ;           \ neg rdi
' = constant native-=
: =   compiling? if, pop-sub, [lit] 15 c, [lit] 148 c, [lit] 192 c, flag-al,  \ sete al
  else, native-= execute then, ; immediate
' <> constant forth-<>
: <>  compiling? if, pop-sub, [lit] 15 c, [lit] 149 c, [lit] 192 c, flag-al,  \ setne al
  else, forth-<> execute then, ; immediate
' < constant native-<
: <   compiling? if, pop-sub, [lit] 248 sar63, mov-rdi-rax,
  else, native-< execute then, ; immediate
' >= constant forth->=
: >=  compiling? if, pop-sub, [lit] 248 sar63,
    [lit] 72 c, [lit] 247 c, [lit] 208 c, mov-rdi-rax,        \ not rax
  else, forth->= execute then, ; immediate
: pop-rsub,  mov-rax-[rbp], add-rbp-8,
             [lit] 72 c, [lit] 41 c, [lit] 199 c, ;           \ sub rdi, rax: b - a
' > constant forth->
: >   compiling? if, pop-rsub, [lit] 255 sar63,
  else, forth-> execute then, ; immediate
' <= constant forth-<=
: <=  compiling? if, pop-rsub, [lit] 255 sar63,
    [lit] 72 c, [lit] 247 c, [lit] 215 c,                     \ not rdi
  else, forth-<= execute then, ; immediate
' 0< constant native-0<
: 0<  compiling? if, [lit] 255 sar63, else, native-0< execute then, ; immediate
\ Constants and variables: a word made by constant, create or variable from
\ here on is immediate.  Compiling, it lays an inline push of its value
\ rather than a CALL; interpreted, it pushes the value as before.  Its body
\ is the 18-byte push, a CALL to push-or-compile, then ret (24 bytes).
: push-or-compile  ( v -- v | )  compiling? if, push-imm64, then, ;
' push-or-compile constant poc-xt
: constant  : push-imm64, poc-xt call, ret, [lit] 0 state ! immediate ;
: create  : here [lit] 24 + push-imm64, poc-xt call, ret, [lit] 0 state ! immediate ;
: variable  create [lit] 0 , ;

\ The seed's find walks every header from LATEST, and about a third of each
\ run went there while the compiler's own source was read.  fh-find answers
\ the same (the newest entry of that name, its header left in LAST_FOUND)
\ from a hash table it brings up to date first: headers are only ever added
\ at LATEST, so the ones newer than the last indexed are new.  Nodes
\ { next, header } live in a 2 MiB anonymous mapping, after 4096 buckets.
variable fh-buckets
variable fh-pool
variable fh-pos
variable fh-latest
variable fh-a
variable fh-u
[lit] 0 [lit] 2097152 [lit] 3 [lit] 34 true [lit] 0 [lit] 9 syscall6
dup fh-buckets !  [lit] 32768 + fh-pool !
: fh-hash  ( a u -- bucket )
  [lit] 5381 >r
  begin, dup while,
    over c@ r> [lit] 33 * + >r
    1- swap 1+ swap
  repeat, 2drop
  r> [lit] 4095 and ;
: fh-insert  ( header -- )
  dup [lit] 10 + over [lit] 9 + c@ fh-hash [lit] 8 * fh-buckets @ +
  fh-pool @ fh-pos @ +
  over @ over !
  rot over [lit] 8 + !
  swap !
  [lit] 16 fh-pos +! ;
: fh-index  ( header -- )  \ every header newer than fh-latest, oldest first
  dup fh-latest @ = over 0= or if, drop exit, then,
  dup @ fh-index fh-insert ;
: fh-find  ( c-addr u -- xt | 0 )
  fh-u ! fh-a !
  latest @ fh-latest @ <> if, latest @ fh-index  latest @ fh-latest ! then,
  fh-a @ fh-u @ fh-hash [lit] 8 * fh-buckets @ + @
  begin, dup while,
    dup [lit] 8 + @
    dup [lit] 9 + c@ fh-u @ = if,
      dup [lit] 10 + fh-a @ fh-u @ bytes-eq if,
        nip dup latest [lit] 16 + !                    \ LAST_FOUND
        [lit] 10 + fh-u @ + exit,
      then,
    then,
    drop @
  repeat, ;
' find ' fh-find native!

```

### The lexer's state block

The reader in section 2 keeps a cursor into the source and a line
count; the lexer (Ch 23) keeps the token it has just read.  Those
eight cells are everything that changes as the compiler moves through
the program, so they live side by side in one block:

```forth file=020-cc-arena.fth
\ ----- The lexer's state: one block -----
\ Everything the source reader (030) and the lexer (050) change as they move
\ through the program lives in this one 8-cell block, so a parser that wants
\ to look ahead can copy the block away and later copy it back
\ (cc-lex-mark / cc-lex-reset, 050).  Each name below is the address of its
\ cell, used exactly like a variable.  The block comes first because cc-die
\ reports the current line from it.
[lit] 64 constant cc-lex-state-size
create cc-lex-state  cc-lex-state-size allot
cc-lex-state             constant cc-src-pos     \ reader: offset of the next byte
cc-lex-state [lit]  8 +  constant cc-src-line    \ reader: 1-based line number
cc-lex-state [lit] 16 +  constant tok-kind       \ lexer: tk-* of the current token
cc-lex-state [lit] 24 +  constant tok-num        \ lexer: number / char / punct code
cc-lex-state [lit] 32 +  constant tok-str-addr   \ lexer: identifier or string bytes
cc-lex-state [lit] 40 +  constant tok-str-len    \ lexer: ... and their length
cc-lex-state [lit] 48 +  constant tok-kw-id      \ lexer: kw-* when tok-kind = tk-kw
cc-lex-state [lit] 56 +  constant cc-tok-pending \ lexer: -1 = current token put back

```

`create cc-lex-state cc-lex-state-size allot` reserves 64 bytes, and
each `constant` names one cell by its address.  A name like
`cc-src-pos` then behaves exactly like a `variable`: `cc-src-pos @`
reads the cell and `cc-src-pos !` writes it.  Keeping the eight cells
contiguous is what lets a parser that must look several tokens ahead
copy the whole block away and later copy it back (`cc-lex-mark` and
`cc-lex-reset`, Ch 23).  The token cells are named here, before Ch 23
explains tokens, because the block has to exist before the next
section's `cc-die`, which reports `cc-src-line`.

### Failing: `cc-die`

When the compiler cannot go on, whether a table is full, a file is
missing, or the source is outside the subset, it calls `cc-die` with
a number that names the failure:

```forth file=020-cc-arena.fth
\ ----- Failing: cc-die -----
\ cc-err-write ( a u -- )  Write u bytes at a to stderr (fd 2).
: cc-err-write  >r >r [lit] 2 r> r> write drop ;

\ cc-err-dec ( u -- )  Write u in decimal to stderr.  Digits come out lowest
\ first, so they fill cc-err-digits from its end backwards.
create cc-err-digits  [lit] 20 allot             \ 2^64 has 20 digits
: cc-err-dec
  cc-err-digits [lit] 20 +                       ( u p )
  begin,
    1-  over [lit] 10 / [lit] 10 * >r  over r> - ( u p digit )
    [char] 0 +  over c!                          ( u p )
    swap [lit] 10 / swap                         ( u/10 p )
    over 0=
  until,
  nip  cc-err-digits [lit] 20 + over -  cc-err-write ;

create cc-die-where  s, cc: bl c, s, line bl c,       \ "cc: line "  9 bytes
create cc-die-what   char : c, bl c, s, error bl c,   \ ": error "   8 bytes
create cc-die-end    nl c,                            \ "\n"         1 byte

\ cc-die ( code -- )  Every compiler failure ends here: write
\ "cc: line N: error CODE" to stderr and exit with status CODE.  N is the
\ reader's line in the preprocessed source, where #include'd files are
\ already spliced in (Appendix G).
: cc-die
  cc-die-where [lit] 9 cc-err-write
  cc-src-line @ cc-err-dec
  cc-die-what [lit] 8 cc-err-write
  dup cc-err-dec
  cc-die-end [lit] 1 cc-err-write
  die ;

\ cc-check-cap ( n cap code -- )  Die with code unless n <= cap.  n is how
\ full a buffer or table will be once the write about to happen is done.
: cc-check-cap
  >r > if, r> cc-die then,
  r> drop ;

```

`cc-die` writes one line to stderr, `cc: line 2: error 30`, then
exits with the code as its status, so `echo $?` shows it too.  The
line is `cc-src-line`: where the reader was when the compiler gave
up.  Appendix G lists every code with the file that owns it; each
file draws its codes from its own range (this file's are 10–19), so
a code names one failure.

`cc-err-dec` is the only number printer in the compiler.  It divides
by 10 until nothing is left, storing each remainder's digit one byte
further left in `cc-err-digits`, then writes the digits it filled.
`until,` (Ch 11) makes it run at least once, so 0 prints as `0`.  The
three message fragments are laid down with `s,` (Ch 12), `char`
(Ch 10) and `c,`: `s,` copies one space-free token, so the spaces and the colon
go in one byte at a time.

`cc-check-cap` is the bounds check every capacity uses: `n` is how
full a buffer or table will be after the write the caller is about to
make, and if that exceeds `cap` the compiler dies with the caller's
code instead of writing past the end.

### The arena

Most of the compiler's state lives in fixed-size parallel arrays: the
symbol table (Ch 24), the macro table (Ch 22), the label fixup table
(Ch 30).  Each is a `create NAME N allot` of pre-sized storage with a
separate counter variable.  That works for anything whose maximum
count we can pin down in advance.

A few things don't fit that mould: struct descriptors, the fixup
chains for `goto` labels and forward function references, the case
list of a `switch`.  For those we need an allocator that hands out
variable-sized blocks:

```forth file=020-cc-arena.fth
\ ----- Storage -----
\ The buffer lives in the dictionary alongside the cc-arena-base header (it's
\ what `create` builds: a header + data area; allot extends the data area).
\ Sized to fit within 000-seed.hex0's mapped segment with room for the compiler
\ dictionary, struct descriptors, labels, and string overflow.
[lit] 32768 constant cc-arena-cap
create cc-arena-base  cc-arena-cap allot
variable cc-arena-ptr
\ Initialize the bump pointer to the base of the buffer.
cc-arena-base cc-arena-ptr !
variable cc-arena-start
variable cc-arena-limit
cc-arena-base cc-arena-start !
cc-arena-cap cc-arena-limit !
\ Opt-in workspace for larger translation units; the seed itself is unchanged.
: cc-arena-map ( bytes -- )
  dup cc-arena-limit !
  [lit] 0 swap [lit] 3 [lit] 34 true [lit] 0 [lit] 9 syscall6
  dup 0< if, [lit] 10 cc-die then,
  dup cc-arena-start ! cc-arena-ptr ! ;

\ ----- cc-alloc -----
\ cc-alloc ( n -- addr )  Bump n bytes (rounded up to an 8-byte boundary)
\ off the arena and return the start address of the allocation.  On exhaustion
\ the compiler dies with code 10.
\
\ Stack trace:
\   ( n )
\   align up to 8:  (n+7)/8*8
\   ( n' )
\   cc-arena-ptr @ swap over +     ( old-top new-top )
\   dup cc-arena-base -            ( old-top new-top used )
\   cc-arena-cap 10 cc-check-cap   ( old-top new-top )
\   cc-arena-ptr !                 ( old-top )
: cc-alloc                                       ( n -- addr )
  [lit] 7 + [lit] 8 / [lit] 8 *                  \ align up to 8 bytes
  cc-arena-ptr @ swap over +                     ( old-top new-top )
  dup cc-arena-start @ -  cc-arena-limit @ [lit] 10 cc-check-cap
  cc-arena-ptr ! ;                               ( -- old-top )
```

`[lit] 32768 constant cc-arena-cap` fixes the default budget at 32 KiB.
`create cc-arena-base cc-arena-cap allot` reserves that storage
directly inside the dictionary: `create` makes a header for the name
and `allot` extends its data area by 32 768 bytes.  Forth's own
defining words serve as the compiler's `malloc`.  `cc-arena-ptr` is
the bump pointer.

The line `cc-arena-base cc-arena-ptr !` runs at load time, so the
pointer starts at the buffer's first byte. `cc-arena-start` and
`cc-arena-limit` initially describe that same 32 KiB buffer. An
explicit `cc-arena-map` call replaces the active base, limit, and
bump pointer with an anonymous mapping: the direct TinyCC driver
requests 8 MiB, while the direct-GCC driver requests a fixed 17 MiB.
The original slab and seed bytes remain unchanged.

`cc-alloc` rounds the request up to a multiple of 8 (`(n+7)/8*8`
keeps every allocation cell-aligned; later passes assume it).  It
reads the current top, computes the new top, and hands the bytes in
use to `cc-check-cap`: past the active limit (32 KiB by default), the
compiler dies with code 10. Mapping failure uses that same error.
Otherwise it stores the new top and leaves the old top on the stack
as the address just allocated.

**No `free`.**  The arena only grows.  Every allocation lives for the
whole compilation, and the kernel reclaims everything at exit.  The
allocator is one screen long, and double-free, use-after-free and
leaks are all impossible.

## 2. The source reader and output writer

The 287-line file `030-cc-io.fth` has four sections: A, the input and
source buffers and the reader; B, the output buffer and emitters; C,
the final file write; D, three helpers the next files share.

### The input and source buffers and the reader

The compiler reads stdin into one large buffer, and the preprocessor
writes its result into a second; the lexer then walks that one
character by character.  With the whole source in memory, the
preprocessor can rewrite it wholesale, the lexer can look ahead, and
there is no buffered I/O to negotiate on the read side.  Section A
starts by placing the buffers.

```forth file=030-cc-io.fth
\ 030-cc-io.fth — Input and source buffers, output-buffer emitter, file I/O
\ wrappers, and a few helpers shared by the preprocessor, lexer and symbol
\ table.  Loaded after 010-lib.fth and 020-cc-arena.fth.
\
\ Four responsibilities:
\   A. Slurp stdin into the 1 MiB cc-in-buf.  The preprocessor (040) turns
\      it into the 2 MiB cc-src-buf, which the lexer walks via peek/next.
\   B. Accumulate the output ELF into cc-out-buf via emit-byte / 4le / 8le
\      with patch-byte / patch-4le for back-fixups.
\   C. Write cc-out-buf to a path via 010-lib.fth's open/write/close.
\   D. Shared helpers: identifier classifiers, cell[], cc-name-find.
\
\ Depends on 010-lib.fth: constant, variable, create, allot, [lit], if,/then,/else,,
\   begin,/while,/repeat,, exit,, +, -, /, =, >, >=, 0=, 0<, +!, !, @, c!, c@,
\   drop, dup, over, swap, >r, r@, r>, read, write, open, close, bytes-eq;
\   020-cc-arena.fth: cc-src-pos, cc-src-line, cc-die, cc-check-cap.

\ ===========================================================================
\ A. Input buffer, source buffer + reader
\ ===========================================================================

\ Skip past the VM's fixed pages (data stack 0x410000..0x411000, I/O scratch
\ 0x412000, token buffer 0x412800, sysvars 0x413000..0x414000) so the
\ megabyte buffers do not overlap runtime VM state.  At 030-cc-io.fth load
\ time HERE is well below 0x410000, so this is a forward bump to 0x414000.
skip-vm-pages                                     \ HERE = 0x414000

\ cc-in-buf holds stdin exactly as read; nothing but the preprocessor reads it.
[lit] 1048576 constant cc-in-default-cap
create cc-in-default-buf cc-in-default-cap allot
variable cc-in-buffer
variable cc-in-limit
cc-in-default-buf cc-in-buffer !
cc-in-default-cap cc-in-limit !
: cc-in-buf ( -- address ) cc-in-buffer @ ;
: cc-in-cap ( -- bytes ) cc-in-limit @ ;
variable cc-in-len

\ cc-src-buf holds the preprocessed source the lexer reads: #include'd files
\ spliced in, directives blanked. The default is twice the raw capacity;
\ direct GCC selects separately measured limits. The reader's cursor is in the lexer's
\ state block (020-cc-arena.fth).
[lit] 2097152 constant cc-src-default-cap
create cc-src-default-buf cc-src-default-cap allot
variable cc-src-buffer
variable cc-src-limit
cc-src-default-buf cc-src-buffer !
cc-src-default-cap cc-src-limit !
: cc-src-buf ( -- address ) cc-src-buffer @ ;
: cc-src-cap ( -- bytes ) cc-src-limit @ ;
variable cc-src-len

```

`skip-vm-pages` is the one trick in the file.  Before
`create cc-in-default-buf cc-in-default-cap allot` reserves a megabyte of dictionary
space, it slides HERE (the dictionary's next-byte pointer, Ch 2)
forward to `0x414000`, one page above the start of the sysvar page
(Ch 12 defines it), so the buffer lives clear of the seed's reserved
pages: the data-stack page at `0x410000–0x411000` (with the stack
itself growing down from the top), the I/O scratch byte at `0x412000`,
the token buffer at `0x412800`, the sysvars at `0x413000`.  Chs 13–20
introduced those addresses.

The two source buffers have one writer each.  `cc-in-buf` holds stdin
exactly as it arrived, and only the preprocessor reads it.
`cc-src-buf` holds what the preprocessor writes, with every
`#include "..."` file spliced in, which is why it is twice the size;
the lexer reads only this one.  Its cursor is `cc-src-pos` and
`cc-src-line` from the lexer's state block.

With the buffers placed, the reader is a reset word, a load loop built
on a general file reader, and three accessors:

```forth file=030-cc-io.fth
\ cc-src-init ( -- )  Empty the source buffer and rewind the reader.
: cc-src-init
  [lit] 0 cc-src-len !
  [lit] 0 cc-src-pos !
  [lit] 1 cc-src-line ! ;

\ cc-read-all ( fd buf cap code -- n )  Read fd to end of file into buf and
\ return the byte count.  Each read asks for all the room left.  A buffer
\ that fills up dies with code: a full buffer and a longer file look the
\ same, so the data must leave at least one byte of buf unused.
variable cc-ra-fd
variable cc-ra-buf
variable cc-ra-cap
variable cc-ra-code
variable cc-ra-n
: cc-read-all
  cc-ra-code ! cc-ra-cap ! cc-ra-buf ! cc-ra-fd !
  [lit] 0 cc-ra-n !
  cc-ra-fd @ 0= if,                    \ stdin: first what key-fill holds (020)
    cc-ra-buf @ cc-ra-cap @ key-drain cc-ra-n !
    cc-ra-n @ 1+ cc-ra-cap @ cc-ra-code @ cc-check-cap
  then,
  begin,
    cc-ra-fd @  cc-ra-buf @ cc-ra-n @ +  cc-ra-cap @ cc-ra-n @ -  read
    dup [lit] 0 >
  while,
    cc-ra-n +!
    cc-ra-n @ 1+ cc-ra-cap @ cc-ra-code @ cc-check-cap   \ full: die
  repeat,
  drop cc-ra-n @ ;

\ cc-load-stdin ( -- )  Read all of fd 0 into cc-in-buf; die 20 if it fills.
\ Rewinds the reader first, so an error here reports line 1.
: cc-load-stdin
  cc-src-init
  [lit] 0 cc-in-buf cc-in-cap [lit] 20 cc-read-all  cc-in-len ! ;

\ cc-eof? ( -- f )  -1 if pos has reached len; 0 otherwise.
: cc-eof?  cc-src-pos @ cc-src-len @ >= ;

\ cc-peek-char ( -- c )  Returns byte at the current position; 0 at EOF.
\ Both arms of if,/else, produce exactly one value, so stack stays balanced.
: cc-peek-char
  cc-eof? if,
    [lit] 0
  else,
    cc-src-buf cc-src-pos @ + c@
  then, ;

\ cc-next-char ( -- c )  Returns current byte and advances pos.
\ Tracks line number when consuming '\n' (10).
: cc-next-char
  cc-peek-char
  [lit] 1 cc-src-pos +!
  dup nl = if,
    [lit] 1 cc-src-line +!
  then, ;

```

`cc-read-all` is one `begin, while, repeat,`.  Each iteration calls
`read` with `(fd, buf+n, cap-n)`, asking for all the room that is
left, duplicates the returned count and tests it against 0.  If
positive, it adds the count to `n`, checks the buffer still has a
free byte, and loops; otherwise it drops the count and returns `n`.
A buffer that fills up is fatal even if the file happened to end
exactly there: a full buffer and a longer file look the same, so the
data must leave one byte unused.  `cc-load-stdin` reads fd 0 into
`cc-in-buf` this way, with code 20; Ch 22 reads `#include` files into
their own buffers with the same word.

`cc-peek-char` and `cc-next-char` are the reader interface every later
pass uses.  `peek` returns the byte at `pos` (or 0 at EOF) without
advancing.  `next` returns the same byte and advances, bumping
`cc-src-line` on newline.

### The output buffer

Section B declares the output buffer and the primitives that append
to it.

```forth file=030-cc-io.fth
\ ===========================================================================
\ B. Output buffer + ELF-aware emit helpers
\ ===========================================================================

\ 1 MiB output cap — fits any reasonable ELF the C-subset compiler emits.
[lit] 1048576 constant cc-out-default-cap
create cc-out-default-buf cc-out-default-cap allot
variable cc-out-buffer
variable cc-out-limit
cc-out-default-buf cc-out-buffer !
cc-out-default-cap cc-out-limit !
: cc-out-buf ( -- address ) cc-out-buffer @ ;
: cc-out-cap ( -- bytes ) cc-out-limit @ ;
variable cc-out-pos

\ cc-out-init ( -- )
: cc-out-init  [lit] 0 cc-out-pos ! ;

\ cc-emit-byte ( b -- )  Append a byte at cc-out-buf[cc-out-pos++]; die 21
\ if the buffer is full.
: cc-emit-byte
  cc-out-pos @ 1+ cc-out-cap [lit] 21 cc-check-cap
  cc-out-buf cc-out-pos @ + c!
  [lit] 1 cc-out-pos +! ;

\ cc-emit-4le ( v -- )  Emit low 4 bytes of v in little-endian.
: cc-emit-4le
  dup cc-emit-byte                              \ byte 0
  [lit] 256 / dup cc-emit-byte                  \ byte 1
  [lit] 256 / dup cc-emit-byte                  \ byte 2
  [lit] 256 / cc-emit-byte ;                    \ byte 3

\ cc-emit-8le ( v -- )  Emit all 8 bytes of v in little-endian.
\ Reuses cc-emit-4le for both halves; shifts by 32 between halves.
: cc-emit-8le
  dup cc-emit-4le                                              \ low 4 bytes
  [lit] 256 / [lit] 256 / [lit] 256 / [lit] 256 /              \ shift right 32
  cc-emit-4le ;                                                \ high 4 bytes

```

`cc-emit-byte` is the obvious `c!` plus `+!` pair.  `cc-emit-4le` and
`cc-emit-8le` peel off bytes from low to high by repeated `/256`.
These mirror `010-lib.fth`'s `,4` and `,8` (Ch 9), but write into
`cc-out-buf` rather than at the dictionary's HERE.

The emitters only append.  Fixing up bytes already written takes a
second family that writes at an explicit offset:

```forth file=030-cc-io.fth
\ cc-out-patch-byte ( v offset -- )  Overwrite cc-out-buf[offset] with low byte of v.
: cc-out-patch-byte  cc-out-buf + c! ;

\ cc-out-patch-4le ( v offset -- )  Overwrite 4 bytes at offset (LE).
\ Stash offset on the return stack so we can compute offset+1, +2, +3.
: cc-out-patch-4le
  >r                                                  ( v       ; R: offset )
  dup r@                       cc-out-patch-byte      ( v       ; R: offset )
  [lit] 256 / dup r@ 1+ cc-out-patch-byte             ( v>>8    ; R: offset )
  [lit] 256 / dup r@ [lit] 2 + cc-out-patch-byte      ( v>>16   ; R: offset )
  [lit] 256 /     r> [lit] 3 + cc-out-patch-byte ;    ( v>>24>>8 popped )

\ cc-out-patch-8le ( v offset -- )  Overwrite 8 bytes at offset (LE).
: cc-out-patch-8le
  >r                                                  ( v       ; R: offset )
  dup r@                       cc-out-patch-byte      ( v       ; R: offset )
  [lit] 256 / dup r@ 1+ cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 2 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 3 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 4 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 5 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 6 + cc-out-patch-byte
  [lit] 256 /     r> [lit] 7 + cc-out-patch-byte ;

```

`cc-out-patch-4le` stashes `offset` on the return stack with
`>r`/`r@`/`r>` (Ch 4) so the four byte-writes can each compute
`offset+0` through `offset+3`.  This is Ch 11's emit-remember-patch
pattern, moved from dictionary branch slots to `cc-out-buf` offsets.
Ch 25 uses it for ELF header fields whose values aren't known until
the rest of the file is laid out.

### Writing the file

Section C writes the buffer to a path.

```forth file=030-cc-io.fth
\ ===========================================================================
\ C. Output file write
\ ===========================================================================
\ Open flags (Linux x86-64 asm-generic):
\   O_WRONLY=1, O_CREAT=64, O_TRUNC=512  →  bitwise OR = 577.
\ Mode 0o755 = decimal 493.
\
\ 010-lib.fth's `open` already takes ( path flags mode -- fd ) — its signature
\ matches what we need, so no open3 wrapper is required here.

\ cc-write-output ( path-addr -- )  path-addr must point at NUL-terminated bytes.
\ Opens path with O_WRONLY|O_CREAT|O_TRUNC, mode 0755; writes
\ cc-out-buf[0..cc-out-pos@] to it; closes.  On open failure (fd < 0),
\ dies with code 22.
: cc-write-output
  [lit] 577 [lit] 493 open                        ( fd )
  dup 0< if,
    drop
    [lit] 22 cc-die
  then,
  >r                                              ( ; R: fd )
  r@ cc-out-buf cc-out-pos @ write drop           \ write all bytes
  r> close drop ;

```

Flag `577 = O_WRONLY|O_CREAT|O_TRUNC` and mode `493 = 0o755` are the
only magic numbers in the file, and the comment derives both.  On open
failure (`fd < 0`) the compiler dies with code 22.

### Shared helpers

Section D holds three words that the preprocessor (Ch 22), the lexer
(Ch 23) and the symbol table (Ch 24) all need, so each is written
once:

```forth file=030-cc-io.fth
\ ===========================================================================
\ D. Helpers shared by the preprocessor, lexer and symbol table
\ ===========================================================================

\ ident-start? ( c -- f )  letter or '_'.
: ident-start?
  dup alpha?  swap [char] _ = or ;

\ ident-cont? ( c -- f )  ident-start? or digit.
: ident-cont?
  dup ident-start?  swap digit? or ;

\ cell[] ( i arr -- addr )  Address of cell i of an array of 8-byte cells —
\ how every parallel-array table (macros, symbols, ...) is indexed.
: cell[]  swap [lit] 8 * + ;

\ cc-name-find ( a u addrs lens count -- i | -1 )  Look the name a u up in
\ a table kept as two parallel arrays, addrs (where each name's bytes are)
\ and lens (how many), of count entries.  Walks from the newest entry to the
\ oldest and returns the first match, so a later entry hides an earlier one
\ of the same name.  The loop index runs down to -1, so "not found" is
\ simply the final index.  The needle waits in globals so the loop body can
\ reach it without deep stack juggling.
variable cc-nf-a
variable cc-nf-u
variable cc-nf-addrs
variable cc-nf-lens
: cc-name-find
  >r  cc-nf-lens ! cc-nf-addrs ! cc-nf-u ! cc-nf-a !
  r> 1-                                          ( i = count-1 )
  begin,
    dup 0< 0=
  while,
    dup cc-nf-lens @ cell[] @  cc-nf-u @ = if,   \ same length?
      dup cc-nf-addrs @ cell[] @  cc-nf-a @  cc-nf-u @
      bytes-eq if, exit, then,                   \ found: return i
    then,
    1-                                           \ i--
  repeat, ;                                      \ not found: i = -1

\ cc-name-hash ( a u -- h )  djb2 over the name, as the linker hashes
\ symbols (140-cc-link.fth), masked to cc-name-buckets.  The macro and
\ symbol tables (040, 070) keep, per hash, their newest entry in a bucket
\ and link the older ones behind it, so a lookup compares only the names
\ that share its hash.
[lit] 4096 constant cc-name-buckets
: cc-name-hash
  [lit] 5381 >r
  begin, dup while,
    over c@ r> [lit] 33 * + >r
    1- swap 1+ swap
  repeat, 2drop
  r> cc-name-buckets 1- and ;

\ Direct GCC source workspace is opt-in; default buffers stay dictionary-backed.
\ Measured raw/expanded/output maxima are 2,782,995/5,415,887/3,901,856 bytes.
\ Raw and output round to whole MiB. Expanded text splices in every included
\ byte, so it and the direct include pool (040) share one bound: the measured
\ maximum (binutils i386-opc.c) plus 25%, rounded up to whole MiB. 3/7/4 MiB.
[lit] 3145728 constant cc-in-direct-cap
[lit] 7340032 constant cc-src-direct-cap
[lit] 4194304 constant cc-out-direct-cap
variable cc-io-direct-base

\ Round before mmap only after rejecting zero, negative and overflowing sizes.
\ Requests are policy constants at callers; this helper never grows a buffer.
: cc-workspace-round ( bytes code -- page-bytes )
  >r dup [lit] 0 <= if, r@ cc-die then,
  dup [lit] 9223372036854771712 > if, r@ cc-die then,
  [lit] 4095 + [lit] 4096 / [lit] 4096 * r> drop ;
: cc-workspace-syscall ( page-bytes -- address )
  [lit] 0 swap [lit] 3 [lit] 34 true [lit] 0 [lit] 9 syscall6 ;
defer cc-workspace-syscall-fwd
' cc-workspace-syscall is cc-workspace-syscall-fwd
: cc-workspace-map ( bytes code -- address )
  >r r@ cc-workspace-round cc-workspace-syscall-fwd
  dup [lit] 0 <= if, r@ cc-die then, r> drop ;
: cc-io-default-workspace ( -- )
  cc-in-default-buf cc-in-buffer ! cc-in-default-cap cc-in-limit !
  cc-src-default-buf cc-src-buffer ! cc-src-default-cap cc-src-limit !
  cc-out-default-buf cc-out-buffer ! cc-out-default-cap cc-out-limit ! ;
: cc-io-direct-workspace ( -- )
  cc-io-direct-base @ 0= if,
    cc-in-direct-cap cc-src-direct-cap + cc-out-direct-cap + [lit] 20 cc-workspace-map
    cc-io-direct-base !
  then,
  cc-io-direct-base @ cc-in-buffer ! cc-in-direct-cap cc-in-limit !
  cc-io-direct-base @ cc-in-direct-cap + cc-src-buffer !
  cc-src-direct-cap cc-src-limit !
  cc-src-buf cc-src-direct-cap + cc-out-buffer ! cc-out-direct-cap cc-out-limit ! ;
```

`ident-start?` and `ident-cont?` classify identifier bytes: a letter
or `_` starts one, and digits may follow.  Every compiler table is a
set of parallel arrays of 8-byte cells, one array per field, indexed
by entry number; `cell[]` turns an index into a cell address, so
`i cc-sym-kind cell[] @` reads entry `i`'s kind.  `cc-name-find` is
the plain lookup: a table that keeps each name as an address array and
a length array wants the newest entry with a given name, so a later
entry hides an earlier one.  It answers the entry's index, or -1.
Small tables (labels, a macro's parameters) use it as it is.  The
macro table, the symbol table and the object records hold thousands
of names when the compiler builds GCC, so they also file each entry
under `cc-name-hash` and compare only the names in one bucket.

## 3. Why one big buffer instead of streaming?

A streaming compiler would pipe characters through lexer, parser and
emitter with no intermediate buffers.  This one reads everything,
walks it, then writes everything out.

Streaming wins on memory when the source is huge; buffering wins on
simplicity when it is small.  M2-Planet's largest single translation
unit is about 220 KiB, so a 1 MiB input cap leaves headroom, and four
megabytes of address space buy a compiler with no I/O interleaving to
reason about.  Every cap is checked: input that does not fit is error
20, output 21.

Several passes also want random access.  The lexer peeks two bytes
ahead to tell `/` from `//` and `0` from `0x`.  The preprocessor
reads the whole input buffer and writes the source buffer.  The code
emitter patches ELF header fields.

This is "one buffer per responsibility" in its simplest form: raw
input, preprocessed source, emitted ELF bytes and global data each get
an owner and a cursor.

## 4. How the buffers connect to what's coming

The rest of Part III reaches for these pieces by name.  Ch 22 walks
`cc-in-buf` with its own cursor and writes its result into
`cc-src-buf`; Ch 23 reads that through `cc-peek-char` /
`cc-next-char`, and backs up only by resetting the whole lexer-state
block.  Every failure from here on ends in `cc-die`.  Ch 24's struct descriptors and Ch 26's forward-call fixup chains
come from `cc-alloc`.  Chs 25, 26 and 29–31 emit into `cc-out-buf` and
back-patch with `cc-out-patch-4le` / `cc-out-patch-8le`, and Ch 32
calls `cc-write-output` last.

## Try it

**Small check:** the repo test script runs the focused probes for
this chapter's two mechanisms, `test-020-cc-arena.fth` and
`test-030-cc-io.fth`.

```sh
./build.sh
./test.sh         # runs test-020-cc-arena.fth and test-030-cc-io.fth
                  # alongside the lexer / types / sym tests.
```

`test-020-cc-arena.fth` exercises `cc-alloc` at several sizes and
asserts the returned addresses are 8-aligned and non-overlapping;
`test-030-cc-io.fth` round-trips bytes through `cc-emit-byte` and
`cc-out-patch-4le`.

**Bootstrap relevance:** the Stage-A gate uses these buffers for every
input byte and every emitted output byte, starting with the smallest C
test case.

```sh
./build.sh && tests/cc/stage-a-check.sh
```

That driver has `seed-forth` compile the M2-Planet monolith, runs the
result on M2-Planet's own sources, and `cmp`s the `.M1` text it
writes against a GCC-built M2-Planet's.

**tri.c at this stage:** compile the running example, then replay
`cc-main`'s steps by hand to watch the buffers fill.  The second
pipeline loads every file except `120-cc-main.fth` (whose last line
runs `cc-main`) and prints a cursor after each step:

```sh
./build.sh
tri() { cat <<'C'
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
}
{ cat 010-lib.fth $(tools/compiler-layers.sh); tri; } | ./seed-forth
/tmp/cc-out                         # draws the triangle
echo "exit: $?"                     # prints "exit: 16"
{ cat 010-lib.fth 0[2-9]0-cc-*.fth 1[01][0-9]-cc-*.fth
  cat <<'FORTH'
: .d  dup [lit] 9 > if, dup [lit] 10 / .d then,
      dup [lit] 10 / [lit] 10 * - [lit] 48 + emit ;
: .n  .d [lit] 32 emit ;
: steps
  cc-load-stdin        cc-in-len @ .n
  cc-preprocess        cc-src-len @ .n
  cc-out-init cc-globals-init
  cc-emit-elf-header   cc-out-pos @ .n
  cc-parse-program     cc-out-pos @ .n
  cc-finalize-globals  cc-out-pos @ .n
  cc-arena-ptr @ cc-arena-base - .d  bye ;
steps
FORTH
  tri; } | ./seed-forth             # prints "484 466 120 1225 1241 440"
```

`cc-load-stdin` puts all 484 bytes of `tri.c` in `cc-in-buf`; the
preprocessor (Ch 22) writes 466 into `cc-src-buf`, the `#define` line
gone and each `ROWS` now ` 4 `.  `cc-out-buf` holds the 120-byte ELF
header (Ch 25) before a single token is parsed, 1,225 bytes once both
functions are compiled, and 1,241 once the 16 bytes of the global `t`
are appended (Ch 26).  The last number is the arena: 440 bytes, the
56-byte descriptor header for `struct tri` and its 320-byte field
table, room for eight 40-byte records (Ch 24), and a 64-byte lexer mark
for the `for` loop's step expression (Ch 30).  `cc-finalize-elf` and `cc-write-output` then
send those 1,241 bytes to `/tmp/cc-out` in one `write`.

## Exercises

1. **★★★ Verify.** The arena is 32 KiB.  Could you reduce it to 16 KiB without
   breaking M2-Planet compilation?  How would you measure?  (Hint:
   instrument `cc-alloc` to record peak `cc-arena-ptr`.)

2. **★★ Verify.** The input buffer is 1 MiB and the source buffer
   2 MiB.  What are the actual peak sizes for M2-Planet?  Could you
   tighten them and save a few megabytes of virtual address space?

3. **★★ Trace.** `cc-out-patch-4le` writes 4 bytes one at a time.  Could you
   write a faster `patch-cell-le` using `!` and some shuffling?
   Would it be worth the bytes-of-code?

4. **★★ Modify.** Add `cc-emit-string ( c-addr u -- )` that emits `u` bytes from
   `c-addr` to the output buffer.  Use it to emit a hardcoded
   "Hi\n" greeting and confirm.

5. **★★ Trace.** The arena's OOM path dies with code 10.  Grep for
   `cc-die` in `020-cc-arena.fth` through `070-cc-sym.fth`, list the
   codes, and check them against Appendix G.  Which range would a new
   failure in the lexer (050) draw from?

## After this chapter

The compiler has a deterministic memory model: stdin lands in
`cc-in-buf`, the preprocessed source in `cc-src-buf`, emitted bytes accumulate in `cc-out-buf` and reach disk
in one `write`, and the arena handles anything that doesn't fit a
fixed slot.  Every byte the Stage-A check compares passes through
these buffers.  But `tri.c`'s 484 bytes are not yet C a parser can
use: line 1, `#define ROWS 4`, is an instruction to a preprocessor,
and Ch 22 has to decide what to do with it.

## Takeaways

- The default compiler keeps three big buffers (input, source, output) and a 32 KiB arena inside the seed's 16 MiB segment (Ch 13). Optional direct drivers map a separate bounded arena without changing the seed.
- Reading and writing are batched: stdin arrives in one loop, and the output leaves in one `write` after the whole ELF is laid out.
- Every capacity is checked with `cc-check-cap`, and every failure ends in `cc-die`, which prints the source line and exits with a code from the owning file's range (Appendix G).
- Back-patching through `cc-out-patch-4le` and `cc-out-patch-8le` handles forward references inside the emitted ELF, the same trick `if,` uses for Forth-level control flow in Ch 11.

Next: Chapter 22 — The Preprocessor.

### Optional direct-GCC source storage

The default raw and expanded buffers remain 1 MiB and 2 MiB dictionary
allocations. Their public words now load a selected address or capacity, so
callers keep exactly the same stack effects. Only the direct-GCC driver opts
into raw/expanded/output slices of 3/7/4 MiB in one anonymous mapping. The unchanged original
`insn-attrtab.c` input is 2,782,995 bytes; its expanded text is 2,747,955 bytes.
The other measured generated unit, `insn-recog.c`, expands to 2,469,308 bytes.
The raw and output capacities are those maxima rounded up to a whole MiB.

The expanded slice was 3 MiB until binutils. Its `opcodes/i386-opc.c` is a
small file that includes `i386-tbl.h`, 5,334,945 bytes of generated
instruction templates, and expands to 5,415,887 bytes. Expanded text holds
every included byte outside directives and skipped groups, so it shares one
bound with the direct include pool (Ch 22 §4): the largest measured
requirement in the binutils 2.30 and GCC 4.0.4 cohort plus a quarter,
rounded up to a whole MiB, 7 MiB. The same rule sizes the object writer's
rodata and data (Ch 35). The suppression shadow (Ch 22) covers the 2 MiB
scratch area and this slice, so it grows from 5 to 9 MiB; with the mapped
include pool and object sections the direct profile reserves 18.5 MiB more
address space. An anonymous mapping costs memory only for the pages a unit
touches.

`cc-workspace-round` rejects zero, negative and overflowing requests before
rounding to Linux pages. `cc-workspace-map` makes one private read/write mapping
request and fails through the existing caller-selected diagnostic. The mapping
is cached within this compiler process; selecting it repeatedly does not grow
it. Selecting default storage again restores the original buffers. The selectors preserve cursors and counts; selection
belongs before loading a new source and normal initialization, and `cc-src-init` and `cc-out-init` retain
their existing cursor-reset roles. The raw reader still reserves one byte to
distinguish end-of-file: its largest accepted payload is capacity minus one.
Neither an allocation failure nor a later capacity error is retried at a larger
size. The seed itself and its 16 MiB segment are unchanged.
