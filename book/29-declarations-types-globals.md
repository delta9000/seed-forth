# Chapter 29 — Declarations: Types, Structs, Locals

> **Status:** ✅ complete.  Contributes lines 1–587 of
> `110-cc-decl.fth` — file header, expectation helpers, struct
> definition parsing, type-spec / pointer parsing, function-pointer
> declarations, local declarations, struct-local declarations, and
> `cc-parse-return`.  Chs 30 and 31 contribute the remaining 2163
> lines.

## Goal

By the end of this chapter the reader can:

- read the token-expectation helpers (`cc-expect-kw-id`,
  `cc-expect-punct-c`, `cc-expect-ident`) and the storage-qualifier
  skipper;
- read `cc-parse-struct-def` and explain how a struct's
  descriptor is built incrementally, including the
  pre-registration trick for self-referential types;
- read the local-declaration path (`cc-parse-decl-with-base` and
  `cc-parse-fnptr-decl`) and trace how `int x;`, `int* p;`,
  `int arr[N];`, `int (*fp)(int);`, and `struct T s;` each
  produce a symbol-table entry;
- read `cc-parse-return` and explain its handling of bare
  `return;` versus `return expr;`.

## Source coverage

`110-cc-decl.fth` lines 1–587.  Ch 30 covers 588–1438
(statements).  Ch 31 covers 1439–2750 (functions, calls,
top-level driver, enums, typedefs, globals, entry stub).

## Concepts introduced

- **Error-status discipline.**  Codes 11–29 (and 70+ for type
  specifics) are reserved for decl/stmt parse failures.  Every
  `die` exits with a distinct status so the test driver can
  diagnose by examining exit codes.
- **Pre-registration for self-referential structs.**
  `cc-parse-struct-def` registers `struct TAG` with an
  empty-descriptor BEFORE parsing the field body, so
  `struct T { struct T* next; }` resolves its own tag.
- **Storage-qualifier skipping.**  `static`, `extern`, `const`,
  `volatile`, `register`, `auto`, `restrict` are all parsed as
  no-ops.  The codegen treats every variable identically.
- **`cc-parse-decl-with-base`.**  The shared scalar/array/initializer
  parser, called from both `cc-parse-decl` (basic types) and the
  typedef-named-declarations path in Ch 30.
- **Function-pointer declarations with 2-token lookahead.**
  `int (*fp)(int);` requires distinguishing from `int x;` after
  the base type.  `cc-peek-fnptr?` saves the lexer, reads two
  tokens, restores.

## Concepts carried in

- Lexer state and `cc-next-token` (Ch 23).
- Symbol table (Ch 24), struct descriptors (Ch 24), arena
  allocator (Ch 21).
- Codegen primitives — `cc-emit-store-local`, `cc-emit-epilogue`,
  `cc-emit-xor-rax-rax`, `cc-emit-mov-rax-rdi` (Chs 25–26).
- Expression parser `cc-parse-expr-balanced` (Ch 28).

## Concepts deferred

- Statements (`cc-parse-stmt`, `cc-parse-if`, the loop family,
  `switch`, `break`, `continue`, `goto`) — Ch 30.
- Function definitions, parameter lists, function calls — Ch 31.
- Enum and typedef definitions, file-scope globals, the
  top-level `cc-parse-function-list`, entry stub — Ch 31.

---

Ch 28 closed the expression parser.  Ch 29 opens the declarations
file — the longest in Part III at 2750 lines.  We split it across
three chapters by source order: Ch 29 covers the top of the file
(declarations and struct parsing), Ch 30 covers statements,
Ch 31 covers everything else (functions, enums, typedefs,
globals, entry stub).

The reason for the source-order split rather than a topical one
is mechanical: literate `file=` blocks accumulate in chapter
order, so the only way to keep the tangled output in source order
is to keep the *chapter* order matching source order.

## 1. File header and expectation helpers

