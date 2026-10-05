# Chapter 29 — Declarations: Types, Structs, Locals

```text
Missing capability: declarations cannot create types, structs, locals, or file-scope symbols.
New pattern: parse base types and declarators into symbol rows, with pre-registration for recursive structs.
Artifact after this chapter: declaration parsing for scalar types, pointers, arrays, structs, and locals.
Proof link: Stage-A decls populate the type and symbol database before statements and functions consume it.
```

Before the statement and expression parsers can use a name, something
has to turn `int x;`, `char* s;`, `int arr[8];`, `int (*fp)(int);`, or
`struct T* p;` into a symbol-table row with the right type word, frame
slot, and array length or struct descriptor (Ch 24 §3).  M2-Planet also leans on structs
that point to their own type, so a struct's tag has to be usable
before its body has finished parsing.

That machinery is `110-cc-decl.fth` (790 lines), the first of the
four files that make up the parser.  This chapter reads all of it.
The other three follow it in load order and each has its own
chapter: `112-cc-stmt.fth` holds the statements (Ch 30), and
`114-cc-func.fth` (function definitions) and `116-cc-prog.fth`
(enums, typedefs, globals, the entry stub, and the top-level
driver) are Ch 31's.

---

## 1. File header and bookkeeping

```forth file=110-cc-decl.fth
\ 110-cc-decl.fth — declaration parser for the C-subset compiler.
\
\ Parses base types, struct definitions, and local declarations (scalars,
\ pointers, arrays, function pointers, struct locals) for the C subset needed
\ to compile M2-Planet, plus the `return` statement.  The rest of the parser
\ follows in load order: statements in 112-cc-stmt.fth, function definitions
\ in 114-cc-func.fth, and file-scope forms, the entry stub, and the top-level
\ driver in 116-cc-prog.fth.
\
\ Depends on 010-lib.fth, 030-cc-io.fth, 050-cc-lex.fth, 060-cc-types.fth, 070-cc-sym.fth,
\ 080-cc-elf.fth, 090-cc-emit.fth, 100-cc-expr.fth.

\ ===========================================================================
\ Bookkeeping
\ ===========================================================================

defer cc-native-type-name-fwd
defer cc-native-decl-fwd
defer cc-native-type-start-fwd
\ Native declarations use dynamically sized frames, patched after the body.
variable cc-native-return-type
variable cc-native-return-desc
variable cc-type-name-array
variable cc-type-name-inner
\ Declaration spelling and executable value support are separate decisions.
: cc-native-float-types-default cc-bootstrap-floatbits @ ;
defer cc-native-float-types-fwd
' cc-native-float-types-default is cc-native-float-types-fwd
variable cc-native-frame-limit
[lit] 131072 cc-native-frame-limit !

variable cc-main-vaddr                            \ vaddr where main starts
variable cc-call-main-patch                       \ file-offset of rel32 to patch
variable cc-fn-local-count                        \ # locals in current function

\ Every function gets the same frame: cc-frame-slots 8-byte slots below rbp,
\ shared by its parameters and every local in every block of its body (a
\ slot is never reused).  cc-fn-add-slots ( n -- ) claims the next n; the
\ one that would pass the frame's end dies with code 162 instead of
\ silently overlapping the stack below it.
[lit] 32 constant cc-frame-slots
: cc-fn-add-slots
  dup cc-fn-local-count @ +
  cc-target-lp64 @ if, cc-native-frame-limit @ else, cc-frame-slots then,
  [lit] 162 cc-check-cap
  cc-fn-local-count +! ;

\ cc-pending-struct-desc is set by cc-parse-base-type when it parses a
\ `struct TAG` base, and consumed by cc-parse-decl / cc-parse-param-list when
\ they record the symbol-table entry (so the struct descriptor pointer ends
\ up in the symbol's struct-desc cell).  For non-struct types it stays at 0.
variable cc-pending-struct-desc

```

The header names the three files that complete the parser.  The
bookkeeping variables are shared across
function definitions.  `cc-fn-local-count` is the next free local
slot; every declaration parser in this chapter allocates from it
through `cc-fn-add-slots`, which refuses (code 162) to hand out a
slot past the frame's 32 (Ch 31 §3).
`cc-pending-struct-desc` carries a struct descriptor from the
base-type parser to whichever parser eventually calls `cc-sym-add`,
so the pointer ends up in the symbol's struct-desc cell.

## 2. Expectation helpers and ignored specifiers

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Token-expectation helpers
\ ===========================================================================

\ Each error path dies through cc-die with its own code, so a failure names
\ its site.  This file's codes are 140..169; 112, 114 and 116 have
\ 170..179, 180..189 and 190..219 (Appendix G).

\ cc-expect-kw-id ( kw-id -- )  Consume one token; abort if not the given kw.
: cc-expect-kw-id
  cc-next-token-keep
  tok-kind @ tk-kw <> if,
    drop
    [lit] 140 cc-die
  then,
  tok-kw-id @ <> if,
    [lit] 141 cc-die
  then, ;

\ cc-expect-punct-c ( char -- )  Consume one token; abort if not that punct.
: cc-expect-punct-c
  cc-next-token-keep
  tok-kind @ tk-punct <> if,
    drop
    [lit] 142 cc-die
  then,
  tok-num @ <> if,
    [lit] 143 cc-die
  then, ;

\ cc-expect-ident ( -- )  Consume one token; abort if not tk-ident.
: cc-expect-ident
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 144 cc-die
  then, ;

