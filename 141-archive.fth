\ 141-archive.fth -- deterministic indexed ar and lazy archive linking.
\ Load on 010/020/030/140. All archive bytes and selection are Forth.
\ Newly reconstructed; regular GNU ar envelope, not thin archives.
\ API: arc-init, arc-add-object (nul-path --), arc-write (nul-path --).
\      lnk-add-archive (nul-path --), arc-check (nul-path --).
\ Errors reuse 250 malformed/unsupported, 251 capacity, 255 file I/O.

[lit] 256 constant arc-member-cap
[lit] 65536 constant arc-index-cap
[lit] 64 constant arc-member-size
create arc-members arc-member-cap arc-member-size * allot
create arc-index arc-index-cap [lit] 24 * allot
create arc-view lnk-object-size allot
variable arc-count
variable arc-nindex
variable arc-long-size
variable arc-names-size
variable arc-image
variable arc-size
variable arc-i
variable arc-j
variable arc-mp
variable arc-ip
variable arc-total
variable arc-pos
variable arc-output
variable arc-output-size
variable arc-name
variable arc-nlen
variable arc-path
variable arc-changed
variable arc-needed
variable arc-index-data
variable arc-index-size
variable arc-long-data
variable arc-long-length
create arc-magic [lit] 33 c, s, <arch> [lit] 10 c,
create arc-bsd s, #1/
create arc-bsd-index s, __.SYMDEF
create arc-mode s, 100644
create arc-bsd-64 s, __.SYMDEF_64
: arc-name-allowed ( address length -- )
  dup [lit] 9 = if,
    over arc-bsd-index [lit] 9 bytes-eq 0= lnk-need
  then,
  dup [lit] 12 = if,
    over arc-bsd-64 [lit] 12 bytes-eq 0= lnk-need
  then, 2drop ;
: arc-member ( index -- row ) arc-member-size * arc-members + ;
: arc-entry ( index -- row ) [lit] 24 * arc-index + ;
: arc-even ( count -- count ) dup [lit] 1 and + ;
: arc-zero ( address count -- )
  begin, dup while, over [lit] 0 swap c! swap 1+ swap 1- repeat, 2drop ;
: arc-release
  [lit] 0 arc-i !
  begin, arc-i @ arc-count @ < while,
    arc-i @ arc-member dup @ swap [lit] 8 + @ lnk-unmap
    [lit] 1 arc-i +!
  repeat,
  [lit] 0 arc-count ! ;
: arc-init
  arc-release lnk-init
  [lit] 0 arc-nindex ! [lit] 0 arc-long-size ! [lit] 0 arc-names-size ! ;
: arc-basename ( nul-path -- address length )
  dup arc-name ! [lit] 0 arc-nlen !
  begin, dup c@ while,
    dup c@ [lit] 47 = if,
      dup 1+ arc-name ! [lit] 0 arc-nlen !
    else, [lit] 1 arc-nlen +! then, 1+
  repeat, drop
  arc-nlen @ [lit] 0 > lnk-need
  arc-nlen @ [lit] 4095 [lit] 251 cc-check-cap
  [lit] 0 arc-j !
  begin, arc-j @ arc-nlen @ < while,
    arc-name @ arc-j @ + c@ dup [lit] 32 > lnk-need
    [lit] 127 < lnk-need [lit] 1 arc-j +!
  repeat,
  arc-name @ arc-nlen @ 2dup arc-name-allowed ;
: arc-add-index ( name length member-index -- )
  arc-nindex @ 1+ arc-index-cap [lit] 251 cc-check-cap
  arc-nindex @ arc-entry >r
  r@ [lit] 16 + ! dup 1+ arc-names-size +!
  r@ [lit] 8 + ! r> ! [lit] 1 arc-nindex +! ;
: arc-add-object ( nul-path -- )
  arc-count @ 1+ arc-member-cap [lit] 251 cc-check-cap
  dup arc-path ! arc-basename
  arc-count @ arc-member arc-mp !
  arc-mp @ [lit] 24 + ! arc-mp @ [lit] 16 + !
  arc-long-size @ arc-mp @ [lit] 56 + !
  arc-nlen @ [lit] 15 > if, arc-nlen @ [lit] 2 + arc-long-size +! then,
  arc-view lnk-op ! arc-path @ lnk-read-object
  arc-mp @ [lit] 8 + ! arc-mp @ !
  arc-mp @ [lit] 8 + @ [lit] 8 lnk-field !
  lnk-header lnk-sections
  [lit] 0 lnk-symbol-index !
  begin, lnk-symbol-index @ [lit] 32 lnk-field @ < while,
    lnk-symbol-index @ lnk-symbol lnk-sp ! lnk-validate-symbol
    lnk-sp @ lnk-binding if,
      lnk-sp @ lnk-symbol-name dup [lit] 0 > lnk-need 2drop
    then,
    lnk-sp @ lnk-binding 0= 0= lnk-sp @ lnk-shndx 0= 0= and if,
      lnk-sp @ lnk-symbol-name arc-count @ arc-add-index
    then,
    [lit] 1 lnk-symbol-index +!
  repeat,
  [lit] 1 arc-count +! ;

