# Chapter 34 — Compiling TinyCC Directly

```text
Missing capability: the Forth compiler reaches TinyCC only through a pnut compiler executable.
New pattern: an opt-in C profile extends the same preprocessor, types, expressions, and ELF emitter, then supplies a private stack ABI and a small Linux boundary.
Artifact after this chapter: a TinyCC seed compiled directly from C by Forth, with no pnut executable or host C toolchain.
Proof link: the rebuilt TinyCC reaches the existing boot2 = boot3 executable and object fixed points.
```

## Goal and source coverage

Ch 33 closed the assembler gap on the M2-Planet route. Here we take
another branch: teach the Forth C compiler enough of the pinned,
patched TinyCC 0.9.27 and portable-libc sources to compile them
itself. The generated executable is a TinyCC seed; that TinyCC
then compiles the next TinyCC and its runtime.

This chapter owns `115-cc-native.fth` (592 lines),
`117-cc-native-program.fth` (100 lines), `118-cc-native-init.fth`
(318 lines), and `119-cc-native-runtime.fth` (111 lines), each in full.
The existing chapters retain canonical coverage of the shared
preprocessor, types, expressions, and statement code they extend.
The compiler files still load in numerical order: the native words
are available before `120-cc-main.fth`, but loading them alone does
not change the default compilation mode.

**Concepts carried in:** lexer mark/reset (Ch 23), types and struct
descriptors (Ch 24), direct ELF emission and fixups (Chs 25–26),
lvalues and expressions (Chs 27–28), declarations and statements
(Chs 29–30), and function scope and entry stubs (Ch 31).

**Concepts introduced:** LP64 object layout, a private all-stack
call convention, initializer lowering through ordinary relocation
fixups, an explicitly restricted bootstrap profile, and separating
source preparation from executable closure.

**Deferred:** a general ISO C compiler, arbitrary external object
linkage, aggregate-by-value calls, genuine floating arithmetic in
the Forth compiler, and rebuilding the full GNU/Linux continuation.

## 1. Two profiles, one compiler

The old driver remains the default. Its M2-compatible widths,
register calls, built-in libc shims, and preprocessing policy are
still tested by Stage A and the pnut controls. The new driver sets
`cc-target-lp64` and `cc-prep-direct` before compiling and calls
`cc-native-program` instead of the legacy program parser.

LP64 describes storage, not a calling convention: `char` occupies
one byte, `short` two, `int` four, and `long` and pointers eight.
Typed loads, stores, casts, promotions, unsigned operations, and
pointer strides use those widths. A machine register still holds
each evaluated scalar; making every register 64 bits does not make
every object eight bytes wide.

The direct preprocessor reads real headers. Quoted includes first
search relative to the including file, then the configured include
directories; angle includes use the configured directories.
Missing headers fail, and repeated inclusion is allowed for macro
lists. Stringizing, token pasting, and rescanning run in Forth.
No host `cpp` output is an input to this route.

The native driver also calls `cc-arena-map` for an additional 8 MiB
compiler workspace. The dictionary, source/output buffers, and tables
stay inside the seed's original 16 MiB segment; recursive native
contexts, descriptors, and fixups use the external mapping. The
legacy default retains its 32 KiB arena. [Appendix B](A2-memory-map.md)
distinguishes those compiler allocations from a generated program's
heap.

The target sources retain their existing `PNUT_CC` compatibility
conditionals. Those macro names select a source dialect; they do
not execute pnut. The repository retains the vendored pnut kit,
TinyCC archive, portable-libc source, patches, licenses, and
provenance, while removing the pnut compiler executable from this
route. Keeping the older route gives us an independent control.

## 2. Native declarations and aligned storage

The native declaration parser saves its state in `cc-nctx`.
Recursive aggregate declarations allocate a fresh context and
restore the enclosing context on return. A field descriptor carries
its own type, nested descriptor, array length, and byte offset;
this is enough to emit a typed access without guessing from the
field's name.

`cc-naggregate` gives struct tags a separate namespace, installs a
forward descriptor before parsing its members, and distinguishes
structs from unions. `cc-nadd-field` aligns the next struct field,
puts each union field at offset zero, and tracks total size and
maximum alignment. `cc-npromote-fields` copies anonymous aggregate
members into the parent with their enclosing offset added.
Qualification provenance for a member (Ch 24 §2) is a list keyed by
the record's address, and a descriptor's field table moves when it
grows (Ch 24 §1), so `cc-nqualified-move` re-keys the moved entries
through the `cc-sd-table-moved` hook.

`cc-nbase-raw` reads the base type of every native declaration and type
name. C90 allows qualifiers between type keywords, so
`cc-nbase-next-specifier` steps over them (noting the qualifier as
usual) to reach the next keyword: `unsigned const char` and
`long volatile int` name the same types as `const unsigned char` and
`volatile long int`. The keywords are counted in `cc-nspec-counts`
rather than folded as they arrive, and `cc-nspec-base` derives the
base from the counts, so their order cannot matter either
(`double long` is `long double`). Two `long`s select `long long` under
LP64, whatever their order: `long unsigned long` and
`unsigned long long int` are one type; the legacy data model has only
one `long`. A target may check the counted set
through `cc-nspec-check-fwd`; the native profile keeps its permissive
keyword sequence, while the System V target rejects invalid sets
(Chapter 36).

`cc-ndeclarator` handles the bounded declarator forms the target
needs: pointers, function pointers, arrays, and function parameter
lists. Grouped declarations distinguish a function returning a pointer
from an array of function pointers, retaining each callback signature.
A lexer mark preserves the parameter tokens so a function
definition can revisit them after it is classified. Two-dimensional
objects are supported, but nested array fields and general
pointer-to-array declarators are outside this profile.

`cc-nobject` separates stack objects from static storage. Tentative
globals reserve bss space; a later declaration may enlarge an array
or move a definition into initialized storage. Existing global
fixup slots are updated with that move, so earlier references do
not keep pointing at the obsolete allocation.

