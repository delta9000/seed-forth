\ 130-asm.fth — M1 + hex2 assembler / linker in Forth.
\
\ Closes the bootstrap gap below seed-forth's C compiler: consumes the
\ M1 macro syntax that M2-Planet emits and produces ELF bytes directly,
\ removing the need to trust GCC-built mescc-tools (M1, hex2).  Stage0-
\ posix's M1+hex2 stays in the picture as an independent byte-level
\ witness; both pipelines are expected to produce identical bytes.
\
\ Self-contained: depends only on 010-lib.fth (and the seed primitives
\ it builds on).  No cross-import from the C-compiler layers — forth-asm
\ sits cleanly below the cc in the bootstrap chain rather than alongside.
\
\ What is implemented (phase 2 complete):
\   - M1 macro expansion: 'DEFINE name value' + name substitution
\   - Six sigils: '!' (1-byte rel), '@' (2-byte rel), '~' (3-byte rel),
\     '%' (4-byte rel, with optional '>base' explicit base), '$' (2-byte
\     abs), '&' (4-byte abs).  Each handles numeric form ('!42', '%0x3C',
\     '%-1', decimal / hex / negative) and label form.
\   - Quoted strings: '"text"' hex-encodes bytes with NUL terminator;
\     "'text'" passes content through verbatim.
\   - ':label' decls; '#' and ';' comments to end of line.
\   - Two-pass label resolution; cmp-identical to mescc-tools' M1+hex2
\     output for the exit42 smoke test, the m1-jump42 fixture, and the
\     full M2-Planet self-compile (~2.4 MiB M1 in, 220 KiB ELF out).
\
\ Not implemented (no real-world inputs use these on amd64):
\   - '<N' padding directive
\   - nibble accumulation across whitespace within a hex pair
\   - architecture-specific ARM/AArch64/RISC-V displacement quirks
\   - the rare unary-'<' / '^' alignment markers used by ARM

\ ============================================================================
\ A. Buffers + cursor abstraction
\ ============================================================================
\ Skip past the VM's fixed pages (data stack 0x410000..0x411000, I/O scratch
\ 0x412000, token buffer 0x412800, sysvars 0x413000..0x414000) so our buffers
\ do not overlap runtime VM state.
skip-vm-pages                                   \ HERE = 0x414000

\ asm-check-cap ( n cap code -- )  Die with code unless n <= cap: the
\ assembler's copy of cc-check-cap (020), since this program loads none of
\ the compiler's files.  n is how full a buffer or table will be once the
\ write about to happen is done.  Codes are 230..249 (Appendix G).
: asm-check-cap
  >r > if, r> die then,
  r> drop ;

\ Raw M1 source (filled by asm-load-stdin).
\ Sized for M2-Planet's ~2.4 MiB self-compile output plus libc + defs + ELF.
[lit] 4194304 constant asm-src-cap            \ 4 MiB
create asm-src-buf  asm-src-cap allot
variable asm-src-len

\ Expanded buffer (filled by asm-expand-pass: M1 macros substituted, DEFINEs
\ stripped).  Passes 1 and 2 read from here, not from asm-src-buf.
[lit] 4194304 constant asm-exp-cap            \ 4 MiB
create asm-exp-buf  asm-exp-cap allot
variable asm-exp-len

\ Cursor: read primitives look at whichever buffer asm-cur-* points to.
\ asm-use-src and asm-use-exp swap the cursor between the two buffers.
variable asm-cur-buf
variable asm-cur-len
variable asm-cur-pos

: asm-use-src
  asm-src-buf asm-cur-buf !
  asm-src-len @ asm-cur-len !
  [lit] 0 asm-cur-pos ! ;

: asm-use-exp
  asm-exp-buf asm-cur-buf !
  asm-exp-len @ asm-cur-len !
  [lit] 0 asm-cur-pos ! ;

