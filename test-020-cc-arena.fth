\ test-020-cc-arena.fth — smoke test for cc-alloc + bytes-eq.
\ Run via: cat 010-lib.fth 020-cc-arena.fth test-020-cc-arena.fth | strip_forth | ./seed-forth
\          echo $?    # 0 = pass, 255 = fail
\
\ Pattern matches test-010-lib.fth: the first test seeds an accumulator, every
\ subsequent test ANDs its boolean in.  The trailing `0= die` turns
\ acc=-1 into exit code 0 and acc=0 into exit code 255.

\ ----- cc-alloc: returns distinct, 8-byte-aligned addresses -----
\ a1 = cc-alloc(16); store 42 there.  a2 = cc-alloc(16).  Verify:
\   - a1 != a2 (different blocks)
\   - a2 = a1 + 16 (alignment is exactly 16 since 16 already is /8)
\   - the value 42 written at a1 reads back unchanged.
[lit] 16 cc-alloc                                ( a1 )
[lit] 42 over !                                  \ store 42 at a1
[lit] 16 cc-alloc                                ( a1 a2 )
2dup <>                                          ( a1 a2 f1 )
>r                                               ( a1 a2  R-f1 )
2dup swap [lit] 16 + =                           ( a1 a2 f2 )
r> and >r                                        ( a1 a2  R-f1andf2 )
swap @ [lit] 42 =                                ( a2 f3 )
r> and                                           ( a2 acc )
swap drop                                        ( acc )

\ ----- bytes-eq: matching buffers -----
\ Allocate two 4-byte regions, fill both with "ABCD", compare.
[lit] 4 cc-alloc                                  ( acc bufM )
dup [lit] 65 swap c!                              \ buf[0] = 'A'
dup [lit] 1 + [lit] 66 swap c!                    \ buf[1] = 'B'
dup [lit] 2 + [lit] 67 swap c!                    \ buf[2] = 'C'
dup [lit] 3 + [lit] 68 swap c!                    \ buf[3] = 'D'
[lit] 4 cc-alloc                                  ( acc bufM bufN )
dup [lit] 65 swap c!
dup [lit] 1 + [lit] 66 swap c!
dup [lit] 2 + [lit] 67 swap c!
dup [lit] 3 + [lit] 68 swap c!
\ stack: ( acc bufM bufN ) — both filled with "ABCD"
[lit] 4 bytes-eq                                  ( acc f-match )
and                                                ( acc' )

\ ----- bytes-eq: mismatched buffers -----
\ "ABCD" vs "ABCc" — last byte different.  bytes-eq returns 0; 0= → -1.
[lit] 4 cc-alloc                                  ( acc bufP )
dup [lit] 65 swap c!
dup [lit] 1 + [lit] 66 swap c!
dup [lit] 2 + [lit] 67 swap c!
dup [lit] 3 + [lit] 68 swap c!                    \ "ABCD"
[lit] 4 cc-alloc                                  ( acc bufP bufQ )
dup [lit] 65 swap c!
dup [lit] 1 + [lit] 66 swap c!
dup [lit] 2 + [lit] 67 swap c!
dup [lit] 3 + [lit] 99 swap c!                    \ "ABCc" (last byte 'c'=99)
[lit] 4 bytes-eq 0=                               ( acc f-mismatch )
and                                                ( acc' )

\ ----- bytes-eq: zero-length is trivially equal -----
\ Pass any addresses with u=0 — should return -1 immediately.
[lit] 4 cc-alloc dup                              ( acc a a )
[lit] 0 bytes-eq                                  ( acc f )
and                                                ( acc' )

\ ----- exit with derived code -----
0= die
