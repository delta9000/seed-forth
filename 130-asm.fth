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
[lit] 4276224 here-addr !                       \ 0x414000

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

\ asm-load-stdin ( -- )  Read all of fd 0 into asm-src-buf in 4 KiB chunks.
: asm-load-stdin
  [lit] 0 asm-src-len !
  begin,
    [lit] 0 asm-src-buf asm-src-len @ + [lit] 4096 read
    dup [lit] 0 >
  while,
    asm-src-len +!
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

\ asm-exp-emit-byte ( b -- )  Append a byte to asm-exp-buf.
: asm-exp-emit-byte
  asm-exp-buf asm-exp-len @ + c!
  [lit] 1 asm-exp-len +! ;

\ ============================================================================
\ B. Output buffer + emit helpers
\ ============================================================================
[lit] 1048576 constant asm-out-cap
create asm-out-buf  asm-out-cap allot
variable asm-out-pos

: asm-out-init  [lit] 0 asm-out-pos ! ;

\ asm-emit-byte ( b -- )
: asm-emit-byte
  asm-out-buf asm-out-pos @ + c!
  [lit] 1 asm-out-pos +! ;

\ asm-emit-4le ( v -- )  Low 4 bytes, little-endian.
: asm-emit-4le
  dup asm-emit-byte
  [lit] 256 / dup asm-emit-byte
  [lit] 256 / dup asm-emit-byte
  [lit] 256 / asm-emit-byte ;

\ ============================================================================
\ C. Output file write
\ ============================================================================
\ Open flags: O_WRONLY=1, O_CREAT=64, O_TRUNC=512 → 577.  Mode 0o755 = 493.

\ asm-write-output ( path-addr -- )  path-addr must point at NUL-terminated bytes.
: asm-write-output
  [lit] 577 [lit] 493 open                      ( fd )
  dup [lit] 0 < if,
    drop [lit] 1 die
  then,
  >r                                            ( ; R: fd )
  r@ asm-out-buf asm-out-pos @ write drop
  r> close drop ;

\ Newline byte for stderr diagnostics.
create asm-nl-byte  [lit] 10 c,

\ ============================================================================
\ Label table — flat array of (name-addr, name-len, ip) triples.
\ ============================================================================

[lit]   24 constant asm-rec-size
[lit] 8192 constant asm-cap                   \ headroom: M2-Planet uses ~4k labels
create asm-labels  asm-rec-size asm-cap * allot
variable asm-count