```forth file=115-cc-native.fth
\ 115-cc-native.fth — opt-in LP64 bootstrap declaration parser.
\ The legacy M2-compatible parser remains the default. Native mode uses
\ LP64 object layout and a private, all-stack call ABI within its image.
\ TinyCC built by this compiler emits its own standard target ABI.

: cc-npick ( x_n ... x_0 n -- x_n ... x_0 x_n )
  dup 0= if, drop dup exit, then,
  1- swap >r cc-npick r> swap ;
: cc-nminus-rot rot rot ;
: cc-nmax 2dup < if, swap then, drop ;
: cc-ncopy ( src dst n -- )
  begin, dup while,
    1- >r over r@ + c@ over r@ + c! r>
  repeat, drop 2drop ;

variable cc-nctx
[lit] 232 constant cc-nctx-bytes
: nc-ty     cc-nctx @ ;
: nc-desc   cc-nctx @ [lit] 8 + ;
: nc-name   cc-nctx @ [lit] 16 + ;
: nc-nlen   cc-nctx @ [lit] 24 + ;
: nc-array  cc-nctx @ [lit] 32 + ;
: nc-inner  cc-nctx @ [lit] 40 + ;
: nc-func   cc-nctx @ [lit] 48 + ;
: nc-params cc-nctx @ [lit] 56 + ;
: nc-td     cc-nctx @ [lit] 120 + ;
: nc-static cc-nctx @ [lit] 128 + ;
: nc-top    cc-nctx @ [lit] 136 + ;
: nc-base   cc-nctx @ [lit] 144 + ;
: nc-sdesc  cc-nctx @ [lit] 152 + ;
: nc-id     cc-nctx @ [lit] 160 + ;
: nc-slot   cc-nctx @ [lit] 168 + ;
: nc-extern cc-nctx @ [lit] 176 + ;
: nc-bound-mask cc-nctx @ [lit] 184 + ;
: nc-base-array cc-nctx @ [lit] 192 + ;
: nc-base-inner cc-nctx @ [lit] 200 + ;
: nc-qualified cc-nctx @ [lit] 208 + ;
: nc-base-qualified cc-nctx @ [lit] 216 + ;
: nc-prefix-qualified cc-nctx @ [lit] 224 + ;
: cc-native-qual-note cc-nctx @ if, true nc-qualified ! then, ;
' cc-native-qual-note is cc-qual-note
: cc-nzero ( a n -- )
  begin, dup while, 1- 2dup + [lit] 0 swap c! repeat, 2drop ;
: cc-ncontext
  cc-nctx-bytes cc-alloc dup cc-nctx ! cc-nctx-bytes cc-nzero ;
: cc-nalign ( n alignment -- n' )
  dup [lit] 0 <= if, drop [lit] 1 then,
  dup >r 1- + r@ / r> * ;
: cc-nsize ( ty desc -- n )
  over ty-base ty-array = over [lit] 0 <> and if,
    over ty-ptr 0= if, nip cc-ad-size exit, then,
  then,
  over ty-base ty-struct = [lit] 2 cc-npick ty-ptr 0= and if,
    dup 0= if, [lit] 210 cc-die then, nip cc-sd-total-size
  else, drop ty-size then, ;
: cc-nalignment ( ty desc -- n )
  over ty-base ty-array = over [lit] 0 <> and if,
    over ty-ptr 0= if, nip cc-ad-align exit, then,
  then,
  over ty-base ty-struct = [lit] 2 cc-npick ty-ptr 0= and if,
    nip cc-sd-align
  else, drop ty-align then, ;

\ Tags live in their own namespace, so typedef struct T T is unambiguous.
variable cc-ntag-a
variable cc-ntag-u
: cc-nfind-tag ( a u -- id|-1 )
  cc-ntag-u ! cc-ntag-a !
  cc-sym-count @
  begin, dup while,
    1-
    dup cc-sym-kind-of sk-struct = if,
      dup cc-sym-name-len cell[] @ cc-ntag-u @ = if,
        dup cc-sym-name-addr cell[] @ cc-ntag-a @ cc-ntag-u @ bytes-eq if,
          exit,
        then,
      then,
    then,
  repeat, drop true ;

: cc-native-type-start
  cc-tok-is-basic-type-kw? cc-qualifier? or
  kw-struct cc-tok-kw? or kw-union cc-tok-kw? or kw-enum cc-tok-kw? or
  kw-float cc-tok-kw? or kw-double cc-tok-kw? or
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find
    dup 0< if, drop else, cc-sym-kind-of sk-typedef = or then,
  then, ;
' cc-native-type-start is cc-native-type-start-fwd

: cc-ntypedef-check-noop ;
defer cc-ntypedef-check-fwd
' cc-ntypedef-check-noop is cc-ntypedef-check-fwd

\ A target may provide C90's omitted int base without changing native mode.
: cc-native-implicit-base-noop [lit] 0 ;
defer cc-native-implicit-base-fwd
' cc-native-implicit-base-noop is cc-native-implicit-base-fwd

defer cc-nbase-fwd

defer cc-naggregate-fwd

\ A target can retain enum provenance without changing its scalar encoding.
: cc-nenum-desc-default [lit] 0 ;
defer cc-nenum-desc-fwd
' cc-nenum-desc-default is cc-nenum-desc-fwd

\ Read an enum type and optionally install its enumerators.
: cc-nenum
  cc-next-token-keep
  tok-kind @ tk-ident = if, cc-next-token-keep then,
  [char] { cc-tok-punct? if,
    [lit] 0
    begin,
      cc-next-token-keep
      [char] } cc-tok-punct? 0= while,
      tok-kind @ tk-ident <> if, [lit] 190 cc-die then,
      tok-str-addr @ tok-str-len @ rot
      cc-next-token-keep
      [char] = cc-tok-punct? if, drop cc-parse-const else, cc-putback-token then,
      dup >r sk-enum swap ty-int [lit] 0 ty-make swap cc-sym-add drop
      r> 1+
      cc-next-token-keep
      [char] , cc-tok-punct? 0= if,
        [char] } cc-tok-punct? 0= if, [lit] 192 cc-die then,
        cc-putback-token
      then,
    repeat,
    drop
  else, cc-putback-token then,
  ty-int [lit] 0 ty-make cc-nenum-desc-fwd ;

\ A target may consume context-specific declaration specifiers around base
\ keywords. Native mode keeps its existing token and qualifier handling.
: cc-nbase-specifiers-default ;
defer cc-nbase-specifiers-fwd
' cc-nbase-specifiers-default is cc-nbase-specifiers-fwd

\ C90 lets qualifiers and target specifiers appear between type keywords:
\ `unsigned const char` and `long volatile int` name the same type as their
\ qualifier-first spellings. Read past them into the next type keyword.
\ Qualifiers keep their existing flag; they never change the base type.
: cc-nbase-next-specifier
  begin,
    cc-nbase-specifiers-fwd
    cc-qualifier? while, cc-qual-note cc-next-token-keep
  repeat, ;

\ Type keywords are counted per spelling: int .. signed use their keyword
\ numbers 0-6, float is 7 and double 8. A target may check the multiset;
\ native mode keeps its permissive keyword sequence.
create cc-nspec-counts [lit] 72 allot
: cc-nspec-count ( slot -- n ) cc-nspec-counts cell[] @ ;
: cc-nspec-keyword? ( -- flag )
  cc-tok-is-basic-type-kw? kw-float cc-tok-kw? or kw-double cc-tok-kw? or ;
: cc-nspec-note
  cc-nspec-keyword? 0= if, exit, then,
  tok-kw-id @
  dup kw-float = if, drop [lit] 7 then,
  dup kw-double = if, drop [lit] 8 then,
  cc-nspec-counts cell[] dup @ 1+ swap ! ;
: cc-nspec-check-default ;
defer cc-nspec-check-fwd
' cc-nspec-check-default is cc-nspec-check-fwd

\ The base comes from the counted keywords. In native mode an invalid set
\ still selects one base: the first of void, float, double, char, short and
\ long that occurs, otherwise int. Long double is double with a long.
\ Two longs name long long only under LP64; the legacy model has one long.
: cc-nspec-base ( -- base )
  kw-void cc-nspec-count if, ty-void exit, then,
  [lit] 7 cc-nspec-count if, ty-float exit, then,
  [lit] 8 cc-nspec-count if,
    kw-long cc-nspec-count if, ty-ldouble else, ty-double then, exit,
  then,
  kw-char cc-nspec-count if, ty-char exit, then,
  kw-short cc-nspec-count if, ty-short exit, then,
  kw-long cc-nspec-count if,
    kw-long cc-nspec-count [lit] 1 > cc-target-lp64 @ and if,
      ty-llong
    else, ty-long then, exit,
  then,
  ty-int ;

\ The current token is a base type. Return encoded type and descriptor.
: cc-nbase-raw
  cc-nctx @ 0= if, cc-ncontext then,
  [lit] 0 nc-base-array ! [lit] 0 nc-base-inner !
  cc-nbase-next-specifier
  cc-native-implicit-base-fwd if, exit, then,
  kw-struct cc-tok-kw? kw-union cc-tok-kw? or if,
    cc-naggregate-fwd exit,
  then,
  kw-enum cc-tok-kw? if, cc-nenum exit, then,
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find
    dup 0< if, [lit] 194 cc-die then,
    dup cc-sym-kind-of sk-typedef <> if, [lit] 195 cc-die then,
    cc-ntypedef-check-fwd
    dup cc-sym-val-of swap cc-sym-struct-desc-of exit,
  then,
  \ Count every keyword first, so the spelling order cannot matter.
  cc-nspec-counts [lit] 72 cc-nzero
  begin,
    cc-nspec-note
    cc-next-token-keep cc-nbase-next-specifier
    cc-nspec-keyword?
  while, repeat,
  cc-putback-token cc-nspec-check-fwd
  cc-nspec-base kw-unsigned cc-nspec-count
  over ty-float = [lit] 2 cc-npick ty-double = or
  [lit] 2 cc-npick ty-ldouble = or cc-native-float-types-fwd 0= and if,
    [lit] 214 cc-die
  then,
  if,
    dup ty-char = if, drop ty-uchar else,
    dup ty-short = if, drop ty-ushort else,
    dup ty-long = if, drop ty-ulong else,
    dup ty-llong = if, drop ty-ullong else,
    drop ty-uint then, then, then, then,
  then,
  [lit] 0 ty-make [lit] 0 ;
 : cc-nbase
  cc-nctx @ 0= if, cc-ncontext then,
  nc-prefix-qualified @ nc-qualified ! [lit] 0 nc-prefix-qualified !
  cc-nbase-raw nc-qualified @ nc-base-qualified ! ;
' cc-nbase is cc-nbase-fwd

\ The optional ABI layer records function-pointer signatures at this seam.
: cc-nfnptr-default ( extra-stars -- )
  drop cc-skip-fnptr-params ty-func [lit] 1 ty-make nc-ty ! ;
defer cc-nfnptr-fwd
' cc-nfnptr-default is cc-nfnptr-fwd
: cc-ndeclarator-check-noop ;
defer cc-ndeclarator-check-fwd
' cc-ndeclarator-check-noop is cc-ndeclarator-check-fwd

\ A named declarator is the bootstrap default. Prototype parameters may
\ opt into an abstract function-pointer declarator with no identifier.
: cc-nfnptr-name-default
  cc-expect-ident
  tok-str-addr @ nc-name ! tok-str-len @ nc-nlen ! ;
defer cc-nfnptr-name-fwd
' cc-nfnptr-name-default is cc-nfnptr-name-fwd

: cc-narray-extra-default ;
defer cc-narray-extra-fwd
' cc-narray-extra-default is cc-narray-extra-fwd

\ Parse array suffixes with the current '[' already read. The count and
\ element type are independent, including arrays of function pointers.
: cc-narray-suffix
  [char] [ cc-tok-punct? if,
    cc-next-token-keep
    [char] ] cc-tok-punct? if, true nc-array ! else,
      [lit] 1 nc-bound-mask !
      cc-putback-token cc-parse-const nc-array ! [char] ] cc-expect-punct-c
    then,
    cc-next-token-keep
    [char] [ cc-tok-punct? if,
      [lit] 2 nc-bound-mask +!
      cc-parse-const nc-inner ! [char] ] cc-expect-punct-c
      cc-next-token-keep
    then,
    cc-narray-extra-fwd
  then, ;

: cc-nfunction-suffix
  \ An array may contain pointers to functions, never functions themselves.
  nc-array @ if, [lit] 238 cc-die then,
  true nc-func !
  nc-params cc-lex-mark
  cc-skip-fnptr-params
  cc-next-token-keep ;

\ A grouped declarator distinguishes (*f()) (function returning a pointer)
\ from (*f)() and (*f[N])() (a pointer or array of pointers to functions).
\ Stars inside the group belong to the object only when no outer function
\ suffix follows. General pointers to arrays still lack a representation.
: cc-npointer-array-default drop [lit] 238 cc-die ;
defer cc-npointer-array-fwd
' cc-npointer-array-default is cc-npointer-array-fwd
: cc-ngrouped-declarator
  cc-count-stars >r
  cc-nfnptr-name-fwd
  cc-next-token-keep
  lparen cc-tok-punct? if,
    nc-nlen @ 0= if, [lit] 203 cc-die then,
    r> nc-ty +!
    cc-nfunction-suffix
    [char] ) cc-tok-punct? 0= if, [lit] 143 cc-die then,
    cc-next-token-keep
    lparen cc-tok-punct? [char] [ cc-tok-punct? or if, [lit] 238 cc-die then,
    exit,
  then,
  cc-narray-suffix
  \ A later grouped pointer/function constructor cannot replace ranked
  \ element metadata. Keep that complex declarator outside this profile.
  nc-array @ nc-ty @ ty-base ty-array = and
  nc-ty @ ty-ptr 0= and if, [lit] 238 cc-die then,
  [char] ) cc-tok-punct? 0= if, [lit] 143 cc-die then,
  cc-next-token-keep
  lparen cc-tok-punct? if,
    r@ 0= if,
      r> drop
      nc-array @ if, [lit] 238 cc-die then,
      cc-nfunction-suffix
    else,
      r> 1- cc-nfnptr-fwd
      cc-next-token-keep
      lparen cc-tok-punct? [char] [ cc-tok-punct? or if, [lit] 238 cc-die then,
    then,
  else,
    r@ [char] [ cc-tok-punct? and if,
      r> cc-npointer-array-fwd exit,
    then,
    nc-array @ [char] [ cc-tok-punct? and if, [lit] 238 cc-die then,
    r> nc-ty +!
  then, ;

\ Declarator after nc-base/nc-sdesc. Function parameter tokens are saved
\ so a definition can return and install parameter names after classification.
: cc-ndeclarator
  nc-base-qualified @ nc-qualified !
  cc-skip-qualifiers
  nc-qualified @ nc-base-qualified !
  nc-base @ cc-count-stars + nc-ty !
  nc-sdesc @ nc-desc !
  [lit] 0 nc-name ! [lit] 0 nc-nlen !
  [lit] 0 nc-array ! [lit] 0 nc-inner ! [lit] 0 nc-func !
  [lit] 0 nc-bound-mask !
  cc-next-token-keep
  lparen cc-tok-punct? if,
    cc-ngrouped-declarator
  else,
    tok-kind @ tk-ident = if,
      tok-str-addr @ nc-name ! tok-str-len @ nc-nlen !
      cc-next-token-keep
    then,
  then,
  cc-narray-suffix
  lparen cc-tok-punct? if, cc-nfunction-suffix then,
  cc-ndeclarator-check-fwd ;

\ Field qualification (070) is keyed by record address, and a growing
\ field table (060) moves its records: re-key the entries that moved.
variable cc-nmove-old
variable cc-nmove-new
variable cc-nmove-bytes
: cc-nqualified-move ( old new bytes -- )
  cc-nmove-bytes ! cc-nmove-new ! cc-nmove-old !
  cc-qualified-fields @ begin, dup while,
    dup [lit] 8 + @ cc-nmove-old @ -             ( entry offset )
    dup 0< 0= over cc-nmove-bytes @ < and if,
      cc-nmove-new @ + over [lit] 8 + !
    else, drop then,
    @
  repeat, drop ;
' cc-nqualified-move is cc-sd-table-moved

\ Add a field, including flattened anonymous aggregate members.
: cc-nadd-field ( desc -- )
  dup cc-sd-field-count over swap cc-sd-field-rec >r
  nc-qualified @ r@ cc-field-set-qualified
  nc-name @ r@ cc-sf-set-name-addr
  nc-nlen @ r@ cc-sf-set-name-len
  nc-ty @ r@ cc-sf-set-type
  nc-desc @ r@ cc-sf-set-desc
  nc-array @ r@ cc-sf-set-array-len
  nc-inner @ r@ cc-sf-set-array-inner
  nc-ty @ nc-desc @ cc-nalignment
  over cc-sd-align over < if, dup [lit] 2 cc-npick cc-sd-set-align then,
  over cc-sd-total-size swap cc-nalign
  over cc-sd-union? if, drop [lit] 0 then,
  dup r> cc-sf-set-offset
  nc-ty @ nc-desc @ cc-nsize
  nc-array @ [lit] 0 > if, nc-array @ * then,
  nc-inner @ [lit] 0 > if, nc-inner @ * then,
  + over cc-sd-total-size cc-nmax over cc-sd-set-total-size
  dup cc-sd-field-count 1+ swap cc-sd-set-field-count ;

\ Anonymous aggregate promotion copies records and adds the enclosing offset.
: cc-npromote-fields ( child parent -- )
  dup cc-sd-field-count 1- over swap cc-sd-field-rec cc-sf-offset >r
  dup cc-sd-field-count 1- over cc-sd-set-field-count
  over cc-sd-field-count [lit] 0
  begin, 2dup > while,
    dup [lit] 4 cc-npick swap cc-sd-field-rec
    [lit] 3 cc-npick dup cc-sd-field-count swap over cc-sd-field-rec
    swap drop
    2dup swap cc-field-qualified nc-qualified @ or swap cc-field-set-qualified
    cc-sd-record-bytes cc-ncopy
    [lit] 2 cc-npick dup cc-sd-field-count cc-sd-field-rec
    dup cc-sf-offset r@ + swap cc-sf-set-offset
    [lit] 2 cc-npick dup cc-sd-field-count 1+ swap cc-sd-set-field-count
    1+
  repeat, 2drop 2drop r> drop ;

\ A target may add member syntax while retaining the shared declarator.
: cc-nmember-default ( desc -- )
  nc-func @ if, [lit] 238 cc-die then,
  dup cc-nadd-field
  nc-nlen @ 0= if, nc-desc @ swap cc-npromote-fields else, drop then, ;
defer cc-nmember-fwd
' cc-nmember-default is cc-nmember-fwd

: cc-naggregate
  kw-union cc-tok-kw? >r
  cc-next-token-keep
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ 2dup cc-nfind-tag
    dup 0< if,
      drop cc-sd-alloc dup >r
      sk-struct swap [lit] 0 swap cc-sym-add drop r>
    else, nip nip cc-sym-val-of then,
    cc-next-token-keep
  else, cc-sd-alloc then,
  r> over cc-sd-set-union
  [char] { cc-tok-punct? if,
    [lit] 1 over cc-sd-set-align
    cc-nctx @ >r cc-ncontext
    begin,
      cc-next-token-keep
      [char] } cc-tok-punct? 0= while,
      cc-nbase-fwd nc-sdesc ! nc-base !
      begin,
        cc-ndeclarator
        dup cc-nmember-fwd
        [char] , cc-tok-punct?
      while, repeat,
      [char] ; cc-tok-punct? 0= if, [lit] 58 cc-die then,
    repeat,
    dup cc-sd-total-size over cc-sd-align cc-nalign over cc-sd-set-total-size
    r> cc-nctx !
  else, cc-putback-token then,
  ty-struct [lit] 0 ty-make swap ;
' cc-naggregate is cc-naggregate-fwd

\ Type queries preserve the enclosing declaration's array base shape.
: cc-native-type-shape-default + ;
defer cc-native-type-shape-fwd
' cc-native-type-shape-default is cc-native-type-shape-fwd
: cc-native-type-name
  cc-nctx @ 0= if, cc-ncontext then,
  nc-base-qualified @ >r nc-qualified @ >r
  nc-base-array @ >r nc-base-inner @ >r
  [lit] 0 cc-type-name-array ! [lit] 0 cc-type-name-inner !
  cc-nbase cc-cast-desc ! cc-skip-qualifiers cc-count-stars
  cc-native-type-shape-fwd
  nc-qualified @ cc-type-name-qualified !
  r> nc-base-inner ! r> nc-base-array !
  r> nc-qualified ! r> nc-base-qualified ! ;
' cc-native-type-name is cc-native-type-name-fwd

defer cc-native-function-fwd

: cc-nobject-size
  nc-ty @ nc-desc @ cc-nsize
  nc-array @ [lit] 0 > if, nc-array @ * then,
  nc-inner @ [lit] 0 > if, nc-inner @ * then, ;

: cc-ninstall-symbol ( kind slot -- id )
  >r >r nc-name @ nc-nlen @ r> nc-ty @ r> cc-sym-add
  nc-desc @ over cc-sym-set-struct-desc
  nc-array @ over cc-sym-set-array-len
  nc-inner @ over cc-sym-set-array-inner
  nc-qualified @ over cc-sym-qualified cell[] ! ;

: cc-ngstore ( value offset bytes -- )
  >r cc-globals-buf + r>
  begin, dup while,
    >r over [lit] 255 and over c!
    1+ swap [lit] 256 / swap r> 1-
  repeat, drop 2drop ;
: cc-nmove-tentative
  nc-slot @ cc-bss-flag >= if,
    cc-globals-pos @ nc-ty @ nc-desc @ cc-nalignment cc-nalign cc-globals-pos !
    cc-nobject-size cc-globals-alloc
    [lit] 0
    begin, dup cc-gfixup-count @ < while,
      dup cc-gfixup-slot cell[] @ nc-slot @ = if,
        over over cc-gfixup-slot cell[] !
      then, 1+
    repeat, drop
    dup nc-id @ cc-sym-val cell[] ! nc-slot !
  then, ;

: cc-native-init-noop ;
defer cc-native-init-prepare-fwd
defer cc-native-init-fwd
defer cc-native-init-entry-fwd
defer cc-native-init-finish-fwd
' cc-native-init-noop is cc-native-init-prepare-fwd
' cc-native-init-noop is cc-native-init-entry-fwd
' cc-native-init-noop is cc-native-init-finish-fwd
: cc-native-scalar-init
  nc-top @ nc-static @ or if,
    cc-nmove-tentative
    cc-parse-const nc-slot @ nc-ty @ ty-size cc-ngstore
  else,
    cc-parse-assign cc-emit-materialize
    nc-slot @ nc-ty @ cc-emit-store-local-typed
  then,
  cc-next-token-keep ;
' cc-native-scalar-init is cc-native-init-fwd

: cc-native-local-layout-default ( -- slots slot )
  cc-nobject-size [lit] 7 + [lit] 8 / dup cc-fn-local-count @ + 1- ;
defer cc-native-local-layout-fwd
' cc-native-local-layout-default is cc-native-local-layout-fwd

: cc-nobject
  [char] = cc-tok-punct? if, cc-native-init-prepare-fwd then,
  nc-name @ nc-nlen @ cc-sym-find nc-id !
  nc-top @ nc-static @ or if,
    nc-top @ 0= if, true nc-id ! then,
    nc-id @ 0< 0= if,
      nc-id @ cc-sym-kind-of sk-global = if,
        nc-id @ cc-sym-val-of nc-slot !
      else, true nc-id ! then,
    then,
    nc-id @ 0< if,
      [char] = cc-tok-punct? if,
        cc-globals-pos @ nc-ty @ nc-desc @ cc-nalignment cc-nalign cc-globals-pos !
        cc-nobject-size cc-globals-alloc
      else,
        cc-bss-pos @ nc-ty @ nc-desc @ cc-nalignment cc-nalign cc-bss-pos !
        cc-nobject-size cc-bss-alloc
      then,
      dup nc-slot ! sk-global swap cc-ninstall-symbol nc-id !
      cc-nobject-size nc-id @ cc-sym-set-object-size
    else,
      cc-nobject-size nc-id @ cc-sym-object-size-of > if,
        cc-bss-pos @ nc-ty @ nc-desc @ cc-nalignment cc-nalign cc-bss-pos !
        cc-nobject-size cc-bss-alloc
        [lit] 0
        begin, dup cc-gfixup-count @ < while,
          dup cc-gfixup-slot cell[] @ nc-slot @ = if,
            over over cc-gfixup-slot cell[] !
          then, 1+
        repeat, drop
        dup nc-id @ cc-sym-val cell[] ! nc-slot !
        cc-nobject-size nc-id @ cc-sym-set-object-size
      then,
      nc-ty @ nc-id @ cc-sym-type cell[] !
      nc-desc @ nc-id @ cc-sym-set-struct-desc
      nc-array @ nc-id @ cc-sym-set-array-len
      nc-inner @ nc-id @ cc-sym-set-array-inner
    then,
  else,
    cc-native-local-layout-fwd dup nc-slot !
    sk-local swap cc-ninstall-symbol nc-id !
    cc-fn-add-slots
  then,
  [char] = cc-tok-punct? if, cc-native-init-fwd then, ;

defer cc-nobject-fwd
' cc-nobject is cc-nobject-fwd

: cc-native-declaration ( top? -- )
  cc-nctx @ >r cc-ncontext nc-top !
  cc-prefix-qualified @ nc-prefix-qualified ! [lit] 0 cc-prefix-qualified !
  cc-decl-static @ nc-static ! cc-decl-extern @ nc-extern !
  kw-typedef cc-tok-kw? if,
    true nc-td ! cc-next-token-keep
  then,
  cc-nbase nc-sdesc ! nc-base !
  cc-next-token-keep
  [char] ; cc-tok-punct? if, r> cc-nctx ! exit, then,
  cc-putback-token
  begin,
    cc-ndeclarator
    nc-nlen @ 0= if, [lit] 203 cc-die then,
    nc-td @ if,
      nc-name @ nc-nlen @ sk-typedef [lit] 0 nc-ty @ cc-sym-add
      nc-qualified @ over cc-sym-qualified cell[] !
      nc-desc @ over cc-sym-set-struct-desc
      nc-array @ over cc-sym-set-array-len
      nc-inner @ swap cc-sym-set-array-inner
    else,
      nc-func @ if,
        cc-native-function-fwd
        [char] } cc-tok-punct? if, r> cc-nctx ! exit, then,
      else, cc-nobject-fwd then,
    then,
    [char] , cc-tok-punct?
  while, repeat,
  [char] ; cc-tok-punct? 0= if, [lit] 205 cc-die then,
  r> cc-nctx ! ;
: cc-native-local-declaration [lit] 0 cc-native-declaration ;
' cc-native-local-declaration is cc-native-decl-fwd
```