: asm-reset-pos  [lit] 0 asm-cur-pos ! ;

\ asm-load-stdin ( -- )  Read all of fd 0 into asm-src-buf.  Each read asks
\ for all the room left; a source that fills the buffer dies with 239 (a
\ full buffer and a longer input look the same, so one byte stays unused).
: asm-load-stdin
  [lit] 0 asm-src-len !
  begin,
    [lit] 0 asm-src-buf asm-src-len @ +  asm-src-cap asm-src-len @ -  read
    dup [lit] 0 >
  while,
    asm-src-len +!
    asm-src-len @ 1+ asm-src-cap [lit] 239 asm-check-cap
  repeat,
  drop ;

\ asm-eof? ( -- f )
: asm-eof?  asm-cur-pos @ asm-cur-len @ >= ;

\ asm-peek-char ( -- c )  Byte at current position; 0 at EOF.
: asm-peek-char
  asm-eof? if,
    [lit] 0
  else,
    asm-cur-buf @ asm-cur-pos @ + c@
  then, ;

\ asm-next-char ( -- c )  Returns current byte, advances pos.
: asm-next-char
  asm-peek-char
  [lit] 1 asm-cur-pos +! ;

\ asm-exp-emit-byte ( b -- )  Append a byte to asm-exp-buf; die 240 if full.
: asm-exp-emit-byte
  asm-exp-len @ 1+ asm-exp-cap [lit] 240 asm-check-cap
  asm-exp-buf asm-exp-len @ + c!
  [lit] 1 asm-exp-len +! ;

\ ============================================================================
\ B. Output buffer + emit helpers
\ ============================================================================
[lit] 1048576 constant asm-out-cap
create asm-out-buf  asm-out-cap allot
variable asm-out-pos

: asm-out-init  [lit] 0 asm-out-pos ! ;

\ asm-emit-byte ( b -- )  Append a byte to asm-out-buf; die 241 if full.
: asm-emit-byte
  asm-out-pos @ 1+ asm-out-cap [lit] 241 asm-check-cap
  asm-out-buf asm-out-pos @ + c!
  [lit] 1 asm-out-pos +! ;

\ ============================================================================
\ C. Output file write
\ ============================================================================
\ Open flags: O_WRONLY=1, O_CREAT=64, O_TRUNC=512 → 577.  Mode 0o755 = 493.

\ asm-write-output ( path-addr -- )  path-addr must point at NUL-terminated bytes.
: asm-write-output
  [lit] 577 [lit] 493 open                      ( fd )
  dup 0< if,
    drop [lit] 230 die
  then,
  >r                                            ( ; R: fd )
  r@ asm-out-buf asm-out-pos @ write drop
  r> close drop ;

\ Newline byte for stderr diagnostics.
create asm-nl-byte  nl c,

\ ============================================================================
\ Label table — flat array of (name-addr, name-len, ip) triples.
\ ============================================================================

[lit]   24 constant asm-rec-size
[lit] 8192 constant asm-cap                   \ headroom: M2-Planet uses ~4k labels
create asm-labels  asm-rec-size asm-cap * allot
variable asm-count

\ Base address.  Default matches mescc-tools' --base-address 0x00600000
\ for the M2-Planet self-compile path.  Callers can override by storing a
\ different value before invoking asm-main, e.g. for GNU Mes (0x1000000):
\
\   cat 010-lib.fth 130-asm.fth                   \ defines words
\   echo '[lit] 16777216 asm-base !'              \ override
\   echo 'asm-main'                                \ then run
\
variable asm-base
[lit] 6291456 asm-base !                          \ 0x600000 default
variable asm-ip
variable asm-pass

\ asm-rec ( i -- a )  Address of the i-th label record.
: asm-rec  asm-rec-size *  asm-labels + ;

