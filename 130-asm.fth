\ 130-asm.fth — Minimum-viable hex2-format linker in Forth.
\
\ Closes the bootstrap gap below seed-forth's C compiler: consumes the
\ hex2 syntax that mescc-tools' M1 produces and emits ELF bytes directly,
\ removing the need to trust a GCC-built hex2 binary.  Stage0-posix's
\ M1+hex2 stays in the picture as an independent byte-level witness.
\
\ Self-contained: depends only on 010-lib.fth (and the seed primitives
\ it builds on).  No cross-import from the C-compiler layers, so the asm
\ sits cleanly below the cc in the bootstrap chain rather than alongside.
\
\ Scope is deliberately narrow (smoke-test grade): hex byte pairs,
\ ':label' decls, '&label' (4-byte absolute), '%label[>base]' (4-byte
\ relative), '#'/';' comments, whitespace.  Sufficient to byte-match
\ mescc-tools on the exit42 fixture (tests/asm/exit42-check.sh).
\
\ Not yet implemented: 1/2/3-byte sigils (! @ ~), 2-byte absolute ($),
\ M1 macro expansion, the '<N' padding directive, nibble accumulation
\ across whitespace.  Those land before phase 2 (assembling M2-Planet's
\ own M1 output).

\ ============================================================================
\ A. Source buffer + reader
\ ============================================================================
\ Skip past the VM's fixed pages (data stack 0x410000..0x411000, I/O scratch
\ 0x412000, token buffer 0x412800, sysvars 0x413000..0x414000) so our 1 MiB
\ source buffer does not overlap runtime VM state.
[lit] 4276224 here-addr !                       \ 0x414000

[lit] 1048576 constant asm-src-cap
create asm-src-buf  asm-src-cap allot
variable asm-src-len
variable asm-src-pos

\ asm-load-stdin ( -- )  Read all of fd 0 into asm-src-buf in 4 KiB chunks.
: asm-load-stdin
  [lit] 0 asm-src-len !
  [lit] 0 asm-src-pos !
  begin,
    [lit] 0 asm-src-buf asm-src-len @ + [lit] 4096 read
    dup [lit] 0 >
  while,
    asm-src-len +!
  repeat,
  drop ;

\ asm-eof? ( -- f )
: asm-eof?  asm-src-pos @ asm-src-len @ >= ;

\ asm-peek-char ( -- c )  Byte at current position; 0 at EOF.
: asm-peek-char
  asm-eof? if,
    [lit] 0
  else,
    asm-src-buf asm-src-pos @ + c@
  then, ;

\ asm-next-char ( -- c )  Returns current byte, advances pos.
: asm-next-char
  asm-peek-char
  [lit] 1 asm-src-pos +! ;

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

\ ============================================================================
\ Label table — flat array of (name-addr, name-len, ip) triples.
\ ============================================================================

[lit]  24 constant asm-rec-size
[lit] 256 constant asm-cap
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
\ Hex digit utilities
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

\ asm-read-token ( -- start len )
\ Whitespace/comment-delimited token slice of asm-src-buf; (0 0) at EOF.
: asm-read-token
  asm-skip-ws
  asm-eof? if,
    [lit] 0 [lit] 0
  else,
    asm-src-buf asm-src-pos @ + asm-tok-start !
    [lit] 0 asm-tok-len !
    [lit] 0 asm-tok-done !
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

\ asm-do-amp-ref ( -- )  '&label': emit 4-byte LE absolute address.
: asm-do-amp-ref
  asm-pass @ [lit] 1 = if,
    [lit] 4 asm-ip +!
  else,
    asm-token-start-tmp @ [lit] 1 +
    asm-token-len-tmp @ [lit] 1 -
    asm-find-label
    if,
      asm-emit-4le
    else,
      drop [lit] 91 die
    then,
    [lit] 4 asm-ip +!
  then, ;

\ asm-do-pct-ref ( -- )  '%label' or '%label>base': emit 4-byte LE relative.
: asm-do-pct-ref
  asm-pass @ [lit] 1 = if,
    [lit] 4 asm-ip +!
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
          drop drop [lit] 92 die
        then,
      else,
        drop [lit] 93 die
      then,
    else,
      asm-token-start-tmp @ [lit] 1 +
      asm-token-len-tmp @ [lit] 1 -
      asm-find-label
      if,
        asm-ip @ [lit] 4 + -
        asm-emit-4le
      else,
        drop [lit] 94 die
      then,
    then,
    [lit] 4 asm-ip +!
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
: asm-process-token
  asm-token-len-tmp !  asm-token-start-tmp !
  asm-token-start-tmp @ c@
  dup [lit] 58 = if,                            \ ':'
    drop asm-do-label-decl
  else,
    dup [lit] 38 = if,                          \ '&'
      drop asm-do-amp-ref
    else,
      dup [lit] 37 = if,                        \ '%'
        drop asm-do-pct-ref
      else,
        drop asm-do-hex
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

: asm-reset-src
  [lit] 0 asm-src-pos ! ;

\ Pre-baked output path: "/tmp/asm-out\0"
create asm-out-path
[lit]  47 c, [lit] 116 c, [lit] 109 c, [lit] 112 c,    \ /tmp
[lit]  47 c, [lit]  97 c, [lit] 115 c, [lit] 109 c,    \ /asm
[lit]  45 c, [lit] 111 c, [lit] 117 c, [lit] 116 c,    \ -out
[lit]   0 c,                                            \ NUL

: asm-main
  asm-load-stdin
  asm-init
  [lit] 1 asm-pass !
  asm-pass-loop
  asm-reset-src
  asm-default-base asm-ip !
  asm-out-init
  [lit] 2 asm-pass !
  asm-pass-loop
  asm-out-path asm-write-output
  bye ;

asm-main