## 3. Private stack calls and whole programs

Every call within the seed image uses caller-owned eight-byte
argument slots. Arguments are pushed right-to-left; after a normal
function's prologue, argument one is at `rbp+16`. There is no
six-register limit, and portable-libc's simple stack-based varargs
can read the remaining arguments. The return value is in `rax`.
This is a private ABI shared by the code we generate together,
including indirect calls and C libc functions.

It is not the ABI of the programs TinyCC later compiles. TinyCC's
own AMD64 backend emits its standard target calling convention.
No host libc or precompiled SysV object is linked into the private
image. Crossing that boundary without an adapter would be wrong.
Aggregate values cannot cross a function boundary: by-value
parameters, returns, and call arguments fail with error 212.
Pointers to aggregates remain valid.

`cc-native-function` resolves forward call and address fixups,
installs parameter names, and parses the body in a fresh scope.
It emits a placeholder frame size, then patches the size after
locals have been counted, aligned to sixteen bytes. This removes
the legacy driver's fixed thirty-two-slot frame limit.

`cc-native-entry` first calls the initializer dispatcher, reads
`argc` and `argv` from the kernel stack, pushes them for `main`,
and exits through the Linux syscall with `main`'s result.
`cc-native-program` installs the runtime primitives, reads all
file-scope declarations, closes the initializer dispatcher, and
checks that every referenced function was defined.

