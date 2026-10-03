\ Isolated symbolic leaves exercise125 independently of object allocation.
variable constant-string-count
variable constant-record-desc
cc-sd-alloc constant-record-desc !
[lit] 12 constant-record-desc @ cc-sd-set-total-size
[lit] 4 constant-record-desc @ cc-sd-set-align
: constant-ident
  tok-str-addr @ c@
  dup [char] i = if,
    drop [lit] 0 ty-int [lit] 1 ty-make [lit] 0 [lit] 17 exit,
  then,
  dup [char] c = if,
    drop [lit] 0 ty-char [lit] 1 ty-make [lit] 0 [lit] 23 exit,
  then,
  dup [char] r = if,
    drop [lit] 0 ty-struct [lit] 1 ty-make constant-record-desc @ [lit] 31 exit,
  then,
  [char] f = if,
    [lit] 0 ty-func [lit] 1 ty-make [lit] 7777 [lit] 37 exit,
  then, cc-const-unsupported ;
: constant-address cc-next-token-keep constant-ident ;
: constant-string
  cc-cx-skip @ 0= if, [lit] 1 constant-string-count +! then,
  [lit] 0 ty-char [lit] 1 ty-make [lit] 0 [lit] 29 ;
' constant-ident is cc-const-ident-fwd
' constant-address is cc-const-address-fwd
' constant-string is cc-const-string-fwd

create constant-output [lit] 32 allot
: constant-write
  constant-output [lit] 24 + !
  dup constant-record-desc @ = if, drop [lit] 9999 then,
  constant-output [lit] 16 + !
  constant-output [lit] 8 + ! constant-output !
  [lit] 1 constant-output [lit] 32 write drop ;
