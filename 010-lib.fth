\ 010-lib.fth — minimal helpers built on top of the 32 hand-encoded primitives.
\ Loaded before any Forth-level vocabulary.
\
\ Conventions:
\   - All arithmetic constants use [lit] (the decimal literal compiler)
\     because the seed has no number parser in interpret mode by default.
\   - Sysvar absolute addresses are baked in (decimal) since [lit] needs a
\     literal.  Update if 000-seed.hex0's sysvar layout ever moves.

\ here-addr ( -- a )  push the address of the HERE sysvar cell.
\ Useful because most "advance HERE" idioms want to update the cell, not just
\ read its current value (which is what `here` does).
: here-addr  [lit] 4272144 ;            \ &HERE = 0x413010

\ c, ( b -- )  store low byte of TOS at HERE and advance HERE by 1.
\ This is the workhorse for any code-emission vocabulary built in Forth.
: c,
  here c!                                 \ *HERE = byte
  here-addr @ [lit] 1 + here-addr !       \ HERE += 1
;

\ ----- bool / bitwise helpers built on nand -----
\ All derived because nand is the only logical primitive in the seed.

\ and ( a b -- a&b ) = ~~(a&b) = nand of nand-of-itself
: and  nand dup nand ;

\ or  ( a b -- a|b ) via De Morgan: ~(~a & ~b)
: or   dup nand swap dup nand nand ;

\ over ( a b -- a b a )  copy second-from-top to top.
\ Standard Forth idiom, missing from our seed primitives.
: over  >r dup r> swap ;

\ - ( a b -- a-b )  subtract via 2's complement (we have + and nand).
\ Used by classifier helpers and the local rel32 CALL encoder below.
: -  dup nand [lit] 1 + + ;

\ ===== Linux syscall wrappers (via syscall6 primitive) =====
\ syscall6 ( a b c d e f n -- rax )  loads a..f into rdi/rsi/rdx/r10/r8/r9
\ and n into rax.  We pad with zeros for unused argument slots.
\
\ Linux x86-64 syscall numbers:
\   read=0  write=1  open=2  close=3  exit=60  brk=12  mmap=9

\ open  ( path flags mode -- fd )    SYS_open=2
: open   [lit] 0 [lit] 0 [lit] 0 [lit]  2 syscall6 ;

\ read  ( fd buf count -- n )        SYS_read=0
: read   [lit] 0 [lit] 0 [lit] 0 [lit]  0 syscall6 ;

\ write ( fd buf count -- n )        SYS_write=1
: write  [lit] 0 [lit] 0 [lit] 0 [lit]  1 syscall6 ;

\ close ( fd -- err )                SYS_close=3
\ Pads 5 zero args + syscall #.
: close  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit]  3 syscall6 ;

\ die ( n -- )  Exit with status n via SYS_exit=60.
\ Used by the C compiler's error paths instead of inlining the full syscall.
: die  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 60 syscall6 ;

\ ===== Character classification helpers =====
\ All return -1 if true, 0 if false (Forth boolean convention).
\ Approach: just hard-code the literal byte values and use 0= equality chains.

\ digit? ( c -- flag )  true if c is in '0'..'9' (ASCII 48..57)
\ Approach: compute (c-48)/10.  If c<48 the subtract underflows to a huge
\ unsigned, /10 is huge, 0= is 0.  If c in 48..57, (c-48)/10 = 0, 0= is -1.
\ If c >= 58, (c-48)/10 >= 1, 0= is 0.  ✓
: digit?  [lit] 48 - [lit] 10 / 0= ;

\ alpha-lower? ( c -- flag )  true if c is 'a'..'z' (97..122)
\ Same trick: (c-97)/26 = 0 iff c in 97..122.
: alpha-lower?  [lit] 97 - [lit] 26 / 0= ;

\ alpha-upper? ( c -- flag )  true if c is 'A'..'Z' (65..90)
: alpha-upper?  [lit] 65 - [lit] 26 / 0= ;

\ alpha? ( c -- flag )  true if c is alphabetic
: alpha?  dup alpha-lower? swap alpha-upper? or ;

\ space? ( c -- flag )  true if c is ' '|tab|LF|CR
: space?  dup [lit] 32 - 0= over [lit]  9 - 0= or
          over [lit] 10 - 0= or  swap [lit] 13 - 0= or ;

\ ===== Comparison operators =====
\ All return -1 (true) / 0 (false), Forth boolean convention.

\ = ( a b -- f )  -1 if a = b, else 0.  Equal iff (a - b) = 0.
: =   - 0= ;