```forth file=117-cc-native-program.fth
\ 117-cc-native-program.fth — program and private stack ABI for direct TinyCC.
\ All linked code is generated together. No system libc or host object is used.
variable cc-native-param-count
variable cc-native-frame-patch

: cc-native-params
  [lit] 0 cc-native-param-count !
  begin,
    cc-next-token-keep
    [char] ) cc-tok-punct? if, exit, then,
    pt-ellipsis cc-tok-punct? if, [char] ) cc-expect-punct-c exit, then,
    kw-void cc-tok-kw? if,
      cc-peek-mark cc-lex-mark cc-next-token-keep
      [char] ) cc-tok-punct? if, exit, then,
      cc-peek-mark cc-lex-reset
    then,
    cc-nbase nc-sdesc ! nc-base !
    cc-ndeclarator
    nc-array @ if, [lit] 1 nc-ty +! [lit] 0 nc-array ! then,
    nc-ty @ dup ty-base ty-struct = swap ty-ptr 0= and if, [lit] 212 cc-die then,
    nc-nlen @ if,
      sk-local [lit] 0 cc-native-param-count @ [lit] 3 + -
      cc-ninstall-symbol drop
    then,
    [lit] 1 cc-native-param-count +!
    [char] , cc-tok-punct? 0= if,
      [char] ) cc-tok-punct? 0= if, [lit] 184 cc-die then,
      exit,
    then,
  again, ;

: cc-native-function
  nc-ty @ dup ty-base ty-struct = swap ty-ptr 0= and if, [lit] 212 cc-die then,
  nc-name @ nc-nlen @ cc-sym-find
  dup 0< 0= if,
    dup cc-sym-kind-of sk-func <> if, drop true then,
  then,
  dup 0< if,
    drop nc-name @ nc-nlen @ sk-func nc-ty @ [lit] 0 cc-sym-add
    nc-desc @ over cc-sym-set-struct-desc
  then,
  nc-id !
  nc-ty @ nc-id @ cc-sym-type cell[] !
  nc-desc @ nc-id @ cc-sym-set-struct-desc
  [char] { cc-tok-punct? 0= if, exit, then,
  nc-id @ cc-sym-val-of if, [lit] 211 cc-die then,
  cc-here-vaddr nc-id @ cc-sym-val cell[] !
  nc-id @ cc-sym-call-fixups @ cc-here-vaddr cc-walk-and-patch-to-vaddr
  [lit] 0 nc-id @ cc-sym-call-fixups !
  nc-id @ cc-sym-addr-fixups @ cc-here-vaddr cc-walk-and-patch-imm64-to-vaddr
  [lit] 0 nc-id @ cc-sym-addr-fixups !
  nc-name @ nc-nlen @ cc-is-main? if, cc-here-vaddr cc-main-vaddr ! then,
  nc-ty @ cc-native-return-type ! nc-desc @ cc-native-return-desc !
  nc-params cc-lex-reset
  cc-nctx @ >r cc-ncontext
  cc-scope-push
  [lit] 0 cc-fn-local-count !
  [lit] 0 cc-label-count !
  [lit] 0 cc-break-stack-head ! [lit] 0 cc-continue-stack-head !
  [lit] 0 cc-switch-depth ! [lit] 0 cc-loop-switch-depth !
  cc-native-params
  [char] { cc-expect-punct-c
  [lit] 0 cc-emit-prologue
  cc-out-pos @ [lit] 4 - cc-native-frame-patch !
  begin,
    cc-next-token-keep [char] } cc-tok-punct? 0= while,
    cc-putback-token cc-parse-stmt
  repeat,
  cc-emit-xor-rax-rax cc-emit-epilogue
  cc-native-finish-gotos
  cc-fn-local-count @ [lit] 8 * [lit] 16 cc-nalign
  cc-native-frame-patch @ cc-out-patch-4le
  cc-scope-pop r> cc-nctx ! ;
' cc-native-function is cc-native-function-fwd

: cc-native-entry
  cc-native-init-entry-fwd
  \ Kernel stack has argc,argv. Push arguments right-to-left for main.
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte [lit] 60 cc-emit-byte [lit] 36 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte [lit] 116 cc-emit-byte [lit] 36 cc-emit-byte [lit] 8 cc-emit-byte
  [lit] 86 cc-emit-byte [lit] 87 cc-emit-byte
  cc-emit-call-rel32-placeholder cc-call-main-patch !
  cc-emit-mov-rdi-rax
  [lit] 184 cc-emit-byte [lit] 60 cc-emit-4le
  [lit] 15 cc-emit-byte [lit] 5 cc-emit-byte ;

: cc-native-runtime-noop ;
defer cc-native-runtime-fwd
' cc-native-runtime-noop is cc-native-runtime-fwd

: cc-native-program
  cc-native-entry
  cc-native-runtime-fwd
  begin,
    cc-skip-storage-quals cc-next-token-keep
    tok-kind @ tk-eof = 0= while,
    true cc-native-declaration
  repeat,
  cc-native-init-finish-fwd
  cc-check-fns-defined cc-patch-call-main ;
```