```forth file=110-cc-decl.fth
\ 110-cc-decl.fth — function/declaration parser for the C-subset compiler.
\
\ Parses top-level declarations, function definitions, local declarations,
\ statements, structs, enums, typedefs, and prototypes for the C subset needed
\ to compile M2-Planet.
\
\ The compiled output begins with a 26-byte entry stub at vaddr 0x400078:
\     call <main>      ; E8 <rel32>             (5 bytes)
\     mov rdi, rax     ; 48 89 C7                (3 bytes)
\     mov rax, 60      ; 48 C7 C0 3C 00 00 00    (7 bytes)
\     syscall          ; 0F 05                    (2 bytes)
\
\ Then the function body.  main returns its value in rax (SYS-V); the stub
\ moves it to rdi and exits.  The call's rel32 is patched after main's
\ vaddr is known.
\
\ Depends on 010-lib.fth, 030-cc-io.fth, 050-cc-lex.fth, 060-cc-types.fth, 070-cc-sym.fth,
\ 080-cc-elf.fth, 090-cc-emit.fth, 100-cc-expr.fth.

\ ===========================================================================
\ Bookkeeping
\ ===========================================================================

variable cc-main-vaddr                            \ vaddr where main starts
variable cc-call-main-patch                       \ file-offset of rel32 to patch
variable cc-fn-local-count                        \ # locals in current function

\ cc-pending-struct-desc is set by cc-parse-base-type when it parses a
\ `struct TAG` base, and consumed by cc-parse-decl / cc-parse-param-list when
\ they record the symbol-table entry (so the struct descriptor pointer ends
\ up in cc-sym-extra).  For non-struct types it stays at 0.
variable cc-pending-struct-desc

\ ===========================================================================
\ Token-expectation helpers
\ ===========================================================================

\ Each error path exits with a distinct status so failures are diagnosable
\ from the shell.  Codes 11..29 are "decl/stmt" errors.

\ cc-expect-kw-id ( kw-id -- )  Consume one token; abort if not the given kw.
: cc-expect-kw-id
  cc-next-token-keep
  tok-kind @ tk-kw <> if,
    drop
    [lit] 11 die
  then,
  tok-kw-id @ <> if,
    [lit] 12 die
  then, ;

\ cc-expect-punct-c ( char -- )  Consume one token; abort if not that punct.
: cc-expect-punct-c
  cc-next-token-keep
  tok-kind @ tk-punct <> if,
    drop
    [lit] 13 die
  then,
  tok-num @ <> if,
    [lit] 14 die
  then, ;

\ cc-expect-ident ( -- )  Consume one token; abort if not tk-ident.
: cc-expect-ident
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 15 die
  then, ;

\ ===========================================================================
\ Statement parsing
\ ===========================================================================

\ cc-count-stars ( -- depth )  After consuming a base type (e.g. 'int'), peek
\ zero or more '*' tokens and return the resulting pointer depth.  Leaves the
\ first non-'*' token pending for the caller.
: cc-count-stars                                  ( -- depth )
  [lit] 0
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 42 = and
  while,
    [lit] 1 +
  repeat,
  cc-putback-token ;

\ Skip storage-class specifiers (static / extern / auto / register) and
\ type qualifiers (const / volatile / restrict).  Reads tokens via
\ cc-next-token-keep; whenever one of these keywords is seen, it's consumed
\ and the loop continues.  When a non-qualifier is encountered it is put back
\ so the caller sees it as the next token.
\
\ These are treated as no-ops.  In particular, local `static int z` behaves
\ like a regular local; M2-Planet does not rely on static local persistence.
variable cc-sq-flag
: cc-skip-storage-quals
  begin,
    cc-next-token-keep
    [lit] 0 cc-sq-flag !
    tok-kind @ tk-kw = if,
      tok-kw-id @ kw-static    = if, [lit] 0 0= cc-sq-flag ! then,
      tok-kw-id @ kw-extern    = if, [lit] 0 0= cc-sq-flag ! then,
      tok-kw-id @ kw-auto      = if, [lit] 0 0= cc-sq-flag ! then,
      tok-kw-id @ kw-register  = if, [lit] 0 0= cc-sq-flag ! then,
      tok-kw-id @ kw-const     = if, [lit] 0 0= cc-sq-flag ! then,
      tok-kw-id @ kw-volatile  = if, [lit] 0 0= cc-sq-flag ! then,
      tok-kw-id @ kw-restrict  = if, [lit] 0 0= cc-sq-flag ! then,
    then,
    cc-sq-flag @
  while,
    \ already consumed; just loop
  repeat,
  cc-putback-token ;

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
  cc-sd-build-desc @ cc-sd-field-count [lit] 1 +
  cc-sd-build-desc @ cc-sd-set-field-count
  cc-sd-build-desc @ cc-sd-total-size [lit] 8 +
  cc-sd-build-desc @ cc-sd-set-total-size ;

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
    [lit] 95 die
  then,
  tok-str-addr @ tok-str-len @ cc-sym-find        ( id-or-neg1 )
  dup [lit] 0 < if,
    drop
    [lit] 96 die
  then,
  dup cc-sym-kind-of sk-struct <> if,
    drop
    [lit] 97 die
  then,
  cc-sym-val-of ;                                  \ descriptor pointer

\ cc-lookup-struct-tag-soft ( -- desc-or-0 )  Like cc-lookup-struct-tag, but
\ returns 0 if the tag isn't found or isn't registered as a struct.  Lets the
\ parser tolerate opaque/incomplete struct references in headers that declare
\ but don't define the struct (e.g. cc_globals.c's `struct type* foo;`).
: cc-lookup-struct-tag-soft                       ( -- desc-or-0 )
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 95 die
  then,
  tok-str-addr @ tok-str-len @ cc-sym-find        ( id-or-neg1 )
  dup [lit] 0 < if,
    drop [lit] 0
  else,
    dup cc-sym-kind-of sk-struct <> if,
      drop [lit] 0
    else,
      cc-sym-val-of
    then,
  then, ;

: cc-parse-struct-def                             ( -- )
  \ Expect IDENT tag.
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 93 die
  then,
  \ Snapshot tag bytes on data stack (rstack would be clobbered by ';' etc.).
  tok-str-addr @ tok-str-len @                    ( tag-addr tag-len )
  \ Expect '{'.
  [lit] 123 cc-expect-punct-c

  \ Allocate descriptor: 16-byte header + room for up to 16 fields = 656 bytes.
  [lit] 656 cc-alloc                              ( tag-addr tag-len desc )
  dup cc-sd-build-desc !
  [lit] 0 over cc-sd-set-total-size
  [lit] 0 over cc-sd-set-field-count
  drop                                            ( tag-addr tag-len )

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
    tok-kind @ tk-punct = tok-num @ [lit] 125 = and 0=
  while,
    cc-putback-token
    \ Parse base type.  Default the pointee-descriptor to 0; the struct-tag
    \ branch overrides when the field is `struct TAG ...`.
    [lit] 0 cc-sd-build-field-desc !
    cc-next-token-keep
    tok-kind @ tk-kw = if,
      tok-kw-id @ kw-int     = if, ty-int  cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-char    = if, ty-char cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-void    = if, ty-void cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-struct  = if,
        \ Look up the tag's descriptor (soft — self-referential `struct T*
        \ next` inside `struct T {...}` works because cc-parse-struct-def
        \ pre-registers the tag with a still-empty descriptor before parsing
        \ fields, and forward refs return 0).  Stored in the field record so
        \ chained '->' can propagate the type.
        cc-lookup-struct-tag-soft cc-sd-build-field-desc !
        ty-struct cc-sd-build-field-ty !
      else,
        [lit] 91 die
      then, then, then, then,
    else,
      \ tk-ident — treat as typedef-name used as a type.  Record as int
      \ (we only care about the storage size = 8).
      tok-kind @ tk-ident <> if,
        [lit] 92 die
      then,
      ty-int cc-sd-build-field-ty !
    then,

    cc-count-stars                                ( ... ptr-depth )
    \ Re-pack the type word with the ptr-depth.
    cc-sd-build-field-ty @ swap ty-make cc-sd-build-field-ty !

    \ Read field name.
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 94 die
    then,
    tok-str-addr @ cc-sd-build-fname-a !
    tok-str-len  @ cc-sd-build-fname-u !
    [lit] 59 cc-expect-punct-c                    \ ';'
    cc-sd-append-field
  repeat,
  \ '}' was the loop test; we consumed it via cc-next-token-keep but DIDN'T
  \ putback this time (the test went 0=, so we entered the exit path).
  \ Expect ';' after '}'.
  [lit] 59 cc-expect-punct-c
  drop drop ;                                     \ discard tag-a tag-u

\ ===========================================================================
\ Function-pointer declaration parsing.
\ ===========================================================================
\ A function-pointer decl has the shape:
\
\    RETURN_TYPE '(' '*' NAME ')' '(' PARAM_TYPES ')' (= expr)? ';'
\
\ Detection: after the base type is parsed, we need 2-token lookahead to
\ distinguish `int (*fp)(int);` from `int x;` and `int *p;`.  The lookahead
\ helpers cc-lookahead-save / cc-lookahead-restore (defined later in this
\ file alongside cc-peek-after-is-colon?) only buffer one token, so we
\ replicate the same save/restore pattern via fresh state slots so a fnptr
\ decl can occur even inside contexts already using the colon-peek slots.

variable cc-fnptr-save-pos
variable cc-fnptr-save-line
variable cc-fnptr-save-pending
variable cc-fnptr-save-tok-kind
variable cc-fnptr-save-tok-num
variable cc-fnptr-save-tok-addr
variable cc-fnptr-save-tok-len
variable cc-fnptr-save-tok-kw

: cc-fnptr-lookahead-save
  cc-src-pos     @ cc-fnptr-save-pos      !
  cc-src-line    @ cc-fnptr-save-line     !
  cc-tok-pending @ cc-fnptr-save-pending  !
  tok-kind       @ cc-fnptr-save-tok-kind !
  tok-num        @ cc-fnptr-save-tok-num  !
  tok-str-addr   @ cc-fnptr-save-tok-addr !
  tok-str-len    @ cc-fnptr-save-tok-len  !
  tok-kw-id      @ cc-fnptr-save-tok-kw   ! ;

: cc-fnptr-lookahead-restore
  cc-fnptr-save-pos      @ cc-src-pos     !
  cc-fnptr-save-line     @ cc-src-line    !
  cc-fnptr-save-pending  @ cc-tok-pending !
  cc-fnptr-save-tok-kind @ tok-kind       !
  cc-fnptr-save-tok-num  @ tok-num        !
  cc-fnptr-save-tok-addr @ tok-str-addr   !
  cc-fnptr-save-tok-len  @ tok-str-len    !
  cc-fnptr-save-tok-kw   @ tok-kw-id      ! ;

\ cc-peek-fnptr? ( -- f )  Look ahead 2 tokens; -1 iff we see '(' then '*'.
\ Always restores the lexer state so the caller resumes at the original
\ position regardless of the result.
: cc-peek-fnptr?
  cc-fnptr-lookahead-save
  cc-next-token
  tok-kind @ tk-punct = tok-num @ [lit] 40 = and 0= if,
    cc-fnptr-lookahead-restore
    [lit] 0
  else,
    cc-next-token
    tok-kind @ tk-punct = tok-num @ [lit] 42 = and
    cc-fnptr-lookahead-restore
  then, ;

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
    tok-kind @ tk-punct = if,
      tok-num @ [lit] 40 = if, [lit] 1 + then,
      tok-num @ [lit] 41 = if, [lit] 1 - then,
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
  [lit]  40 cc-expect-punct-c
  [lit]  42 cc-expect-punct-c

  \ NAME (IDENT).
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 140 die
  then,
  tok-str-addr @ tok-str-len @                    ( name-a name-u )

  \ ')' '(' PARAM-TYPES ')'
  [lit] 41 cc-expect-punct-c
  [lit] 40 cc-expect-punct-c
  cc-skip-fnptr-params

  \ Register as an sk-local function pointer: ty-func + ptr-depth=1.
  sk-local
  ty-func [lit] 1 ty-make                         ( a u kind type )
  cc-fn-local-count @                             ( a u kind type slot )
  cc-sym-add drop
  [lit] 1 cc-fn-local-count +!

  \ Optional '= expr;' initializer.
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 61 = and if,
    cc-parse-expr-balanced
    cc-fn-local-count @ [lit] 1 - cc-emit-store-local
    [lit] 59 cc-expect-punct-c
  else,
    tok-kind @ tk-punct = tok-num @ [lit] 59 = and 0= if,
      [lit] 141 die
    then,
  then, ;

\ cc-parse-decl-with-base ( base initial-ptr -- )
\ Common scalar/array declaration parser.  Caller has already consumed any
\ keyword or typedef-name that established the base type, and supplies
\ (base, initial-ptr-depth) on the stack.  initial-ptr-depth is non-zero only
\ when the base came from a pointer-typed typedef (`typedef int* int_ptr;`).
\ Parses `'*'* ident ( '[' NUM ']' | ('=' expr)? ) ';'`.
\
\ If the next two tokens after the base are '(' '*', dispatch to
\ cc-parse-fnptr-decl instead (function-pointer declaration).
\
\ The base type is stashed in cc-decl-base so the data stack only needs to
\ thread ( ptr-depth a u [N] ) — preserving the layouts of the older code.
variable cc-decl-base                              \ base type kind
: cc-parse-decl-with-base                         ( base init-ptr -- )
  swap cc-decl-base !                              ( init-ptr )
  \ Detect function-pointer decl shape.  Only when there are no leading
  \ stars from the caller (init-ptr=0) — `int* (*fp)()` is a func-ptr returning
  \ int*, which is outside this subset.
  dup [lit] 0 = cc-peek-fnptr? and if,
    drop                                           ( -- )
    cc-parse-fnptr-decl
  else,
  cc-count-stars +                                 ( ptr-depth )
  cc-expect-ident
  tok-str-addr @ tok-str-len @                     ( ptr-depth a u )
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 91 = and if,
    \ -------- Array declaration: T name [ N ] ; --------
    cc-next-token-keep
    tok-kind @ tk-num <> if,
      [lit] 23 die
    then,
    tok-num @                                      ( ptr-depth a u N )
    dup [lit] 0 <= if,
      [lit] 24 die
    then,
    cc-next-token-keep
    tok-kind @ tk-punct <> tok-num @ [lit] 93 <> or if,
      [lit] 25 die
    then,
    cc-next-token-keep
    tok-kind @ tk-punct <> tok-num @ [lit] 59 <> or if,
      [lit] 26 die
    then,
    ( ptr-depth a u N )
    >r                                             ( ptr-depth a u ; R: N )
    rot                                            ( a u ptr-depth ; R: N )
    sk-local swap                                  ( a u sk-local ptr-depth )
    cc-decl-base @ swap ty-make                    ( a u kind type )
    cc-fn-local-count @ r@ + [lit] 1 -             ( a u kind type slot )
    cc-sym-add                                     ( id ; R: N )
    r@ swap cc-sym-set-extra                       ( ; R: N )
    r> cc-fn-local-count +!
  else,
    \ -------- Scalar declaration: T name ('=' expr)? ; --------
    ( ptr-depth a u )
    rot                                            ( a u ptr-depth )
    sk-local swap                                  ( a u sk-local ptr-depth )
    cc-decl-base @ swap ty-make                    ( a u kind type )
    cc-fn-local-count @                            ( a u kind type slot )
    cc-sym-add drop                                ( -- )
    [lit] 1 cc-fn-local-count +!

    tok-kind @ tk-punct = tok-num @ [lit] 61 = and if,
      cc-parse-expr-balanced
      cc-fn-local-count @ [lit] 1 - cc-emit-store-local
      cc-next-token-keep                           \ ';'
    then,
    tok-kind @ tk-punct <> tok-num @ [lit] 59 <> or if,
      [lit] 22 die
    then,
  then,
  then, ;                                          \ close fnptr-or-not

\ cc-parse-decl ( -- )  Legacy entry from cc-parse-stmt.  The basic-type kw is
\ the current token (still in tok-*); pick ty-char for `char`, ty-int for the
\ rest (int / long / short / unsigned / signed).  ty-char matters because the
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
  [lit] 0 cc-parse-decl-with-base ;

\ cc-tok-is-basic-type-kw? ( -- f )  -1 iff current token is a basic-type
\ keyword that introduces a local declaration: int / char / void / long /
\ short / unsigned / signed.  All are treated as 8-byte slot in codegen.
variable cc-bt-flag
: cc-tok-is-basic-type-kw?
  [lit] 0 cc-bt-flag !
  tok-kind @ tk-kw = if,
    tok-kw-id @ kw-int      = if, [lit] 0 0= cc-bt-flag ! then,
    tok-kw-id @ kw-char     = if, [lit] 0 0= cc-bt-flag ! then,
    tok-kw-id @ kw-void     = if, [lit] 0 0= cc-bt-flag ! then,
    tok-kw-id @ kw-long     = if, [lit] 0 0= cc-bt-flag ! then,
    tok-kw-id @ kw-short    = if, [lit] 0 0= cc-bt-flag ! then,
    tok-kw-id @ kw-unsigned = if, [lit] 0 0= cc-bt-flag ! then,
    tok-kw-id @ kw-signed   = if, [lit] 0 0= cc-bt-flag ! then,
  then,
  cc-bt-flag @ ;

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
\ Symbol entry: val = slot of field 0; cc-sym-extra = descriptor pointer.
\
\ ptr-depth>=1 form (`struct TAG* p;`): reserves a single slot for the pointer.
\ Symbol entry: val = slot, cc-sym-extra = descriptor pointer of the pointee
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
    [lit] 98 die
  then,
  tok-str-addr @ cc-sld-name-a !
  tok-str-len  @ cc-sld-name-u !

  cc-sld-ptr-depth @ [lit] 0 = if,
    \ struct TAG name; — reserve slot-count slots.  No initializer support.
    [lit] 59 cc-expect-punct-c                    \ ';'
    cc-sld-name-a @ cc-sld-name-u @
    sk-local
    ty-struct [lit] 0 ty-make
    cc-fn-local-count @ cc-sld-desc @ cc-sd-total-size [lit] 8 / + [lit] 1 -
                                                  ( a u kind ty slot )
    cc-sym-add                                    ( id )
    cc-sld-desc @ swap cc-sym-set-extra
    \ Reserve slots.
    cc-sld-desc @ cc-sd-total-size [lit] 8 / cc-fn-local-count +!
  else,
    \ struct TAG* p ('=' expr)? ; — one slot for the pointer.
    cc-sld-name-a @ cc-sld-name-u @
    sk-local
    ty-struct cc-sld-ptr-depth @ ty-make          ( a u kind ty )
    cc-fn-local-count @                           ( a u kind ty slot )
    cc-sym-add                                    ( id )
    cc-sld-desc @ swap cc-sym-set-extra
    [lit] 1 cc-fn-local-count +!

    \ Optional '= expr;' initializer (M2-Planet uses `struct T* i = expr;`).
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 61 = and if,
      cc-parse-expr-balanced
      cc-fn-local-count @ [lit] 1 - cc-emit-store-local
      [lit] 59 cc-expect-punct-c
    else,
      tok-kind @ tk-punct = tok-num @ [lit] 59 = and 0= if,
        [lit] 99 die
      then,
    then,
  then, ;

\ cc-parse-return ( -- )  "return" already consumed; parse [expr] ';'.
\ Bare `return;` (no expression) is legal C — emit rax := 0 + epilogue.
\ Peek the next token: if it's ';' the peek already consumed it, so do NOT
\ call cc-expect-punct-c again.  Otherwise putback and parse the expression.
: cc-parse-return
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 59 = and if,
    cc-emit-xor-rax-rax                           \ rax := 0 (no value returned)
    cc-emit-epilogue
  else,
    cc-putback-token
    cc-parse-expr-balanced
    cc-emit-mov-rax-rdi                           \ result -> rax (SYS-V)
    cc-emit-epilogue
    [lit] 59 cc-expect-punct-c                    \ ';'
  then, ;

```