```

`cc-expect-kw-id`, `cc-expect-punct-c`, and `cc-expect-ident` are the
file's "consume one token and check it" idiom.  Each failure has its
own code: 140/141 for the keyword pair, 142/143 for punctuation,
144 for an identifier (this file owns 140–169; Ch 30's
statements, Ch 31's functions and the program driver have 170–179,
180–189 and 190–219).  When a compile dies, `cc-die` prints
`cc: line N: error C` on stderr and exits with status C, a number you
can grep for in those files.

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Statement parsing
\ ===========================================================================

\ cc-qualifier? ( -- f )  True if the current token is a type qualifier
\ (const / volatile / restrict).  They change nothing in this subset, so
\ every place that reads a type skips them.
: cc-qualifier?
  tok-kind @ tk-kw =
    tok-kw-id @ kw-const    =
    tok-kw-id @ kw-volatile = or
    tok-kw-id @ kw-restrict = or
  and ;

\ cc-skip-qualifiers ( -- )  Read past any qualifiers; the first token that
\ isn't one is left pending.
: cc-qual-note-noop ;
defer cc-qual-note
' cc-qual-note-noop is cc-qual-note
variable cc-prefix-qualified
variable cc-type-name-qualified

: cc-skip-qualifiers
  begin,
    cc-next-token-keep cc-qualifier?
  while, cc-qual-note
  repeat,
  cc-putback-token ;

\ cc-count-stars ( -- depth )  After consuming a base type (e.g. 'int'), peek
\ zero or more '*' tokens and return the resulting pointer depth.  A
\ qualifier may follow each '*' (`char * const msg`).  Leaves the first
\ other token pending for the caller.
: cc-count-stars                                  ( -- depth )
  [lit] 0
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] * = and
  while,
    1+ cc-skip-qualifiers
  repeat,
  cc-putback-token ;

\ Skip storage-class specifiers (static / extern / auto / register) and
\ type qualifiers (const / volatile / restrict).  Reads tokens via
\ cc-next-token-keep; whenever one of these keywords is seen, it's consumed
\ and the loop continues.  When a non-qualifier is encountered it is put back
\ so the caller sees it as the next token.
\
\ Only `static` matters: cc-decl-static records whether it was seen, and a
\ local declared static gets file-scope storage instead of a frame slot
\ (cc-parse-local-declarator).  The rest are no-ops.
variable cc-decl-static
variable cc-decl-extern

: cc-skip-storage-quals
  [lit] 0 cc-prefix-qualified !
  [lit] 0 cc-decl-static ! [lit] 0 cc-decl-extern !
  begin,
    cc-next-token-keep
    cc-qualifier? if, true cc-prefix-qualified ! then,
    kw-static cc-tok-kw? if, true cc-decl-static ! then,
    kw-extern cc-tok-kw? if, true cc-decl-extern ! then,
    tok-kind @ tk-kw =
      tok-kw-id @ kw-static    =
      tok-kw-id @ kw-extern    = or
      tok-kw-id @ kw-auto      = or
      tok-kw-id @ kw-register  = or
      tok-kw-id @ kw-inline    = or
      tok-kw-id @ kw-const     = or
      tok-kw-id @ kw-volatile  = or
      tok-kw-id @ kw-restrict  = or
    and
  while,
    \ already consumed; just loop
  repeat,
  cc-putback-token ;

\ cc-skip-enum-tag ( -- )  The current token is `enum` used as a type
\ (`enum BINDING kind`): consume the tag.  An enum's values are ints, so
\ the type is int.
: cc-skip-enum-tag
  cc-next-token-keep
  tok-kind @ tk-ident <> if, cc-putback-token then, ;

```

`cc-count-stars` reads zero or more `*` tokens after a base type,
returns the count, and puts back the first token that isn't a `*`.
Every pointer-depth calculation in the file goes through it.  (The
"Statement parsing" banner above it is a leftover; the statements
start in Ch 30.)  A qualifier may follow any `*`, as in pnut's
`char * const msg`, so the loop skips them with `cc-skip-qualifiers`;
`cc-qualifier?` recognises `const`, `volatile` and `restrict`, and
every place in the parser that reads a type skips them, since the
type system has no `const`.

`cc-skip-storage-quals` consumes `static`, `extern`, `auto`,
`register` and the qualifiers.  Only one of them changes anything:
`static` sets `cc-decl-static`, and a `static` local gets file-scope
storage (§4).  `extern` needs no flag: a global declared twice is one
variable (Ch 31 §7).  `cc-skip-enum-tag` handles `enum TAG` used as a
type, as in pnut's `enum BINDING kind`: an enum's values are ints, so
the tag is read and dropped and the type is `int`.

## 3. Struct definitions

A struct definition builds a descriptor (the layout from Ch 24 §1)
one field at a time.  The scratch globals hold the field being built,
and `cc-sd-append-field` copies it into the next field record:

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Struct definition and base-type parsing.
\ ===========================================================================

\ Scratch globals used while building one struct descriptor.  cc-parse-struct-
\ def runs single-threaded (no recursion / nested struct defs), so a
\ single set of globals is enough — they're saved here and read back when the
\ field loop body needs them.
variable cc-sd-build-desc                         \ descriptor under construction
variable cc-sd-build-fname-a
variable cc-sd-build-fname-u
variable cc-sd-build-field-ty
variable cc-sd-build-field-desc                   \ pointee desc for struct-ptr fields (0 if none)

\ cc-sd-append-field ( -- )  Append the field whose name is in cc-sd-build-
\ fname-{a,u}, type in cc-sd-build-field-ty, pointee descriptor in
\ cc-sd-build-field-desc, to the descriptor in cc-sd-build-desc.  Assigns
\ offset = total-size BEFORE this field, then bumps total-size by 8.  This
\ subset stores every field in an 8-byte slot.  Increments field-count.
: cc-sd-append-field                              ( -- )
  cc-sd-build-desc @ cc-sd-field-count            ( i )
  cc-sd-build-desc @ swap cc-sd-field-rec         ( rec )
  cc-sd-build-fname-a @ over cc-sf-set-name-addr
  cc-sd-build-fname-u @ over cc-sf-set-name-len
  cc-sd-build-field-ty @ over cc-sf-set-type
  cc-sd-build-field-desc @ over cc-sf-set-desc
  cc-sd-build-desc @ cc-sd-total-size swap cc-sf-set-offset
  \ Increment field-count and total-size by 8.
  cc-sd-build-desc @ cc-sd-field-count 1+
  cc-sd-build-desc @ cc-sd-set-field-count
  cc-sd-build-desc @ cc-sd-total-size [lit] 8 +
  cc-sd-build-desc @ cc-sd-set-total-size ;