## 4. Initializers reuse expression fixups

An initializer describes a destination and a tree of values.
`cc-ni-value` saves the type, descriptor, dimensions, byte offset,
and brace state in a small recursive frame. Arrays advance by
element size; structures visit field records; a union initializes
its first member. An omitted member remains zero. Character-array
strings decode escapes, concatenate adjacent literals, and allow
an exactly full fixed array without a terminating NUL.

Before allocating an unsized array, `cc-ni-infer` scans its
initializer to count outer elements, then restores the lexer mark.
For inferred arrays, nested aggregates require their own braces;
known-size arrays also accept the supported brace-elided forms.
Excess elements and unsupported shapes produce diagnostics.
Designated initializers are outside the profile.

The interesting choice is static storage. Rather than write a
second relocation evaluator, we emit small initialization routines
and queue their addresses with `cc-ni-queue`. The entry dispatcher
calls them once before `main`. Their expressions use the ordinary
global-address and function-address fixups, including references
to declarations that appear later in the translation unit.

This is an implementation of constant initialization, not arbitrary
code at file scope. `cc-native-static-init` turns on an expression
category guard: evaluated calls, object loads, assignments, and
increments are rejected. Address constants, scalar constants, and
their supported combinations can be lowered. Runtime execution of
the emitted stores does not expand the C initializer language.

