\ 110-cc-decl.fth — function/declaration parser for the C-subset compiler.
\
\ Parses top-level declarations, function definitions, local declarations,
\ statements, structs, enums, typedefs, and prototypes for the C subset needed
\ to compile M2-Planet.
\
\ The compiled output begins with a 26-byte entry stub at vaddr 0x400078:
\     mov rdi, [rsp]   ; 48 8B 3C 24             (4 bytes, argc)
\     lea rsi, [rsp+8] ; 48 8D 74 24 08          (5 bytes, argv)
\     call <main>      ; E8 <rel32>             (5 bytes)
\     mov rdi, rax     ; 48 89 C7                (3 bytes)
\     mov rax, 60      ; 48 C7 C0 3C 00 00 00    (7 bytes)
\     syscall          ; 0F 05                    (2 bytes)
\
\ Then come the shims, declarations, and function bodies.  main returns its
\ value in rax (SYS-V); the stub moves it to rdi and exits.  The call's rel32
\ is patched after main's vaddr is known.
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

\ ===========================================================================
\ Switch-scrutinee unwind
\ ===========================================================================
\ cc-parse-switch (defined later in this file) parks the outer rbx with
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
    [lit] 1 -
  repeat,
  drop ;

\ cc-parse-return ( -- )  "return" already consumed; parse [expr] ';'.
\ Bare `return;` (no expression) is legal C — emit rax := 0 + epilogue.
\ Peek the next token: if it's ';' the peek already consumed it, so do NOT
\ call cc-expect-punct-c again.  Otherwise putback and parse the expression.
\ Either way, unwind any open switch scrutinees so rbx is restored before
\ the epilogue's ret.
: cc-parse-return
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 59 = and if,
    cc-emit-xor-rax-rax                           \ rax := 0 (no value returned)
    cc-switch-depth @ cc-emit-switch-unwind
    cc-emit-epilogue
  else,
    cc-putback-token
    cc-parse-expr-balanced
    cc-emit-mov-rax-rdi                           \ result -> rax (SYS-V)
    cc-switch-depth @ cc-emit-switch-unwind
    cc-emit-epilogue
    [lit] 59 cc-expect-punct-c                    \ ';'
  then, ;

\ ===========================================================================
\ Statement dispatch
\ ===========================================================================
\ cc-parse-stmt is mutually recursive with cc-parse-if and cc-parse-compound,
\ so we route through cc-parse-stmt-vec.  The vec is set after all three
\ words are defined.

variable cc-parse-stmt-vec

: cc-parse-stmt-tramp  cc-parse-stmt-vec @ execute ;

\ cc-parse-compound ( -- )  '{' (stmt | decl)* '}'
\ Caller has already consumed '{'.  Pushes/pops a scope so locals declared
\ inside the block are discarded at end-of-block.
: cc-parse-compound
  cc-scope-push
  begin,
    cc-next-token-keep
    \ Stop on '}'.
    tok-kind @ tk-punct = tok-num @ [lit] 125 = and 0=
  while,
    cc-putback-token
    cc-parse-stmt-tramp
  repeat,
  \ '}' was consumed by the loop test.
  cc-scope-pop ;