## 2. Reading the listings

A walk-through of the high points:

**Bookkeeping (lines 24–32).**  `cc-main-vaddr`,
`cc-call-main-patch`, `cc-fn-local-count`, and
`cc-pending-struct-desc` are the four cross-function variables.
`cc-fn-local-count` tracks the next local slot to allocate;
`cc-pending-struct-desc` is set whenever a `struct TAG` base type
is parsed so the eventual `cc-sym-add` can plant the descriptor
pointer in `cc-sym-extra`.

**Expectation helpers (lines 42–68).**  `cc-expect-kw-id`,
`cc-expect-punct-c`, and `cc-expect-ident` are the canonical
"consume one token and check" idiom.  Each has its own error
status: 11/12 for the keyword pair, 13/14 for punctuation, 15 for
identifier.  Distinct status codes mean a failing stage-A check
prints a number you can grep for in this file.

**`cc-count-stars` (lines 77–85).**  Reads zero or more `*`
tokens after a base type.  Returns the count and putbacks the
first non-`*`.  Pointer-depth machinery throughout the file
funnels through this.

**`cc-skip-storage-quals` (lines 95–113).**  Treats every storage
class and qualifier as a no-op.  The compiler's frame layout
doesn't care about `static` versus `auto`; the type system has
no `const`-correctness; `register` is advisory anyway.  These
words exist so M2-Planet source can use them without the
compiler choking.