\ Decimal fields are left justified, as required by portable ar headers.
create arc-digits [lit] 32 allot
variable arc-ndigit
variable arc-dest
variable arc-width
: arc-decimal ( value destination width -- )
  arc-width ! arc-dest ! [lit] 0 arc-ndigit !
  begin,
    dup dup [lit] 10 / [lit] 10 * - [lit] 48 + arc-digits arc-ndigit @ + c!
    [lit] 1 arc-ndigit +! [lit] 10 / dup 0=
  until, drop
  arc-ndigit @ arc-width @ <= lnk-need
  begin, arc-ndigit @ while,
    [lit] 1 arc-ndigit -!
    arc-digits arc-ndigit @ + c@ arc-dest @ c!
    [lit] 1 arc-dest +!
  repeat, ;
: arc-put-be32 ( value address -- )
  >r dup [lit] 16777216 / r@ c!
  dup [lit] 65536 / r@ 1+ c!
  dup [lit] 256 / r@ [lit] 2 + c! r> [lit] 3 + c! ;
: arc-be32 ( address -- value )
  dup c@ [lit] 16777216 * over 1+ c@ [lit] 65536 * +
  over [lit] 2 + c@ [lit] 256 * + swap [lit] 3 + c@ + ;
variable arc-header-p
: arc-header ( size -- )
  arc-output @ arc-pos @ + arc-header-p !
  [lit] 0
  begin, dup [lit] 60 < while,
    dup arc-header-p @ + [lit] 32 swap c! 1+
  repeat, drop
  [lit] 48 arc-header-p @ [lit] 16 + c!
  [lit] 48 arc-header-p @ [lit] 28 + c!
  [lit] 48 arc-header-p @ [lit] 34 + c!
  arc-mode arc-header-p @ [lit] 40 + [lit] 6 lnk-copy
  arc-header-p @ [lit] 48 + [lit] 10 arc-decimal
  [lit] 96 arc-header-p @ [lit] 58 + c!
  [lit] 10 arc-header-p @ [lit] 59 + c!
  [lit] 60 arc-pos +! ;
: arc-pad
  arc-pos @ [lit] 1 and if,
    [lit] 10 arc-output @ arc-pos @ + c! [lit] 1 arc-pos +!
  then, ;
: arc-plan
  arc-nindex @ [lit] 4 * [lit] 4 + arc-names-size @ + arc-index-size !
  [lit] 68 arc-index-size @ arc-even + arc-total !
  arc-long-size @ if, arc-long-size @ arc-even [lit] 60 + arc-total +! then,
  [lit] 0 arc-i !
  begin, arc-i @ arc-count @ < while,
    arc-i @ arc-member arc-mp !
    arc-total @ arc-mp @ [lit] 48 + !
    arc-mp @ [lit] 8 + @ arc-even [lit] 60 + arc-total +!
    arc-total @ lnk-cap [lit] 1 arc-i +!
  repeat,
  arc-total @ lnk-cap
  arc-total @ lnk-map arc-output ! arc-total @ arc-output-size ! ;
: arc-emit-index
  arc-index-size @ arc-header
  [lit] 47 arc-header-p @ c!
  arc-output @ arc-pos @ + arc-index-data !
  arc-nindex @ arc-index-data @ arc-put-be32
  [lit] 4 arc-pos +!
  [lit] 0 arc-i !
  begin, arc-i @ arc-nindex @ < while,
    arc-i @ arc-entry [lit] 16 + @ arc-member [lit] 48 + @
    arc-output @ arc-pos @ + arc-put-be32
    [lit] 4 arc-pos +! [lit] 1 arc-i +!
  repeat,
  [lit] 0 arc-i !
  begin, arc-i @ arc-nindex @ < while,
    arc-i @ arc-entry arc-ip !
    arc-ip @ @ arc-output @ arc-pos @ + arc-ip @ [lit] 8 + @ lnk-copy
    arc-ip @ [lit] 8 + @ 1+ arc-pos +! [lit] 1 arc-i +!
  repeat, arc-pad ;
