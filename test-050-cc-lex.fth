\ test-050-cc-lex.fth — smoke test for 050-cc-lex.fth.
\ Run via:
\   cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 040-cc-prep.fth 050-cc-lex.fth \
\       test-050-cc-lex.fth | strip_forth | seed/seed-forth ; echo $?
\     # 0 = pass, 255 = fail
\
\ Pattern: first test seeds the AND-accumulator, every subsequent test ANDs
\ its boolean in.  Final `0= die` turns acc=-1 into exit 0, acc=0 into 255.

\ ----- Helper: write a byte at cc-src-buf[i] -----
: tput  ( b i -- )  cc-src-buf + c! ;

\ ===========================================================================
\ Source 1: "int main(){return 42;}"  (22 bytes)
\ Tokens: int, main, (, ), {, return, 42, ;, }, EOF
\ ===========================================================================

[lit] 105 [lit]  0 tput  \ i
[lit] 110 [lit]  1 tput  \ n
[lit] 116 [lit]  2 tput  \ t
[lit]  32 [lit]  3 tput  \ space
[lit] 109 [lit]  4 tput  \ m
[lit]  97 [lit]  5 tput  \ a
[lit] 105 [lit]  6 tput  \ i
[lit] 110 [lit]  7 tput  \ n
[lit]  40 [lit]  8 tput  \ (
[lit]  41 [lit]  9 tput  \ )
[lit] 123 [lit] 10 tput  \ {
[lit] 114 [lit] 11 tput  \ r
[lit] 101 [lit] 12 tput  \ e
[lit] 116 [lit] 13 tput  \ t
[lit] 117 [lit] 14 tput  \ u
[lit] 114 [lit] 15 tput  \ r
[lit] 110 [lit] 16 tput  \ n
[lit]  32 [lit] 17 tput  \ space
[lit]  52 [lit] 18 tput  \ 4
[lit]  50 [lit] 19 tput  \ 2
[lit]  59 [lit] 20 tput  \ ;
[lit] 125 [lit] 21 tput  \ }

[lit] 22 cc-src-len !
[lit]  0 cc-src-pos !
[lit]  1 cc-src-line !

\ Token 1: "int"  (kw)
cc-next-token
tok-kind  @ tk-kw   =                                  \ seed accumulator
tok-kw-id @ kw-int  =                              and

\ Token 2: "main"  (ident, len=4)
cc-next-token
tok-kind    @ tk-ident =                           and
tok-str-len @ [lit] 4  =                           and
tok-str-addr @ c@ [lit] 109 =                      and  \ first byte 'm'

\ Token 3: "("  (single-char punct, code=40)
cc-next-token
tok-kind @ tk-punct =                              and
tok-num  @ [lit] 40 =                              and

\ Token 4: ")"
cc-next-token
tok-kind @ tk-punct =                              and
tok-num  @ [lit] 41 =                              and

\ Token 5: "{"
cc-next-token
tok-kind @ tk-punct =                              and
tok-num  @ [lit] 123 =                             and

\ Token 6: "return"  (kw)
cc-next-token
tok-kind  @ tk-kw     =                            and
tok-kw-id @ kw-return =                            and

\ Token 7: 42  (number)
cc-next-token
tok-kind @ tk-num   =                              and
tok-num  @ [lit] 42 =                              and

\ Token 8: ";"
cc-next-token
tok-kind @ tk-punct =                              and
tok-num  @ [lit] 59 =                              and

\ Token 9: "}"
cc-next-token
tok-kind @ tk-punct =                              and
tok-num  @ [lit] 125 =                             and

\ Token 10: EOF
cc-next-token
tok-kind @ tk-eof =                                and

\ ===========================================================================
\ Source 2: "x<=y&&z>>=1"  (multi-char punct: <=, &&, >>=)
\ Tokens: x, <=, y, &&, z, >>=, 1, EOF
\ Bytes: x < = y & & z > > = 1
\ ASCII: 120 60 61 121 38 38 122 62 62 61 49
\ ===========================================================================

[lit] 120 [lit]  0 tput  \ x
[lit]  60 [lit]  1 tput  \ <
[lit]  61 [lit]  2 tput  \ =
[lit] 121 [lit]  3 tput  \ y
[lit]  38 [lit]  4 tput  \ &
[lit]  38 [lit]  5 tput  \ &
[lit] 122 [lit]  6 tput  \ z
[lit]  62 [lit]  7 tput  \ >
[lit]  62 [lit]  8 tput  \ >
[lit]  61 [lit]  9 tput  \ =
[lit]  49 [lit] 10 tput  \ 1