## 3. Struct definitions

`cc-sd-append-field` (lines 134–146) accumulates one field into
the descriptor under construction: store name/type/desc/offset
into the field record at index `cc-sd-field-count`, then bump
both `field-count` and `total-size` by 8.  Every field is an
8-byte slot regardless of declared type.

`cc-parse-struct-def` (lines 194–277) does the full
`struct TAG { … };` form.

The pre-registration step at lines 216–220 is what makes
self-referential structs work.  Before parsing any field, we
`cc-sym-add` the tag with the *empty* descriptor.  Then when a
field declares `struct T* next;`, the inner
`cc-lookup-struct-tag-soft` finds the tag, gets the still-empty
descriptor pointer, and stores it in the field record.  When
the body later finishes parsing, the descriptor has been
populated *in place* — and every `next` field record correctly
points at the now-finished descriptor.

The field loop (lines 226–272) dispatches on the field's base
type: `int`/`char`/`void` produce a simple type word; `struct`
recurses via `cc-lookup-struct-tag-soft`; an identifier is
treated as a typedef-name and falls back to `ty-int`.  Pointer
stars are counted via `cc-count-stars` and merged with `ty-make`.

## 4. Function-pointer declarations

`int (*fp)(int);` is its own awkward syntactic form.  It looks
like `int x;` (a basic decl) for the first three tokens, then
suddenly there's `(*` and we have to back up.

