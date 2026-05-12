\ test-030-cc-io.fth — smoke test for 030-cc-io.fth.
\ Run via:
\   cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth test-030-cc-io.fth | strip_forth | seed/seed-forth
\   echo $?    # 0 = pass, 255 = fail
\
\ Pattern matches test-020-cc-arena.fth: the first test seeds the AND-accumulator,
\ every subsequent test ANDs its boolean in.  The final 0= die turns
\ acc=-1 into exit code 0 and acc=0 into exit code 255.

\ =========================================================================
\ Source-buffer reader
\ =========================================================================
\ Manually fill cc-src-buf with "Ab\nC" (bytes 65, 98, 10, 67) and reset
\ pos/len/line, bypassing cc-load-stdin since we have no stdin in this test.
[lit] 65 cc-src-buf c!
[lit] 98 cc-src-buf [lit] 1 + c!
[lit] 10 cc-src-buf [lit] 2 + c!
[lit] 67 cc-src-buf [lit] 3 + c!
[lit] 4 cc-src-len !
[lit] 0 cc-src-pos !
[lit] 1 cc-src-line !

\ Initial state: peek and EOF behave correctly at pos=0.
cc-peek-char [lit] 65 =                            \ peek 'A' (seed accumulator)
cc-eof? 0=                                     and \ not at EOF

\ Consume 'A' via next-char; verify byte and pos advanced.
cc-next-char [lit] 65 =                        and
cc-src-pos @ [lit] 1 =                         and

\ Peek then next 'b'.
cc-peek-char [lit] 98 =                        and
cc-next-char [lit] 98 =                        and

\ Consume '\n' — line counter must increment from 1 to 2.
cc-next-char [lit] 10 =                        and
cc-src-line @ [lit] 2 =                        and

\ Pos is at index 3 ('C'); not yet EOF.
cc-eof? 0=                                     and

\ Consume 'C', then we should be at EOF.
cc-next-char [lit] 67 =                        and
cc-eof?                                        and

\ Peek at EOF returns 0.
cc-peek-char [lit] 0 =                         and

\ =========================================================================
\ Output-buffer emitter
\ =========================================================================
cc-out-init
cc-out-pos @ [lit] 0 =                         and \ init resets pos

[lit] 65 cc-emit-byte                              \ 'A' at offset 0
[lit] 66 cc-emit-byte                              \ 'B' at offset 1
[lit] 1297 cc-emit-4le                             \ 0x511 → 11 05 00 00 at offsets 2..5

cc-out-pos @ [lit] 6 =                         and \ 1 + 1 + 4 bytes emitted
cc-out-buf            c@ [lit] 65 =            and
cc-out-buf [lit] 1 +  c@ [lit] 66 =            and
cc-out-buf [lit] 2 +  c@ [lit] 17 =            and \ 0x11
cc-out-buf [lit] 3 +  c@ [lit]  5 =            and \ 0x05
cc-out-buf [lit] 4 +  c@ [lit]  0 =            and
cc-out-buf [lit] 5 +  c@ [lit]  0 =            and

\ =========================================================================
\ Patch
\ =========================================================================
\ Overwrite the first 4 bytes with 0x12345678 → 78 56 34 12 (LE).
[lit] 305419896 [lit] 0 cc-out-patch-4le
cc-out-buf            c@ [lit] 120 =           and \ 0x78
cc-out-buf [lit] 1 +  c@ [lit]  86 =           and \ 0x56
cc-out-buf [lit] 2 +  c@ [lit]  52 =           and \ 0x34
cc-out-buf [lit] 3 +  c@ [lit]  18 =           and \ 0x12

\ patch-byte alone: write 0xAB at offset 5.
[lit] 171 [lit] 5 cc-out-patch-byte
cc-out-buf [lit] 5 + c@ [lit] 171 =            and

\ =========================================================================
\ 8LE emitter
\ =========================================================================
cc-out-init
\ Emit 0x0807060504030201 → bytes 01 02 03 04 05 06 07 08
[lit] 578437695752307201 cc-emit-8le
cc-out-pos @ [lit] 8 =                         and
cc-out-buf            c@ [lit] 1 =             and
cc-out-buf [lit] 1 +  c@ [lit] 2 =             and
cc-out-buf [lit] 2 +  c@ [lit] 3 =             and
cc-out-buf [lit] 3 +  c@ [lit] 4 =             and
cc-out-buf [lit] 4 +  c@ [lit] 5 =             and
cc-out-buf [lit] 5 +  c@ [lit] 6 =             and
cc-out-buf [lit] 6 +  c@ [lit] 7 =             and
cc-out-buf [lit] 7 +  c@ [lit] 8 =             and

\ =========================================================================
\ Final exit
\ =========================================================================
0= die