\ cc-parse-if ( -- )  'if' already consumed.
\   if (expr) stmt
\   if (expr) stmt else stmt
\
\ Codegen:
\     <eval cond>
\     test rdi, rdi
\     jz   <else-or-end>            (rel32 fixup #1)
\     <then-body>
\     [if else:]
\     jmp  <end>                    (rel32 fixup #2)
\   else-or-end:
\     <else-body>
\   end:
: cc-parse-if
  [lit]  40 cc-expect-punct-c                     \ '('
  cc-parse-expr-balanced
  [lit]  41 cc-expect-punct-c                     \ ')'

  cc-emit-test-rdi
  cc-emit-jz-rel32-placeholder                    ( fixup-jz )

  cc-parse-stmt-tramp                             \ then-body

  \ Optional else.
  cc-next-token-keep
  tok-kind @ tk-kw = tok-kw-id @ kw-else = and if,
    \ jmp end ; patch jz to here ; else-body ; patch jmp to here.
    cc-emit-jmp-rel32-placeholder                 ( fixup-jz fixup-jmp )
    swap cc-patch-rel32-to-here                   ( fixup-jmp )
    cc-parse-stmt-tramp                           \ else-body
    cc-patch-rel32-to-here                        ( -- )
  else,
    cc-putback-token
    cc-patch-rel32-to-here                        ( -- )
  then, ;

\ ===========================================================================
\ Loop helpers
\ ===========================================================================
\ cc-emit-jmp-vaddr lives here (rather than in 090-cc-emit.fth) because it
\ references cc-base-vaddr, which is defined in 080-cc-elf.fth — loaded AFTER
\ 090-cc-emit.fth but BEFORE 110-cc-decl.fth.

\ cc-emit-jmp-vaddr ( target-vaddr -- )  Emit `E9 <rel32>` to absolute target.
\ After emitting the E9 opcode, cc-out-pos points at the rel32 slot's first
\ byte; the address of the next instruction is cc-base-vaddr + cc-out-pos + 4.
: cc-emit-jmp-vaddr                               ( target-vaddr -- )
  [lit] 233 cc-emit-byte                          \ E9 opcode
  cc-base-vaddr cc-out-pos @ + [lit] 4 + -        \ rel32
  cc-emit-4le ;

\ cc-emit-jnz-vaddr ( target-vaddr -- )  Emit `0F 85 <rel32>` to absolute target.
\ After emitting `0F 85`, cc-out-pos points at the rel32 slot's first byte.
: cc-emit-jnz-vaddr                               ( target-vaddr -- )
  [lit]  15 cc-emit-byte                          \ 0F prefix
  [lit] 133 cc-emit-byte                          \ 85 opcode
  cc-base-vaddr cc-out-pos @ + [lit] 4 + -        \ rel32
  cc-emit-4le ;

\ cc-emit-je-vaddr ( target-vaddr -- )  Emit `0F 84 <rel32>` to absolute
\ target.  Mirror of cc-emit-jnz-vaddr; used by switch dispatch.
: cc-emit-je-vaddr                                ( target-vaddr -- )
  [lit]  15 cc-emit-byte                          \ 0F prefix
  [lit] 132 cc-emit-byte                          \ 84 opcode
  cc-base-vaddr cc-out-pos @ + [lit] 4 + -        \ rel32
  cc-emit-4le ;

\ ===========================================================================
\ Break / continue fixup-list infrastructure
\ ===========================================================================
\ Each loop maintains TWO linked lists of pending forward-jump fixups: one for
\ break-statements (target = end-of-loop), one for continue-statements (target =
\ continue-point — for-loop step, do-while cond test, while-loop top).
\
\ A node is two cells (16 bytes): { fixup-offset (8), next-pointer (8) }.  The
\ list head is just the variable cc-break-stack-head / cc-continue-stack-head.
\ "0" is the empty-list sentinel.
\
\ When entering a loop, save the outer head on the rstack and reset to 0.  When
\ leaving, walk the list patching each fixup's rel32 to a known target vaddr,
\ then restore the outer head.

variable cc-break-stack-head
variable cc-continue-stack-head
\ Temp slot for cc-walk-and-patch-to-vaddr (avoids deeper stack juggling).
variable cc-fixup-target-tmp
variable cc-for-top-vaddr
variable cc-for-end-fixup
variable cc-for-step-start
variable cc-for-step-end

\ cc-add-fixup-to-list is now defined in 090-cc-emit.fth so 100-cc-expr.fth can
\ reference it from cc-parse-primary's forward-function-rvalue path.

: cc-add-break-fixup                              ( off -- )
  cc-break-stack-head cc-add-fixup-to-list ;

: cc-add-continue-fixup                           ( off -- )
  cc-continue-stack-head cc-add-fixup-to-list ;

\ cc-walk-and-patch-to-vaddr ( head-ptr target-vaddr -- )
\ Walk the linked list head-ptr, patching each fixup's rel32 to point at
\ target-vaddr.
: cc-walk-and-patch-to-vaddr                      ( head target -- )
  cc-fixup-target-tmp !                           ( head )
  begin,
    dup [lit] 0 <>
  while,
    \ Stack: ( node-ptr ).  Read the fixup-offset (node[0]).
    dup @                                         ( node off )
    \ rel32 = target - (cc-base-vaddr + off + 4)
    cc-fixup-target-tmp @                         ( node off target )
    over cc-base-vaddr + [lit] 4 + -              ( node off rel32 )
    \ Patch 4 bytes at off with rel32.
    over cc-out-patch-4le                         ( node off )
    drop                                          ( node )
    \ Advance to next node: head := node[8].
    [lit] 8 + @                                   ( next-node )
  repeat,
  drop ;

\ cc-walk-and-patch-imm64-to-vaddr ( head target-vaddr -- )
\ Walk the linked list head, patching each fixup's 8-byte imm64 to the
\ absolute target vaddr.  Used for forward `movabs rdi, imm64` sites that
\ load a function's address as an rvalue before the function is defined.
: cc-walk-and-patch-imm64-to-vaddr                ( head target -- )
  cc-fixup-target-tmp !                           ( head )
  begin,
    dup [lit] 0 <>
  while,
    dup @                                         ( node off )
    cc-fixup-target-tmp @                         ( node off target )
    swap cc-out-patch-8le                         ( node )
    [lit] 8 + @                                   ( next-node )
  repeat,
  drop ;

\ cc-walk-and-patch-fixups ( head-ptr -- )  Patch each fixup to current cc-out-pos.
: cc-walk-and-patch-fixups                        ( head -- )
  cc-base-vaddr cc-out-pos @ +
  cc-walk-and-patch-to-vaddr ;

\ cc-parse-while ( -- )  'while' already consumed.
\
\ Codegen:
\   <top:>           ; record vaddr; continue-target
\   <eval cond>      ; rdi = cond
\   test rdi, rdi
\   jz   <end>       ; rel32 placeholder
\   <body>           ; break/continue inside emit forward-fixed jmps
\   jmp  <top>       ; absolute via cc-emit-jmp-vaddr
\   <end:>           ; patch jz to here; break-target
\
\ The outer break/continue list heads are saved/restored on the rstack.
\ During the body, both heads are 0 (= empty list); break/continue stmts
\ inside add forward-jmp fixup nodes that we patch at end-of-loop.
: cc-parse-while
  \ Save outer break/continue list heads + loop switch-depth on rstack.
  cc-break-stack-head    @ >r
  cc-continue-stack-head @ >r
  cc-loop-switch-depth   @ >r
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !
  cc-switch-depth @ cc-loop-switch-depth !

  [lit]  40 cc-expect-punct-c                     \ '('
  cc-base-vaddr cc-out-pos @ +                    ( top-vaddr )
  cc-parse-expr
  [lit]  41 cc-expect-punct-c                     \ ')'
  cc-emit-test-rdi
  cc-emit-jz-rel32-placeholder                    ( top fixup-end )

  \ Park top-vaddr on rstack so it survives the body parse.
  swap >r                                         ( fixup-end ; R: ... top )

  cc-parse-stmt-tramp                             \ body

  \ Continue target = top-vaddr.  Walk continue list (no-op if empty).
  cc-continue-stack-head @ r@ cc-walk-and-patch-to-vaddr

  \ Emit jmp top, then patch jz fixup.
  r> cc-emit-jmp-vaddr                            ( fixup-end )
  cc-patch-rel32-to-here

  \ Break target = here.  Walk break list (no-op if empty).
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-loop-switch-depth   !
  r> cc-continue-stack-head !
  r> cc-break-stack-head    ! ;

\ cc-parse-for ( -- )  'for' already consumed.
\
\ Grammar: 'for' '(' init? ';' cond? ';' step? ')' stmt
\
\ The step expression appears textually BEFORE the body but must execute
\ AFTER it.  We handle this by recording the source range of the step,
\ scanning past the close-paren, parsing the body, then rewinding the lexer
\ to re-parse the step in place after the body.
\
\ Codegen:
\   <init expr (if any)>
\   <top:>
\   <cond expr (if any, else mov rdi, 1)>
\   test rdi, rdi
\   jz   <end>
\   <body>
\   <step expr (if any)>
\   jmp  <top>
\   <end:>
: cc-parse-for
  [lit]  40 cc-expect-punct-c                     \ '('

  \ --- Init (optional) ---
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 59 = and if,
    \ ';' — empty init; token is consumed.
  else,
    cc-putback-token
    cc-parse-expr
    [lit] 59 cc-expect-punct-c
  then,

  \ Save outer break/continue heads + loop switch-depth on rstack (after
  \ init, since init runs outside the loop and shouldn't see this loop's
  \ break/continue).
  cc-break-stack-head    @ >r
  cc-continue-stack-head @ >r
  cc-loop-switch-depth   @ >r
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !
  cc-switch-depth @ cc-loop-switch-depth !

  \ Top of loop.
  cc-base-vaddr cc-out-pos @ +                    ( top-vaddr )

  \ --- Cond (optional) ---
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 59 = and if,
    \ ';' — empty cond; emit `mov rdi, 1` for unconditional truth.
    [lit] 1 cc-emit-mov-rdi-imm32
  else,
    cc-putback-token
    cc-parse-expr
    [lit] 59 cc-expect-punct-c
  then,

  cc-emit-test-rdi
  cc-emit-jz-rel32-placeholder                    ( top fixup-end )
  cc-for-end-fixup !
  cc-for-top-vaddr !

  \ --- Step source-range capture ---
  \ Before scanning forward we must clear any pending putback so the lexer's
  \ next read after we rewind re-tokenises from the new cc-src-pos.
  \ (No putback is in flight here — cc-expect-punct-c above consumed it — but
  \ the assertion is cheap.)
  [lit] 0 cc-tok-pending !
  cc-src-pos @ cc-for-step-start !
  \ Scan to the matching ')'.  Track depth starting at 1 (we're already
  \ inside the outer for-paren).
  [lit] 1                                         ( depth )
  begin,
    dup [lit] 0 >  cc-eof? 0= and
  while,
    cc-peek-char [lit] 40 = if,
      [lit] 1 +
    else,
      cc-peek-char [lit] 41 = if,
        [lit] 1 -
      then,
    then,
    cc-next-char drop
  repeat,
  drop                                            ( -- )
  \ cc-src-pos is now just past ')'.  step-end = position of ')'.
  cc-src-pos @ [lit] 1 - cc-for-step-end !

  \ --- Body ---
  cc-parse-stmt-tramp

  \ Continue target = HERE (just before step).  Walk continue list.
  cc-continue-stack-head @ cc-walk-and-patch-fixups

  \ --- Re-parse step at recorded range ---
  \ Save current lexer state, set pos := step-start, len := step-end (so the
  \ tokenizer naturally hits EOF at the close-paren).  After parsing, restore.
  cc-src-pos @ >r
  cc-src-len @ >r
  cc-for-step-end @ cc-src-len !
  cc-for-step-start @ cc-src-pos !
  \ Clear any pending putback before re-tokenising at the new position.
  [lit] 0 cc-tok-pending !
  \ Parse step iff there is one (pos < len).
  cc-src-pos @ cc-src-len @ < if,
    cc-parse-expr
  then,
  \ Restore lexer state.
  [lit] 0 cc-tok-pending !
  r> cc-src-len !
  r> cc-src-pos !

  \ Emit jmp top.
  cc-for-top-vaddr @ cc-emit-jmp-vaddr

  \ Patch jz fixup to current position.
  cc-for-end-fixup @ cc-patch-rel32-to-here

  \ Break target = here.  Walk break list (no-op if empty).
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-loop-switch-depth   !
  r> cc-continue-stack-head !
  r> cc-break-stack-head    ! ;

\ ===========================================================================
\ do-while loop
\ ===========================================================================
\ Codegen:
\   <top:>           ; record vaddr (back-target for jnz)
\   <body>           ; break/continue inside emit forward-fixup jmps
\   <continue-here:> ; walk continue list, patch each to here
\   <eval cond>      ; rdi = cond
\   test rdi, rdi
\   jnz <top>        ; absolute backward branch
\   <break-here:>    ; walk break list, patch each to here
\
\ "do" has already been consumed.  Grammar:  do stmt while ( expr ) ;
: cc-parse-do-while
  \ Save outer break/continue heads + loop switch-depth.
  cc-break-stack-head    @ >r
  cc-continue-stack-head @ >r
  cc-loop-switch-depth   @ >r
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !
  cc-switch-depth @ cc-loop-switch-depth !

  \ Record top-vaddr for the backward jnz.
  cc-base-vaddr cc-out-pos @ + >r                 ( ; R: ... top )

  cc-parse-stmt-tramp                             \ body

  \ Continue target = HERE (just before cond test).
  cc-continue-stack-head @ cc-walk-and-patch-fixups

  \ Parse 'while ( expr ) ;'
  kw-while cc-expect-kw-id
  [lit]  40 cc-expect-punct-c                     \ '('
  cc-parse-expr
  [lit]  41 cc-expect-punct-c                     \ ')'
  [lit]  59 cc-expect-punct-c                     \ ';'

  cc-emit-test-rdi
  r> cc-emit-jnz-vaddr                            \ jnz top

  \ Break target = here.
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer heads.
  r> cc-loop-switch-depth   !
  r> cc-continue-stack-head !
  r> cc-break-stack-head    ! ;

\ ===========================================================================
\ switch / case / default
\ ===========================================================================
\ Codegen layout (single-pass with a deferred dispatch table):
\
\     <eval e>                  ; rdi = scrutinee
\     push rbx                  ; preserve outer rbx
\     mov  rbx, rdi             ; rbx = scrutinee for the rest of the switch
\     jmp  <dispatch>           ; rel32, patched after body parse
\   case-K1-body:               ; vaddr recorded in case-list
\     <stmts>
\     [break: jmp <end-A>]      ; (registered as a break fixup)
\     ... (falls through to next case-body if no break)
\   default-body:               ; (or absent)
\     <stmts>
\     jmp <end-A>               ; fall-through past last case (always emitted)
\   dispatch:
\     cmp rbx, K1; je case-K1-body
\     cmp rbx, K2; je case-K2-body
\     ...
\     [jmp default-body | jmp <end-A>]
\   end-A:                      ; break fixups + fall-through + no-default land here
\     pop rbx                   ; restore outer rbx
\   end:
\
\ The break list and the cc-switch-default-vaddr / cc-switch-cases-head state
\ are saved/restored on the rstack across recursion (nested switches and
\ switch-inside-loop and loop-inside-switch all work).

variable cc-switch-cases-head     \ linked list of { K (8), vaddr (8), next (8) }
variable cc-switch-default-vaddr  \ 0 if no default seen

\ cc-add-switch-case ( K body-vaddr -- )  Allocate a 24-byte node and prepend
\ it to cc-switch-cases-head.  The list is built in reverse source order;
\ this is fine because the dispatch table semantics are order-independent
\ (duplicate K is illegal C anyway).
: cc-add-switch-case                              ( K vaddr -- )
  [lit] 24 cc-alloc                               ( K vaddr node )
  >r                                              ( K vaddr ; R: node )
  r@ [lit] 8 + !                                  \ node[8] = vaddr
  r@ !                                            \ node[0] = K
  cc-switch-cases-head @ r@ [lit] 16 + !          \ node[16] = old head
  r> cc-switch-cases-head ! ;                     \ head := node

\ cc-emit-switch-dispatch ( -- )  Walk cc-switch-cases-head, emitting
\ `cmp rbx, K; je <body-vaddr>` for each entry.  Order is reverse of source,
\ which is semantically irrelevant for switch/case.
: cc-emit-switch-dispatch                         ( -- )
  cc-switch-cases-head @                          ( node )
  begin,
    dup [lit] 0 <>
  while,
    dup @                                         ( node K )
    cc-emit-cmp-rbx-imm32                         \ cmp rbx, K
    dup [lit] 8 + @                               ( node body-vaddr )
    cc-emit-je-vaddr                              \ je <body-vaddr>
    [lit] 16 + @                                  \ next
  repeat,
  drop ;

\ cc-parse-switch ( -- )  'switch' already consumed by cc-parse-stmt.
\ Grammar:  switch ( expr ) { (case INT : | default : | stmt)* }
\ The body is a single compound statement; we parse it inline rather than
\ via cc-parse-compound so that case/default can be intercepted.
: cc-parse-switch
  \ Save outer state on rstack.
  cc-switch-cases-head    @ >r
  cc-switch-default-vaddr @ >r
  cc-break-stack-head     @ >r
  [lit] 0 cc-switch-cases-head    !
  [lit] 0 cc-switch-default-vaddr !
  [lit] 0 cc-break-stack-head     !

  \ '(' expr ')'
  [lit]  40 cc-expect-punct-c                     \ '('
  cc-parse-expr                                   \ rdi = scrutinee
  [lit]  41 cc-expect-punct-c                     \ ')'

  \ Save outer rbx, then move scrutinee into rbx.  Mark the switch open so
  \ return/continue/goto inside the body emit a balancing pop (see
  \ cc-emit-switch-unwind).
  cc-emit-push-rbx
  cc-emit-mov-rbx-rdi
  [lit] 1 cc-switch-depth +!

  \ Forward jmp to the dispatch table (emitted after the body).
  cc-emit-jmp-rel32-placeholder                   ( jmp-to-dispatch )
  >r

  \ '{' (case|default|stmt)* '}'
  [lit] 123 cc-expect-punct-c                     \ '{'

  begin,
    cc-next-token-keep
    \ Stop on '}'.
    tok-kind @ tk-punct = tok-num @ [lit] 125 = and 0=
  while,
    \ Three sub-cases: 'case' INT ':', 'default' ':', or generic stmt.
    tok-kind @ tk-kw = tok-kw-id @ kw-case = and if,
      \ 'case' has been consumed; read constant (int literal only
      \ doesn't handle constant-expressions for case labels).
      cc-next-token-keep
      tok-kind @ tk-num <> if,
        [lit] 90 die
      then,
      tok-num @                                   ( K )
      [lit]  58 cc-expect-punct-c                 \ ':'
      cc-base-vaddr cc-out-pos @ +                ( K body-vaddr )
      cc-add-switch-case
    else,
      tok-kind @ tk-kw = tok-kw-id @ kw-default = and if,
        \ 'default' has been consumed.
        [lit]  58 cc-expect-punct-c               \ ':'
        cc-base-vaddr cc-out-pos @ +
        cc-switch-default-vaddr !
      else,
        \ Generic statement — put back, parse via the trampoline.
        cc-putback-token
        cc-parse-stmt-tramp
      then,
    then,
  repeat,
  \ '}' was consumed by the loop test.

  \ Fall-through past the last case-body must skip the dispatch table and
  \ land at end-A.  Emit a jmp placeholder and register it in the break list
  \ so it gets patched together with the rest.
  cc-emit-jmp-rel32-placeholder
  cc-add-break-fixup

  \ Patch the initial jmp-to-dispatch to land here (start of dispatch table).
  r> cc-patch-rel32-to-here                       ( -- )

  \ Emit the dispatch chain.
  cc-emit-switch-dispatch

  \ After the dispatch chain: if there's a default, jump to it; otherwise
  \ register a final jmp to end-A (no case matched, no default).
  cc-switch-default-vaddr @ [lit] 0 <> if,
    cc-switch-default-vaddr @ cc-emit-jmp-vaddr
  else,
    cc-emit-jmp-rel32-placeholder
    cc-add-break-fixup
  then,

  \ end-A: walk break list, patching each fixup to here.
  cc-break-stack-head @ cc-walk-and-patch-fixups

  \ Restore outer rbx; the switch is closed again.
  cc-emit-pop-rbx
  cc-switch-depth @ [lit] 1 - cc-switch-depth !

  \ Restore outer state.
  r> cc-break-stack-head     !
  r> cc-switch-default-vaddr !
  r> cc-switch-cases-head    ! ;

\ ===========================================================================
\ break / continue statements
\ ===========================================================================
\ Each emits a forward-jmp placeholder and prepends its rel32-fixup-offset to
\ the innermost loop's break or continue list.  The enclosing loop walks the
\ list at end-of-loop, patching each fixup's rel32 to the appropriate target.
\
\ cc-parse-break-stmt ( -- )  "break" already consumed by cc-parse-stmt.
\ NB: detecting "break outside any loop" requires a depth counter.  This
\ compiler assumes break/continue appear in valid loop or switch contexts.
: cc-parse-break-stmt
  [lit]  59 cc-expect-punct-c                     \ ';'
  cc-emit-jmp-rel32-placeholder                   ( fixup-offset )
  cc-add-break-fixup ;

\ cc-parse-continue-stmt ( -- )  "continue" already consumed.
\ Unwind the scrutinee pushes of any switches between here and the loop
\ being continued before jumping out of them.
: cc-parse-continue-stmt
  [lit]  59 cc-expect-punct-c                     \ ';'
  cc-switch-depth @ cc-loop-switch-depth @ - cc-emit-switch-unwind
  cc-emit-jmp-rel32-placeholder                   ( fixup-offset )
  cc-add-continue-fixup ;

\ ===========================================================================
\ Label table (per-function) + goto / label definition
\ ===========================================================================
\ Labels are function-local.  We use parallel arrays similar to cc-sym, sized
\ small (64 labels max per function).  cc-label-count is reset to 0 on
\ function entry.
\
\ Each label tracks:
\   cc-label-name-addr [id] : pointer into cc-src-buf where name begins
\   cc-label-name-len  [id] : length
\   cc-label-vaddr     [id] : 0 if undefined, else absolute vaddr of the label
\   cc-label-fixup     [id] : head-pointer of forward-jmp fixup list (0 = none)

[lit] 64 constant cc-label-cap
create cc-label-name-addr  cc-label-cap [lit] 8 * allot
create cc-label-name-len   cc-label-cap [lit] 8 * allot
create cc-label-vaddr      cc-label-cap [lit] 8 * allot
create cc-label-fixup      cc-label-cap [lit] 8 * allot
variable cc-label-count

\ cc-label-slot ( id arr -- addr )  Compute the address of slot id in arr.
: cc-label-slot  swap [lit] 8 * + ;

\ cc-label-vaddr-of ( id -- vaddr )
: cc-label-vaddr-of   cc-label-vaddr   cc-label-slot @ ;
: cc-label-fixup-of   cc-label-fixup   cc-label-slot @ ;
: cc-label-set-vaddr  cc-label-vaddr   cc-label-slot ! ;     \ ( v id -- )
: cc-label-set-fixup  cc-label-fixup   cc-label-slot ! ;     \ ( v id -- )

\ cc-label-find-result holds -1 (= [lit] 0 0=) while still searching, or the id.
variable cc-label-find-result
variable cc-label-find-needle-addr
variable cc-label-find-needle-len

\ cc-label-find ( name-addr name-len -- id-or-neg1 )
: cc-label-find
  cc-label-find-needle-len  !
  cc-label-find-needle-addr !
  [lit] 0 0= cc-label-find-result !               \ -1 = "not found"
  cc-label-count @ [lit] 1 -                      ( i = count-1 )
  begin,
    dup [lit] 0 >=
  while,
    cc-label-find-result @ [lit] 0 0= = if,       \ still searching?
      dup cc-label-name-len cc-label-slot @
      cc-label-find-needle-len @ = if,
        dup cc-label-name-addr cc-label-slot @    ( i entry-addr )
        cc-label-find-needle-addr @ swap
        cc-label-find-needle-len @
        bytes-eq if,
          dup cc-label-find-result !
        then,
      then,
    then,
    [lit] 1 -
  repeat,
  drop
  cc-label-find-result @ ;

\ cc-label-create ( name-addr name-len -- id )  Append a new label entry.
\ Initial vaddr=0 (undefined), fixup=0 (no forward refs yet).
: cc-label-create                                 ( a u -- id )
  cc-label-count @ cc-label-cap >= if,
    [lit] 82 die
  then,
  cc-label-count @                                ( a u id )
  >r                                              \ R: id
  r@ cc-label-name-len  cc-label-slot !           \ store len
  r@ cc-label-name-addr cc-label-slot !           \ store addr
  [lit] 0 r@ cc-label-set-vaddr                   \ vaddr := 0
  [lit] 0 r@ cc-label-set-fixup                   \ fixup-list := 0
  [lit] 1 cc-label-count +!
  r> ;

\ cc-label-find-or-create ( name-addr name-len -- id )
\ Look up by name; if not found, append a new entry.
: cc-label-find-or-create                         ( a u -- id )
  2dup cc-label-find                              ( a u id )
  dup [lit] 0 >= if,
    \ Found.  Discard name args, keep id.
    >r 2drop r>
  else,
    drop                                          ( a u )
    cc-label-create
  then, ;

\ cc-define-label ( name-addr name-len -- )
\ Bind the label to the current cc-out-pos and resolve any forward refs.
\ Errors out (status 81) on duplicate definition.
: cc-define-label                                 ( a u -- )
  cc-label-find-or-create                         ( id )
  \ Reject duplicates.
  dup cc-label-vaddr-of [lit] 0 <> if,
    [lit] 81 die
  then,
  \ Set vaddr.
  dup >r                                          ( id ; R: id )
  cc-base-vaddr cc-out-pos @ + r@ cc-label-set-vaddr
  \ Walk forward-fixup list, patch each to current pos.
  r> cc-label-fixup-of cc-walk-and-patch-fixups ;

\ cc-parse-goto-stmt ( -- )  "goto" already consumed.  Grammar:  goto IDENT ;
\
\ If the target label is already defined, emit an absolute backward jmp.
\ Otherwise emit a forward-jmp placeholder and prepend its rel32-fixup-offset
\ to the label's fixup list (resolved when the label is defined).
: cc-parse-goto-stmt
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 80 die
  then,
  tok-str-addr @ tok-str-len @ cc-label-find-or-create   ( id )

  \ Unwind any open switch scrutinees before jumping (assumes the label is
  \ not inside any switch — a goto to a label inside any switch is unsupported).
  cc-switch-depth @ cc-emit-switch-unwind

  dup cc-label-vaddr-of                           ( id vaddr )
  dup [lit] 0 <> if,
    \ Backward jump to known target.
    cc-emit-jmp-vaddr                             ( id )
    drop                                          ( -- )
  else,
    drop                                          ( id )
    \ Forward ref: emit placeholder, prepend offset to label's fixup list.
    cc-emit-jmp-rel32-placeholder                 ( id fixup-offset )
    over cc-label-fixup-of                        ( id off old-head )
    \ Allocate node: { off, old-head }.
    [lit] 16 cc-alloc                             ( id off old-head node )
    >r                                            ( id off old-head ; R: node )
    swap                                          ( id old-head off ; R: node )
    r@ !                                          ( id old-head ; R: node )
    r@ [lit] 8 + !                                ( id ; R: node )
    \ Set label's fixup-list head to the new node.
    r> swap cc-label-set-fixup                    ( -- )
  then,
  [lit]  59 cc-expect-punct-c ;                   \ ';'

\ ===========================================================================
\ One-token lookahead used to detect "IDENT :" label definitions.
\ ===========================================================================
\ The current putback layer (cc-tok-pending) only buffers one token.  To peek
\ TWO tokens ahead we save the lexer + token state, read one fresh token, and
\ either commit (if it confirms a label) or restore everything (if not).
variable cc-lookahead-save-pos
variable cc-lookahead-save-line
variable cc-lookahead-save-pending
variable cc-lookahead-save-tok-kind
variable cc-lookahead-save-tok-num
variable cc-lookahead-save-tok-addr
variable cc-lookahead-save-tok-len
variable cc-lookahead-save-tok-kw

: cc-lookahead-save
  cc-src-pos     @ cc-lookahead-save-pos      !
  cc-src-line    @ cc-lookahead-save-line     !
  cc-tok-pending @ cc-lookahead-save-pending  !
  tok-kind       @ cc-lookahead-save-tok-kind !
  tok-num        @ cc-lookahead-save-tok-num  !
  tok-str-addr   @ cc-lookahead-save-tok-addr !
  tok-str-len    @ cc-lookahead-save-tok-len  !
  tok-kw-id      @ cc-lookahead-save-tok-kw   ! ;

: cc-lookahead-restore
  cc-lookahead-save-pos      @ cc-src-pos     !
  cc-lookahead-save-line     @ cc-src-line    !
  cc-lookahead-save-pending  @ cc-tok-pending !
  cc-lookahead-save-tok-kind @ tok-kind       !
  cc-lookahead-save-tok-num  @ tok-num        !
  cc-lookahead-save-tok-addr @ tok-str-addr   !
  cc-lookahead-save-tok-len  @ tok-str-len    !
  cc-lookahead-save-tok-kw   @ tok-kw-id      ! ;

\ cc-peek-after-is-colon? ( -- f )
\ Caller has already consumed one token (e.g. IDENT) into tok-* via
\ cc-next-token-keep.  This peeks the FOLLOWING token without consuming.
\ Returns -1 iff that token is the punctuation ':'.
\
\ If the answer is true, the caller should also consume the colon (it has
\ been read into tok-* and cc-tok-pending=0 — i.e. it's "current").
\ If false, this word restores everything so the IDENT remains pending.
: cc-peek-after-is-colon?
  cc-lookahead-save
  cc-next-token
  tok-kind @ tk-punct = tok-num @ [lit] 58 = and
  dup 0= if,
    \ Not a colon — rewind.
    cc-lookahead-restore
  then, ;

\ cc-parse-stmt ( -- )  Dispatch on the leading token.
\ Silently skip any leading storage-class / type-qualifier keywords
\ (static, extern, const, volatile, ...).
: cc-parse-stmt
  cc-skip-storage-quals
  cc-next-token-keep
  cc-tok-is-basic-type-kw? if,
    cc-parse-decl
  else,
    tok-kind @ tk-kw = tok-kw-id @ kw-struct = and if,
      \ `struct TAG ... ;` at stmt scope is always a local declaration
      \ (struct *definition* — `struct TAG { ... };` — is only allowed at top
      \ level).  The 'struct' keyword is the current token and is
      \ already consumed; cc-parse-struct-local-decl reads from here.
      cc-parse-struct-local-decl
    else,
    tok-kind @ tk-kw = tok-kw-id @ kw-return = and if,
      cc-parse-return
    else,
      tok-kind @ tk-kw = tok-kw-id @ kw-if = and if,
        cc-parse-if
      else,
        tok-kind @ tk-kw = tok-kw-id @ kw-while = and if,
          cc-parse-while
        else,
          tok-kind @ tk-kw = tok-kw-id @ kw-for = and if,
            cc-parse-for
          else,
            tok-kind @ tk-kw = tok-kw-id @ kw-do = and if,
              cc-parse-do-while
            else,
            tok-kind @ tk-kw = tok-kw-id @ kw-switch = and if,
              cc-parse-switch
            else,
              tok-kind @ tk-kw = tok-kw-id @ kw-break = and if,
                cc-parse-break-stmt
              else,
                tok-kind @ tk-kw = tok-kw-id @ kw-continue = and if,
                  cc-parse-continue-stmt
                else,
                  tok-kind @ tk-kw = tok-kw-id @ kw-goto = and if,
                    cc-parse-goto-stmt
                  else,
                    tok-kind @ tk-punct = tok-num @ [lit] 123 = and if,
                      cc-parse-compound
                    else,
                      \ Possibly an IDENT followed by ':' — a label definition.
                      \ An IDENT that resolves to a typedef name introduces
                      \ a declaration instead.  Check the symbol table first.
                      tok-kind @ tk-ident = if,
                        \ typedef-led declaration?
                        tok-str-addr @ tok-str-len @ cc-sym-find        ( id-or-neg1 )
                        dup [lit] 0 >= if,
                          dup cc-sym-kind-of sk-typedef = if,
                            \ Resolved typedef: consume IDENT (it IS consumed —
                            \ tok-* still holds it), then parse decl with the
                            \ typedef's encoded base+ptr-depth.
                            cc-sym-val-of                                ( ty )
                            dup ty-base swap ty-ptr                      ( base ptr-depth )
                            cc-parse-decl-with-base
                          else,
                            \ Not a typedef; fall back to label / expr-stmt path.
                            drop
                            tok-str-addr @ tok-str-len @                ( a u )
                            cc-peek-after-is-colon? if,
                              cc-define-label
                            else,
                              2drop
                              cc-putback-token
                              cc-parse-expr-balanced
                              [lit]  59 cc-expect-punct-c
                            then,
                          then,
                        else,
                          \ Symbol not found yet — still might be a forward label.
                          drop
                          tok-str-addr @ tok-str-len @                  ( a u )
                          cc-peek-after-is-colon? if,
                            cc-define-label
                          else,
                            2drop
                            cc-putback-token
                            cc-parse-expr-balanced
                            [lit]  59 cc-expect-punct-c
                          then,
                        then,
                      else,
                        \ Expression statement leading with non-IDENT.
                        cc-putback-token
                        cc-parse-expr-balanced
                        [lit]  59 cc-expect-punct-c
                      then,
                    then,
                  then,
                then,
              then,
            then,
            then,
          then,
        then,
      then,
    then,
    then,
  then, ;

\ Wire the trampoline now that cc-parse-stmt is defined.
' cc-parse-stmt cc-parse-stmt-vec !

\ ===========================================================================
\ Function parsing: multiple functions, params, SYS-V calling convention
\ ===========================================================================
\ The current-function bookkeeping uses two globals so the name token's bytes
\ aren't lost when subsequent tokens are read for the parameter list.
variable cc-fn-name-addr
variable cc-fn-name-len
variable cc-fn-param-count                        \ # params in current function
variable cc-fn-prior-sym-id                       \ prior sk-func id for fwd-fixup walk; -1 if none

\ Pre-baked literal "main" for cc-is-main? — laid out as 4 raw bytes (no length
\ prefix here, because cc-is-main? only consumes 4 bytes).
create cc-main-name-bytes
[lit] 109 c, [lit]  97 c, [lit] 105 c, [lit] 110 c,    \ "main"

\ cc-is-main? ( name-addr name-len -- f )  -1 if (addr, len) names "main".
: cc-is-main?                                     ( addr len -- f )
  dup [lit] 4 = if,
    drop                                          ( addr )
    cc-main-name-bytes swap [lit] 4 bytes-eq
  else,
    drop drop [lit] 0
  then, ;

\ cc-block-end? ( -- f )  After cc-next-token-keep, returns -1 if current
\ token is '}'.  Helper used by the function body loop.
: cc-block-end?
  tok-kind @ tk-punct =
  tok-num @ [lit] 125 = and ;

\ ===========================================================================
\ Function-call codegen (the body of cc-parse-call, wired to cc-parse-call-vec)
\ ===========================================================================

\ cc-emit-call-vaddr ( target-vaddr -- )  Emit `call <abs-target>` (5 bytes).
\ rel32 = target_vaddr - (callsite_after_E8 + 4) = target - (callsite_vaddr+5)
\ where callsite_vaddr = cc-base-vaddr + cc-out-pos@ at the moment of E8.
: cc-emit-call-vaddr
  [lit] 232 cc-emit-byte                          \ E8 opcode
  \ At this point cc-out-pos@ points at the rel32 slot's first byte.
  \ rel32 = target - (cc-base-vaddr + cc-out-pos@ + 4)
  cc-base-vaddr cc-out-pos @ + [lit] 4 + -        ( rel32 )
  cc-emit-4le ;

\ cc-emit-pop-by-arg-index ( arg-index -- )  Emit a pop into the SYS-V arg
\ register corresponding to arg-index (0=rdi, 1=rsi, 2=rdx, 3=rcx, 4=r8, 5=r9).
\ Caller is responsible for not asking past 5.
: cc-emit-pop-by-arg-index
  dup [lit] 0 = if, drop cc-emit-pop-rdi else,
  dup [lit] 1 = if, drop cc-emit-pop-rsi else,
  dup [lit] 2 = if, drop cc-emit-pop-rdx else,
  dup [lit] 3 = if, drop cc-emit-pop-rcx else,
  dup [lit] 4 = if, drop cc-emit-pop-r8  else,
                    drop cc-emit-pop-r9
  then, then, then, then, then, ;

\ cc-emit-pops-for-args ( n -- )  Pop n values off the stack into the first n
\ SYS-V arg registers, in REVERSE order (so the last-pushed value lands in the
\ n-th argument register).  After this, args 1..n live in rdi/rsi/rdx/rcx/r8/r9.
\
\ Walks i = n-1 down to 0, emitting pop-into-reg(i) at each step.  Loop drives
\ a counter on the data stack.
: cc-emit-pops-for-args                           ( n -- )
  [lit] 1 -                                       ( i = n-1 )
  begin,
    dup [lit] 0 >=
  while,
    dup cc-emit-pop-by-arg-index
    [lit] 1 -
  repeat,
  drop ;

\ cc-parse-call ( id -- )  Parse a comma-separated argument list — the leading
\ '(' has ALREADY been consumed by cc-parse-primary (it was the lookahead
\ token that triggered dispatch here).  Evaluate each arg left-to-right
\ (each result pushed onto the stack), then emit the SYS-V argument-register
\ loads, the call, and post-call rdi <- rax move so the caller sees the
\ return value in rdi.
\
\ Stack at entry: ( id ).  The id is the symbol-table id of the callee.
\ Stack at exit:  ( ).
: cc-parse-call
  \ Parse the argument list.  Stack underneath: ( id ).  We thread an
  \ argument count below the id.  Initial state: ( id 0 ).
  [lit] 0                                         ( id arg-count )

  \ Empty arg list?
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 41 = and if,
    \ ')' — empty arg list, leave count = 0.
  else,
    cc-putback-token
    \ Loop: parse one arg, push, increment count; continue while next is ','.
    [lit] 0 0=                                    \ keep-going flag = -1
    begin,
      dup
    while,
      drop                                        ( id arg-count )
      cc-parse-expr-balanced-2                    \ rdi := arg value
      cc-emit-push-rdi
      [lit] 1 +                                   \ count++
      cc-next-token-keep
      tok-kind @ tk-punct = tok-num @ [lit] 44 = and if,
        [lit] 0 0=                                \ continue
      else,
        cc-putback-token
        [lit] 0                                   \ stop
      then,
    repeat,
    drop                                          \ discard final flag
    \ The token AFTER the last arg should be ')'.  Consume it.
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 41 = and 0= if,
      [lit] 36 die
    then,
  then,

  ( id arg-count )

  \ The SYS-V register path supports up to 6 args.  Reject excess.
  dup [lit] 6 > if,
    [lit] 37 die
  then,

  \ NOTE on alignment: argument values are pushed while parsing, then popped
  \ into registers before the call.  The pops restore rsp to its pre-argument
  \ value, which our prologue keeps 16-aligned.  Nested calls happen during
  \ expression parsing before these argument pushes are popped, so they have
  \ their own balanced call sequence.

  \ Pop arg-count values off the stack into the arg registers.
  dup cc-emit-pops-for-args                       ( id arg-count )
  drop                                            ( id )

  \ Dispatch on symbol kind.
  \   sk-func, val != 0 -> direct call: E8 <rel32> to absolute vaddr.
  \   sk-func, val == 0 -> forward call: emit placeholder, register fixup
  \                        on this prototype's cc-sym-extra slot.  When the
  \                        function is later defined, cc-parse-function walks
  \                        the list and patches each rel32.
  \   sk-local + ty-func -> indirect call: load fp slot into rax, call rax.
  \                        rdi/rsi/... already hold args; rax is free.
  dup cc-sym-kind-of sk-func = if,
    dup cc-sym-val-of [lit] 0 = if,
      \ Forward call.  Emit E8 + 4-byte placeholder; thread the slot offset
      \ onto the prototype's fixup list (cc-sym-extra at id).
      cc-emit-call-rel32-placeholder              ( id patch-off )
      swap cc-sym-extra sym-slot                  ( patch-off extra-cell-addr )
      cc-add-fixup-to-list
    else,
      cc-sym-val-of                               ( target-vaddr )
      cc-emit-call-vaddr
    then,
  else,
    dup cc-sym-kind-of sk-local =
    over cc-sym-type-of ty-base ty-func = and if,
      cc-sym-val-of                               ( slot )
      cc-emit-load-local-into-rax                 \ rax := fp value
      cc-emit-call-rax
    else,
      drop
      [lit] 38 die
    then,
  then,

  \ Move return value into rdi (so the caller's expression machinery picks it up).
  cc-emit-mov-rdi-rax ;

\ Wire the trampoline so cc-parse-primary (in 100-cc-expr.fth) can dispatch here.
' cc-parse-call cc-parse-call-vec !

\ ===========================================================================
\ Parameter-list parsing + spill
\ ===========================================================================

\ cc-parse-param-list-loop ( -- )  Parse one or more parameters separated by
\ ','.  T may be int / char / void / long / short / struct TAG / typedef-name,
\ with '*' modifiers.  Consumes the closing ')'.
: cc-parse-param-list-loop
  [lit] 0 0=                                      \ keep-going flag = -1
  begin,
    dup
  while,
    drop
    \ Base type.  Both branches leave ( base ptr-depth-so-far ); the kw path
    \ starts ptr-depth at 0; the typedef path inherits the typedef's encoded
    \ ptr-depth (so FUNCTION = void (*)() stays a function pointer in params).
    cc-next-token-keep
    tok-kind @ tk-kw = if,
      tok-kw-id @ kw-struct = if,
        cc-lookup-struct-tag cc-pending-struct-desc !
        ty-struct [lit] 0
      else,
        \ int/char/void/long/short/unsigned/signed — char is distinguished so
        \ `char* s` params get ty-char + ptr-depth, which the array-index path
        \ needs to emit byte stride / byte load for `s[i]`.  Others collapse
        \ to ty-int.
        [lit] 0 cc-pending-struct-desc !
        tok-kw-id @ kw-char = if,
          ty-char
        else,
          ty-int
        then,
        [lit] 0
      then,
    else,
      tok-kind @ tk-ident = if,
        \ Typedef-name (e.g. FILE, FUNCTION).  Look up and unpack its encoded
        \ base+ptr-depth so function-pointer typedefs survive into param type.
        tok-str-addr @ tok-str-len @ cc-sym-find   ( id )
        dup [lit] 0 < if,
          [lit] 38 die
        then,
        dup cc-sym-kind-of sk-typedef <> if,
          [lit] 38 die
        then,
        [lit] 0 cc-pending-struct-desc !
        cc-sym-val-of                              ( ty )
        dup ty-base swap ty-ptr                    ( base ptr-depth )
      else,
        [lit] 38 die
        ty-int [lit] 0                            \ unreachable
      then,
    then,
    ( base ptr-depth )
    cc-count-stars                                ( base ptr-depth extra )
    +                                              ( base total-ptr )
    ty-make                                       ( ty )
    \ Expect IDENT.
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 38 die
    then,
    \ Add as a local: name in tok-str-addr/len, kind=sk-local, type=ty,
    \ val=current local count (= slot).  Stack on entry: ( ty ).
    tok-str-addr @ tok-str-len @                  ( ty a u )
    rot                                            ( a u ty )
    sk-local swap                                  ( a u sk-local ty )
    cc-fn-local-count @                            ( a u kind ty slot )
    cc-sym-add                                    ( id )
    cc-pending-struct-desc @ swap cc-sym-set-extra
    [lit] 1 cc-fn-local-count +!
    [lit] 1 cc-fn-param-count +!
    \ Continue if next is ','.
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 44 = and if,
      [lit] 0 0=                                  \ continue
    else,
      cc-putback-token
      [lit] 0                                     \ stop
    then,
  repeat,
  drop                                            \ discard flag
  \ Now consume the closing ')'.
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 41 = and 0= if,
    [lit] 39 die
  then, ;

\ Shared lexer/token lookahead save/restore.  Top-level peeking uses this,
\ and parameter parsing uses it for the `(void)` special case.
variable cc-top-save-pos
variable cc-top-save-line
variable cc-top-save-pending
variable cc-top-save-tok-kind
variable cc-top-save-tok-num
variable cc-top-save-tok-addr
variable cc-top-save-tok-len
variable cc-top-save-tok-kw

: cc-top-lookahead-save
  cc-src-pos     @ cc-top-save-pos      !
  cc-src-line    @ cc-top-save-line     !
  cc-tok-pending @ cc-top-save-pending  !
  tok-kind       @ cc-top-save-tok-kind !
  tok-num        @ cc-top-save-tok-num  !
  tok-str-addr   @ cc-top-save-tok-addr !
  tok-str-len    @ cc-top-save-tok-len  !
  tok-kw-id      @ cc-top-save-tok-kw   ! ;

: cc-top-lookahead-restore
  cc-top-save-pos      @ cc-src-pos     !
  cc-top-save-line     @ cc-src-line    !
  cc-top-save-pending  @ cc-tok-pending !
  cc-top-save-tok-kind @ tok-kind       !
  cc-top-save-tok-num  @ tok-num        !
  cc-top-save-tok-addr @ tok-str-addr   !
  cc-top-save-tok-len  @ tok-str-len    !
  cc-top-save-tok-kw   @ tok-kw-id      ! ;

\ cc-parse-param-list ( -- )  Parse a possibly-empty comma-separated list of
\ parameters.  Caller has NOT yet consumed any tokens.  When this returns the
\ closing ')' has been consumed.  Each parameter becomes an sk-local symbol.
: cc-parse-param-list
  [lit] 0 cc-fn-param-count !
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 41 = and if,
    \ ')' — empty list, done.
  else,
    \ Special case: `(void)` = no params.  Peek for kw-void followed by ')'.
    tok-kind @ tk-kw = tok-kw-id @ kw-void = and if,
      cc-top-lookahead-save
      cc-next-token                               \ advance past void; tok-* := next
      tok-kind @ tk-punct = tok-num @ [lit] 41 = and >r
      cc-top-lookahead-restore
      r> if,
        \ It IS '(void)'.  void is already consumed; now consume ')'.
        cc-next-token
      else,
        cc-putback-token
        cc-parse-param-list-loop
      then,
    else,
      cc-putback-token
      cc-parse-param-list-loop
    then,
  then, ;

\ cc-emit-spill-params ( -- )  In the function prologue, spill the SYS-V
\ argument registers (rdi/rsi/rdx/rcx/r8/r9) into the local slots reserved
\ for them by cc-parse-param-list (slots 0..cc-fn-param-count-1).
: cc-emit-spill-params
  cc-fn-param-count @ [lit] 1 >= if,
    [lit] 0 cc-emit-store-local
  then,
  cc-fn-param-count @ [lit] 2 >= if,
    [lit] 1 cc-emit-store-local-from-rsi
  then,
  cc-fn-param-count @ [lit] 3 >= if,
    [lit] 2 cc-emit-store-local-from-rdx
  then,
  cc-fn-param-count @ [lit] 4 >= if,
    [lit] 3 cc-emit-store-local-from-rcx
  then,
  cc-fn-param-count @ [lit] 5 >= if,
    [lit] 4 cc-emit-store-local-from-r8
  then,
  cc-fn-param-count @ [lit] 6 >= if,
    [lit] 5 cc-emit-store-local-from-r9
  then, ;

\ ===========================================================================
\ cc-parse-fn-return-type ( -- )
\ Consume the function's return type, which may be:
\   - int / char / void
\   - struct TAG       (tag ident consumed)
\   - typedef-name     (any non-keyword ident — FILE, etc.)
\ Followed by zero or more '*' modifiers.  Codegen treats every return as a
\ single rax-sized value, so the type is not recorded — it's just consumed.
: cc-parse-fn-return-type
  cc-next-token-keep
  tok-kind @ tk-kw = if,
    tok-kw-id @ kw-struct = if,
      cc-next-token-keep
      tok-kind @ tk-ident <> if,
        [lit] 42 die
      then,
    then,
  else,
    tok-kind @ tk-ident <> if,
      [lit] 43 die
    then,
  then,
  cc-count-stars drop ;

\ cc-parse-function — one user-defined `T NAME(params) { body }`.  T may be
\ int / char / void / struct TAG / typedef-name, optionally followed by '*'s.
\ ===========================================================================
\ Layout:
\   1. Consume return type, NAME, '('.
\   2. Capture the function's start vaddr (cc-base-vaddr + cc-out-pos@) and
\      register it in the symbol table BEFORE parsing params/body — this lets
\      the body call this function recursively, and is also needed before any
\      forward-call patch.
\   3. If the name is "main", record cc-main-vaddr for the entry stub.
\   4. Push a fresh scope.  Reset local counter.
\   5. Parse the parameter list — each param becomes a local in slots 0..N-1.
\   6. Consume `{`.
\   7. Emit prologue (256-byte frame, room for 32 locals incl. params).
\   8. Spill arg registers into their slots.
\   9. Loop: parse statements until `}`.
\  10. Emit implicit return (xor rax,rax + epilogue) — wasted bytes if the
\      function already ended with a `return`, but harmless.
\  11. Pop scope.
: cc-parse-function
  cc-parse-fn-return-type
  \ Function name.
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 41 die
  then,
  tok-str-addr @ cc-fn-name-addr !
  tok-str-len  @ cc-fn-name-len  !

  [lit]  40 cc-expect-punct-c                     \ '('

  \ Capture any prior sk-func entry for this name BEFORE adding our own,
  \ so we can walk its forward-call fixup list and patch each call site.
  \ cc-sym-find returns the newest match; if a prototype was registered
  \ earlier (cc-register-fn-proto), that's what we get.  -1 means none.
  cc-fn-name-addr @ cc-fn-name-len @ cc-sym-find
  cc-fn-prior-sym-id !

  \ Register the function in the symbol table BEFORE pushing the per-function
  \ scope, so the entry survives cc-scope-pop at function-end and remains
  \ visible to subsequent function bodies.  Its vaddr is the address of the
  \ next byte we'll emit (the prologue's first byte, which we haven't emitted
  \ yet — but we will, immediately after the param list and the spill).
  cc-fn-name-addr @ cc-fn-name-len @
  sk-func
  ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +                    ( a u kind ty vaddr )
  cc-sym-add drop

  \ Patch any forward-call fixups registered against the prior prototype.
  \ The fixup list head lives in that entry's cc-sym-extra cell.  After
  \ patching we zero the head so a repeat definition doesn't double-patch.
  \ cc-sym-extra2 holds a parallel list for `movabs rdi, imm64` rvalue sites
  \ (function-pointer references that appear before the definition).
  cc-fn-prior-sym-id @ [lit] 0 >= if,
    cc-fn-prior-sym-id @ cc-sym-kind-of sk-func = if,
      cc-fn-prior-sym-id @ cc-sym-extra-of
      cc-base-vaddr cc-out-pos @ +
      cc-walk-and-patch-to-vaddr
      [lit] 0 cc-fn-prior-sym-id @ cc-sym-set-extra
      cc-fn-prior-sym-id @ cc-sym-extra2-of
      cc-base-vaddr cc-out-pos @ +
      cc-walk-and-patch-imm64-to-vaddr
      [lit] 0 cc-fn-prior-sym-id @ cc-sym-set-extra2
    then,
  then,

  \ If this is main, also record the vaddr for the entry-stub patch.
  cc-fn-name-addr @ cc-fn-name-len @ cc-is-main? if,
    cc-base-vaddr cc-out-pos @ + cc-main-vaddr !
  then,

  \ Reset locals; push scope (so params + body locals are popped together).
  [lit] 0 cc-fn-local-count !
  \ Reset per-function label table, break/continue stacks, switch depths.
  [lit] 0 cc-label-count !
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !
  [lit] 0 cc-switch-depth        !
  [lit] 0 cc-loop-switch-depth   !
  cc-scope-push

  \ Parameter list (consumes through ')').
  cc-parse-param-list

  [lit] 123 cc-expect-punct-c                     \ '{'

  \ Prologue.
  [lit] 256 cc-emit-prologue

  \ Spill SYS-V argument registers into local slots 0..N-1.
  cc-emit-spill-params

  \ Body: stmt* until '}'.
  begin,
    cc-next-token-keep
    cc-block-end? 0=
  while,
    cc-putback-token
    cc-parse-stmt-tramp
  repeat,
  \ '}' was consumed by the loop test.

  \ Implicit return: if the body already ended with `return`, this is a few
  \ bytes of unreachable epilogue — harmless.  If it didn't, the function
  \ falls through to here and we need to terminate properly.
  cc-emit-xor-rax-rax                             \ rax := 0 (default return)
  cc-emit-epilogue

  cc-scope-pop ;

\ ===========================================================================
\ Enum and typedef definitions (file-scope only).
\ ===========================================================================
\ Enum:  `enum [TAG] { NAME (= INT)?, NAME, ... };`
\ Typedef: `typedef BASE '*'* NAME ;`   (BASE = int / char / void / struct TAG)
\
\ Both register their introduced names in the symbol table so later code can
\ reference them via the standard cc-sym-find path.

variable cc-enum-next-val

\ cc-parse-enum-def ( -- )  'enum' keyword has been consumed by the dispatcher.
\ Parses an optional tag, then `{ enumerator-list };`.
\ Each enumerator becomes an sk-enum entry whose val is the enumerator's
\ integer value (0-based by default, restart-from-N after `= N`).
: cc-parse-enum-def
  \ Optional tag — discard.
  cc-next-token-keep
  tok-kind @ tk-ident = if,
    \ Tag IDENT — ignore.
  else,
    cc-putback-token
  then,

  [lit] 123 cc-expect-punct-c                     \ '{'

  [lit] 0 cc-enum-next-val !

  \ Enumerator loop.
  [lit] 0 0=                                       \ keep-going flag = -1
  begin,
    dup
  while,
    drop
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 100 die
    then,
    tok-str-addr @ tok-str-len @                  ( a u )

    \ Optional `= INT_LITERAL`.
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 61 = and if,
      cc-next-token-keep
      tok-kind @ tk-num <> if,
        [lit] 102 die
      then,
      tok-num @ cc-enum-next-val !
    else,
      cc-putback-token
    then,

    \ Add to symbol table as sk-enum.  ( a u kind type val )
    sk-enum
    [lit] 0                                       \ type unused
    cc-enum-next-val @                            \ val
    cc-sym-add drop

    [lit] 1 cc-enum-next-val +!

    \ Separator: ',' continues, '}' terminates.  A trailing ',' before '}'
    \ is allowed: peek the next token; if it's '}', stop.
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 44 = and if,
      \ Peek to allow trailing comma.
      cc-next-token-keep
      tok-kind @ tk-punct = tok-num @ [lit] 125 = and if,
        cc-putback-token                           \ leave '}' for the close
        [lit] 0                                    \ stop
      else,
        cc-putback-token                           \ not '}', let next iter read
        [lit] 0 0=                                 \ continue
      then,
    else,
      tok-kind @ tk-punct = tok-num @ [lit] 125 = and if,
        cc-putback-token                           \ leave '}' for the close
        [lit] 0                                    \ stop
      else,
        [lit] 101 die
      then,
    then,
  repeat,
  drop                                             \ discard final flag

  [lit] 125 cc-expect-punct-c                     \ '}'
  [lit]  59 cc-expect-punct-c ;                   \ ';'

\ cc-parse-typedef ( -- )  'typedef' has been consumed by the dispatcher.
\ Grammar: typedef BASE '*'* NAME ';'
\ Supported bases: int / char / void / struct TAG / another typedef.
\ Registers NAME as sk-typedef with val = encoded type word.
\
\ Uses cc-td-ty to stage the type so the data stack stays shallow across
\ keyword / pointer / IDENT parsing — easier than r-stack juggling.
variable cc-td-ty
: cc-parse-typedef
  cc-next-token-keep
  \ Parse base type into cc-td-ty.
  tok-kind @ tk-kw = if,
    tok-kw-id @ kw-int = if,
      ty-int [lit] 0 ty-make cc-td-ty !
    else, tok-kw-id @ kw-char = if,
      ty-char [lit] 0 ty-make cc-td-ty !
    else, tok-kw-id @ kw-void = if,
      ty-void [lit] 0 ty-make cc-td-ty !
    else, tok-kw-id @ kw-struct = if,
      cc-lookup-struct-tag drop
      ty-struct [lit] 0 ty-make cc-td-ty !
    else,
      [lit] 110 die
    then, then, then, then,
  else,
    tok-kind @ tk-ident = if,
      tok-str-addr @ tok-str-len @ cc-sym-find
      dup [lit] 0 < if,
        [lit] 111 die
      then,
      dup cc-sym-kind-of sk-typedef <> if,
        [lit] 112 die
      then,
      cc-sym-val-of cc-td-ty !
    else,
      [lit] 113 die
    then,
  then,

  \ Add pointer stars onto whatever base we got.
  cc-count-stars                                   ( extra-stars )
  cc-td-ty @ +                                     ( final-ty )
  cc-td-ty !

  \ Distinguish:
  \   typedef BASE *... NAME ';'                  (simple alias)
  \   typedef BASE (*NAME) ( params ) ';'         (function-pointer typedef)
  \ M2-Planet's gcc_req.h uses the fn-ptr form for `typedef void (*FUNCTION)(void);`.
  \ The return type and parameter types are parsed-and-discarded; NAME is
  \ registered as a pointer-to-function (ty-func, depth 1), matching how
  \ encodes inline `int (*op)(int)` locals — sufficient for parse-through
  \ without enabling actual indirect call via a typedef'd name yet.
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 40 = and if,
    \ '(' — function-pointer typedef.  Consume one or more '*'s, then IDENT,
    \ then ')'.  Then consume the parameter list parens (balanced).
    cc-count-stars drop                            \ at least one star expected
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 116 die
    then,
    tok-str-addr @ tok-str-len @                   ( a u )
    [lit] 41 cc-expect-punct-c                     \ ')'
    [lit] 40 cc-expect-punct-c                     \ '(' of param list
    \ Skip tokens paren-balanced until matching ')'.  Depth starts at 1.
    [lit] 1
    begin,
      dup [lit] 0 >
    while,
      cc-next-token-keep
      tok-kind @ tk-punct = if,
        tok-num @ [lit] 40 = if, [lit] 1 + else,
        tok-num @ [lit] 41 = if, [lit] 1 - else,
        then, then,
      then,
    repeat,
    drop                                           ( a u )
    sk-typedef [lit] 0                             ( a u kind type )
    ty-func [lit] 1 ty-make                        ( a u kind type val )
    cc-sym-add drop
  else,
    \ Plain IDENT (the new typedef name) — putback first since we just peeked.
    tok-kind @ tk-ident <> if,
      [lit] 114 die
    then,
    tok-str-addr @ tok-str-len @                   ( a u )
    sk-typedef [lit] 0 cc-td-ty @                  ( a u kind type val )
    cc-sym-add drop
  then,

  [lit] 59 cc-expect-punct-c ;                    \ ';'

\ ---------------------------------------------------------------------------
\ Top-level forward-decl / file-scope-var elision.
\ ---------------------------------------------------------------------------
\ Our compiler only knows how to emit code for `int NAME(params) { body }`
\ function definitions.  When parsing real-world C headers we encounter a
\ profusion of other top-level forms:
\
\   void f(args);             /* forward fn decl, non-int return type */
\   char* f(args);            /* forward fn decl, pointer return type */
\   struct T* f(args);        /* forward fn decl, struct-ptr return type */
\   int f(args);              /* forward fn decl, int return type (no body) */
\   extern int g;             /* file-scope variable */
\   struct T* g_list;         /* file-scope variable */
\
\ None of these need to GENERATE anything in our target (the body is missing
\ for forward decls; file-scope vars aren't yet supported).  But they DO need
\ to PARSE without exploding so the headers can flow through.
\
\ Strategy: at top level, when we see a type-introducing keyword (int / char /
\ void / struct / typedef-name) that isn't a struct/enum/typedef DEFINITION,
\ peek ahead through balanced parens for the next ';' vs '{':
\   - ';' first → forward decl or file-scope var → elide everything up to and
\     including that ';'.
\   - '{' first → function definition.  Rewind and dispatch to cc-parse-function
\     which expects 'int' return type (so 'void f() { ... }' will still fail).
\
\ The peek uses a save/restore of the lexer state (cc-src-pos / cc-src-line /
\ cc-tok-pending plus tok-* globals), separate from cc-fnptr-* slots so it
\ won't conflict with nested function-body parsing.

\ cc-top-peek-is-fn-def? ( -- f )
\ Scan tokens forward (paren-balanced) until we hit ';' or '{' at depth 0,
\ or EOF.  Return -1 iff '{' is hit first.  ALWAYS restores lexer state.
\ Loop convention: begin, COND while, repeat, runs while COND is non-zero.
\ So we push -1 (continue) for "keep scanning" and 0 (stop) to exit.
variable cc-top-peek-result
variable cc-top-peek-depth
variable cc-top-peek-go                            \ -1 keep scanning, 0 stop

: cc-top-peek-is-fn-def?
  cc-top-lookahead-save
  [lit] 0 cc-top-peek-depth !
  [lit] 0 cc-top-peek-result !                  \ default: not a fn def
  [lit] 0 0= cc-top-peek-go !                   \ -1 = keep scanning
  begin,
    cc-top-peek-go @
  while,
    cc-next-token-keep
    tok-kind @ tk-eof = if,
      [lit] 0 cc-top-peek-go !
    else,
      tok-kind @ tk-punct = if,
        tok-num @ [lit] 40 = if, [lit] 1 cc-top-peek-depth +! then,
        tok-num @ [lit] 41 = if, [lit] 1 cc-top-peek-depth -! then,
        tok-num @ [lit] 59 = if,                  \ ';'
          cc-top-peek-depth @ [lit] 0 = if,
            [lit] 0 cc-top-peek-result !
            [lit] 0 cc-top-peek-go !
          then,
        then,
        tok-num @ [lit] 123 = if,                 \ '{'
          cc-top-peek-depth @ [lit] 0 = if,
            [lit] 0 0= cc-top-peek-result !
            [lit] 0 cc-top-peek-go !
          then,
        then,
      then,
    then,
  repeat,
  cc-top-lookahead-restore
  cc-top-peek-result @ ;

\ cc-top-peek-has-paren? ( -- f )
\ Walks tokens forward (paren-balanced) until ';' or '{' or EOF.  Returns -1
\ iff at least one '(' was encountered before the terminator.  Always restores
\ lexer state.  Used to distinguish function prototypes from global decls when
\ cc-top-peek-is-fn-def? has already returned 0.
variable cc-top-paren-flag
variable cc-top-paren-go
: cc-top-peek-has-paren?
  cc-top-lookahead-save
  [lit] 0 cc-top-paren-flag !
  [lit] 0 0= cc-top-paren-go !
  begin,
    cc-top-paren-go @
  while,
    cc-next-token-keep
    tok-kind @ tk-eof = if,
      [lit] 0 cc-top-paren-go !
    else,
      tok-kind @ tk-punct = if,
        tok-num @ [lit] 40 = if, [lit] 0 0= cc-top-paren-flag ! then,
        tok-num @ [lit] 59 = if, [lit] 0 cc-top-paren-go ! then,
        tok-num @ [lit] 123 = if, [lit] 0 cc-top-paren-go ! then,
      then,
    then,
  repeat,
  cc-top-lookahead-restore
  cc-top-paren-flag @ ;

\ cc-top-skip-to-semi ( -- )
\ Consume tokens through and including the next top-level ';'.  Paren-balanced
\ so commas / parens inside parameter lists don't fool us.  If we run into
\ EOF first, we exit cleanly so the outer loop also exits.
variable cc-top-skip-depth
variable cc-top-skip-go
: cc-top-skip-to-semi
  [lit] 0 cc-top-skip-depth !
  [lit] 0 0= cc-top-skip-go !
  begin,
    cc-top-skip-go @
  while,
    cc-next-token-keep
    tok-kind @ tk-eof = if,
      [lit] 0 cc-top-skip-go !
    else,
      tok-kind @ tk-punct = if,
        tok-num @ [lit] 40 = if, [lit] 1 cc-top-skip-depth +! then,
        tok-num @ [lit] 41 = if, [lit] 1 cc-top-skip-depth -! then,
        tok-num @ [lit] 59 = if,
          cc-top-skip-depth @ [lit] 0 = if,
            [lit] 0 cc-top-skip-go !
          then,
        then,
      then,
    then,
  repeat, ;

\ cc-register-fn-proto ( -- )  Parse `T '*'* NAME (...);` and register NAME
\ as sk-func with vaddr=0 so call sites resolve.  When the actual definition
\ is later parsed, cc-parse-function adds a newer sk-func entry; cc-sym-find
\ (newest-first) returns the definition for backward calls.  Forward calls
\ (call to fn before its def) are patched through the symbol's fixup list.
\ Caller has put-back the first token of the prototype.  Consumes through ';'.
\
\ Idempotency: real-world headers often re-declare the same prototype across
\ TUs (e.g. M2-Planet has `struct token_list* read_all_tokens(...)` in both
\ cc_macro.c and cc.c, with the definition in cc_reader.c sandwiched in
\ between).  Concatenated into our monolith the post-definition prototype
\ would register a new sk-func with val=0, and because cc-sym-find returns
\ the newest match, every later call site emits a forward-call placeholder
\ against a stale entry whose fixups are never patched.  Skip the re-add if
\ the name is already an sk-func.
: cc-register-fn-proto
  cc-parse-fn-return-type
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 44 die
  then,
  tok-str-addr @ tok-str-len @                    ( a u )
  2dup cc-sym-find                                ( a u id-or-neg1 )
  dup [lit] 0 >= if,
    cc-sym-kind-of sk-func = if,
      \ Already registered as a function — drop the leftover ( a u ).
      2drop
      cc-top-skip-to-semi
    else,
      sk-func ty-int [lit] 0 ty-make [lit] 0      ( a u kind ty val=0 )
      cc-sym-add drop
      cc-top-skip-to-semi
    then,
  else,
    drop                                          ( a u )
    sk-func ty-int [lit] 0 ty-make [lit] 0        ( a u kind ty val=0 )
    cc-sym-add drop
    cc-top-skip-to-semi
  then, ;

\ ===========================================================================
\ File-scope global variable declaration.
\ ===========================================================================
\ Parses ONE top-level declaration of the form
\
\    T '*'* name ';'
\    T '*'* name '=' int-literal ';'
\    T '*'* name '[' N ']' ';'
\
\ where T is one of int/char/void/long/short/etc.  The base type is consumed
\ by the caller (cc-parse-function-list) — when we get here the lookahead has
\ been put back so cc-next-token-keep yields the type keyword again.  We
\ re-consume it, accept star-modifiers, then expect IDENT, then optional
\ [N] OR optional `= NUM`, then ';'.
\
\ Storage is allocated in cc-globals-buf (8 bytes per scalar — a struct
\ VALUE gets its full descriptor size rounded up to 8 — N*8 per array).
\ Scalar initializer (must be an int literal — possibly negated) is written
\ into the buffer directly so the runtime image already contains the value.
\ Arrays start zero-initialized.  Function-pointer, aggregate, and struct
\ initializers are not implemented.
\
\ Errors abort with status 16x so they're distinguishable
\ from older codes).

variable cc-gdecl-base
variable cc-gdecl-name-a
variable cc-gdecl-name-u
variable cc-gdecl-n                                \ element count (>=1)
variable cc-gdecl-is-array
variable cc-gdecl-slot
variable cc-gdecl-desc
variable cc-gdecl-ptr-depth

\ cc-parse-global-int-literal ( -- v )
\ Read a single int literal as an initializer value.  Accepts an optional
\ leading '-' for negative literals.  Anything else aborts.
: cc-parse-global-int-literal                     ( -- v )
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 45 = and if,
    cc-next-token-keep
    tok-kind @ tk-num <> if,
      [lit] 163 die
    then,
    [lit] 0 tok-num @ -
  else,
    tok-kind @ tk-num <> if,
      [lit] 163 die
    then,
    tok-num @
  then, ;

\ cc-gdecl-scalar-bytes ( -- n )  Byte size of one non-array global slot.
\ A struct VALUE (ty-struct base, zero pointer depth, descriptor known)
\ needs its full descriptor size, rounded up to a multiple of 8 — a flat 8
\ would let stores past the first field clobber the next global.  Everything
\ else — ints, chars, pointers, struct pointers, opaque struct refs — is one
\ 8-byte slot.
: cc-gdecl-scalar-bytes                           ( -- n )
  cc-gdecl-base @ ty-struct =
  cc-gdecl-ptr-depth @ [lit] 0 = and
  cc-gdecl-desc @ [lit] 0 <> and if,
    cc-gdecl-desc @ cc-sd-total-size [lit] 7 + [lit] 8 / [lit] 8 *
  else,
    [lit] 8
  then, ;

\ cc-parse-global-decl ( -- )  Caller has already done cc-skip-storage-quals;
\ the next token is the base-type keyword OR a typedef-name IDENT.  Consumes
\ through ';'.
: cc-parse-global-decl                            ( -- )
  [lit] 0 cc-gdecl-desc !
  ty-int cc-gdecl-base !
  \ Read base type.
  cc-next-token-keep
  tok-kind @ tk-kw = if,
    \ Support struct TAG as base type.
    tok-kw-id @ kw-struct = if,
      ty-struct cc-gdecl-base !
      \ Soft lookup: descriptor pointer if the struct is defined, 0 otherwise.
      \ cc_globals.c declares `struct type* foo;` without a `struct type {...}`
      \ in scope — that's an opaque-pointer pattern we still need to parse.
      cc-lookup-struct-tag-soft cc-gdecl-desc !
    then,
    \ Distinguish `char` from other primitives so `char* foo;` records ty-char
    \ in the symbol table.  Without this, `char* hold_string;` looks identical
    \ to `int* foo;` and the array-index path uses qword stride/load on its
    \ bytes — corrupting tokenizer scratch buffers in M2-Planet's preprocessor.
    \ int/void/long/short/etc. all collapse to ty-int (storage is 8 bytes
    \ regardless; only the byte-stride dispatch cares).
    tok-kw-id @ kw-char = if,
      ty-char cc-gdecl-base !
    then,
  else,
    \ Typedef-name IDENT (FILE, uint8_t, ...).  We don't need to verify it
    \ actually resolves to a known typedef — the caller already determined
    \ this is a declaration via cc-top-peek-* lookahead.
    tok-kind @ tk-ident <> if,
      [lit] 160 die
    then,
  then,

  \ Star-modifiers (pointer depth).
  cc-count-stars cc-gdecl-ptr-depth !

  \ Name IDENT.
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 161 die
  then,
  tok-str-addr @ cc-gdecl-name-a !
  tok-str-len  @ cc-gdecl-name-u !

  \ Peek next token: '[', '=', or ';'.
  cc-next-token-keep
  [lit] 0 cc-gdecl-is-array !
  [lit] 1 cc-gdecl-n !

  tok-kind @ tk-punct = tok-num @ [lit] 91 = and if,
    \ Array form: 'T name [ N ]'.
    cc-next-token-keep
    tok-kind @ tk-num <> if,
      [lit] 162 die
    then,
    tok-num @ cc-gdecl-n !
    [lit] 0 0= cc-gdecl-is-array !
    [lit] 93 cc-expect-punct-c                      \ ']'
    [lit] 59 cc-expect-punct-c                      \ ';'
  else,
    tok-kind @ tk-punct = tok-num @ [lit] 61 = and if,
      \ Scalar with initializer.  Allocate slot first so we can write the
      \ initializer bytes; then add the symbol.
      cc-gdecl-scalar-bytes cc-globals-alloc
      cc-gdecl-slot !
      cc-parse-global-int-literal
      cc-gdecl-slot @ cc-globals-store-8le
      [lit] 59 cc-expect-punct-c                    \ ';'
    else,
      tok-kind @ tk-punct = tok-num @ [lit] 59 = and if,
        \ Bare uninitialized scalar.  Allocate the slot.
        cc-gdecl-scalar-bytes cc-globals-alloc cc-gdecl-slot !
      else,
        [lit] 164 die
      then,
    then,
  then,

  \ For arrays, allocate the slot now (initializer was not consumed above).
  cc-gdecl-is-array @ if,
    cc-gdecl-n @ [lit] 8 * cc-globals-alloc cc-gdecl-slot !
  then,

  \ Register the symbol.  Stack target for cc-sym-add: ( a u kind type val ).
  cc-gdecl-name-a @ cc-gdecl-name-u @               ( a u )
  sk-global                                          ( a u kind )
  cc-gdecl-base @ cc-gdecl-ptr-depth @ ty-make      ( a u kind type )
  cc-gdecl-slot @                                    ( a u kind type val )
  cc-sym-add                                         ( id )

  \ Arrays: record element count in the extra field so the codegen path can
  \ tell array decay from scalar deref.
  cc-gdecl-is-array @ if,
    cc-gdecl-n @ swap cc-sym-set-extra
  else,
    \ Not an array — record the struct descriptor if any.
    cc-gdecl-desc @ swap cc-sym-set-extra
  then, ;

\ cc-finalize-globals ( -- )  After the entire program has been parsed and
\ all functions emitted, append cc-globals-buf to cc-out-buf and patch every
\ recorded fixup to point at the now-known global vaddrs.
\
\ cc-globals-base-vaddr is set to cc-base-vaddr + (cc-out-pos at the moment
\ globals are appended).  Once that's known, each fixup's imm64 placeholder
\ is overwritten with (cc-globals-base-vaddr + slot).
: cc-finalize-globals
  cc-base-vaddr cc-out-pos @ + cc-globals-base-vaddr !
  \ Append cc-globals-pos bytes from cc-globals-buf to cc-out-buf.
  [lit] 0
  begin, dup cc-globals-pos @ < while,
    dup cc-globals-buf + c@ cc-emit-byte
    [lit] 1 +
  repeat, drop
  \ Patch each fixup.  i walks 0..cc-gfixup-count-1.
  [lit] 0
  begin, dup cc-gfixup-count @ < while,
    dup cc-gfixup-slot     sym-slot @              \ slot
    cc-globals-base-vaddr @ +                       \ vaddr = base + slot
    over cc-gfixup-out-pos sym-slot @              \ patch-offset
    cc-out-patch-8le
    [lit] 1 +
  repeat, drop ;

\ cc-parse-function-list ( -- )  Loop over top-level declarations until EOF.
\ See the long comment above for the elision rules.
: cc-parse-function-list
  begin,
    cc-skip-storage-quals
    cc-next-token-keep
    tok-kind @ tk-eof = 0=
  while,
    tok-kind @ tk-kw = if,
      tok-kw-id @ kw-struct = if,
        \ Four forms to distinguish:
        \   `struct TAG { ... };`         → struct definition
        \   `struct TAG* foo(...) { ... }` → function definition (struct-ptr return)
        \   `struct TAG* foo(...);`        → fn proto → register with vaddr=0
        \   `struct TAG* g;`               → file-scope var → cc-parse-global-decl
        cc-top-lookahead-save
        cc-next-token                              \ consume tag IDENT (lookahead)
        cc-next-token                              \ peek next token
        tok-kind @ tk-punct = tok-num @ [lit] 123 = and >r
        cc-top-lookahead-restore
        r> if,
          cc-parse-struct-def
        else,
          cc-putback-token
          cc-top-peek-is-fn-def? if,
            cc-parse-function
          else,
            cc-top-peek-has-paren? if,
              cc-register-fn-proto
            else,
              cc-parse-global-decl
            then,
          then,
        then,
      else,
        tok-kw-id @ kw-enum = if,
          cc-parse-enum-def
        else,
          tok-kw-id @ kw-typedef = if,
            cc-parse-typedef
          else,
            \ int/char/void/long/short/etc. — could be fn def or fwd decl/var.
            cc-putback-token
            cc-top-peek-is-fn-def? if,
              cc-parse-function
            else,
              cc-top-peek-has-paren? if,
                \ Function prototype `T name(...);` — register as sk-func.
                cc-register-fn-proto
              else,
                \ File-scope global variable.
                cc-parse-global-decl
              then,
            then,
          then,
        then,
      then,
    else,
      \ Top-level starting with an ident — typedef-name used as a type
      \ (e.g. `FILE* p;`, `FILE* foo();`, `FILE* foo(){...}`).
      cc-putback-token
      cc-top-peek-is-fn-def? if,
        cc-parse-function
      else,
        cc-top-peek-has-paren? if,
          cc-register-fn-proto
        else,
          cc-parse-global-decl
        then,
      then,
    then,
  repeat, ;

\ ===========================================================================
\ Entry-stub emission and rel32 patching.
\ ===========================================================================

\ cc-emit-entry-stub ( -- )  Emit at vaddr cc-entry-vaddr (0x400078):
\     mov  rdi, [rsp]      48 8B 3C 24      ; argc (kernel puts it at [rsp])
\     lea  rsi, [rsp+8]    48 8D 74 24 08   ; argv = &argv[0]
\     call <main>          E8 <rel32>
\     mov  rdi, rax        48 89 C7         ; main's return -> exit code
\     mov  rax, 60         48 C7 C0 3C 00 00 00
\     syscall              0F 05
\ Records the file-offset of the rel32 in cc-call-main-patch.
\ Stack alignment: kernel hands us rsp 16-aligned and we don't touch it before
\ `call`, so main enters 8-mod-16 as SysV requires.
: cc-emit-entry-stub
  \ mov rdi, [rsp]   — argc
  [lit]  72 cc-emit-byte
  [lit] 139 cc-emit-byte
  [lit]  60 cc-emit-byte
  [lit]  36 cc-emit-byte

  \ lea rsi, [rsp+8] — argv
  [lit]  72 cc-emit-byte
  [lit] 141 cc-emit-byte
  [lit] 116 cc-emit-byte
  [lit]  36 cc-emit-byte
  [lit]   8 cc-emit-byte

  [lit] 232 cc-emit-byte                          \ E8
  cc-out-pos @ cc-call-main-patch !               \ remember rel32 file-offset
  [lit] 0 cc-emit-4le                             \ rel32 placeholder

  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 199 cc-emit-byte                          \ mov rdi, rax

  [lit]  72 cc-emit-byte
  [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte
  [lit]  60 cc-emit-4le                           \ mov rax, 60

  [lit]  15 cc-emit-byte
  [lit]   5 cc-emit-byte ;                        \ syscall

\ cc-patch-call-main ( -- )  Compute and store the call's rel32.
\ rel32 = main_vaddr - vaddr_of_next_instr
\       = main_vaddr - (cc-base-vaddr + cc-call-main-patch + 4)
: cc-patch-call-main
  cc-main-vaddr @
  cc-base-vaddr cc-call-main-patch @ + [lit] 4 + -
  cc-call-main-patch @
  cc-out-patch-4le ;

\ ===========================================================================
\ Top-level driver
\ ===========================================================================

\ ===========================================================================
\ Built-in libc shim emission + symtab registration.
\ ===========================================================================
\ The shims (putchar, exit, getchar) live at the very start of the code
\ segment, immediately after the 26-byte entry stub.  Registering them in
\ the symbol table BEFORE parsing user functions means cc-parse-call's
\ name-lookup path finds them just like any user-defined function.

\ Pre-baked name strings (raw bytes, no length prefix; the length is supplied
\ explicitly to cc-sym-add).
create cc-name-putchar
[lit] 112 c, [lit] 117 c, [lit] 116 c, [lit]  99 c,
[lit] 104 c, [lit]  97 c, [lit] 114 c,            \ "putchar"

create cc-name-exit
[lit] 101 c, [lit] 120 c, [lit] 105 c, [lit] 116 c,    \ "exit"

create cc-name-getchar
[lit] 103 c, [lit] 101 c, [lit] 116 c, [lit]  99 c,
[lit] 104 c, [lit]  97 c, [lit] 114 c,            \ "getchar"

create cc-name-fputs
[lit] 102 c, [lit] 112 c, [lit] 117 c, [lit] 116 c, [lit] 115 c,
create cc-name-fopen
[lit] 102 c, [lit] 111 c, [lit] 112 c, [lit] 101 c, [lit] 110 c,
create cc-name-fclose
[lit] 102 c, [lit]  99 c, [lit] 108 c, [lit] 111 c, [lit] 115 c, [lit] 101 c,
create cc-name-fputc
[lit] 102 c, [lit] 112 c, [lit] 117 c, [lit] 116 c, [lit]  99 c,
create cc-name-fread
[lit] 102 c, [lit] 114 c, [lit] 101 c, [lit]  97 c, [lit] 100 c,
create cc-name-fwrite
[lit] 102 c, [lit] 119 c, [lit] 114 c, [lit] 105 c, [lit] 116 c, [lit] 101 c,
create cc-name-calloc
[lit]  99 c, [lit]  97 c, [lit] 108 c, [lit] 108 c, [lit] 111 c, [lit]  99 c,
create cc-name-memset
[lit] 109 c, [lit] 101 c, [lit] 109 c, [lit] 115 c, [lit] 101 c, [lit] 116 c,
create cc-name-free
[lit] 102 c, [lit] 114 c, [lit] 101 c, [lit] 101 c,

\ cc-emit-shims ( -- )  Emit each shim's body and register it in the symbol
\ table as sk-func with val = its absolute vaddr.
: cc-emit-shims
  \ putchar
  cc-name-putchar [lit] 7
  sk-func
  ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +                    ( a u kind ty vaddr )
  cc-sym-add drop
  cc-emit-putchar-shim

  \ exit
  cc-name-exit [lit] 4
  sk-func
  ty-void [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-exit-shim

  \ getchar
  cc-name-getchar [lit] 7
  sk-func
  ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-getchar-shim

  \ fputs
  cc-name-fputs [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fputs-shim

  \ fputc
  cc-name-fputc [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fputc-shim

  \ fopen
  cc-name-fopen [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fopen-shim

  \ fclose
  cc-name-fclose [lit] 6
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fclose-shim

  \ fwrite
  cc-name-fwrite [lit] 6
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fwrite-shim

  \ fread
  cc-name-fread [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-fread-shim

  \ calloc
  cc-name-calloc [lit] 6
  sk-func ty-int [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-calloc-shim

  \ free (no-op bump allocator)
  cc-name-free [lit] 4
  sk-func ty-void [lit] 0 ty-make
  cc-base-vaddr cc-out-pos @ +
  cc-sym-add drop
  cc-emit-free-shim ;

\ ===========================================================================
\ M2 test-suite external prototype.  The M2 monolith itself does not call
\ memset, but the published parity script compares selected upstream tests
\ where memset is declared by an elided system header.
\ ===========================================================================

: cc-emit-external-protos
  cc-name-memset  [lit] 6  sk-func ty-int [lit] 0 ty-make  [lit] 0 cc-sym-add drop ;

\ Built-in typedefs for opaque libc/stdint names.  All map to ty-int so the
\ parser will accept `FILE* p;`, `uint8_t x;`, etc. — codegen still treats
\ them as 8-byte slots regardless of the C-visible width.
create cc-name-FILE
[lit]  70 c, [lit]  73 c, [lit]  76 c, [lit]  69 c,
create cc-name-int8_t
[lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  56 c, [lit]  95 c, [lit] 116 c,
create cc-name-int16_t
[lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  49 c, [lit]  54 c, [lit]  95 c, [lit] 116 c,
create cc-name-int32_t
[lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  51 c, [lit]  50 c, [lit]  95 c, [lit] 116 c,
create cc-name-int64_t
[lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  54 c, [lit]  52 c, [lit]  95 c, [lit] 116 c,
create cc-name-uint8_t
[lit] 117 c, [lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  56 c, [lit]  95 c, [lit] 116 c,
create cc-name-uint16_t
[lit] 117 c, [lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  49 c, [lit]  54 c, [lit]  95 c, [lit] 116 c,
create cc-name-uint32_t
[lit] 117 c, [lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  51 c, [lit]  50 c, [lit]  95 c, [lit] 116 c,
create cc-name-uint64_t
[lit] 117 c, [lit] 105 c, [lit] 110 c, [lit] 116 c, [lit]  54 c, [lit]  52 c, [lit]  95 c, [lit] 116 c,
create cc-name-size_t
[lit] 115 c, [lit] 105 c, [lit] 122 c, [lit] 101 c, [lit]  95 c, [lit] 116 c,
create cc-name-ssize_t
[lit] 115 c, [lit] 115 c, [lit] 105 c, [lit] 122 c, [lit] 101 c, [lit]  95 c, [lit] 116 c,

\ cc-emit-libc-typedefs ( -- )  Register the typedef names above so headers
\ that say `FILE* fp;` or `uint8_t b;` parse without rc 30.  All map to ty-int
\ encoded as the sk-typedef's val field (matching cc-parse-typedef's layout).
: cc-emit-libc-typedefs
  cc-name-FILE     [lit] 4  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int8_t   [lit] 6  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int16_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int32_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int64_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint8_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint16_t [lit] 8  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint32_t [lit] 8  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint64_t [lit] 8  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-size_t   [lit] 6  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-ssize_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop ;

\ cc-parse-program ( -- )  Emit entry stub, emit libc shims, register the
\ one external prototype and built-in typedefs, parse all functions, patch
\ entry stub.
: cc-parse-program
  cc-emit-entry-stub
  cc-emit-shims
  cc-emit-external-protos
  cc-emit-libc-typedefs
  cc-parse-function-list
  cc-patch-call-main ;
