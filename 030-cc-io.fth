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
