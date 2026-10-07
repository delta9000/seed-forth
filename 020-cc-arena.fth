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