\ Base address for amd64 (matches mescc-tools' --base-address 0x00600000).
[lit] 6291456 constant asm-default-base
variable asm-ip
variable asm-pass

\ asm-rec ( i -- a )  Address of the i-th label record.
: asm-rec  asm-rec-size *  asm-labels + ;

\ asm-store-label ( name-addr name-len -- )
: asm-store-label
  asm-count @ asm-rec                       ( addr len rec )
  >r                                         ( addr len ; R: rec )
  r@ [lit] 8 + !                             \ rec[8] = len
  r@ !                                       \ rec[0] = addr
  asm-ip @ r> [lit] 16 + !                   \ rec[16] = ip
  [lit] 1 asm-count +! ;

variable asm-find-addr
variable asm-find-len
variable asm-find-ip
variable asm-find-flag

\ asm-find-label ( name-addr name-len -- ip flag )
\ Linear scan from newest to oldest entry.  flag = -1 if found else 0.
: asm-find-label
  asm-find-len !  asm-find-addr !
  [lit] 0 asm-find-flag !
  [lit] 0 asm-find-ip !
  asm-count @
  begin,
    dup [lit] 0 >
  while,
    [lit] 1 -                                ( i )
    dup asm-rec                              ( i rec )
    dup [lit] 8 + @ asm-find-len @ =         ( i rec len-eq )
    if,
      dup @ asm-find-addr @ asm-find-len @ bytes-eq   ( i rec name-eq )
      if,
        [lit] 16 + @ asm-find-ip !
        [lit] 0 0= asm-find-flag !
        drop
        [lit] 0
      else,
        drop
      then,
    else,
      drop
    then,
  repeat,
  drop
  asm-find-ip @ asm-find-flag @ ;

\ ============================================================================
\ Hex digit utilities + decimal parser + variable-width emit
\ ============================================================================

\ hex-val ( c -- v )  Convert one hex digit char to 0-15.
\ Caller must ensure c is a valid hex digit.
: hex-val
  dup digit? if,
    [lit] 48 -
  else,
    dup [lit] 97 - [lit] 6 / 0= if,
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

\ asm-parse-decimal ( addr len -- value )
\ Integer with optional leading '-' and optional '0x' / '0X' prefix for hex.
\ (Matches a subset of mescc-tools' strtoint sufficient for amd64 inputs;
\ 0b binary and bare-0 octal are not used by M2-Planet's M1 output.)
: asm-parse-decimal
  asm-dec-len ! asm-dec-addr !
  [lit] 0 asm-dec-val !
  [lit] 0 asm-dec-neg !
  [lit] 0 asm-dec-hex !
  [lit] 0 asm-dec-i !
  \ Leading '-'?
  asm-dec-len @ [lit] 0 > if,
    asm-dec-addr @ c@ [lit] 45 = if,
      [lit] 0 0= asm-dec-neg !
      [lit] 1 asm-dec-i !
    then,
  then,
  \ '0x' / '0X' hex prefix?
  asm-dec-len @ asm-dec-i @ - [lit] 2 >= if,
    asm-dec-addr @ asm-dec-i @ + c@ [lit] 48 = if,
      asm-dec-addr @ asm-dec-i @ + [lit] 1 + c@
      dup [lit] 120 = swap [lit] 88 = or if,    \ 'x' = 120, 'X' = 88
        [lit] 0 0= asm-dec-hex !
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
      asm-dec-addr @ asm-dec-i @ + c@ [lit] 48 -
      asm-dec-val @ [lit] 10 * +
      asm-dec-val !
      [lit] 1 asm-dec-i +!
    repeat,
  then,
  asm-dec-val @
  asm-dec-neg @ if,
    [lit] 0 swap -
  then, ;

\ Variable-width little-endian byte emitters.
: asm-emit-1le  asm-emit-byte ;
: asm-emit-2le
  dup asm-emit-byte
  [lit] 256 / asm-emit-byte ;
: asm-emit-3le
  dup asm-emit-byte
  [lit] 256 / dup asm-emit-byte
  [lit] 256 / asm-emit-byte ;

\ ============================================================================
\ Whitespace / comment skipper and token reader
\ ============================================================================
\
\ asm-skip-ws and asm-skip-rest-of-line use DISTINCT done-flag variables —
\ sharing one short-circuits the outer skipper after the first comment.

variable asm-ws-done
variable asm-cl-done

\ asm-skip-rest-of-line ( -- )  Consume bytes until newline or EOF.
: asm-skip-rest-of-line
  [lit] 0 asm-cl-done !
  begin,
    asm-cl-done @ 0=
  while,
    asm-eof? if,
      [lit] 0 0= asm-cl-done !
    else,
      asm-next-char [lit] 10 = if,
        [lit] 0 0= asm-cl-done !
      then,
    then,
  repeat, ;

\ asm-skip-ws ( -- )  Advance past whitespace and '#'/';' comments.
: asm-skip-ws
  [lit] 0 asm-ws-done !
  begin,
    asm-ws-done @ 0=
  while,
    asm-eof? if,
      [lit] 0 0= asm-ws-done !
    else,
      asm-peek-char dup space? if,
        drop asm-next-char drop
      else,
        dup [lit] 35 = if,                    \ '#'
          drop asm-next-char drop
          asm-skip-rest-of-line
        else,
          dup [lit] 59 = if,                  \ ';'
            drop asm-next-char drop
            asm-skip-rest-of-line
          else,
            drop
            [lit] 0 0= asm-ws-done !
          then,
        then,
      then,
    then,
  repeat, ;

variable asm-tok-start
variable asm-tok-len
variable asm-tok-done
variable asm-quote-char

\ asm-read-token ( -- start len )
\ Whitespace/comment-delimited token slice of the active buffer; (0 0) at EOF.
\ '"' and "'" start a quoted string token that runs until the matching close
\ quote (whitespace and newlines inside count as body bytes).  The returned
\ slice includes both quote characters.
: asm-read-token
  asm-skip-ws
  asm-eof? if,
    [lit] 0 [lit] 0
  else,
    asm-cur-buf @ asm-cur-pos @ + asm-tok-start !
    [lit] 0 asm-tok-len !
    [lit] 0 asm-tok-done !
    asm-peek-char dup [lit] 34 = swap [lit] 39 = or if,
      \ Quoted-string mode: read until matching close quote.
      asm-peek-char asm-quote-char !
      asm-next-char drop
      [lit] 1 asm-tok-len +!
      begin,
        asm-tok-done @ 0=
      while,
        asm-eof? if,
          [lit] 0 0= asm-tok-done !
        else,
          asm-next-char asm-quote-char @ = if,
            [lit] 1 asm-tok-len +!
            [lit] 0 0= asm-tok-done !
          else,
            [lit] 1 asm-tok-len +!
          then,
        then,
      repeat,
    else,
      \ Whitespace-delimited bareword.
      begin,
        asm-tok-done @ 0=
      while,
        asm-eof? if,
          [lit] 0 0= asm-tok-done !
        else,
          asm-peek-char dup space? if,
            drop [lit] 0 0= asm-tok-done !
          else,
            dup [lit] 35 = if,
              drop [lit] 0 0= asm-tok-done !
            else,
              dup [lit] 59 = if,
                drop [lit] 0 0= asm-tok-done !
              else,
                drop asm-next-char drop
                [lit] 1 asm-tok-len +!
              then,
            then,
          then,
        then,
      repeat,
    then,
    asm-tok-start @ asm-tok-len @
  then, ;

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
    asm-token-start-tmp @ [lit] 1 + c@
    dup [lit] 45 = swap digit? or
  then, ;

\ asm-find-gt ( -- )  Set asm-gt-pos to position of '>' in token name, or -1.
: asm-find-gt
  [lit] 0 0= asm-gt-pos !
  [lit] 1 asm-scan-i !
  begin,
    asm-scan-i @ asm-token-len-tmp @ <
  while,
    asm-token-start-tmp @ asm-scan-i @ + c@ [lit] 62 = if,
      asm-scan-i @ [lit] 1 - asm-gt-pos !
      asm-token-len-tmp @ asm-scan-i !
    else,
      [lit] 1 asm-scan-i +!
    then,
  repeat, ;

\ asm-do-label-decl ( -- )
: asm-do-label-decl
  asm-pass @ [lit] 1 = if,
    asm-token-start-tmp @ [lit] 1 +
    asm-token-len-tmp @ [lit] 1 -
    asm-store-label
  then, ;

\ asm-tok-err ( code -- )  Write current token + newline to fd 2, then exit code.
: asm-tok-err
  [lit] 2 asm-token-start-tmp @ asm-token-len-tmp @ write drop
  [lit] 2 asm-nl-byte [lit] 1 write drop
  die ;

\ ---- Numeric / absolute / relative emission helpers ----
\ Each handler: pass 1 just bumps IP by W; pass 2 emits W bytes resolving the
\ ref.  Numeric form (`!42`, `%-1`, etc.) emits the value directly LE; label
\ form looks the name up in the label table.

\ asm-emit-numeric-N ( w -- )  Pass 2: parse decimal from token body, emit w bytes LE.
\ For width 1/2/3/4 dispatched inline by each sigil handler (no asm-emit-Nle
\ generic to avoid extra dispatch overhead).

\ asm-do-amp-ref ( -- )  '&':  4-byte absolute (label) or 4-byte LE (numeric).
: asm-do-amp-ref
  asm-pass @ [lit] 1 = if,
    [lit] 4 asm-ip +!
  else,
    asm-tok-numeric? if,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-parse-decimal asm-emit-4le
    else,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-find-label
      if,
        asm-emit-4le
      else,
        drop [lit] 91 asm-tok-err
      then,
    then,
    [lit] 4 asm-ip +!
  then, ;

\ asm-do-pct-ref ( -- )  '%': 4-byte relative (label[>base]) or 4-byte LE (numeric).
: asm-do-pct-ref
  asm-pass @ [lit] 1 = if,
    [lit] 4 asm-ip +!
  else,
    asm-tok-numeric? if,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-parse-decimal asm-emit-4le
    else,
      asm-find-gt
      asm-gt-pos @ [lit] 0 >= if,
        asm-token-start-tmp @ [lit] 1 +
        asm-gt-pos @
        asm-find-label                            ( target flag )
        if,
          asm-token-start-tmp @ [lit] 1 + asm-gt-pos @ + [lit] 1 +
          asm-token-len-tmp @ asm-gt-pos @ - [lit] 2 -
          asm-find-label                          ( target base flag )
          if,
            - asm-emit-4le
          else,
            drop drop [lit] 92 asm-tok-err
          then,
        else,
          drop [lit] 93 asm-tok-err
        then,
      else,
        asm-token-start-tmp @ [lit] 1 +
        asm-token-len-tmp @ [lit] 1 -
        asm-find-label
        if,
          asm-ip @ [lit] 4 + -
          asm-emit-4le
        else,
          drop [lit] 94 asm-tok-err
        then,
      then,
    then,
    [lit] 4 asm-ip +!
  then, ;

\ asm-do-bang-ref ( -- )  '!': 1-byte relative (label) or 1-byte LE (numeric).
: asm-do-bang-ref
  asm-pass @ [lit] 1 = if,
    [lit] 1 asm-ip +!
  else,
    asm-tok-numeric? if,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-parse-decimal asm-emit-1le
    else,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-find-label
      if,
        asm-ip @ [lit] 1 + -
        asm-emit-1le
      else,
        drop [lit] 95 asm-tok-err
      then,
    then,
    [lit] 1 asm-ip +!
  then, ;

\ asm-do-at-ref ( -- )  '@': 2-byte relative (label) or 2-byte LE (numeric).
: asm-do-at-ref
  asm-pass @ [lit] 1 = if,
    [lit] 2 asm-ip +!
  else,
    asm-tok-numeric? if,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-parse-decimal asm-emit-2le
    else,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-find-label
      if,
        asm-ip @ [lit] 2 + -
        asm-emit-2le
      else,
        drop [lit] 96 asm-tok-err
      then,
    then,
    [lit] 2 asm-ip +!
  then, ;

\ asm-do-tilde-ref ( -- )  '~': 3-byte relative (label) or 3-byte LE (numeric).
: asm-do-tilde-ref
  asm-pass @ [lit] 1 = if,
    [lit] 3 asm-ip +!
  else,
    asm-tok-numeric? if,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-parse-decimal asm-emit-3le
    else,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-find-label
      if,
        asm-ip @ [lit] 3 + -
        asm-emit-3le
      else,
        drop [lit] 97 asm-tok-err
      then,
    then,
    [lit] 3 asm-ip +!
  then, ;

\ asm-do-dollar-ref ( -- )  '$': 2-byte absolute (label) or 2-byte LE (numeric).
: asm-do-dollar-ref
  asm-pass @ [lit] 1 = if,
    [lit] 2 asm-ip +!
  else,
    asm-tok-numeric? if,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-parse-decimal asm-emit-2le
    else,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-find-label
      if,
        asm-emit-2le
      else,
        drop [lit] 98 asm-tok-err
      then,
    then,
    [lit] 2 asm-ip +!
  then, ;

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
      asm-token-start-tmp @ asm-hex-i @ [lit] 1 + + c@ hex-val
      +
      asm-emit-byte
      [lit] 1 asm-ip +!
      [lit] 2 asm-hex-i +!
    repeat,
  then, ;

\ asm-process-token ( start len -- )  Dispatch on first char.
\ Sigil bytes:  ':' 58  '!' 33  '@' 64  '~' 126  '%' 37  '$' 36  '&' 38
: asm-process-token
  asm-token-len-tmp !  asm-token-start-tmp !
  asm-token-start-tmp @ c@
  dup [lit] 58 = if,                            \ ':'
    drop asm-do-label-decl
  else,
    dup [lit] 33 = if,                          \ '!'
      drop asm-do-bang-ref
    else,
      dup [lit] 64 = if,                        \ '@'
        drop asm-do-at-ref
      else,
        dup [lit] 126 = if,                     \ '~'
          drop asm-do-tilde-ref
        else,
          dup [lit] 37 = if,                    \ '%'
            drop asm-do-pct-ref
          else,
            dup [lit] 36 = if,                  \ '$'
              drop asm-do-dollar-ref
            else,
              dup [lit] 38 = if,                \ '&'
                drop asm-do-amp-ref
              else,
                drop asm-do-hex
              then,
            then,
          then,
        then,
      then,
    then,
  then, ;

\ ============================================================================
\ Two-pass driver
\ ============================================================================

variable asm-loop-done

: asm-pass-loop
  [lit] 0 asm-loop-done !
  begin,
    asm-loop-done @ 0=
  while,
    asm-read-token
    dup [lit] 0 = if,
      drop drop
      [lit] 0 0= asm-loop-done !
    else,
      asm-process-token
    then,
  repeat, ;

: asm-init
  asm-default-base asm-ip !
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

\ asm-def-store ( name-addr name-len body-addr body-len -- )
: asm-def-store
  asm-def-count @ asm-def-rec                ( name-a name-l body-a body-l rec )
  >r                                          ( name-a name-l body-a body-l ; R: rec )
  r@ [lit] 24 + !                             \ rec[24] = body-len
  r@ [lit] 16 + !                             \ rec[16] = body-addr
  r@ [lit] 8 + !                              \ rec[8] = name-len
  r> !                                        \ rec[0] = name-addr
  [lit] 1 asm-def-count +! ;

variable asm-deff-addr
variable asm-deff-len
variable asm-deff-body-a
variable asm-deff-body-l
variable asm-deff-found

\ asm-def-find ( name-addr name-len -- body-addr body-len flag )
\ flag = -1 if found, 0 otherwise; body-* are 0 when not found.
: asm-def-find
  asm-deff-len !  asm-deff-addr !
  [lit] 0 asm-deff-found !
  [lit] 0 asm-deff-body-a !
  [lit] 0 asm-deff-body-l !
  asm-def-count @
  begin,
    dup [lit] 0 >
  while,
    [lit] 1 -                                ( i )
    dup asm-def-rec                          ( i rec )
    dup [lit] 8 + @ asm-deff-len @ =         ( i rec len-eq )
    if,
      dup @ asm-deff-addr @ asm-deff-len @ bytes-eq   ( i rec name-eq )
      if,
        dup [lit] 16 + @ asm-deff-body-a !
        [lit] 24 + @ asm-deff-body-l !       \ consume rec
        [lit] 0 0= asm-deff-found !
        drop
        [lit] 0                               \ exit loop
      else,
        drop
      then,
    else,
      drop
    then,
  repeat,
  drop
  asm-deff-body-a @ asm-deff-body-l @ asm-deff-found @ ;

\ "DEFINE" = 0x44 0x45 0x46 0x49 0x4E 0x45 (6 bytes).
create asm-define-kw
[lit] 68 c, [lit] 69 c, [lit] 70 c, [lit] 73 c, [lit] 78 c, [lit] 69 c,

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
    [lit] 48 +
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
    asm-cp-i @ asm-cp-len @ [lit] 1 - <
  while,
    asm-cp-addr @ asm-cp-i @ + c@
    dup [lit] 16 / asm-hex-digit asm-exp-emit-byte
    [lit] 15 and asm-hex-digit asm-exp-emit-byte
    [lit] 32 asm-exp-emit-byte
    [lit] 1 asm-cp-i +!
  repeat,
  \ NUL terminator: "00 "
  [lit] 48 asm-exp-emit-byte [lit] 48 asm-exp-emit-byte
  [lit] 32 asm-exp-emit-byte ;

\ asm-exp-string-single ( start len -- )
\ Token = "'" body "'".  Emit body bytes verbatim, then a space separator.
: asm-exp-string-single
  asm-cp-len !  asm-cp-addr !
  [lit] 1 asm-cp-i !
  begin,
    asm-cp-i @ asm-cp-len @ [lit] 1 - <
  while,
    asm-cp-addr @ asm-cp-i @ + c@ asm-exp-emit-byte
    [lit] 1 asm-cp-i +!
  repeat,
  [lit] 32 asm-exp-emit-byte ;

variable asm-xp-done

\ asm-expand-pass ( -- )  Walk current cursor (asm-src-buf), build defs table,
\ write expanded text into asm-exp-buf.
: asm-expand-pass
  [lit] 0 asm-exp-len !
  [lit] 0 asm-def-count !
  [lit] 0 asm-xp-done !
  begin,
    asm-xp-done @ 0=
  while,
    asm-read-token                            ( start len )
    dup [lit] 0 = if,
      drop drop
      [lit] 0 0= asm-xp-done !
    else,
      2dup asm-is-define? if,
        drop drop
        asm-read-token                        ( name-a name-l )
        asm-read-token                        ( name-a name-l body-a body-l )
        asm-def-store
      else,
        \ Quoted strings: dispatch on first char.
        over c@ [lit] 34 = if,
          asm-exp-string-double
        else,
          over c@ [lit] 39 = if,
            asm-exp-string-single
          else,
            2dup asm-def-find                 ( start len body-a body-l flag )
            if,
              asm-exp-bytes
              drop drop
            else,
              drop drop
              asm-exp-bytes
            then,
            [lit] 32 asm-exp-emit-byte
          then,
        then,
      then,
    then,
  repeat, ;

\ Pre-baked output path: "/tmp/asm-out\0"
create asm-out-path
[lit]  47 c, [lit] 116 c, [lit] 109 c, [lit] 112 c,    \ /tmp
[lit]  47 c, [lit]  97 c, [lit] 115 c, [lit] 109 c,    \ /asm
[lit]  45 c, [lit] 111 c, [lit] 117 c, [lit] 116 c,    \ -out
[lit]   0 c,                                            \ NUL

: asm-main
  asm-load-stdin
  asm-use-src
  asm-expand-pass             \ build defs table + write asm-exp-buf
  asm-use-exp
  asm-init
  [lit] 1 asm-pass !
  asm-pass-loop
  asm-reset-pos
  asm-default-base asm-ip !
  asm-out-init
  [lit] 2 asm-pass !
  asm-pass-loop
  asm-out-path asm-write-output
  bye ;

asm-main