\ <> ( a b -- f )  inverse of =.
: <>  = 0= ;

\ neg-flag ( n -- f )  -1 if n is signed-negative (bit 63 set), else 0.
\ Strategy: the seed's `/` is unsigned (DIV instruction).  A value with
\ bit 63 set, divided by 2^63, yields exactly 1; any non-negative value
\ yields 0.  Then `0= 0=` canonicalises (1 -> -1, 0 -> 0).
\ The literal 9223372036854775808 = 2^63 = 0x8000000000000000 round-trips
\ through parse_decimal_code because that parser uses an unsigned 64-bit
\ 2^63 = 0x8000000000000000, the sign bit of a 64-bit signed integer.
: 2^63  [lit] 9223372036854775808 ;

\ neg-flag ( n -- f )  return true if n is negative (sign bit set).
\ Dividing by 2^63 yields 0 for non-negative, 1 for negative.
: neg-flag  2^63 / 0= 0= ;

\ < ( a b -- f )  signed less-than: a < b iff (a - b) is negative.
: <   - neg-flag ;

\ > ( a b -- f )  signed greater-than: b < a.
: >   swap < ;

\ <= ( a b -- f )  not (a > b).
: <=  > 0= ;

\ >= ( a b -- f )  not (a < b).
: >=  < 0= ;

\ ===== Stack shuffles =====
\ Standard Forth stack-manipulation words built on the seed primitives
\ swap, dup, drop, >r, r>, plus over (defined above).

\ nip ( a b -- b )  drop second-from-top.
: nip   swap drop ;

\ rot ( a b c -- b c a )  rotate third-from-top to top.
: rot   >r swap r> swap ;

\ 2dup ( a b -- a b a b )  duplicate the top pair.
: 2dup  over over ;

\ 2drop ( a b -- )  drop the top pair.
: 2drop drop drop ;

\ ===== Memory update helpers =====

\ +! ( n addr -- )  add n to the cell at addr.
: +!  swap over @ + swap ! ;

\ -! ( n addr -- )  subtract n from the cell at addr.
: -!  swap over @ swap - swap ! ;

\ ===== 4-byte little-endian writer =====
\ ,4 ( v -- )  emit low 4 bytes of v at HERE in LE order.
\ Used by comma-call (rel32) and any Forth-level code emitter that needs
\ compact little-endian immediates.
: ,4
  dup c,                       \ byte 0
  [lit] 256 / dup c,           \ byte 1
  [lit] 256 / dup c,           \ byte 2
  [lit] 256 / c, ;             \ byte 3

\ ,8 ( v -- )  emit all 8 bytes of v at HERE in LE order.
\ Used for movabs imm64 in defining words and for 8-byte branch target slots.
: ,8
  dup ,4                                                 \ low 4 bytes
  [lit] 256 / [lit] 256 / [lit] 256 / [lit] 256 /        \ shift right 32
  ,4 ;                                                   \ high 4 bytes

\ ===== immediate flag toggle =====
\ immediate ( -- )  Set the IMMEDIATE bit in the flags byte of the most-recent
\ dict entry.  An immediate word executes at compile time even when STATE=1
\ (inside : ... ;).  Mirrors the manual `01` flags byte on `;` in 000-seed.hex0.
\
\ Layout reminder: a dict entry is  link(8) flags(1) name-len(1) name(N) body.
\ `latest` is a seed primitive — it pushes the address of the LATEST sysvar
\ cell; `latest @` fetches the current dict tail pointer; `+ 8` is the
\ flags-byte address.
: immediate  latest @ [lit] 8 + [lit] 1 swap c! ;