```forth file=118-cc-native-init.fth
\ 118-cc-native-init.fth — bounded C initializers for the native bootstrap.
\ Scalar stores, brace lists, nested arrays/aggregates and character strings
\ are lowered by the Forth compiler. Static expressions use the expression
\ parser's constant-category guard; they run once before main. This avoids
\ a second relocation engine: ordinary global/function fixups serve both
\ executable expressions and initializers. No host compiler is involved.
\ Designators and more than two array dimensions are outside this profile.

variable cc-ni-frame
variable cc-ni-static
variable cc-ni-head
variable cc-ni-tail
variable cc-ni-entry-patch

: ni-type   cc-ni-frame @ ;
: ni-desc   cc-ni-frame @ [lit] 8 + ;
: ni-array  cc-ni-frame @ [lit] 16 + ;
: ni-inner  cc-ni-frame @ [lit] 24 + ;
: ni-offset cc-ni-frame @ [lit] 32 + ;
: ni-index  cc-ni-frame @ [lit] 40 + ;
: ni-brace  cc-ni-frame @ [lit] 48 + ;
: ni-nested cc-ni-frame @ [lit] 56 + ;

: cc-ni-aggregate?
  ni-type @ ty-base ty-struct = ni-type @ ty-ptr 0= and ;
: cc-ni-address ( offset -- )
  cc-ni-static @ if,
    nc-slot @ cc-emit-global-ref
  else, nc-slot @ cc-emit-lea-rdi-local then,
  dup if, cc-emit-add-rdi-imm32 else, drop then, ;
: cc-ni-count-rcx ( n -- )
  [lit] 185 cc-emit-byte cc-emit-4le ;
: cc-ni-mov-rsi-rdi
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 254 cc-emit-byte ;
: cc-ni-copy-bytes ( n -- )
  cc-ni-count-rcx [lit] 243 cc-emit-byte [lit] 164 cc-emit-byte ;
: cc-ni-zero-object
  [lit] 0 cc-ni-address
  cc-nobject-size cc-ni-count-rcx
  cc-emit-xor-rax-rax
  [lit] 243 cc-emit-byte [lit] 170 cc-emit-byte ;

\ The literal lexer retains escapes. Count exactly their decoded bytes.
: cc-ni-string-size ( a u -- n )
  [lit] 0 >r
  begin, dup [lit] 0 > while,
    over c@ backslash = over [lit] 1 > and if,
      over 1+ cc-decode-escape nip 1+
    else, [lit] 1 then,
    >r swap r@ + swap r> -
    r> 1+ >r
  repeat, 2drop r> ;

\ Before allocating an inferred array, count its outer brace elements.
\ Nested aggregates in inferred arrays require their own braces. Known-size
\ arrays additionally accept the ordinary brace-elided nested form.
variable cc-ni-scan-mark
variable cc-ni-scan-count
variable cc-ni-scan-depth
variable cc-ni-scan-have
variable cc-ni-scan-brace
: cc-ni-infer
  nc-array @ [lit] 0 < 0= if, exit, then,
  cc-lex-state-size cc-alloc dup cc-ni-scan-mark ! cc-lex-mark
  cc-next-token-keep
  [lit] 0 cc-ni-scan-brace !
  nc-inner @ 0= nc-ty @ ty-ptr 0= and
  nc-ty @ ty-size [lit] 1 = and [char] { cc-tok-punct? and if,
    cc-lex-state-size cc-alloc dup >r cc-lex-mark
    cc-next-token-keep
    tok-kind @ tk-str = if,
      true cc-ni-scan-brace ! r> drop
    else, r> cc-lex-reset then,
  then,
  tok-kind @ tk-str = if,
    nc-ty @ ty-ptr if, [lit] 220 cc-die then,
    nc-ty @ ty-size [lit] 1 <> if, [lit] 220 cc-die then,
    [lit] 0
    begin, tok-kind @ tk-str = while,
      tok-str-addr @ tok-str-len @ cc-ni-string-size +
      cc-next-token-keep
    repeat, 1+ nc-array !
    cc-ni-scan-brace @ if,
      [char] , cc-tok-punct? if, cc-next-token-keep then,
      [char] } cc-tok-punct? 0= if, [lit] 223 cc-die then,
    then,
  else,
    [char] { cc-tok-punct? 0= if, [lit] 220 cc-die then,
    [lit] 0 cc-ni-scan-count ! [lit] 0 cc-ni-scan-depth !
    [lit] 0 cc-ni-scan-have !
    begin,
      cc-next-token-keep
      tok-kind @ tk-eof = if, [lit] 221 cc-die then,
      [char] } cc-tok-punct? cc-ni-scan-depth @ 0= and if,
        cc-ni-scan-have @ if, [lit] 1 cc-ni-scan-count +! then,
        cc-ni-scan-count @ dup 0= if, [lit] 220 cc-die then, nc-array !
        cc-ni-scan-mark @ cc-lex-reset exit,
      then,
      [char] , cc-tok-punct? cc-ni-scan-depth @ 0= and if,
        cc-ni-scan-have @ 0= if, [lit] 221 cc-die then,
        [lit] 1 cc-ni-scan-count +! [lit] 0 cc-ni-scan-have !
      else,
        cc-ni-scan-have @ 0= if,
          nc-ty @ ty-base dup ty-struct = swap ty-array = or
          nc-ty @ ty-ptr 0= and if,
            [char] { cc-tok-punct? 0= if, [lit] 222 cc-die then,
          then,
          nc-inner @ if,
            [char] { cc-tok-punct? 0= if,
              tok-kind @ tk-str = nc-ty @ ty-ptr 0= and
              nc-ty @ ty-size [lit] 1 = and 0= if, [lit] 222 cc-die then,
            then,
          then,
        then,
        true cc-ni-scan-have !
        [char] { cc-tok-punct? lparen cc-tok-punct? or
        [char] [ cc-tok-punct? or if, [lit] 1 cc-ni-scan-depth +! then,
        [char] } cc-tok-punct? [char] ) cc-tok-punct? or
        [char] ] cc-tok-punct? or if, true cc-ni-scan-depth +! then,
        cc-ni-scan-depth @ [lit] 0 < if, [lit] 221 cc-die then,
      then,
    again,
  then,
  cc-ni-scan-mark @ cc-lex-reset ;
' cc-ni-infer is cc-native-init-prepare-fwd

defer cc-ni-value-fwd

\ Emit one complete (possibly concatenated) character string and copy its
\ decoded bytes. C permits a fixed char[N] string of exactly N non-NUL bytes.
: cc-ni-string
  cc-emit-jmp-rel32-placeholder >r
  cc-here-vaddr cc-out-pos @
  begin, tok-kind @ tk-str = while,
    tok-str-addr @ tok-str-len @ cc-emit-string-bytes
    true cc-out-pos +!
    cc-next-token-keep
  repeat,
  cc-out-pos @ swap -
  dup ni-array @ > if, [lit] 223 cc-die then,
  [lit] 0 cc-emit-byte
  1+ dup ni-array @ > if, drop ni-array @ then,
  r> cc-patch-rel32-to-here
  swap cc-emit-movabs-rdi-imm64 cc-ni-mov-rsi-rdi
  ni-offset @ cc-ni-address cc-ni-copy-bytes ;

: cc-value-static-init-default drop ;
defer cc-value-static-init-fwd
' cc-value-static-init-default is cc-value-static-init-fwd

: cc-ni-scalar
  cc-ni-aggregate? cc-ni-static @ and if, [lit] 219 cc-die then,
  cc-ni-static @ if, ni-type @ cc-value-static-init-fwd then,
  ni-offset @ cc-ni-address cc-emit-push-rdi
  cc-putback-token cc-parse-assign
  cc-ni-aggregate? if,
    cc-last-expr-type @ ty-base ty-struct <>
    cc-last-expr-type @ ty-ptr [lit] 0 <> or
    cc-last-struct-desc @ ni-desc @ <> or if, [lit] 224 cc-die then,
    cc-ni-mov-rsi-rdi
    cc-emit-pop-rdi
    ni-type @ ni-desc @ cc-nsize cc-ni-copy-bytes
  else,
    cc-emit-materialize
    cc-last-expr-type @ cc-last-struct-desc @ ni-type @ ni-desc @ cc-value-shape-fwd
    cc-last-expr-type @ ni-type @ cc-value-init-fwd
    cc-emit-pop-rcx ni-type @ cc-emit-store-typed-via-rcx
  then,
  cc-next-token-keep ;

defer cc-ni-scalar-fwd
defer cc-ni-string-fwd
' cc-ni-scalar is cc-ni-scalar-fwd
' cc-ni-string is cc-ni-string-fwd

: cc-ni-child-count
  ni-array @ if, ni-array @ exit, then,
  ni-desc @ cc-sd-union? if, [lit] 1 else, ni-desc @ cc-sd-field-count then, ;

: cc-ni-field-default ( rec -- handled? ) drop [lit] 0 ;
defer cc-ni-field-fwd
' cc-ni-field-default is cc-ni-field-fwd

: cc-ni-child
  ni-array @ if,
    ni-type @ ni-desc @ ni-inner @ [lit] 0
    ni-type @ ni-desc @ cc-nsize
    ni-inner @ if, ni-inner @ * then,
    ni-index @ * ni-offset @ + true cc-ni-value-fwd
  else,
    ni-desc @ ni-index @ cc-sd-field-rec
    dup cc-ni-field-fwd if, drop exit, then,
    dup cc-sf-type over cc-sf-desc
    [lit] 2 cc-npick cc-sf-array-len
    [lit] 3 cc-npick cc-sf-array-inner
    [lit] 4 cc-npick cc-sf-offset ni-offset @ +
    true cc-ni-value-fwd drop
  then, ;

: cc-ni-list
  [char] { cc-tok-punct? ni-brace !
  ni-brace @ if, cc-next-token-keep then,
  [lit] 0 ni-index !
  begin,
    [char] } cc-tok-punct? 0=
    ni-index @ cc-ni-child-count < and
  while,
    cc-ni-child [lit] 1 ni-index +!
    [char] , cc-tok-punct? if,
      ni-brace @ ni-index @ cc-ni-child-count < or if,
        cc-next-token-keep
      else, exit, then,
    else,
      ni-brace @ if,
        [char] } cc-tok-punct? 0= if, [lit] 225 cc-die then,
      else, exit, then,
    then,
  repeat,
  ni-brace @ if,
    [char] } cc-tok-punct? 0= if, [lit] 226 cc-die then,
    cc-next-token-keep
  then, ;

\ Character-array strings may optionally have a single pair of braces.
: cc-ni-char-array
  tok-kind @ tk-str = if, cc-ni-string-fwd exit, then,
  [char] { cc-tok-punct? if,
    cc-lex-state-size cc-alloc dup >r cc-lex-mark
    cc-next-token-keep
    tok-kind @ tk-str = if,
      r> drop cc-ni-string-fwd
      [char] , cc-tok-punct? if, cc-next-token-keep then,
      [char] } cc-tok-punct? 0= if, [lit] 223 cc-die then,
      cc-next-token-keep exit,
    then,
    r> cc-lex-reset
  then,
  [char] { cc-tok-punct? ni-nested @ or 0= if, [lit] 225 cc-die then,
  cc-ni-list ;

: cc-ni-value ( ty desc array inner offset nested? -- )
  cc-ni-frame @ >r
  [lit] 64 cc-alloc dup cc-ni-frame ! [lit] 64 cc-nzero
  ni-nested ! ni-offset ! ni-inner ! ni-array ! ni-desc ! ni-type !
  \ Re-enter the existing array traversal for a recursively typed element.
  ni-array @ 0= ni-type @ ty-base ty-array = and
  ni-type @ ty-ptr 0= and if,
    ni-desc @ dup cc-ad-type ni-type !
    dup cc-ad-count ni-array ! dup cc-ad-inner ni-inner !
    cc-ad-desc ni-desc !
  then,
  ni-array @ [lit] 0 > if,
    ni-inner @ 0= ni-type @ ty-ptr 0= and
    ni-type @ ty-size [lit] 1 = and if,
      cc-ni-char-array
    else,
      [char] { cc-tok-punct? ni-nested @ or 0= if, [lit] 225 cc-die then,
      cc-ni-list
    then,
  else,
    cc-ni-aggregate? if,
      [char] { cc-tok-punct? ni-nested @ or if,
        cc-ni-list
      else, cc-ni-scalar-fwd then,
    else,
      [char] { cc-tok-punct? if,
        cc-next-token-keep
        ni-type @ ni-desc @ [lit] 0 [lit] 0 ni-offset @ true cc-ni-value-fwd
        [char] , cc-tok-punct? if, cc-next-token-keep then,
        [char] } cc-tok-punct? 0= if, [lit] 227 cc-die then,
        cc-next-token-keep
      else, cc-ni-scalar-fwd then,
    then,
  then,
  r> cc-ni-frame ! ;
' cc-ni-value is cc-ni-value-fwd

: cc-ni-queue ( vaddr -- )
  [lit] 16 cc-alloc dup >r !
  [lit] 0 r@ [lit] 8 + !
  cc-ni-tail @ if, r@ cc-ni-tail @ [lit] 8 + ! else, r@ cc-ni-head ! then,
  r> cc-ni-tail ! ;

: cc-native-initializer
  nc-top @ nc-static @ or cc-ni-static !
  cc-ni-static @ if,
    cc-emit-jmp-rel32-placeholder >r
    cc-here-vaddr cc-ni-queue
    true cc-native-static-init !
  else,
    nc-array @ nc-ty @ ty-base ty-struct = nc-ty @ ty-ptr 0= and or if,
      cc-ni-zero-object
    then,
  then,
  cc-next-token-keep
  nc-ty @ nc-desc @ nc-array @ nc-inner @ [lit] 0 [lit] 0 cc-ni-value
  cc-ni-static @ if,
    [lit] 0 cc-native-static-init !
    [lit] 195 cc-emit-byte
    r> cc-patch-rel32-to-here
  then, ;
' cc-native-initializer is cc-native-init-fwd

: cc-ni-entry
  [lit] 0 cc-ni-head ! [lit] 0 cc-ni-tail !
  cc-emit-call-rel32-placeholder cc-ni-entry-patch ! ;
' cc-ni-entry is cc-native-init-entry-fwd

: cc-ni-finish
  cc-ni-entry-patch @ cc-patch-rel32-to-here
  cc-ni-head @
  begin, dup while,
    [lit] 232 cc-emit-byte
    dup @ cc-here-vaddr [lit] 4 + - cc-emit-4le
    [lit] 8 + @
  repeat, drop
  [lit] 195 cc-emit-byte ;
' cc-ni-finish is cc-native-init-finish-fwd
```