```

The new field's offset is the descriptor's current `total-size`;
then `field-count` goes up by one and `total-size` by 8.  Every field
gets an 8-byte slot whatever its declared type.

Field types and struct locals both need to turn a tag name into a
descriptor.  There are two lookups:

```forth file=110-cc-decl.fth
\ cc-parse-struct-def ( -- )  Called with the 'struct' keyword ALREADY consumed
\ (it's the current token).  Handles ONLY the definition form:
\
\    struct TAG '{' (field-decl)* '}' ';'
\
\ Registers TAG in the symbol table as sk-struct with val = descriptor pointer.
\ Descriptor layout: see 060-cc-types.fth.
\ cc-lookup-struct-tag ( -- desc )  Reads an IDENT token (must be the current
\ position; will be advanced past), looks it up as sk-struct in the symbol
\ table, returns the descriptor pointer.  Aborts on lookup failure.
: cc-lookup-struct-tag                            ( -- desc )
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 145 cc-die
  then,
  tok-str-addr @ tok-str-len @ cc-sym-find-tag        ( id-or-neg1 )
  dup 0< if,
    drop
    [lit] 146 cc-die
  then,
  dup cc-sym-kind-of sk-struct <> if,
    drop
    [lit] 147 cc-die
  then,
  cc-sym-val-of ;                                  \ descriptor pointer

\ cc-lookup-struct-tag-soft ( -- desc-or-0 )  Like cc-lookup-struct-tag, but
\ returns 0 if the tag isn't found or isn't registered as a struct.  Lets the
\ parser tolerate opaque/incomplete struct references in headers that declare
\ but don't define the struct (e.g. cc_globals.c's `struct type* foo;`).
: cc-lookup-struct-tag-soft                       ( -- desc-or-0 )
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 148 cc-die
  then,
  tok-str-addr @ tok-str-len @ cc-sym-find-tag        ( id-or-neg1 )
  dup 0< if,
    drop [lit] 0
  else,
    dup cc-sym-kind-of sk-struct <> if,
      drop [lit] 0
    else,
      cc-sym-val-of
    then,
  then, ;

```

(The comment for `cc-parse-struct-def` sits at the top of this block,
merged into the comment for `cc-lookup-struct-tag`.)  The strict
lookup dies with code 145–147 on a missing or non-struct tag.  The
soft lookup returns 0 instead, which lets a header mention
`struct type*` without defining it.

```forth file=110-cc-decl.fth
: cc-parse-struct-def                             ( -- )
  \ Expect IDENT tag.
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 149 cc-die
  then,
  \ Snapshot tag bytes on data stack (rstack would be clobbered by ';' etc.).
  tok-str-addr @ tok-str-len @                    ( tag-addr tag-len )
  \ Expect '{'.
  [char] { cc-expect-punct-c

  \ Allocate a zeroed descriptor; its field table grows as fields arrive.
  cc-sd-alloc cc-sd-build-desc !                  ( tag-addr tag-len )

  \ Pre-register the struct tag (with the still-empty descriptor) BEFORE
  \ parsing the body, so self-referential field types `struct T* next` can
  \ resolve their own tag.  We snapshot tag-addr/tag-len off-stack via 2>r so
  \ the symbol-add doesn't disturb the stack layout the loop expects.
  over over                                       ( tag-a tag-u tag-a tag-u )
  sk-struct
  [lit] 0
  cc-sd-build-desc @
  cc-sym-add drop                                 ( tag-a tag-u )

  \ Field-parsing loop.  Each iteration parses `T '*'* IDENT ;` where T is
  \ one of: int / char / void / struct TAG / IDENT (typedef-name).  All
  \ fields are 8 bytes in our codegen, so the *type* is mostly cosmetic;
  \ what matters is correctness of name+offset.
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] } = and 0=
  while,
    cc-putback-token
    \ Parse base type.  Default the pointee-descriptor to 0; the struct-tag
    \ branch overrides when the field is `struct TAG ...`.
    [lit] 0 cc-sd-build-field-desc !
    cc-skip-qualifiers
    cc-next-token-keep
    tok-kind @ tk-kw = if,
      tok-kw-id @ kw-int     = if, ty-int  cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-char    = if, ty-char cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-void    = if, ty-void cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-enum    = if,
        cc-skip-enum-tag ty-int cc-sd-build-field-ty !
      else,
      tok-kw-id @ kw-struct  = if,
        \ Look up the tag's descriptor (soft — self-referential `struct T*
        \ next` inside `struct T {...}` works because cc-parse-struct-def
        \ pre-registers the tag with a still-empty descriptor before parsing
        \ fields, and forward refs return 0).  Stored in the field record so
        \ chained '->' can propagate the type.
        cc-lookup-struct-tag-soft cc-sd-build-field-desc !
        ty-struct cc-sd-build-field-ty !
      else,
        [lit] 150 cc-die
      then, then, then, then, then,
    else,
      \ tk-ident — treat as typedef-name used as a type.  Record as int
      \ (we only care about the storage size = 8).
      tok-kind @ tk-ident <> if,
        [lit] 151 cc-die
      then,
      ty-int cc-sd-build-field-ty !
    then,

    cc-count-stars                                ( ... ptr-depth )
    \ Re-pack the type word with the ptr-depth.
    cc-sd-build-field-ty @ swap ty-make cc-sd-build-field-ty !

    \ Read field name.
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 152 cc-die
    then,
    tok-str-addr @ cc-sd-build-fname-a !
    tok-str-len  @ cc-sd-build-fname-u !
    [char] ; cc-expect-punct-c
    cc-sd-append-field
  repeat,
  \ '}' was the loop test; we consumed it via cc-next-token-keep but DIDN'T
  \ putback this time (the test went 0=, so we entered the exit path).
  \ Expect ';' after '}'.
  [char] ; cc-expect-punct-c
  drop drop ;                                     \ discard tag-a tag-u

```

`cc-parse-struct-def` handles `struct TAG { … };`.  It allocates a
descriptor header (Ch 24 §1), then calls `cc-sym-add` for the tag *before*
reading any field.  When a field later declares `struct T* next;`,
`cc-lookup-struct-tag-soft` finds the tag and returns the
still-empty descriptor pointer, which goes into the field record.
The field loop fills that same descriptor in place, so by the closing
`}` every `next` field points at a complete descriptor.

The field loop dispatches on the base type, after skipping any
qualifiers.  `int`, `char`, and `void` set a plain type word, and so
does `enum TAG` (an int); `struct` looks up the tag's descriptor
and records it as the field's pointee; an identifier is taken as a
typedef name and recorded as `ty-int`, since only the 8-byte slot
matters.  `cc-count-stars` supplies the pointer depth, and `ty-make`
packs it into the type word.

## 4. Function pointers and the declaration engine