\ ===== constant (defined early so branch-xt/0branch-xt can use it) =====
\ The control-flow combinators below need to know branch/0branch's xts.
\ Hardcoding them as numeric literals would break every time 000-seed.hex0's
\ dictionary layout changes; instead, resolve them at load time via the
\ seed's `'` (tick) primitive, captured into a constant.  This requires
\ `constant` to be defined before the combinators — hence its position here.
\
\ Runtime body is 19 bytes:
\   48 83 ED 08          sub rbp, 8       ; make data-stack room
\   48 89 7D 00          mov [rbp+0], rdi ; spill old TOS
\   48 BF <imm64>        movabs rdi, V    ; load the value as the new TOS
\   C3                   ret
: constant
  :                                                        \ parse name, build header, STATE=1
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,         \ 48 83 ED 08  sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,         \ 48 89 7D 00  mov [rbp], rdi
  [lit] 72 c, [lit] 191 c,                                 \ 48 BF        movabs rdi, ...
  ,8                                                       \ imm64 = v (consumes v)
  [lit] 195 c,                                             \ C3          ret
  [lit] 0 state ! ;                                        \ STATE=0 (back to interpret)

\ ===== Control-flow combinators =====
\ Compile-time helpers that emit calls to the seed's `branch` and `0branch`
\ primitives, plus inline 8-byte target slots, structured per traditional
\ Forth idiom (begin/until/again/while/repeat/if/else/then).
\
\ The seed's branch/0branch primitives work with inline 8-byte target cells.
\ Their x86 machine code is:
\     pop rax           ; rax = return address = address of inline slot
\     mov rax, [rax]    ; rax = contents of slot = branch destination
\     push rax          ; push destination as new return address
\     ret               ; "return" to destination (indirect jump)
\
\ zbranch_code is the same except it first inspects TOS (in rdi/rdx) and
\ either loads the slot (branch taken) or skips past it (fall through).
\
\ This means the combinators must emit a 5-byte CALL rel32 followed
\ immediately by an 8-byte absolute target address.  The CALL lands
\ inside branch_code / zbranch_code which pop their own return address
\ (pointing at the slot), dereference it, and jump.
\
\ The slot is thus "consumed" — it does NOT remain on the return stack.
\ backward branches simply emit the back-target cell; forward branches
\ reserve a slot, return its address as a fixup, and patch it later.
\
\ slot-layout for a forward branch (e.g. if, ... then,):
\     E8 xx xx xx xx    ; CALL rel32 -> 0branch_code
\     <8-byte slot>     ; initially 0, patched by then, to target HERE
\ After CALL, rax -> slot; zbranch_code tests flag, either:
\   - flag==0: mov rax,[rax] -> load slot -> push -> ret to target
\   - flag!=0: add rax,8    -> skip slot -> push -> ret past slot
\
\ Names end in `,` per Forth-asm convention ("emits code") and to keep them
\ distinct from any plain runtime `if`/`then` words.
\
\ branch-xt / 0branch-xt — the xts of the seed's `branch` and `0branch`
\ primitives, captured via `'` at load time so any 000-seed.hex0 layout change
\ is automatically tracked.
' branch  constant branch-xt
' 0branch constant 0branch-xt

\ comma-call ( target -- )  Emit a 5-byte x86-64 CALL to absolute `target`
\ at HERE.  rel32 = target - (HERE + 5).  After `[lit] 232 c,` advances
\ HERE by 1, HERE points at the rel32's first byte and HERE+4 points just
\ past the 5-byte CALL — so rel32 = target - (HERE_now + 4).
\ Kept here so the control-flow combinators do not need another assembler layer.
: comma-call
  [lit] 232 c,                 \ 0xE8 CALL opcode
  here [lit] 4 + - ,4 ;        \ rel32 = target - (HERE+4); emit 4 LE bytes