## 5. A finite Linux boundary

The portable C libc supplies allocation, strings, FILE operations,
formatting, and callbacks. The Forth compiler emits only the
kernel operations it needs: `exit`, `read`, `write`, `open`,
`close`, `lseek`, `unlink`, `mkdir`, `chmod`, `access`, `mprotect`,
`time`, and `gettimeofday`. These leaf functions have no frame,
so their first argument is at `rsp+8`.

`cc-native-syscall` moves arguments into Linux's registers and
issues `syscall`. Linux errors in the range −4095 through −1
become exactly −1, matching the portable libc's failure tests;
this boundary does not set `errno`. Wide results such as `lseek`
use signed 64-bit return types. The regression suite includes a
file position above 4 GiB to catch accidental truncation.

The initial TinyCC profile additionally enables
`cc-bootstrap-floatbits`. Its float, double, and long-double objects
use eight-byte integer bit transport. This is deliberately not
general IEEE floating arithmetic. The profile supplies exactly
three unavailable operations, `localtime`, `ldexp`, and `longjmp`,
as fail-closed bodies: name the unsupported operation on stderr
and exit 125. Successful bootstrap executions must avoid them;
we do not infer that the paths are unreachable.

Outside that restricted profile, floating types are rejected with
error 214, including types in casts, members, and skipped function
signatures. The three stub names have no bodies: ordinary references
are undefined-function error 206, while the usual `ldexp` declaration
is rejected earlier for its floating type. An arbitrary unknown
function is rejected in either mode. The fuller
reasoning and tests are in
[`tests/tcc/native-runtime.md`](https://github.com/delta9000/seed-forth/blob/master/tests/tcc/native-runtime.md).

```forth file=119-cc-native-runtime.fth
\ 119-cc-native-runtime.fth — Linux AMD64 primitives for the native ABI.
\ Every argument occupies an eight-byte caller-owned stack slot. These
\ leaf functions have no frame: argument one is at rsp+8, not in rdi.
\ Portable libc supplies FILE, allocation, strings, stdio and formatting.
\ Only its kernel boundary is emitted here; no SysV libc shim is linked.

create cc-native-name-exit     s, exit
create cc-native-name-read     s, read
create cc-native-name-write    s, write
create cc-native-name-open     s, open
create cc-native-name-close    s, close
create cc-native-name-lseek    s, lseek
create cc-native-name-unlink   s, unlink
create cc-native-name-mkdir    s, mkdir
create cc-native-name-chmod    s, chmod
create cc-native-name-access   s, access
create cc-native-name-mprotect s, mprotect
create cc-native-name-time     s, time
create cc-native-name-gettimeofday s, gettimeofday

\ cc-native-sysarg ( stack-byte-offset modrm -- )
\ MOV a full stack cell into a syscall argument register. Narrow C values
\ arrive extended by expression evaluation; pointers/size_t/off_t stay 64-bit.
: cc-native-sysarg
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  cc-emit-byte [lit] 36 cc-emit-byte cc-emit-byte ;

\ cc-native-syscall ( syscall-number argument-count -- )
\ Linux returns -errno in rax. Portable libc tests fd == -1, so turn
\ [-4095,-1] into -1. This bootstrap boundary does not maintain errno.
\ Unlike the old pnut boundary, an absent file therefore makes fopen fail
\ cleanly rather than allocating a FILE containing a negative errno.
: cc-native-syscall
  dup [lit] 0 > if, [lit] 8 [lit] 124 cc-native-sysarg then,
  dup [lit] 1 > if, [lit] 16 [lit] 116 cc-native-sysarg then,
  [lit] 2 > if, [lit] 24 [lit] 84 cc-native-sysarg then,
  [lit] 184 cc-emit-byte cc-emit-4le             \ mov eax, syscall-number
  [lit] 15 cc-emit-byte [lit] 5 cc-emit-byte     \ syscall
  [lit] 72 cc-emit-byte [lit] 61 cc-emit-byte
  [lit] 0 [lit] 4095 - cc-emit-4le              \ cmp rax, -4095
  [lit] 114 cc-emit-byte [lit] 7 cc-emit-byte    \ jb .ok (unsigned)
  [lit] 72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 192 cc-emit-byte
  [lit] 0 1- cc-emit-4le                        \ mov rax, -1
  [lit] 195 cc-emit-byte ;                      \ .ok: ret

\ cc-native-primitive ( name-addr name-len return-base syscall argc -- )
\ Register the real return type before parsing source prototypes. In
\ particular read/write/lseek return signed LP64 long, never 32-bit int.
: cc-native-primitive
  >r >r [lit] 0 ty-make sk-func swap cc-here-vaddr cc-sym-add drop
  r> r> cc-native-syscall ;

\ These three unavailable library paths are part of the measured seed-only
\ profile. Do not generalize this allow-list to arbitrary unresolved names.
\ Successful bootstrap builds must never execute one: each names the missing
\ operation on stderr and exits 125. Normal native mode does not define them.
create cc-native-name-localtime s, localtime
create cc-native-name-ldexp     s, ldexp
create cc-native-name-longjmp   s, longjmp
create cc-native-trap-prefix
  s, seed-forth [lit] 32 c, s, bootstrap: [lit] 32 c,
  s, unsupported [lit] 32 c,
here cc-native-trap-prefix - constant cc-native-trap-prefix-length
variable cc-native-trap-message
variable cc-native-trap-length

: cc-native-emit-raw ( addr len -- )
  begin, dup while,
    over c@ cc-emit-byte swap 1+ swap 1-
  repeat, 2drop ;

: cc-native-unavailable ( name-addr name-len return-type -- )
  >r 2dup
  cc-here-vaddr cc-native-trap-message !
  cc-native-trap-prefix cc-native-trap-prefix-length cc-native-emit-raw
  cc-native-emit-raw [lit] 10 cc-emit-byte
  dup cc-native-trap-prefix-length 1+ + cc-native-trap-length !
  sk-func r> cc-here-vaddr cc-sym-add drop
  [lit] 184 cc-emit-byte [lit] 1 cc-emit-4le       \ mov eax, SYS_write
  [lit] 191 cc-emit-byte [lit] 2 cc-emit-4le       \ mov edi, stderr
  [lit] 72 cc-emit-byte [lit] 190 cc-emit-byte
  cc-native-trap-message @ cc-emit-8le            \ movabs rsi, message
  [lit] 186 cc-emit-byte cc-native-trap-length @ cc-emit-4le
  [lit] 15 cc-emit-byte [lit] 5 cc-emit-byte       \ syscall
  [lit] 184 cc-emit-byte [lit] 60 cc-emit-4le      \ mov eax, SYS_exit
  [lit] 191 cc-emit-byte [lit] 125 cc-emit-4le     \ mov edi, 125
  [lit] 15 cc-emit-byte [lit] 5 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 11 cc-emit-byte ;    \ ud2: never return

: cc-native-runtime
  cc-native-name-exit     [lit] 4 ty-void [lit] 60 [lit] 1 cc-native-primitive
  cc-native-name-read     [lit] 4 ty-long [lit] 0 [lit] 3 cc-native-primitive
  cc-native-name-write    [lit] 5 ty-long [lit] 1 [lit] 3 cc-native-primitive
  \ open's third stack slot contains mode for O_CREAT/O_TMPFILE. Linux
  \ ignores that slot for a two-argument open without those flags.
  cc-native-name-open     [lit] 4 ty-int [lit] 2 [lit] 3 cc-native-primitive
  cc-native-name-close    [lit] 5 ty-int [lit] 3 [lit] 1 cc-native-primitive
  cc-native-name-lseek    [lit] 5 ty-long [lit] 8 [lit] 3 cc-native-primitive
  cc-native-name-unlink   [lit] 6 ty-int [lit] 87 [lit] 1 cc-native-primitive
  cc-native-name-mkdir    [lit] 5 ty-int [lit] 83 [lit] 2 cc-native-primitive
  cc-native-name-chmod    [lit] 5 ty-int [lit] 90 [lit] 2 cc-native-primitive
  cc-native-name-access   [lit] 6 ty-int [lit] 21 [lit] 2 cc-native-primitive
  cc-native-name-mprotect [lit] 8 ty-int [lit] 10 [lit] 3 cc-native-primitive
  cc-native-name-time     [lit] 4 ty-long [lit] 201 [lit] 1 cc-native-primitive
  cc-native-name-gettimeofday [lit] 12 ty-int [lit] 96 [lit] 2 cc-native-primitive
  cc-bootstrap-floatbits @ if,
    cc-native-name-localtime [lit] 9 ty-struct [lit] 1 ty-make cc-native-unavailable
    cc-native-name-ldexp [lit] 5 ty-double [lit] 0 ty-make cc-native-unavailable
    cc-native-name-longjmp [lit] 7 ty-void [lit] 0 ty-make cc-native-unavailable
  then, ;
' cc-native-runtime is cc-native-runtime-fwd
```

## 6. What the bootstrap result proves

The default route begins with raw pinned inputs, not an expanded
TinyCC tree. Host setup verifies/copies the original archive, libc,
and helper sources. The seed builds the recipe runner, then Forth
compiles raw portable libc together with the exact-patch and archive
helper sources. Those generated tools unpack the archive's 400
regular files and apply the exact kit, amd64, and libc replacements.
The recipe checks 440 prepared-file pins: 439 source files and
their manifest. This restores the raw-archive boundary without a
pnut compiler executable.

The host `prep-stage-sources.py` helper remains a separate oracle
for focused tests and independent verification. It extracts and
patches source in that workflow, but supplies nothing to the
default `tools/tcc-ladder-start.fth` route. Neither workflow feeds
host-preprocessed C to Forth.

The prepared input then goes through the actual Forth preprocessor,
parser, instruction emitter, and ELF writer. The resulting seed is
870,752 bytes, SHA-256
`7411c326d30ff5a0ebadfe36d6218b6e46d2e8357f76d3a003e74ed9aee2fc3a`.
That intermediate is not the final full TinyCC.

A fresh downstream run executes forty generated compiler/runtime
programs to build the boot stages and check their products. It
reaches byte-identical `tcc-boot2` and `tcc-boot3` executables and
objects, matching the existing control pins. The final executable
hash is
`514bc4d3af6b79d2fc99d1178933f3e2ee093ff7ce7362d92dc81708f13fa5c1`.
All 136 portable-libc checks pass. Separate acceptance programs
exercise real float, double, and long-double arithmetic, bitfields,
variable-length arrays, and block-scope enums in rebuilt TinyCC.
These tests establish that the seed's restricted float transport
has not been mistaken for the final compiler's language support.

The raw-input host recipe now passes end to end. A separate, earlier
prepared-source test also rebuilds the product in a fresh root with
no `/bin` or `/usr` and no prebuilt compiler, preserving every input
hash. That narrower test starts after extraction/patching. Its stronger
exec-syscall audit reports SKIP here because tracing is denied; an
isolated build success is not an audited-gate PASS.

A separate fresh raw-input K0 → K1 guest run passed under QEMU TCG.
K0 built the helpers and TinyCC from raw sources, compiled K1 with
that generated TinyCC, and handed off. K1 rebuilt the seed through
hex0 and repeated the raw-helper, TinyCC fixed-point, and runtime
sequence. The wrapper and guest init both report success. The full
GNU/Linux continuation is not established by this check. A separate longer
attempt was interrupted before completion; its full result remains unverified.

Source preparation, compilation, fixed-point equality, and
executable-closure auditing are distinct claims. See the exact
commands and boundary in [`tests/tcc/README.md`](https://github.com/delta9000/seed-forth/blob/master/tests/tcc/README.md),
and the pins in [`REPRODUCIBLE.md`](https://github.com/delta9000/seed-forth/blob/master/REPRODUCIBLE.md).

## Try it

From the repository root, build and run a small LP64 program and
an eight-argument/function-pointer program:

```sh
./build.sh
tests/tcc/compile-native.sh tests/tcc/native-basics.c build-out/native-basics
./build-out/native-basics
tests/tcc/compile-native.sh tests/tcc/native-stack-call.c build-out/native-stack-call
./build-out/native-stack-call
```

Both programs exit zero. The driver takes `SOURCE OUTPUT` followed
by optional include directories. For normal native programs leave
`SF_NATIVE_FLOATBITS` unset; the restricted initial TinyCC build
uses `SF_NATIVE_FLOATBITS=1`. The complete staged-source recipe is
in the linked test README. The commands above test the compiler
profile without claiming a whole-chain proof.

## Exercises

1. **★** Trace an `int` parameter and a `long` parameter from their
   caller's stack slots to their typed loads. Why do equal slot
   widths not imply equal object widths?
2. **★★** Run `tests/tcc/native-runtime-check.sh`, then explain why
   a missing-file result must be normalized before portable libc's
   `fopen` sees it.
3. **★★** Follow a static pointer initializer referring to a later
   global. Identify the initializer routine, the global fixup, and
   the entry call that makes the initialized value visible to `main`.
4. **★★★** Design an aggregate-by-value extension. Specify its
   caller and callee layout and rejection tests before changing the
   parser; compare it with TinyCC's own target ABI.

## Takeaways

- LP64 storage and a private all-stack ABI let the Forth compiler directly compile the pinned TinyCC and portable-libc profile while preserving the legacy default.
- Initializers reuse ordinary fixups, and the small native runtime makes its unsupported seed-only operations fail visibly.
- A working seed, a rebuilt full compiler, a fixed point, and a source-only execution proof are separate results with separate checks.

Next: the appendices give reference cards for the seed, compiler,
reproducibility checks, supported profiles, and diagnostics.