`int (*fp)(int);` reads like `int x;` for one token and then turns
into something else.  The parser needs to see both `(` and `*` before
committing, which is one token more than the putback layer from
Ch 27 can give back.  So this code snapshots the entire lexer state:

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Function-pointer declaration parsing.
\ ===========================================================================
\ A function-pointer decl has the shape:
\
\    RETURN_TYPE '(' '*' NAME ')' '(' PARAM_TYPES ')' (= expr)? ';'
\
\ Detection: after the base type is parsed, we need 2-token lookahead to
\ distinguish `int (*fp)(int);` from `int x;` and `int *p;`.  Putback holds
\ only one token, so we mark the lexer state in cc-peek-mark (050-cc-lex.fth),
\ read ahead, and reset to the mark.

\ cc-peek-fnptr? ( -- f )  Look ahead 2 tokens; -1 iff we see '(' then '*'.
\ The first may be a token put back (the mark saves the putback flag too).
\ Always restores the lexer state so the caller resumes at the original
\ position regardless of the result.
: cc-peek-fnptr?
  cc-peek-mark cc-lex-mark
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ lparen = and 0= if,
    cc-peek-mark cc-lex-reset
    [lit] 0
  else,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] * = and
    cc-peek-mark cc-lex-reset
  then, ;

```

`cc-peek-fnptr?` marks the lexer state in `cc-peek-mark` (Ch 23 §7),
reads up to two tokens, tests for `(` then `*`, and resets to the mark
on both paths.  The caller gets a flag and a lexer that hasn't moved.
It reads with `cc-next-token-keep`, so the first of the two may be a
token that was put back: after `unsigned long`, `cc-more-type-kws`
has read one token too many and put it back, and the mark saves the
putback flag with everything else.
`cc-peek-mark` is the only mark buffer in the parser: every look-ahead
that uses it reads only tokens between marking and resetting, so no
second look-ahead can start while one is in progress.

```forth file=110-cc-decl.fth
\ cc-skip-fnptr-params ( -- )  Skip everything from the current position
\ through the matching ')'.  Uses paren-depth counter starting at 1
\ (the opening '(' has just been consumed).  Tokens are consumed one at
\ a time via cc-next-token-keep so cc-tok-pending is left clear at exit.
: cc-skip-fnptr-params
  [lit] 1
  begin,
    dup [lit] 0 >
  while,
    cc-next-token-keep
    tok-kind @ tk-eof = if, [lit] 184 cc-die then,
    cc-target-lp64 @ cc-native-float-types-fwd 0= and if,
      kw-float cc-tok-kw? kw-double cc-tok-kw? or if, [lit] 214 cc-die then,
    then,
    tok-kind @ tk-punct = if,
      tok-num @ lparen = if, 1+ then,
      tok-num @ [char] ) = if, 1- then,
    then,
  repeat,
  drop ;

\ cc-parse-fnptr-decl ( -- )  The base type has been consumed by the caller;
\ the next two tokens are '(' and '*'.  Parses
\
\    '(' '*' NAME ')' '(' PARAM_TYPES ')' ('=' expr)? ';'
\
\ and registers NAME as an sk-local with type ty-func + ptr-depth=1.  The
\ parameter types are skipped; signatures are not validated.
: cc-parse-fnptr-decl
  \ Consume '(' and '*'.
  lparen cc-expect-punct-c
  [char] * cc-expect-punct-c

  \ NAME (IDENT).
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 153 cc-die
  then,
  tok-str-addr @ tok-str-len @                    ( name-a name-u )

  \ ')' '(' PARAM-TYPES ')'
  [char] ) cc-expect-punct-c
  lparen cc-expect-punct-c
  cc-skip-fnptr-params

  \ Register as an sk-local function pointer: ty-func + ptr-depth=1.
  sk-local
  ty-func [lit] 1 ty-make                         ( a u kind type )
  cc-fn-local-count @                             ( a u kind type slot )
  cc-sym-add drop
  [lit] 1 cc-fn-add-slots

  \ Optional '= expr;' initializer.
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] = = and if,
    cc-parse-expr
    cc-fn-local-count @ 1- cc-emit-store-local
    [char] ; cc-expect-punct-c
  else,
    tok-kind @ tk-punct = tok-num @ [char] ; = and 0= if,
      [lit] 154 cc-die
    then,
  then, ;

variable cc-decl-base                              \ base type kind

\ cc-parse-local-declarator ( init-ptr -- )  One declarator of a local
\ declaration whose base type is in cc-decl-base: '*'* NAME, then
\ '[' SIZE ']' or ('=' EXPR)? .  SIZE is a constant expression.  Ends with
\ the token after the declarator read (the caller wants ',' or ';').
\ init-ptr is non-zero only when the base came from a pointer-typed
\ typedef (`typedef int* int_ptr;`).
\
\ An array's element 0 sits in its deepest slot.  A `static` local
\ (cc-decl-static) gets file-scope storage instead of frame slots, so it
\ keeps its value between calls: the symbol is an sk-global that only
\ this block can see, an array in the bss, a scalar in the data area with
\ its constant initializer.
: cc-parse-local-declarator                       ( init-ptr -- )
  cc-count-stars +                                 ( ptr-depth )
  cc-expect-ident
  tok-str-addr @ tok-str-len @ rot                 ( a u ptr-depth )
  cc-decl-base @ swap ty-make                      ( a u type )
  cc-next-token-keep
  [char] [ cc-tok-punct? if,
    \ -------- Array: T name [ N ] --------
    cc-parse-const                                 ( a u type N )
    dup [lit] 0 <= if, [lit] 156 cc-die then,
    cc-next-token-keep
    [char] ] cc-tok-punct? 0= if, [lit] 157 cc-die then,
    >r                                             ( a u type ; R: N )
    cc-decl-static @ if,
      sk-global swap  r@ [lit] 8 * cc-bss-alloc    ( a u kind type slot )
    else,
      sk-local swap  cc-fn-local-count @ r@ + 1-
    then,
    cc-sym-add                                     ( id ; R: N )
    r@ swap cc-sym-set-array-len
    cc-decl-static @ 0= if, r@ cc-fn-add-slots then,
    r> drop
    cc-next-token-keep exit,
  then,
  \ -------- Scalar: T name ('=' expr)? --------
  cc-decl-static @ if,
    sk-global swap  [lit] 8 cc-globals-alloc       ( a u kind type slot )
    dup >r cc-sym-add drop                         ( ; R: slot )
    [char] = cc-tok-punct? if,
      cc-parse-const r@ cc-globals-store-8le
      cc-next-token-keep
    then,
    r> drop exit,
  then,
  sk-local swap  cc-fn-local-count @               ( a u kind type slot )
  cc-sym-add drop
  [lit] 1 cc-fn-add-slots
  [char] = cc-tok-punct? if,
    cc-parse-expr
    cc-fn-local-count @ 1- cc-emit-store-local
    cc-next-token-keep
  then, ;