\ if, ( -- fixup )  At compile time: emit `CALL 0branch` + reserved 8-byte
\ target slot.  Returns the slot's address as a fixup for `then,` or `else,`.
\ Runtime semantics: pops a flag; if flag = 0, jumps to the patched target
\ (the matching `then,`/`else,`'s HERE).  If flag is non-zero, falls through.
: if,
  0branch-xt comma-call
  here                         \ slot address, returned as fixup
  [lit] 0 ,                    \ reserve 8 bytes (` ,` emits a cell)
;
immediate

\ then, ( fixup -- )  Patch the fixup slot to current HERE so the matching
\ if,/while,/else, jumps here when its branch is taken.
: then,
  here swap ! ;
immediate

\ else, ( fixup-if -- fixup-else )  Emit unconditional `CALL branch` + slot
\ to leap over the else-arm; patch the if-fixup to land at the start of the
\ else-arm; return the new (else-arm-end) fixup for `then,` to patch.
: else,
  branch-xt comma-call
  here                         \ start of new (else-end) target slot
  [lit] 0 ,                    \ reserve 8 bytes
  swap                         \ ( fixup-else fixup-if )
  here swap !                  \ patch fixup-if -> just past unconditional branch
;
immediate

\ begin, ( -- back-target )  Mark the top of a loop; just records HERE.
: begin,  here ;
immediate

\ while, ( back-target -- back-target fixup )  Test flag, exit loop if false.
\ Emits `CALL 0branch` + reserved slot; returns the slot addr as the loop-exit
\ fixup, leaving back-target underneath for repeat,.
: while,
  0branch-xt comma-call
  here [lit] 0 , ;
immediate

\ repeat, ( back-target fixup -- )  Emit unconditional jump back to begin-target;
\ patch the loop-exit fixup to land just past it.
: repeat,
  swap branch-xt comma-call ,  \ unconditional `CALL branch` + back-target cell
  here swap !                  \ patch loop-exit fixup -> just-past-repeat
;
immediate

\ ===== Defining-words: allot / constant / variable / create =====
\ These let Forth code build named constants, variables, and arbitrary data
\ structures without escaping back into 000-seed.hex0.  All three of constant /
\ variable / create call the seed's `:` primitive to do the dirty work of
\ tokenizing the next input word and constructing a dictionary header (link,
\ flags=0, name-len, name bytes); then they hand-emit a 19-byte runtime body
\ and reset STATE=0 (since `:` left it at 1).

\ allot ( n -- )  Bump HERE by n bytes (no initialization).
\ Used after `create` to grow an array, or stand-alone for scratch buffers.
: allot  here-addr @ + here-addr ! ;

\ ----- runtime body shared by constant/variable/create -----
\ All three emit the same prologue: spill old TOS, load a new TOS via movabs.
\ The differences are what 64-bit value goes into the movabs imm64 slot,
\ and what (if anything) follows the `ret`.  Bytes:
\
\   48 83 ED 08          sub rbp, 8       ; make data-stack room
\   48 89 7D 00          mov [rbp+0], rdi ; spill old TOS
\   48 BF <imm64>        movabs rdi, V    ; load the value as the new TOS
\   C3                   ret
\
\ Total: 4 + 4 + 10 + 1 = 19 bytes.

\ (constant is defined earlier in this file, before the control-flow
\ combinators, so they can capture branch/0branch xts at load time.)

\ create ( -- )  Reads next token; defines a word that pushes the address of
\ the data area immediately following its body.  Caller fills the data area
\ via `,` / `c,` / `allot`.
\
\ At the moment `,8` is about to consume its argument, HERE points at the
\ first byte of the imm64 slot.  After `,8` (8 bytes) and the `ret` byte
\ (1 byte), HERE will point exactly at the data area — i.e. data-area-start
\ = HERE_now + 9.
: create
  :
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,        \ sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,        \ mov [rbp], rdi
  [lit] 72 c, [lit] 191 c,                                 \ movabs rdi prefix
  here [lit] 9 +                                           \ data-area starts 9 bytes ahead
  ,8                                                       \ imm64 = data-area address
  [lit] 195 c,                                             \ ret
  [lit] 0 state ! ;

\ variable ( -- )  Reads next token; defines a word that pushes the address
\ of an 8-byte cell (initialized to 0) embedded in the dictionary right after
\ the body.  Identical to `create` followed by `0 ,`, inlined here for
\ clarity (and to avoid depending on dispatch through `create`'s xt).
: variable
  :
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,        \ sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,        \ mov [rbp], rdi
  [lit] 72 c, [lit] 191 c,                                 \ movabs rdi prefix
  here [lit] 9 +                                           \ cell address = HERE+9
  ,8
  [lit] 195 c,                                             \ ret
  [lit] 0 ,                                                \ data cell, init 0 (8 bytes)
  [lit] 0 state ! ;

\ ===== bytes-eq =====
\ bytes-eq ( a1 a2 u -- f )  -1 if first u bytes at a1 match those at a2; 0 else.
\ Used by symbol-table name comparison and keyword recognition in the C
\ compiler.  Because the seed has no `exit` primitive, we cannot short-
\ circuit out of the loop on first mismatch.  Instead we accumulate the
\ still-equal flag in a variable and examine every byte.  This is O(u)
\ even on early mismatch, which is acceptable for the short names compared by
\ this compiler.
variable bytes-eq-flag
: bytes-eq
  [lit] 0 0= bytes-eq-flag !                     \ flag := -1 (assume equal)
  begin,
    dup [lit] 0 >
  while,
    >r                                           ( a1 a2  R-u )
    over c@ over c@ =                            ( a1 a2 byte-eq )
    bytes-eq-flag @ and bytes-eq-flag !          ( a1 a2 )
    [lit] 1 + swap [lit] 1 + swap                ( a1+1 a2+1 )
    r> [lit] 1 -                                  ( a1+1 a2+1 u-1 )
  repeat,
  drop drop drop                                  \ discard a1, a2, u(=0)
  bytes-eq-flag @ ;