[lit] 11 cc-src-len !
[lit]  0 cc-src-pos !
[lit]  1 cc-src-line !

\ x
cc-next-token
tok-kind @ tk-ident =                              and
tok-str-len @ [lit] 1 =                            and

\ <=
cc-next-token
tok-kind @ tk-punct =                              and
tok-num  @ pt-le    =                              and

\ y
cc-next-token
tok-kind @ tk-ident =                              and
tok-str-len @ [lit] 1 =                            and
tok-str-addr @ c@ [lit] 121 =                      and

\ &&
cc-next-token
tok-kind @ tk-punct  =                             and
tok-num  @ pt-and-and =                            and

\ z
cc-next-token
tok-kind @ tk-ident =                              and

\ >>=
cc-next-token
tok-kind @ tk-punct  =                             and
tok-num  @ pt-shr-eq =                             and

\ 1
cc-next-token
tok-kind @ tk-num    =                             and
tok-num  @ [lit] 1   =                             and

\ EOF
cc-next-token
tok-kind @ tk-eof =                                and

\ ===========================================================================
\ Source 3: ws + comments + string + char
\ Source: "  /* a */ \"hi\" 'A' // tail\n+"
\ Bytes (length 28):
\   SP SP / * SP a SP * / SP " h i " SP ' A ' SP / / SP t a i l LF +
\   32 32 47 42 32 97 32 42 47 32 34 104 105 34 32 39 65 39 32 47 47 32 116 97 105 108 10 43
\ Tokens: "hi", 'A', '+', EOF
\ ===========================================================================

[lit]  32 [lit]  0 tput
[lit]  32 [lit]  1 tput
[lit]  47 [lit]  2 tput
[lit]  42 [lit]  3 tput
[lit]  32 [lit]  4 tput
[lit]  97 [lit]  5 tput
[lit]  32 [lit]  6 tput
[lit]  42 [lit]  7 tput
[lit]  47 [lit]  8 tput
[lit]  32 [lit]  9 tput
[lit]  34 [lit] 10 tput  \ "
[lit] 104 [lit] 11 tput  \ h
[lit] 105 [lit] 12 tput  \ i
[lit]  34 [lit] 13 tput  \ "
[lit]  32 [lit] 14 tput
[lit]  39 [lit] 15 tput  \ '
[lit]  65 [lit] 16 tput  \ A
[lit]  39 [lit] 17 tput  \ '
[lit]  32 [lit] 18 tput
[lit]  47 [lit] 19 tput  \ /
[lit]  47 [lit] 20 tput  \ /
[lit]  32 [lit] 21 tput
[lit] 116 [lit] 22 tput  \ t
[lit]  97 [lit] 23 tput  \ a
[lit] 105 [lit] 24 tput  \ i
[lit] 108 [lit] 25 tput  \ l
[lit]  10 [lit] 26 tput  \ LF
[lit]  43 [lit] 27 tput  \ +

[lit] 28 cc-src-len !
[lit]  0 cc-src-pos !
[lit]  1 cc-src-line !

\ "hi" — string literal, len=2, first byte 'h'=104
cc-next-token
tok-kind    @ tk-str  =                            and
tok-str-len @ [lit] 2 =                            and
tok-str-addr @ c@ [lit] 104 =                      and

\ 'A' — char literal, value=65
cc-next-token
tok-kind @ tk-chr   =                              and
tok-num  @ [lit] 65 =                              and

\ '+' — single-char punct after // line comment
cc-next-token
tok-kind @ tk-punct =                              and
tok-num  @ [lit] 43 =                              and

\ EOF
cc-next-token
tok-kind @ tk-eof =                                and

\ ===========================================================================
\ Source 4: char escape '\n'
\ Bytes: ' \ n '   →   39 92 110 39
\ ===========================================================================

[lit]  39 [lit]  0 tput
[lit]  92 [lit]  1 tput
[lit] 110 [lit]  2 tput
[lit]  39 [lit]  3 tput

[lit]  4 cc-src-len !
[lit]  0 cc-src-pos !
[lit]  1 cc-src-line !

cc-next-token
tok-kind @ tk-chr   =                              and
tok-num  @ [lit] 10 =                              and  \ '\n' = 10

\ ===========================================================================
\ Final exit
\ ===========================================================================
0= die