: arc-emit-longs
  arc-long-size @ 0= if, exit, then,
  arc-long-size @ arc-header
  [lit] 47 arc-header-p @ c! [lit] 47 arc-header-p @ 1+ c!
  [lit] 0 arc-i !
  begin, arc-i @ arc-count @ < while,
    arc-i @ arc-member arc-mp !
    arc-mp @ [lit] 24 + @ [lit] 15 > if,
      arc-mp @ [lit] 16 + @ arc-output @ arc-pos @ +
      arc-mp @ [lit] 24 + @ lnk-copy
      arc-mp @ [lit] 24 + @ arc-pos +!
      [lit] 47 arc-output @ arc-pos @ + c!
      [lit] 10 arc-output @ arc-pos @ 1+ + c! [lit] 2 arc-pos +!
    then, [lit] 1 arc-i +!
  repeat, arc-pad ;
: arc-emit-members
  [lit] 0 arc-i !
  begin, arc-i @ arc-count @ < while,
    arc-i @ arc-member arc-mp !
    arc-pos @ arc-mp @ [lit] 48 + @ = lnk-need
    arc-mp @ [lit] 8 + @ arc-header
    arc-mp @ [lit] 24 + @ [lit] 15 > if,
      [lit] 47 arc-header-p @ c!
      arc-mp @ [lit] 56 + @ arc-header-p @ 1+ [lit] 15 arc-decimal
    else,
      arc-mp @ [lit] 16 + @ arc-header-p @ arc-mp @ [lit] 24 + @ lnk-copy
      [lit] 47 arc-header-p @ arc-mp @ [lit] 24 + @ + c!
    then,
    arc-mp @ @ arc-output @ arc-pos @ + arc-mp @ [lit] 8 + @ lnk-copy
    arc-mp @ [lit] 8 + @ arc-pos +! arc-pad [lit] 1 arc-i +!
  repeat, ;
: arc-write ( nul-path -- )
  arc-path ! arc-plan
  arc-magic arc-output @ [lit] 8 lnk-copy [lit] 8 arc-pos !
  arc-emit-index arc-emit-longs arc-emit-members
  arc-pos @ arc-output-size @ = lnk-need
  arc-output @ lnk-image ! arc-output-size @ lnk-file-size !
  arc-path @ lnk-path ! lnk-write
  arc-output @ arc-output-size @ lnk-unmap [lit] 0 lnk-image ! ;

\ Archive reader: validate the whole envelope and index, not every payload.
\ Rows hold data,size,name,length,selected,header-offset,reserved,reserved.
variable arc-number
variable arc-numeric-end
variable arc-numeric-a
variable arc-num-base
variable arc-any
: arc-number-field ( address length base -- value )
  arc-num-base ! over + arc-numeric-end ! arc-numeric-a !
  [lit] 0 arc-number ! [lit] 0 arc-any !
  begin, arc-numeric-a @ arc-numeric-end @ < while,
    arc-numeric-a @ c@ [lit] 32 = if,
      begin, arc-numeric-a @ arc-numeric-end @ < while,
        arc-numeric-a @ c@ [lit] 32 = lnk-need [lit] 1 arc-numeric-a +!
      repeat,
    else,
      arc-numeric-a @ c@ [lit] 48 - dup [lit] 0 >= lnk-need
      dup arc-num-base @ < lnk-need
      arc-number @ [lit] 268435456 <= lnk-need
      arc-number @ arc-num-base @ * + arc-number !
      true arc-any ! [lit] 1 arc-numeric-a +!
    then,
  repeat,
  arc-any @ lnk-need arc-number @ ;
: arc-span ( offset size -- address )
  lnk-nonnegative >r lnk-nonnegative
  dup arc-size @ <= lnk-need arc-size @ over - r> >= lnk-need
  arc-image @ + ;
variable arc-member-data
variable arc-member-length
variable arc-name-kind
: arc-read-name
  [lit] 0 arc-name-kind !
  arc-header-p @ arc-name ! [lit] 16 arc-nlen !
  begin, arc-nlen @ while,
    arc-name @ arc-nlen @ 1- + c@ [lit] 32 <> if, exit, then,
    [lit] 1 arc-nlen -!
  repeat, lnk-bad ;