`cc-peek-fnptr?` (lines 325–335) does the 2-token lookahead.
It saves the lexer state, reads two tokens, tests them against
`(` then `*`, restores the state.  The boolean is the dispatch
key.

`cc-parse-fnptr-decl` (lines 361–395) handles the form after the
two-token lookahead has confirmed it.  It consumes `(`, `*`,
the NAME, `)`, `(`, skips the parameter list to the matching `)`,
and registers the name as `sk-local` with type
`ty-func + ptr-depth=1`.  Parameter types are not validated.

`cc-parse-decl-with-base` (lines 410–469) is the common
scalar/array path.  After the base type is on the stack and the
fnptr lookahead has failed, it counts stars, reads the name,
then dispatches on the next token: `[` → array, `=` → scalar
initializer, `;` → bare scalar.  Each branch builds a symbol
table entry with the right metadata in `cc-sym-extra` (array
length for arrays, struct descriptor for structs, 0 otherwise).

## 5. Struct-local declarations

`cc-parse-struct-local-decl` (lines 526–569) handles
`struct TAG x;` and `struct TAG* p;` *inside a function body*.

For the value form (`struct TAG x;`), we reserve `total-size/8`
slots; field 0 lives at the *lowest* address (deepest slot in the
frame, addressed `[rbp - 8*(N)]`).  The symbol's val stores the
slot of field 0; `cc-sym-extra` stores the descriptor pointer.