\ asm-store-label ( name-addr name-len -- )  Die 242 if the table is full.
: asm-store-label
  asm-count @ 1+ asm-cap [lit] 242 asm-check-cap
  asm-count @ asm-rec                       ( addr len rec )
  >r                                         ( addr len ; R: rec )
  r@ [lit] 8 + !                             \ rec[8] = len
  r@ !                                       \ rec[0] = addr
  asm-ip @ r> [lit] 16 + !                   \ rec[16] = ip
  [lit] 1 asm-count +! ;

variable asm-find-addr
variable asm-find-len

\ asm-find-label ( name-addr name-len -- ip flag )
\ Linear scan from newest to oldest entry.  flag = -1 if found (returning
\ at once, with exit,), else ip = flag = 0.
: asm-find-label
  asm-find-len !  asm-find-addr !
  asm-count @
  begin,
    dup [lit] 0 >
  while,
    1-                                       ( i )
    dup asm-rec                              ( i rec )
    dup [lit] 8 + @ asm-find-len @ = if,
      dup @ asm-find-addr @ asm-find-len @ bytes-eq if,
        nip [lit] 16 + @ true exit,          ( ip -1 )
      then,
    then,
    drop                                     ( i )
  repeat,
  drop [lit] 0 [lit] 0 ;

\ ============================================================================
\ Hex digit utilities + decimal parser + variable-width emit
\ ============================================================================

\ hex-val ( c -- v )  Convert one hex digit char to 0-15.
\ Caller must ensure c is a valid hex digit.
: hex-val
  dup digit? if,
    [char] 0 -
  else,
    dup [char] a - [lit] 6 / 0= if,
      [lit] 87 -                             \ 'a'..'f' -> 10..15
    else,
      [lit] 55 -                             \ 'A'..'F' -> 10..15
    then,
  then, ;

variable asm-dec-addr
variable asm-dec-len
variable asm-dec-val
variable asm-dec-neg
variable asm-dec-hex
variable asm-dec-i