: arc-ordinary
  arc-count @ 1+ arc-member-cap [lit] 251 cc-check-cap
  arc-count @ arc-member arc-mp !
  arc-member-data @ arc-mp @ ! arc-member-length @ arc-mp @ [lit] 8 + !
  arc-name @ arc-mp @ [lit] 16 + ! arc-nlen @ arc-mp @ [lit] 24 + !
  [lit] 0 arc-mp @ [lit] 32 + ! arc-pos @ arc-mp @ [lit] 40 + !
  arc-name-kind @ arc-mp @ [lit] 48 + ! [lit] 1 arc-count +! ;
: arc-record-member
  arc-read-name
  arc-name @ c@ [lit] 47 = if,
    arc-nlen @ [lit] 1 = if,
      arc-index-data @ 0= lnk-need
      arc-member-data @ arc-index-data ! arc-member-length @ arc-index-size ! exit,
    then,
    arc-nlen @ [lit] 2 = arc-name @ 1+ c@ [lit] 47 = and if,
      arc-long-data @ 0= lnk-need
      arc-member-data @ arc-long-data ! arc-member-length @ arc-long-length ! exit,
    then,
    arc-name @ 1+ arc-nlen @ 1- [lit] 10 arc-number-field
    arc-name ! [lit] 1 arc-name-kind ! arc-ordinary exit,
  then,
  arc-nlen @ [lit] 3 > if,
    arc-name @ arc-bsd [lit] 3 bytes-eq if,
      arc-name @ [lit] 3 + arc-nlen @ [lit] 3 - [lit] 10 arc-number-field
      dup [lit] 0 > lnk-need dup arc-member-length @ <= lnk-need
      arc-member-data @ arc-name ! dup arc-nlen !
      dup arc-member-data +! arc-member-length @ swap - arc-member-length !
      begin, arc-nlen @ while,
        arc-name @ arc-nlen @ 1- + c@ if, arc-ordinary exit, then,
        [lit] 1 arc-nlen -!
      repeat, lnk-bad
    then,
  then,
  arc-name @ arc-nlen @ 1- + c@ [lit] 47 = if, [lit] 1 arc-nlen -! then,
  arc-ordinary ;
: arc-check-name
  arc-nlen @ [lit] 0 > lnk-need
  arc-nlen @ [lit] 4095 [lit] 251 cc-check-cap
  arc-name @ arc-nlen @ arc-name-allowed
  [lit] 0 arc-j !
  begin, arc-j @ arc-nlen @ < while,
    arc-name @ arc-j @ + c@ dup [lit] 32 > lnk-need [lit] 127 < lnk-need
    [lit] 1 arc-j +!
  repeat, ;
: arc-resolve-names
  [lit] 0 arc-i !
  begin, arc-i @ arc-count @ < while,
    arc-i @ arc-member arc-mp !
    arc-mp @ [lit] 16 + @ arc-name ! arc-mp @ [lit] 24 + @ arc-nlen !
    arc-mp @ [lit] 48 + @ if,
      arc-long-data @ [lit] 0 <> lnk-need
      arc-name @ arc-long-length @ < lnk-need
      arc-name @ if,
        arc-long-data @ arc-name @ + 1- c@ [lit] 10 = lnk-need
      then,
      arc-long-data @ arc-name @ + arc-name ! [lit] 0 arc-nlen !
      begin,
        arc-name @ arc-nlen @ + arc-long-data @ arc-long-length @ + < lnk-need
        arc-name @ arc-nlen @ + c@ [lit] 10 <>
      while, [lit] 1 arc-nlen +! repeat,
      arc-nlen @ [lit] 1 > lnk-need
      arc-name @ arc-nlen @ 1- + c@ [lit] 47 = lnk-need [lit] 1 arc-nlen -!
      arc-name @ arc-mp @ [lit] 16 + ! arc-nlen @ arc-mp @ [lit] 24 + !
    then,
    arc-check-name [lit] 1 arc-i +!
  repeat, ;