For the pointer form (`struct TAG* p;`), we reserve one slot for
the pointer, with the same descriptor in `cc-sym-extra` so that
`p->field` (Ch 28's postfix `->`) can resolve fields.

## 6. `cc-parse-return`

`cc-parse-return` (lines 575–586) is the simplest statement
parser.  Two forms:

- `return ;` — bare return.  Emit `xor rax, rax` (so callers see
  0) followed by `cc-emit-epilogue` (Ch 25 §5).
- `return expr ;` — parse the expression, `cc-emit-mov-rax-rdi`
  to move the result into the SYS-V return register, then
  `cc-emit-epilogue`.

The peek-and-dispatch reads the `;` only if it's actually
present, putting back if not — the trailing `cc-expect-punct-c`
catches missing semicolons in the expression form.

`cc-parse-return` emits `xor rax, rax` (3 bytes, the default return
value when no expression is supplied) followed by the standard
`mov rsp, rbp ; pop rbp ; ret` epilogue (5 bytes; Ch 25 §5).
Ch 31's `cc-parse-function` *also* emits the epilogue at function-
body close, which means a function ending with explicit `return`
has an extra unreachable epilogue tacked on.  That's a wasted 8
bytes (zero+epilogue) but harmless.

## Try it

```sh
./build.sh
./test.sh
tests/cc/stage-a-check.sh
```

`tests/cc/G3.c` exercises basic local declarations inside function
bodies; `G9b.c` exercises struct declarations and field arithmetic;
`G14d.c` exercises global variables (`g_counter`) and global arrays
(`g_array[5]`).  `G10b.c` tests `typedef`.

## Exercises

1. Pre-registration of struct tags makes `struct T { struct T*
   next; }` work.  What about `struct A { struct B* b; };
   struct B { struct A* a; };` — mutual recursion?  Trace what
   happens.

2. Storage qualifiers are all no-ops.  Construct a program where
   omitting `static` from a local variable would cause a bug
   (e.g. expecting cross-call persistence) and verify the
   compiler's behaviour.

3. Function-pointer decls use 2-token lookahead.  How could you
   reduce this to 1?  Hint: `(*` is two ASCII bytes; you could
   peek the next byte after `(` via the lexer's `cc-peek-char-2`.

4. `cc-parse-decl-with-base` accepts at most one initializer
   expression.  Could you extend it to handle `int arr[N] =
   {a, b, c};`?  What new vocabulary in the codegen would
   that need?

5. Every field is 8 bytes regardless of `char` vs `int`.  This
   wastes memory on a struct full of `char` fields.  What
   would change in `cc-sd-append-field` to support packed
   layouts?

## Takeaways

- Declarations are a careful tower of lookaheads.  Without
  putback layers and save/restore helpers, distinguishing
  `int (*fp)()` from `int (x);` would be impossible inside a
  recursive-descent parser.
- Pre-registration of struct tags is the small move that makes
  self-referential and mutually-recursive types work without a
  separate two-pass scheme.
- `cc-parse-return` is the only statement parser in this
  chapter because source order forces it to live alongside the
  declaration code; the *statement dispatcher* lives in Ch 30.

Next: Chapter 30 — Statements: if, while, for, switch, break,
continue, goto.