\ asm-parse-number ( addr len -- value )
\ Decimal or hex integer: optional leading '-', then an optional '0x' / '0X'
\ prefix for hex.
\ (Matches a subset of mescc-tools' strtoint sufficient for amd64 inputs;
\ 0b binary and bare-0 octal are not used by M2-Planet's M1 output.)
: asm-parse-number
  asm-dec-len ! asm-dec-addr !
  [lit] 0 asm-dec-val !
  [lit] 0 asm-dec-neg !
  [lit] 0 asm-dec-hex !
  [lit] 0 asm-dec-i !
  \ Leading '-'?
  asm-dec-len @ [lit] 0 > if,
    asm-dec-addr @ c@ [char] - = if,
      true asm-dec-neg !
      [lit] 1 asm-dec-i !
    then,
  then,
  \ '0x' / '0X' hex prefix?
  asm-dec-len @ asm-dec-i @ - [lit] 2 >= if,
    asm-dec-addr @ asm-dec-i @ + c@ [char] 0 = if,
      asm-dec-addr @ asm-dec-i @ + 1+ c@
      dup [char] x = swap [char] X = or if,
        true asm-dec-hex !
        [lit] 2 asm-dec-i +!
      then,
    then,
  then,
  asm-dec-hex @ if,
    begin,
      asm-dec-i @ asm-dec-len @ <
    while,
      asm-dec-addr @ asm-dec-i @ + c@ hex-val
      asm-dec-val @ [lit] 16 * +
      asm-dec-val !
      [lit] 1 asm-dec-i +!
    repeat,
  else,
    begin,
      asm-dec-i @ asm-dec-len @ <
    while,
      asm-dec-addr @ asm-dec-i @ + c@ [char] 0 -
      asm-dec-val @ [lit] 10 * +
      asm-dec-val !
      [lit] 1 asm-dec-i +!
    repeat,
  then,
  asm-dec-val @
  asm-dec-neg @ if,
    [lit] 0 swap -
  then, ;

\ asm-emit-le ( v width -- )  Emit the low width bytes of v, little-endian.
: asm-emit-le
  begin,
    dup
  while,
    over asm-emit-byte                     ( v width )
    swap [lit] 256 / swap 1-               ( v/256 width-1 )
  repeat,
  2drop ;

\ ============================================================================
\ Whitespace / comment skipper and token reader
\ ============================================================================
\
\ asm-skip-rest-of-line ( -- )  Consume bytes until newline or EOF.
: asm-skip-rest-of-line
  begin,
    asm-eof? if, exit, then,
    asm-next-char nl =
  until, ;

\ asm-skip-ws ( -- )  Advance past whitespace and '#'/';' comments.
: asm-skip-ws
  begin,
    asm-eof? if, exit, then,
    asm-peek-char dup space? if,
      drop asm-next-char drop
    else,
      dup [char] # =  swap [char] ; =  or 0= if, exit, then,
      asm-next-char drop
      asm-skip-rest-of-line
    then,
  again, ;

variable asm-tok-start
variable asm-tok-len
variable asm-quote-char

\ asm-read-quoted ( -- )  At an opening quote: count bytes through the
\ matching close quote (whitespace and newlines inside are body bytes).
: asm-read-quoted
  asm-next-char asm-quote-char !
  [lit] 1 asm-tok-len +!
  begin,
    asm-eof? if, exit, then,
    [lit] 1 asm-tok-len +!
    asm-next-char asm-quote-char @ =
  until, ;

\ asm-read-bareword ( -- )  Count bytes up to whitespace, '#', ';' or EOF.
: asm-read-bareword
  begin,
    asm-eof? if, exit, then,
    asm-peek-char  dup space?  over [char] # = or  swap [char] ; = or
    if, exit, then,
    asm-next-char drop
    [lit] 1 asm-tok-len +!
  again, ;

\ asm-read-token ( -- start len )
\ Whitespace/comment-delimited token slice of the active buffer; (0 0) at EOF.
\ '"' and "'" start a quoted string token that runs until the matching close
\ quote.  The returned slice includes both quote characters.
: asm-read-token
  asm-skip-ws
  asm-eof? if, [lit] 0 [lit] 0 exit, then,
  asm-cur-buf @ asm-cur-pos @ + asm-tok-start !
  [lit] 0 asm-tok-len !
  asm-peek-char dup [char] " = swap [char] ' = or if,
    asm-read-quoted
  else,
    asm-read-bareword
  then,
  asm-tok-start @ asm-tok-len @ ;

\ ============================================================================
\ Per-token processing
\ ============================================================================

variable asm-token-start-tmp
variable asm-token-len-tmp
variable asm-gt-pos
variable asm-scan-i
variable asm-hex-i

\ asm-tok-numeric? ( -- f )  Token's body starts with digit or '-' -> numeric form.
\ Token in asm-token-start-tmp / asm-token-len-tmp.
: asm-tok-numeric?
  asm-token-len-tmp @ [lit] 2 < if,
    [lit] 0
  else,
    asm-token-start-tmp @ 1+ c@
    dup [char] - = swap digit? or
  then, ;

\ asm-find-gt ( -- )  Set asm-gt-pos to position of '>' in token name, or -1.
: asm-find-gt
  [lit] 1 asm-scan-i !
  begin,
    asm-scan-i @ asm-token-len-tmp @ <
  while,
    asm-token-start-tmp @ asm-scan-i @ + c@ [char] > = if,
      asm-scan-i @ 1- asm-gt-pos ! exit,
    then,
    [lit] 1 asm-scan-i +!
  repeat,
  true asm-gt-pos ! ;

\ asm-do-label-decl ( -- )
: asm-do-label-decl
  asm-pass @ [lit] 1 = if,
    asm-token-start-tmp @ 1+
    asm-token-len-tmp @ 1-
    asm-store-label
  then, ;

\ asm-tok-err ( code -- )  Write current token + newline to fd 2, then exit code.
: asm-tok-err
  [lit] 2 asm-token-start-tmp @ asm-token-len-tmp @ write drop
  [lit] 2 asm-nl-byte [lit] 1 write drop
  die ;

\ ---- Sigil references ----
\ A token that starts with one of the six sigils stands for a number of
\ width bytes: its body is either a number (`!42`, `%-1`, `$0x3C`), emitted
\ as is, or a label, whose address is emitted either absolute or relative
\ to the end of the field.  Pass 1 only advances the IP by width; pass 2
\ emits the bytes.
\
\   sigil  width  label form
\     !      1    relative
\     @      2    relative
\     ~      3    relative
\     %      4    relative, or %target>base: target - base
\     $      2    absolute
\     &      4    absolute

\ asm-ref-name ( -- a u )  The token's body: everything after the sigil.
: asm-ref-name  asm-token-start-tmp @ 1+  asm-token-len-tmp @ 1- ;

\ asm-do-ref ( width relative? err -- )  Handle a sigil token of width
\ bytes.  A label that is not defined dies with err (after echoing the
\ token).
: asm-do-ref
  asm-pass @ [lit] 1 = if,
    2drop asm-ip +! exit,                   \ pass 1: count the bytes
  then,
  >r >r                                     ( width ; R: err relative? )
  asm-tok-numeric? if,
    asm-ref-name asm-parse-number           ( width v )
  else,
    asm-ref-name asm-find-label 0= if,      ( width ip )
      r> drop r> asm-tok-err                \ undefined label: exits
    then,
    r@ if,                                  \ relative to the field's end
      over asm-ip @ + -                     ( width ip-IP-width )
    then,
  then,
  r> drop r> drop                           ( width v )
  over asm-emit-le                          ( width )
  asm-ip +! ;

\ asm-do-pct-ref ( -- )  '%': asm-do-ref's 4-byte relative form, plus
\ '%target>base', which emits target - base (two labels, no IP).
: asm-do-pct-ref
  asm-pass @ [lit] 2 =  asm-tok-numeric? 0=  and if,
    asm-find-gt
    asm-gt-pos @ [lit] 0 >= if,
      asm-token-start-tmp @ 1+
      asm-gt-pos @
      asm-find-label                        ( target flag )
      0= if,
        drop [lit] 233 asm-tok-err          \ target undefined
      then,
      asm-token-start-tmp @ 1+ asm-gt-pos @ + 1+
      asm-token-len-tmp @ asm-gt-pos @ - [lit] 2 -
      asm-find-label                        ( target base flag )
      0= if,
        2drop [lit] 232 asm-tok-err         \ base undefined
      then,
      - [lit] 4 asm-emit-le
      [lit] 4 asm-ip +! exit,
    then,
  then,
  [lit] 4 true [lit] 234 asm-do-ref ;

\ asm-do-hex ( -- )  Token of hex digits -> 1 byte per pair.
: asm-do-hex
  asm-pass @ [lit] 1 = if,
    asm-token-len-tmp @ [lit] 2 / asm-ip +!
  else,
    [lit] 0 asm-hex-i !
    begin,
      asm-hex-i @ asm-token-len-tmp @ <
    while,
      asm-token-start-tmp @ asm-hex-i @ + c@ hex-val [lit] 16 *
      asm-token-start-tmp @ asm-hex-i @ 1+ + c@ hex-val
      +
      asm-emit-byte
      [lit] 1 asm-ip +!
      [lit] 2 asm-hex-i +!
    repeat,
  then, ;

\ asm-process-token ( start len -- )  Dispatch on the token's first char:
\ a label declaration, one of the six sigils (width, relative?, and the
\ code for an undefined label), or else hex bytes.
: asm-process-token
  asm-token-len-tmp !  asm-token-start-tmp !
  asm-token-start-tmp @ c@                  ( c )
  dup [char] : = if, drop asm-do-label-decl                   exit, then,
  dup [char] ! = if, drop [lit] 1 true    [lit] 235 asm-do-ref exit, then,
  dup [char] @ = if, drop [lit] 2 true    [lit] 236 asm-do-ref exit, then,
  dup [char] ~ = if, drop [lit] 3 true    [lit] 237 asm-do-ref exit, then,
  dup [char] % = if, drop asm-do-pct-ref                      exit, then,
  dup [char] $ = if, drop [lit] 2 [lit] 0 [lit] 238 asm-do-ref exit, then,
  dup [char] & = if, drop [lit] 4 [lit] 0 [lit] 231 asm-do-ref exit, then,
  drop asm-do-hex ;

\ ============================================================================
\ Two-pass driver
\ ============================================================================

: asm-pass-loop
  begin,
    asm-read-token
    dup [lit] 0 = if, 2drop exit, then,
    asm-process-token
  again, ;

: asm-init
  asm-base @ asm-ip !
  [lit] 0 asm-count ! ;

\ ============================================================================
\ M1 macro expansion (phase 2b)
\ ============================================================================
\ Single linear pass over the raw source.  Tokens:
\   - "DEFINE" -> consume next 2 tokens (name, value), store in defs table;
\     emit nothing to asm-exp-buf.
\   - defined name -> emit its body bytes (followed by a space separator).
\   - any other token -> copy verbatim to asm-exp-buf (followed by a space).
\ DEFINEs always appear before use in real M1 sources, so single-pass works.

[lit]   32 constant asm-def-rec-size          \ name-addr 8 + name-len 8 + body-addr 8 + body-len 8
[lit] 4096 constant asm-def-cap
create asm-defs  asm-def-rec-size asm-def-cap * allot
variable asm-def-count

: asm-def-rec  asm-def-rec-size * asm-defs + ;

\ asm-def-store ( name-addr name-len body-addr body-len -- )  Die 243 if
\ the table is full.
: asm-def-store
  asm-def-count @ 1+ asm-def-cap [lit] 243 asm-check-cap
  asm-def-count @ asm-def-rec                ( name-a name-l body-a body-l rec )
  >r                                          ( name-a name-l body-a body-l ; R: rec )
  r@ [lit] 24 + !                             \ rec[24] = body-len
  r@ [lit] 16 + !                             \ rec[16] = body-addr
  r@ [lit] 8 + !                              \ rec[8] = name-len
  r> !                                        \ rec[0] = name-addr
  [lit] 1 asm-def-count +! ;

variable asm-deff-addr
variable asm-deff-len

\ asm-def-find ( name-addr name-len -- body-addr body-len flag )
\ flag = -1 if found, 0 otherwise; body-* are 0 when not found.
: asm-def-find
  asm-deff-len !  asm-deff-addr !
  asm-def-count @
  begin,
    dup [lit] 0 >
  while,
    1-                                       ( i )
    dup asm-def-rec                          ( i rec )
    dup [lit] 8 + @ asm-deff-len @ = if,
      dup @ asm-deff-addr @ asm-deff-len @ bytes-eq if,
        nip dup [lit] 16 + @ swap [lit] 24 + @ true exit,
      then,
    then,
    drop                                     ( i )
  repeat,
  drop [lit] 0 [lit] 0 [lit] 0 ;

\ asm-define-kw: the 6 bytes of "DEFINE".
create asm-define-kw  s, DEFINE

\ asm-is-define? ( addr len -- f )  True if token equals "DEFINE".
: asm-is-define?
  dup [lit] 6 = if,
    drop asm-define-kw [lit] 6 bytes-eq
  else,
    drop drop [lit] 0
  then, ;

variable asm-cp-addr
variable asm-cp-len
variable asm-cp-i

\ asm-exp-bytes ( addr len -- )  Copy len bytes from addr to asm-exp-buf.
: asm-exp-bytes
  asm-cp-len !  asm-cp-addr !
  [lit] 0 asm-cp-i !
  begin,
    asm-cp-i @ asm-cp-len @ <
  while,
    asm-cp-addr @ asm-cp-i @ + c@ asm-exp-emit-byte
    [lit] 1 asm-cp-i +!
  repeat, ;

\ asm-hex-digit ( n -- c )  Map 0..15 to ASCII '0'..'9' / 'A'..'F'.
: asm-hex-digit
  dup [lit] 10 < if,
    [char] 0 +
  else,
    [lit] 55 +
  then, ;

\ asm-exp-string-double ( start len -- )
\ Token = '"' body '"' (len includes both quotes).  Emit hex-encoded body
\ bytes (separated by spaces) plus a trailing 00 NUL terminator, matching
\ mescc-tools M1's double-quoted-string semantics.
: asm-exp-string-double
  asm-cp-len !  asm-cp-addr !
  [lit] 1 asm-cp-i !
  begin,
    asm-cp-i @ asm-cp-len @ 1- <
  while,
    asm-cp-addr @ asm-cp-i @ + c@
    dup [lit] 16 / asm-hex-digit asm-exp-emit-byte
    [lit] 15 and asm-hex-digit asm-exp-emit-byte
    bl asm-exp-emit-byte
    [lit] 1 asm-cp-i +!
  repeat,
  \ NUL terminator: "00 "
  [char] 0 asm-exp-emit-byte [char] 0 asm-exp-emit-byte
  bl asm-exp-emit-byte ;

\ asm-exp-string-single ( start len -- )
\ Token = "'" body "'".  Emit body bytes verbatim, then a space separator.
: asm-exp-string-single
  asm-cp-len !  asm-cp-addr !
  [lit] 1 asm-cp-i !
  begin,
    asm-cp-i @ asm-cp-len @ 1- <
  while,
    asm-cp-addr @ asm-cp-i @ + c@ asm-exp-emit-byte
    [lit] 1 asm-cp-i +!
  repeat,
  bl asm-exp-emit-byte ;

\ asm-expand-pass ( -- )  Walk current cursor (asm-src-buf), build defs table,
\ write expanded text into asm-exp-buf.
: asm-expand-pass
  [lit] 0 asm-exp-len !
  [lit] 0 asm-def-count !
  begin,
    asm-read-token                            ( start len )
    dup [lit] 0 = if, 2drop exit, then,
    2dup asm-is-define? if,
      2drop
      asm-read-token                          ( name-a name-l )
      asm-read-token                          ( name-a name-l body-a body-l )
      asm-def-store
    else,
      \ Quoted strings: dispatch on first char.
      over c@ [char] " = if,
        asm-exp-string-double
      else,
        over c@ [char] ' = if,
          asm-exp-string-single
        else,
          2dup asm-def-find                   ( start len body-a body-l flag )
          if,
            asm-exp-bytes
            drop drop
          else,
            drop drop
            asm-exp-bytes
          then,
          bl asm-exp-emit-byte
        then,
      then,
    then,
  again, ;

\ Pre-baked output path: "/tmp/asm-out\0"
create asm-out-path  s, /tmp/asm-out  [lit] 0 c,

: asm-main
  asm-load-stdin
  asm-use-src
  asm-expand-pass             \ build defs table + write asm-exp-buf
  asm-use-exp
  asm-init
  [lit] 1 asm-pass !
  asm-pass-loop
  asm-reset-pos
  asm-base @ asm-ip !
  asm-out-init
  [lit] 2 asm-pass !
  asm-pass-loop
  asm-out-path asm-write-output
  bye ;

\ The caller invokes 'asm-main' (after optionally setting 'asm-base').
\ Existing pipelines append it on stdin between the Forth prelude and the M1
\ source; see tests/asm/*.sh.