variable arc-index-offset
variable arc-index-cursor
variable arc-index-end
variable arc-found
: arc-parse-index
  arc-index-data @ 0= if, arc-count @ 0= lnk-need exit, then,
  arc-index-size @ [lit] 4 >= lnk-need
  arc-index-data @ arc-be32 dup arc-index-cap [lit] 251 cc-check-cap arc-nindex !
  arc-nindex @ [lit] 4 * [lit] 4 + arc-index-size @ <= lnk-need
  arc-index-data @ arc-nindex @ [lit] 4 * [lit] 4 + + arc-index-cursor !
  arc-index-data @ arc-index-size @ + arc-index-end !
  [lit] 0 arc-i !
  begin, arc-i @ arc-nindex @ < while,
    arc-index-data @ arc-i @ [lit] 4 * [lit] 4 + + arc-be32 arc-index-offset !
    [lit] 0 arc-j ! [lit] 0 arc-found !
    begin, arc-j @ arc-count @ < while,
      arc-j @ arc-member [lit] 40 + @ arc-index-offset @ = if,
        arc-j @ arc-found ! [lit] 1 arc-found +! 
      then, [lit] 1 arc-j +!
    repeat,
    arc-found @ [lit] 0 > lnk-need
    arc-i @ arc-entry arc-ip !
    arc-found @ 1- arc-ip @ [lit] 16 + !
    arc-index-cursor @ arc-ip @ ! [lit] 0 arc-nlen !
    begin,
      arc-index-cursor @ arc-index-end @ < lnk-need
      arc-index-cursor @ c@
    while, [lit] 1 arc-index-cursor +! [lit] 1 arc-nlen +! repeat,
    arc-nlen @ [lit] 0 > lnk-need arc-nlen @ arc-ip @ [lit] 8 + !
    [lit] 1 arc-index-cursor +! [lit] 1 arc-i +!
  repeat,
  begin, arc-index-cursor @ arc-index-end @ < while,
    arc-index-cursor @ c@ 0= lnk-need [lit] 1 arc-index-cursor +!
  repeat, ;
: arc-parse
  [lit] 0 arc-count ! [lit] 0 arc-nindex !
  [lit] 0 arc-index-data ! [lit] 0 arc-long-data !
  [lit] 0 [lit] 8 arc-span arc-magic [lit] 8 bytes-eq lnk-need
  [lit] 8 arc-pos !
  begin, arc-pos @ arc-size @ < while,
    arc-pos @ [lit] 60 arc-span arc-header-p !
    arc-header-p @ [lit] 58 + c@ [lit] 96 = lnk-need
    arc-header-p @ [lit] 59 + c@ [lit] 10 = lnk-need
    arc-header-p @ [lit] 48 + [lit] 10 [lit] 10 arc-number-field arc-member-length !
    arc-pos @ [lit] 60 + arc-member-length @ arc-span arc-member-data !
    arc-member-length @ >r arc-record-member
    r@ [lit] 1 and if,
      arc-pos @ [lit] 60 + r@ + [lit] 1 arc-span c@ [lit] 10 = lnk-need
    then,
    r> arc-even [lit] 60 + arc-pos +!
    arc-pos @ arc-size @ <= lnk-need
  repeat,
  arc-resolve-names arc-parse-index ;
: arc-open ( nul-path -- )
  arc-release arc-view lnk-op ! lnk-read-file arc-size ! arc-image ! arc-parse ;
: arc-close arc-image @ arc-size @ lnk-unmap [lit] 0 arc-count ! ;
: arc-check ( nul-path -- ) arc-open arc-close ;

\ Member order is stable; repeat the archive until no new member is needed.
\ Only strong unresolved names trigger extraction; weak definitions may serve
\ them. Local symbols never enter the archive index or global demand table.
: arc-member-needed ( member-index -- flag )
  arc-needed ! [lit] 0 arc-j !
  begin, arc-j @ arc-nindex @ < while,
    arc-j @ arc-entry arc-ip !
    arc-ip @ [lit] 16 + @ arc-needed @ = if,
      arc-ip @ @ arc-ip @ [lit] 8 + @ lnk-find
      dup @ if,
        [lit] 16 + @ dup lnk-shndx 0= swap lnk-binding [lit] 1 = and
        if, true exit, then,
      else, drop then,
    then, [lit] 1 arc-j +!
  repeat, [lit] 0 ;
: lnk-add-archive ( nul-path -- )
  arc-open
  begin,
    [lit] 0 arc-changed ! [lit] 0 arc-i !
    begin, arc-i @ arc-count @ < while,
      arc-i @ arc-member arc-mp !
      arc-mp @ [lit] 32 + @ 0= if,
        arc-i @ arc-member-needed if,
          true arc-mp @ [lit] 32 + ! true arc-changed !
          arc-mp @ @ arc-mp @ [lit] 8 + @ lnk-add-buffer
        then,
      then, [lit] 1 arc-i +!
    repeat,
    arc-changed @ 0=
  until, arc-close ;
