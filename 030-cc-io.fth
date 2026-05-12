\ seed/030-cc-io.fth — Source-buffer reader, output-buffer emitter, and file I/O
\ wrappers for the C-subset compiler.  Loaded after 010-lib.fth.
\
\ Three responsibilities:
\   A. Slurp stdin into a 1 MiB cc-src-buf and walk it via peek/next.
\   B. Accumulate the output ELF into cc-out-buf via emit-byte / 4le / 8le
\      with patch-byte / patch-4le for back-fixups.
\   C. Write cc-out-buf to a path via 010-lib.fth's open/write/close.
\
\ Depends on 010-lib.fth: constant, variable, create, allot, [lit], if,/then,/else,,
\   begin,/while,/repeat,, +, -, /, =, >, >=, 0=, +!, !, @, c!, c@, drop, dup,
\   over, swap, >r, r@, r>, syscall6, read, write, open, close.

\ ===========================================================================
\ A. Source buffer + reader
\ ===========================================================================

\ 1 MiB source cap — comfortable for M2-Planet's monolithic concatenations.
[lit] 1048576 constant cc-src-cap

\ Skip past the VM's fixed pages (data stack 0x410000..0x411000, I/O scratch
\ 0x412000, token buffer 0x412800, sysvars 0x413000..0x414000) so the 1 MiB
\ cc-src-buf does not overlap runtime VM state.  At 030-cc-io.fth load time HERE
\ is well below 0x414000, so this is a forward bump of a few KiB.
[lit] 4276224 here-addr !                         \ 0x414000

create cc-src-buf  cc-src-cap allot
variable cc-src-len
variable cc-src-pos
variable cc-src-line                            \ 1-based, for error messages

\ cc-src-init ( -- )  Reset reader state.
: cc-src-init
  [lit] 0 cc-src-len !
  [lit] 0 cc-src-pos !
  [lit] 1 cc-src-line ! ;

\ cc-load-stdin ( -- )  Read all of fd 0 into cc-src-buf.
\ Loops until read returns 0 (EOF).  4 KiB chunks.
\ Stack note: at begin, the stack is empty.  read leaves n on TOS; dup/>
\ produces ( n flag ); while, pops flag leaving ( n ); +! pops n leaving ( ).
\ When the loop exits (n<=0), stack is ( n ) which we drop.
: cc-load-stdin
  cc-src-init
  begin,
    [lit] 0 cc-src-buf cc-src-len @ + [lit] 4096 read
    dup [lit] 0 >
  while,
    cc-src-len +!
  repeat,
  drop ;

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
  dup [lit] 10 = if,
    [lit] 1 cc-src-line +!
  then, ;

\ ===========================================================================
\ B. Output buffer + ELF-aware emit helpers
\ ===========================================================================

\ 1 MiB output cap — fits any reasonable ELF the C-subset compiler emits.
[lit] 1048576 constant cc-out-cap
create cc-out-buf  cc-out-cap allot
variable cc-out-pos

\ cc-out-init ( -- )
: cc-out-init  [lit] 0 cc-out-pos ! ;

\ cc-emit-byte ( b -- )  Append a byte at cc-out-buf[cc-out-pos++].
: cc-emit-byte
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

\ cc-out-patch-byte ( v offset -- )  Overwrite cc-out-buf[offset] with low byte of v.
: cc-out-patch-byte  cc-out-buf + c! ;

\ cc-out-patch-4le ( v offset -- )  Overwrite 4 bytes at offset (LE).
\ Stash offset on the return stack so we can compute offset+1, +2, +3.
: cc-out-patch-4le
  >r                                                  ( v       ; R: offset )
  dup r@                       cc-out-patch-byte      ( v       ; R: offset )
  [lit] 256 / dup r@ [lit] 1 + cc-out-patch-byte      ( v>>8    ; R: offset )
  [lit] 256 / dup r@ [lit] 2 + cc-out-patch-byte      ( v>>16   ; R: offset )
  [lit] 256 /     r> [lit] 3 + cc-out-patch-byte ;    ( v>>24>>8 popped )

\ cc-out-patch-8le ( v offset -- )  Overwrite 8 bytes at offset (LE).
: cc-out-patch-8le
  >r                                                  ( v       ; R: offset )
  dup r@                       cc-out-patch-byte      ( v       ; R: offset )
  [lit] 256 / dup r@ [lit] 1 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 2 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 3 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 4 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 5 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 6 + cc-out-patch-byte
  [lit] 256 /     r> [lit] 7 + cc-out-patch-byte ;

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
\ exits with status 1 (cannot recover — we have no place to write a diagnostic).
: cc-write-output
  [lit] 577 [lit] 493 open                        ( fd )
  dup [lit] 0 < if,
    drop
    [lit] 1 die
  then,
  >r                                              ( ; R: fd )
  r@ cc-out-buf cc-out-pos @ write drop           \ write all bytes
  r> close drop ;