```

Once the peek says yes, `cc-parse-fnptr-decl` consumes `(`, `*`, the
name, `)`, and `(`, then `cc-skip-fnptr-params` counts parentheses
until the parameter list closes.  The name becomes an `sk-local`
whose type is `ty-func` with pointer depth 1.  Parameter types are
skipped, not checked.  That type is what Ch 28's `cc-parse-primary`
tests to accept an indirect call.

```forth file=110-cc-decl.fth
\ cc-parse-decl-with-base ( base initial-ptr -- )
\ A local declaration after its base type: one or more declarators
\ separated by ',', then ';' (else die 159).  The caller has consumed the
\ keyword or typedef-name that gave the base type, and supplies (base,
\ initial-ptr-depth).
\
\ If the next two tokens after the base are '(' '*', dispatch to
\ cc-parse-fnptr-decl instead (function-pointer declaration).
: cc-parse-decl-with-base                         ( base init-ptr -- )
  swap cc-decl-base !                              ( init-ptr )
  \ Detect function-pointer decl shape.  Only when there are no leading
  \ stars from the caller (init-ptr=0) — `int* (*fp)()` is a func-ptr returning
  \ int*, which is outside this subset.
  dup [lit] 0 = cc-peek-fnptr? and if,
    drop cc-parse-fnptr-decl exit,
  then,
  begin,
    dup cc-parse-local-declarator                  ( init-ptr )
```

`cc-parse-decl-with-base` takes the base type and an initial pointer
depth (non-zero only for a pointer typedef).  With no leading stars
it tries the function-pointer peek first.  Otherwise it parses
declarators separated by commas, `int a = 1, *b, c[4];`, until the
`;` (code 159 if something else ends them).  `cc-parse-local-declarator`
does one: it counts stars, reads the name, and looks at the next token:

- `[` starts an array.  The size is a constant expression (Ch 28 §9),
  `int buf[N * 2]`, and must be positive (code 156).  The symbol's
  slot is the *last* of the N slots it reserves, and N goes in as the
  array length (`cc-sym-set-array-len`) so Ch 28 can tell an array
  from a scalar.
- Anything else is a scalar: one slot, and an optional `= expr`
  whose value is stored with `cc-emit-store-local`.

A `static` local is different: its value must outlive the call, so it
cannot live in the frame.  It gets file-scope storage instead, a data
slot (Ch 26 §5) for a scalar, whose initializer must then be a
constant and is written into the data area once, or the bss for an
array.  Its symbol is an `sk-global` added in the block's scope, so
only the block can name it; when the scope ends the name goes, the
storage stays.  `tests/cc/K-static-local.c` counts calls with one,
with other calls in between that reuse the stack; when `static` was
ignored, the count came out as whatever the stack held.

```forth file=110-cc-decl.fth
    [char] , cc-tok-punct?
  while,
  repeat,
  drop
  [char] ; cc-tok-punct? 0= if,
    [lit] 159 cc-die
  then, ;

\ cc-tok-is-basic-type-kw? ( -- f )  -1 iff current token is a basic-type
\ keyword that introduces a local declaration: int / char / void / long /
\ short / unsigned / signed.  All are treated as 8-byte slot in codegen.
: cc-tok-is-basic-type-kw?
  tok-kind @ tk-kw =
    tok-kw-id @ kw-int      =
    tok-kw-id @ kw-char     = or
    tok-kw-id @ kw-void     = or
    tok-kw-id @ kw-long     = or
    tok-kw-id @ kw-short    = or
    tok-kw-id @ kw-unsigned = or
    tok-kw-id @ kw-signed   = or
  and ;

\ cc-more-type-kws ( base -- base' )  After a basic-type keyword, read any
\ more (`unsigned int`, `long long`, `unsigned char`): they all name the
\ one 8-byte integer, except that a char among them makes the type char.
: cc-more-type-kws
  begin,
    cc-next-token-keep cc-tok-is-basic-type-kw?
  while,
    kw-char cc-tok-kw? if, drop ty-char then,
  repeat,
  cc-putback-token ;

\ cc-parse-decl ( -- )  Entry from cc-parse-stmt.  The basic-type kw is
\ the current token (still in tok-*); pick ty-char for `char`, ty-int for the
\ rest (int / long / short / unsigned / signed), then read any further type
\ keywords.  ty-char matters because the
\ array-index path uses base==ty-char + ptr-depth==1 to decide on a byte-wide
\ load/store for `s[i]` where s is `char*` — without this distinction every
\ char pointer is treated like an int pointer (qword stride / qword load).
\ void as a local doesn't make sense; it would have been rejected anyway.
: cc-parse-decl
  tok-kw-id @ kw-char = if,
    ty-char
  else,
    ty-int
  then,
  cc-more-type-kws
  [lit] 0 cc-parse-decl-with-base ;

```

`cc-parse-decl` is the entry from the statement parser.  It maps
`char` to `ty-char` and every other basic type to `ty-int`.  The
distinction matters: Ch 28's subscript code uses base `char` with
pointer depth 1 to choose byte-wide loads and stores for `s[i]`.
`cc-tok-is-basic-type-kw?` is the test the statement dispatcher uses
to decide that a statement is a declaration, and `cc-more-type-kws`
reads the keywords that may follow the first (`unsigned long x`,
`long long n`, `unsigned char c`): they all name the one 8-byte
integer, except that a `char` among them makes a `char`.

## 5. Type names and casts

A cast, `(char*) p`, names a type without declaring anything.  Ch 28's
`cc-parse-operand` meets a `(` and cannot tell a cast from a
parenthesised expression without knowing whether the next token
starts a type, and type names are this file's business, so the whole
cast is parsed here and reached through `cc-try-cast-fwd` (Ch 27 §4):

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Type names and casts
\ ===========================================================================
\ A cast `( TYPE ) operand` names a type without declaring anything:
\ qualifiers, a base (a type keyword or several, struct TAG, enum TAG, or
\ a typedef-name), then '*'s.  Its value is the operand's; only the type
\ the parser tracks changes, so `*(char*)p` loads one byte and
\ `((struct T*)p)->f` finds the field.  A (char) cast keeps the low byte.

variable cc-cast-desc                              \ struct TAG's descriptor, or 0

\ cc-type-start? ( -- f )  Does the current token begin a type name?
: cc-type-start?
  cc-target-lp64 @ if, cc-native-type-start-fwd exit, then,
  cc-tok-is-basic-type-kw?  cc-qualifier? or
  kw-struct cc-tok-kw? or  kw-enum cc-tok-kw? or
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find
    dup 0< if, drop else, cc-sym-kind-of sk-typedef = or then,
  then, ;

\ cc-parse-type-name ( -- ty )  The current token begins a type name; read
\ it, stars and all, and leave the token after it pending.
: cc-parse-type-name
  cc-target-lp64 @ if, cc-native-type-name-fwd exit, then,
  [lit] 0 cc-cast-desc !
  begin, cc-qualifier? while, cc-next-token-keep repeat,
  kw-struct cc-tok-kw? if,
    cc-lookup-struct-tag-soft cc-cast-desc !
    ty-struct [lit] 0
  else,
  kw-enum cc-tok-kw? if,
    cc-skip-enum-tag ty-int [lit] 0
  else,
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find cc-sym-val-of
    dup ty-base swap ty-ptr
  else,
    \ Keywords: int, char, void, and combinations such as `unsigned int`
    \ or `long long`; any char makes it char.
    ty-int
    begin,
      kw-char cc-tok-kw? if, drop ty-char then,
      kw-void cc-tok-kw? if, drop ty-void then,
      cc-next-token-keep cc-tok-is-basic-type-kw?
    while,
    repeat,
    cc-putback-token
    [lit] 0
  then, then, then,                                ( base ptr )
  cc-skip-qualifiers
  cc-count-stars + ty-make ;

\ cc-try-cast ( -- f )  The current token is '('.  If a type name follows,
\ compile the whole cast — type, ')', then the operand, a unary
\ expression — and answer true.  Otherwise answer false with the token
\ after the '(' put back, for cc-parse-paren.
: cc-cast-types-default ( source destination -- ) 2drop ;
defer cc-cast-types-fwd
' cc-cast-types-default is cc-cast-types-fwd
\ Runtime conversion stays separate from the pure cast-type policy.
: cc-cast-value-default ( source destination -- ) cc-emit-convert-value ;
defer cc-cast-value-fwd
' cc-cast-value-default is cc-cast-value-fwd
\ Only target-approved integer constant zero casts retain null provenance.
: cc-cast-null-default ( source destination null qualified -- null ) 2drop 2drop [lit] 0 ;
defer cc-cast-null-fwd
' cc-cast-null-default is cc-cast-null-fwd
\ The operand's own decay happens while this flag is set. Its type is then
\ replaced by the type name, so no shape built for that decay survives.
variable cc-cast-operand-decay
[lit] 0 cc-cast-operand-decay !

: cc-try-cast
  cc-next-token-keep
  cc-type-start? 0= if,
    cc-putback-token [lit] 0 exit,
  then,
  cc-parse-type-name >r                            ( ; R: ty )
  cc-target-lp64 @ if, cc-type-name-array @ if, [lit] 238 cc-die then, then,
  [char] ) cc-expect-punct-c
  cc-type-name-qualified @ >r
  cc-cast-desc @ >r                                ( ; R: ty qualification desc )
  cc-parse-unary
  true cc-cast-operand-decay ! cc-emit-materialize
  [lit] 0 cc-cast-operand-decay !
  r> r> r> swap >r                                 ( desc ty ; R: qualification )
  cc-target-lp64 @ if,
    cc-last-expr-type @ over cc-cast-types-fwd
    cc-last-expr-type @ over cc-cast-value-fwd
  else,
    dup ty-base ty-char = over ty-ptr 0= and if, cc-emit-zx-byte-rdi then,
  then,
  cc-last-expr-type @ over cc-last-expr-null @ r@ cc-cast-null-fwd >r
  cc-mark-not-lvalue
  cc-last-expr-type !
  cc-last-struct-desc !
  r> cc-last-expr-null !
  r> cc-last-expr-qualified !
  true ;

' cc-try-cast is cc-try-cast-fwd

```

`cc-type-start?` accepts a type keyword, a qualifier, `struct`,
`enum`, or a name the symbol table knows as a typedef; anything else
means the `(` groups an expression.  `cc-parse-type-name` reads the
type into one type word (Ch 24), keeping a struct's descriptor aside
in `cc-cast-desc`.  `cc-try-cast` then parses the operand as a unary
expression, since a cast binds tighter than any binary operator
(`(char) x + 1` is `((char) x) + 1`), and materializes it.
`cc-cast-operand-decay` is set only around that last materialization,
so a target can tell an array decaying as the cast's own operand
(whose type the cast immediately replaces) from any other decay;
Chapter 36 uses it for qualified arrays.

A cast changes no bits, except `(char)`, which keeps the low byte
(`movzx edi, dil`, Ch 25), so `(char) 321` is 65.  What it changes is
what the parser believes about the value: its type goes into
`cc-last-expr-type`, so `*(char*) p` loads one byte, and a struct
pointer's descriptor into `cc-last-struct-desc`, so
`((struct pt*) raw)->y` finds `y`.  `(void) 0` evaluates and discards,
as everywhere.  `tests/cc/P3-casts.c` checks each of these.  pnut casts
a lot: `(intptr_t) fd` into its include stack and `(char*)` back out,
and `((void) 0)` as an empty statement.

## 6. Struct-local declarations

```forth file=110-cc-decl.fth
\ ===========================================================================
\ cc-parse-struct-local-decl
\ ===========================================================================
\ Called with 'struct' keyword ALREADY consumed (it was the dispatch token).
\ Parses:
\
\    struct TAG '*'* IDENT ';'
\
\ ptr-depth=0 form (`struct TAG name;`): reserves total-size/8 local slots
\ (one per int field) with field-0 at the LOWEST address (deepest slot).
\ Symbol entry: val = slot of field 0; struct-desc = descriptor pointer.
\
\ ptr-depth>=1 form (`struct TAG* p;`): reserves a single slot for the pointer.
\ Symbol entry: val = slot, struct-desc = descriptor pointer of the pointee
\ (so '->field' can resolve field offsets).
\
\ Uses globals to avoid deep stack juggling.

variable cc-sld-desc
variable cc-sld-ptr-depth
variable cc-sld-name-a
variable cc-sld-name-u

: cc-parse-struct-local-decl                      ( -- )
  cc-lookup-struct-tag cc-sld-desc !
  cc-count-stars cc-sld-ptr-depth !
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 160 cc-die
  then,
  tok-str-addr @ cc-sld-name-a !
  tok-str-len  @ cc-sld-name-u !

  cc-sld-ptr-depth @ [lit] 0 = if,
    \ struct TAG name; — reserve slot-count slots.  No initializer support.
    [char] ; cc-expect-punct-c
    cc-sld-name-a @ cc-sld-name-u @
    sk-local
    ty-struct [lit] 0 ty-make
    cc-fn-local-count @ cc-sld-desc @ cc-sd-total-size [lit] 8 / + 1-
                                                  ( a u kind ty slot )
    cc-sym-add                                    ( id )
    cc-sld-desc @ swap cc-sym-set-struct-desc
    \ Reserve slots.
    cc-sld-desc @ cc-sd-total-size [lit] 8 / cc-fn-add-slots
  else,
    \ struct TAG* p ('=' expr)? ; — one slot for the pointer.
    cc-sld-name-a @ cc-sld-name-u @
    sk-local
    ty-struct cc-sld-ptr-depth @ ty-make          ( a u kind ty )
    cc-fn-local-count @                           ( a u kind ty slot )
    cc-sym-add                                    ( id )
    cc-sld-desc @ swap cc-sym-set-struct-desc
    [lit] 1 cc-fn-add-slots

    \ Optional '= expr;' initializer (M2-Planet uses `struct T* i = expr;`).
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] = = and if,
      cc-parse-expr
      cc-fn-local-count @ 1- cc-emit-store-local
      [char] ; cc-expect-punct-c
    else,
      tok-kind @ tk-punct = tok-num @ [char] ; = and 0= if,
        [lit] 161 cc-die
      then,
    then,
  then, ;

```

`cc-parse-struct-local-decl` handles `struct TAG x;` and
`struct TAG* p;` inside a function body.

For the value form, it reserves `total-size/8` slots.  Field 0 lives
at the lowest address, the deepest slot in the frame, and that slot
is the symbol's value.  `cc-sym-set-struct-desc` records the
descriptor pointer.
The value form takes no initializer.

The pointer form reserves one slot and stores the pointee's
descriptor the same way, which is what Ch 28's postfix `->`
reads to resolve field offsets.  It accepts `= expr`, because
M2-Planet writes `struct T* i = expr;` constantly.

## 7. `cc-parse-return`

`cc-parse-switch` (Ch 30) saves the outer `rbx` with a `push` whose
matching `pop` sits at the switch's end label.  A statement that
leaves the switch body some other way has to emit its own `pop rbx`
for each switch it crosses:

```forth file=110-cc-decl.fth
\ ===========================================================================
\ Switch-scrutinee unwind
\ ===========================================================================
\ cc-parse-switch (112-cc-stmt.fth) parks the outer rbx with
\ `push rbx` and restores it with `pop rbx` at the switch's end label.  Any
\ statement that jumps out of the switch body without passing the end label —
\ return, continue, goto — must first emit compensating pops, or each
\ traversal leaks 8 bytes of stack per open switch (and return hands the
\ caller a clobbered callee-saved rbx).
\
\ cc-switch-depth counts the switches lexically open at the current parse
\ point; cc-loop-switch-depth snapshots it at the innermost enclosing loop.
\   return:    pop cc-switch-depth times (every open switch in the function),
\   continue:  pop (cc-switch-depth - cc-loop-switch-depth) times (the
\              switches between the statement and the loop it continues),
\   goto:      pop cc-switch-depth times — correct for labels outside any
\              switch; goto to a label INSIDE a switch is unsupported.
\ break needs nothing: it targets the innermost loop or switch end label,
\ so it never jumps across a scrutinee push.
variable cc-switch-depth
variable cc-loop-switch-depth

\ cc-emit-switch-unwind ( n -- )  Emit n `pop rbx` instructions.
: cc-emit-switch-unwind                           ( n -- )
  begin,
    dup [lit] 0 >
  while,
    cc-emit-pop-rbx
    1-
  repeat,
  drop ;

```

`cc-switch-depth` counts open switches; `cc-loop-switch-depth`
records that count at the innermost loop.  `return` pops them all,
`continue` pops the ones opened inside the loop, and `goto` pops them
all (so a `goto` into a switch is unsupported).  `break` needs
nothing, because its target is the innermost loop's or switch's own
end label.

```forth file=110-cc-decl.fth
\ cc-parse-return ( -- )  "return" already consumed; parse [expr] ';'.
\ Bare `return;` (no expression) is legal C — emit rax := 0 + epilogue.
\ Peek the next token: if it's ';' the peek already consumed it, so do NOT
\ call cc-expect-punct-c again.  Otherwise putback and parse the expression.
\ Either way, unwind any open switch scrutinees so rbx is restored before
\ the epilogue's ret.
defer cc-value-return-fwd
' cc-emit-mov-rax-rdi is cc-value-return-fwd

: cc-parse-return
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] ; = and if,
    cc-emit-xor-rax-rax                           \ rax := 0 (no value returned)
    cc-switch-depth @ cc-emit-switch-unwind
    cc-emit-epilogue
  else,
    cc-putback-token
    cc-parse-expr
    cc-target-lp64 @ if,
      cc-last-expr-type @ cc-native-return-type @ cc-emit-convert-value
    then,
    cc-value-return-fwd                           \ result -> rax (SYS-V)
    cc-switch-depth @ cc-emit-switch-unwind
    cc-emit-epilogue
    [char] ; cc-expect-punct-c
  then, ;
```

`cc-parse-return` has two forms.  A bare `return;` emits
`xor rax, rax`, so the caller sees 0.  `return expr;` parses the
expression and moves `rdi` into `rax` with `cc-emit-mov-rax-rdi`.
Both then unwind open switches, which restores the caller's `rbx`,
and emit the `mov rsp, rbp ; pop rbp ; ret` epilogue (5 bytes;
Ch 25 §5).

The peek reads the `;` only when it is there; otherwise the token
goes back and the trailing `cc-expect-punct-c` catches a missing
semicolon after the expression.

Ch 31's `cc-parse-function` also emits a zero and an epilogue when
the body closes, so a function that ends with an explicit `return`
carries 8 unreachable bytes (the 3-byte zero plus the 5-byte
epilogue).  They cost space, not correctness.

**tri.c at this stage.**  tri.c declares a struct type, a struct
global and two locals, and none of them emits an instruction.
With tri.c compiled to `/tmp/cc-out` (Ch 21), look at the start of
`main` and the end of the file's code:

```sh
for r in 0x2e2:0x2fe 0x4b2:0x4c9; do
  objdump -D -b binary -m i386:x86-64 -M intel \
      --start-address=${r%:*} --stop-address=${r#*:} /tmp/cc-out | grep '^ '
done
```

```
 2e2:   55                      push   rbp
 2e3:   48 89 e5                mov    rbp,rsp
 2e6:   48 81 ec 00 01 00 00    sub    rsp,0x100
 2ed:   48 bf c9 04 40 00 00    movabs rdi,0x4004c9
 2f4:   00 00 00 
 2f7:   48 81 c7 00 00 00 00    add    rdi,0x0
 4b2:   48 c7 c7 01 00 00 00    mov    rdi,0x1
 4b9:   48 89 f8                mov    rax,rdi
 4bc:   48 89 ec                mov    rsp,rbp
 4bf:   5d                      pop    rbp
 4c0:   c3                      ret
 4c1:   48 31 c0                xor    rax,rax
 4c4:   48 89 ec                mov    rsp,rbp
 4c7:   5d                      pop    rbp
 4c8:   c3                      ret
```

Right after the prologue, at 0x2ed, is line 14's `t.rows`: `int
w[ROWS];` and `int r;` emitted no bytes.  What they left is
bookkeeping that later code reads.  The `struct tri` descriptor puts
`rows` at offset 0 (the `add rdi,0x0`) and `stars` at 8, and `w`
reserves slots 0–3 with its symbol on the last, so its base is
`[rbp-0x20]` and `r` gets `[rbp-0x28]`.  At the other end, `return
1;` is `mov rax,rdi` plus the 5-byte epilogue, and the 8 bytes at
0x4c1 are the unreachable zero-and-epilogue described above.

## Try it

**Small check:** start with one fixture below and map each
declaration to the symbol table row it creates.

**Layer check:** run the root unit suite and the focused C fixtures.

```sh
./build.sh
./test.sh
```

**Bootstrap relevance:** Stage-A covers declarations at M2-Planet
scale, including structs, typedefs, locals, and file-scope data.

```sh
tests/cc/stage-a-check.sh
```

The fixtures for the small check:
`tests/cc/G3.c` exercises basic local declarations inside function
bodies; `G9b.c` exercises struct declarations and field arithmetic;
`G14d.c` exercises global variables (`g_counter`) and global arrays
(`g_array[5]`).  `G10b.c` tests `typedef`.  `P3-casts.c` casts to
every kind of type, `P4-declarations.c` puts `const` everywhere it
may go and declares several names per declaration, and
`K-static-local.c` keeps a count in a `static` local.

## Exercises

1. **★★ Trace.** Pre-registration of struct tags makes `struct T { struct T*
   next; }` work.  What about `struct A { struct B* b; };
   struct B { struct A* a; };` — mutual recursion?  Trace what
   `cc-lookup-struct-tag-soft` returns for `struct B*` inside
   `struct A`, then explain why `b->a->y` compiles but `a->b->x`
   dies with code 100.

2. **★★ Verify.** A `static` local is an `sk-global` in the block's scope.
   Declare `static int n;` in two different functions: do they share
   storage?  Now declare a global `n` *after* both functions.  Which
   variable does each `n` name, and why does Ch 31's "a global
   declared twice is one variable" rule not merge them?

3. **★★★ Modify.** Function-pointer decls use 2-token lookahead.  How could you
   reduce this to 1?  Hint: `(*` is two ASCII bytes; you could
   peek the next byte after `(` via the lexer's `cc-peek-char-2`.

4. **★★★ Extend.** `cc-parse-decl-with-base` accepts at most one initializer
   expression.  Could you extend it to handle `int arr[N] =
   {a, b, c};`?  What new vocabulary in the codegen would
   that need?

5. **★★★ Extend.** Every field is 8 bytes regardless of `char` vs `int`.  This
   wastes memory on a struct full of `char` fields.  What
   would change in `cc-sd-append-field` to support packed
   layouts?

## After this chapter

The compiler can parse declarations: base types with pointer and
array modifiers, several declarators at once, `static` locals, struct
definitions (including self-referential ones), function pointers,
struct locals, and the type names inside casts.  Typedefs, enum constants, and
file-scope globals reuse this engine but are wired up in Ch 31.

You can trace how `int x;`, `int* p;`, `int arr[N];`, and
`struct T s;` each become a symbol-table row, and explain why
`struct T { struct T *next; };` works.

With names declared and expressions compiled, what is missing is
order.  tri.c's `for` must emit a jump out of the loop before it has
seen the loop's body, so the jump's target does not exist yet.
Ch 30 is about jumps to places that don't exist yet.

## Takeaways

- Most declarations need only the one-token putback from Ch 27, but
  spotting `int (*fp)(int)` takes a full save, two-token read, and
  restore of the lexer state.
- Registering a struct's tag before parsing its body makes
  `struct T { struct T* next; }` work, but a field naming a struct
  not yet defined gets descriptor 0, so mutually recursive structs
  fail (Exercise 1).
- `cc-parse-return` and the switch-unwind counters close
  `110-cc-decl.fth`, and so this chapter, only because source order
  puts them there; the statement dispatcher that calls them is in
  `112-cc-stmt.fth` (Ch 30).

Next: Chapter 30 — Statements: if, while, for, switch, break,
continue, goto.


```forth file=110-cc-decl.fth

\ Bind the expression parser's native sizeof type queries after declaration parsing.
: cc-native-sizeof-type cc-parse-type-name cc-cast-desc @ ;
' cc-type-start? is cc-sizeof-type-start-fwd
' cc-native-sizeof-type is cc-sizeof-type-fwd
```
