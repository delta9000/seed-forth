# 15. Declarations and recursive records

The expression chapters started with useful facts already available: `w` was an array with base slot 3, `r` was a local in slot 4, and `t.stars` meant an offset of eight bytes within an object. Where did those facts come from?

A declaration is a request written in the source language. The compiler turns it into several different things: a name record, type metadata, a storage reservation, and sometimes instructions or data that establish an initial value. This chapter follows those products separately. Its central question is concrete: after reading one declaration, what has the compiler recorded, what storage has it reserved, and what work will the generated program still perform?

By the end, you should be able to construct `tri`'s descriptor and the local rows used earlier, trace a comma-separated declaration without spreading one pointer star across every name, and explain why a self-referential record works while a missing forward descriptor remains missing. You will also distinguish a name going out of scope from its generated storage disappearing.

**Core route.** Read through “Construct the records behind `tri`,” then “One descriptor can refer to itself” and “Value locals and pointer locals.” These sections establish the main mechanism. The function-pointer section is a bounded detour; the provider and return sections close the file's interfaces without requiring the later statement or frame chapters. If you already know the representation, attempt C15-02 and C15-04 first, then use the relevant sections to explain any discrepancy.

**Prerequisites.** C06 supplies current versus pending tokens and full lexer marks. C07 supplies packed type words and stable descriptor headers; C08 supplies symbol rows and scope markers. C12 distinguishes a place from a value, and [C14](14-expressions-and-constant-evaluation.md) supplies the runtime-expression, constant-expression, and type-query interfaces used here. You do not need to predict function prologues, switch labels, or native argument placement yet.

**Evidence boundary.** This is an inspected-source account of [110-cc-decl.fth at revision 7d7e1996d1753118181d43e1a413960d3a1ec24b](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth). The main traces use the legacy profile, with `cc-target-lp64` false, eight-byte frame slots, valid retained source-name spans, sufficient compiler storage, and bounded arithmetic. They are manual predictions, not executed C or Forth examples. They describe these parser paths, not a general C grammar or a conformance claim. Native differences are explicitly named.

## Keep five questions separate

Consider these illustrative declarations within an otherwise valid function:

```c
int count = 3;
static int saved = 3;
```

They both contain the numeral three. That does not make their compilation identical.

| Question | Ordinary local `count` | Legacy local-static `saved` |
|---|---|---|
| What does the source request? | A local scalar with an initializer | A block-visible scalar with persistent generated storage |
| What compiler record names it? | An `sk-local` symbol | An `sk-global` symbol added at the current lexical scope |
| What does its symbol payload mean? | A frame-slot index | An offset in the global data area |
| When is the initializer calculated? | Generated instructions calculate it when execution reaches the declaration | The compiler's constant evaluator calculates it while compiling |
| What happens when the lexical scope closes? | Its symbol leaves the visible prefix | Its symbol also leaves the visible prefix; its global storage is retained |

The symbol arrays and descriptors live in the **compiler's** memory. A local slot or global object belongs to the **generated program's** storage model. A builder write to a descriptor is not a generated instruction that writes an object. Conversely, calling `cc-emit-store-local` writes instruction bytes now; it does not immediately store into a running C function's frame.

One quick prerequisite check: if an `sk-local` row has payload 4, what does the 4 mean? It identifies the slot addressed at `RBP−8*(4+1)`, or `RBP−40`. It says nothing about the value currently held there. If you answered “the variable contains four,” return to C08's kind-dependent payloads before continuing. This distinction prevents most later storage mistakes.

## Exact expectations advance the parser

The three expectation helpers consume the next token with `cc-next-token-keep`. They do not merely inspect an already-current token, and they do not put a mismatching token back.

| Helper | First test | Further test |
|---|---|---|
| `cc-expect-kw-id ( expected-id -- )` | Kind must be `tk-kw`, otherwise error 140 | Keyword ID must match, otherwise 141 |
| `cc-expect-punct-c ( expected-character -- )` | Kind must be `tk-punct`, otherwise 142 | Punctuation payload must match, otherwise 143 |
| `cc-expect-ident` | Kind must be `tk-ident`, otherwise 144 | Leaves the accepted identifier's span in `tok-*` |

For a requested semicolon, a `)` is the right token kind with the wrong payload: 143. A name is the wrong kind: 142. Both paths terminate through `cc-die`; neither promises recovery. This lets a caller write the structural requirement exactly where it belongs.

The distinction matters at a declaration's end. Some words finish with the semicolon already current; others require an expectation helper to fetch it. Fetching again in the first case would consume the following declaration's token. Keep a small token ledger: “current and consumed,” “pending for reread,” or “not yet read.” A token's continued presence in `tok-*` alone does not make it pending.

Source: [`cc-expect-kw-id`, `cc-expect-punct-c`, and `cc-expect-ident`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L62-L89).

## Scan prefixes, then count stars for each name

The statement dispatcher begins with `cc-skip-storage-quals`. It resets four pieces of declaration state: prefix qualification, the static flag, the extern flag, and the storage-class count. It then consumes leading `static`, `extern`, `auto`, `register`, `inline`, `const`, `volatile`, and `restrict` tokens. The first other token is put back.

The collected information has different jobs:

- `const`, `volatile`, and `restrict` contribute bits 1, 2, and 4 to `cc-prefix-qualified`, using bitwise OR
- `static` sets `cc-decl-static`; `extern` sets `cc-decl-extern`
- Each `static`, `extern`, `auto`, or `register` increments `cc-decl-storage`
- `inline` is consumed but is not included in that count

For the prefix `static const volatile unsigned`, the skipper stops with `unsigned` pending, qualification 3, static true, extern false, and storage count 1. It has collected facts; it has not yet selected a scalar type or allocated an object. Repeated qualifier bits do not increase the set, whereas repeated storage keywords increase the count. Counting does not itself reject an invalid combination; later consumers decide what to do with the recorded facts.

Do not expand the source comment “only static matters” into an edition-wide rule. The legacy scalar/array consumer here uses the static flag, while the native declaration provider receives qualification, extern, and storage-count state too. Nor does recording a qualifier establish every rule associated with that qualifier.

After a base type, `cc-count-stars` returns the number of pointer stars and leaves the first other token pending. The exact word is:

```forth
: cc-count-stars                                  ( -- depth )
  [lit] 0
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] * = and
  while,
    1+ cc-skip-qualifiers
  repeat,
  cc-putback-token ;
```

Each star allows a following qualifier sequence. Thus the scanner can pass over `* const * volatile` and return two. `cc-skip-qualifiers` calls `cc-qual-note` for each qualifier; its initial binding is a no-op. The provider in `115` instead ORs qualifier bits into the current native declaration context when one exists. These are distinct from the leading prefix set. The legacy trace does not acquire native qualifier enforcement merely because the spelling was consumed.

The admitted **basic-type spellings** are also bounded. `cc-tok-is-basic-type-kw?` recognizes `int`, `char`, `void`, `long`, `short`, `unsigned`, and `signed`. `cc-parse-decl` initially chooses `ty-char` for `char` and `ty-int` otherwise; `cc-more-type-kws` consumes further basic keywords and switches to `ty-char` if it encounters `char`. Consequently this legacy path collapses spellings such as `unsigned int` and `long long` into its integer type. It does not build a full signedness/rank model from them.

Read this as the algorithm that exists, not a list of every legal C declaration. In particular, the presence of `void` in the keyword recognizer is not a complete object-type validity check. Qualifiers handled before a base or after a star do not imply arbitrary qualifier placement in every legacy branch. `enum` used as a type has a separate small helper: it consumes an optional identifier tag and puts back a nonidentifier; its callers supply integer type. Enumerator definitions belong to C19.

Sources: [qualifiers and star counting](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L95-L140), [storage-prefix and enum-tag scanning](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L142-L190), [legacy basic-type parsing](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L531-L571), and [native qualifier recording](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/115-cc-native.fth#L37-L43).

## One declarator, then the comma loop

A **declarator** is the part that introduces one name and its pointer/array shape after the shared base. Here `cc-parse-decl-with-base ( base initial-pointer-depth -- )` stores the base in `cc-decl-base` and keeps the initial depth available across the list. `cc-parse-local-declarator` adds the stars it sees for this particular name.

For this paper input, begin with local-slot count zero:

```c
int *p, q = 3, **links;
```

| Declarator | Initial depth | Its stars | Recorded type | Payload slot | Count afterward |
|---|---:|---:|---|---:|---:|
| `*p` | 0 | 1 | Pointer to legacy int | 0 | 1 |
| `q = 3` | 0 | 0 | Legacy int | 1 | 2 |
| `**links` | 0 | 2 | Pointer-to-pointer to legacy int | 2 | 3 |

The comma means “parse another declarator using the same initial depth.” It does not carry `p`'s added star into `q`. Only `q` has initializer code in this example. `p` and `links` receive storage and name records, without a promised initial pointer value.

A typedef can change the initial depth. C08 established that an `sk-typedef` payload is its encoded type. The statement identifier path extracts its base and pointer depth and passes both to this loop. Given an already-defined typedef `int_ptr` whose payload encodes `int*`, `int_ptr a, *b;` supplies initial depth one for each declarator: `a` has depth one and `b` depth two. Constructing the typedef row itself remains a later producer.

For an ordinary scalar, the local-declarator word expects the name, packs base and pointer depth with `ty-make`, and reads the next token. It appends an `sk-local` symbol whose payload is the current count, then claims one slot. When that next token is `=`, it calls `cc-parse-expr`, emits a store into the newly claimed slot, and reads the following delimiter.

C14's interface is enough here: the runtime parser emits the expression calculation and materializes its result in the expression-value convention. It does not return the calculated C value as a builder-stack integer. In the legacy profile it stops before the declaration's comma, leaving that token pending; the declarator then reads it. This is why `int a=1,b=2;` can initialize both scalars. There is no one-initializer-per-declaration restriction.

The loop's exit contract is precise: `cc-parse-local-declarator` returns with the token after its declarator already current. If it is a comma, the outer loop continues. Otherwise the outer word requires the current token to be a semicolon, or dies with 159. It does not call `cc-expect-punct-c` for that final semicolon, because it has already been read.

The special function-pointer branch runs before this ordinary loop and returns separately. The ordinary array branch also has its own stopping point; it is not a universal initializer parser. In `int a[2]={1,2};`, that branch returns with `=` current after `]`, and the outer comma/semicolon check fails. This contrasts a missing brace-initializer mechanism with the supported scalar comma list.

Sources: [local declarators and their comma loop](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L450-L529), [typedef-name dispatch](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L835-L846), and [symbol append initialization](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/070-cc-sym.fth#L69-L91).

## Arrays reserve a range; the base is its deepest slot

An array declarator calls `cc-parse-const` after `[`. C14 established its different phase: this parser calculates a builder-cell result now. Here that result is the element count N. The word requires N to be positive, otherwise error 156, and requires a closing `]`, otherwise 157.

For a non-static local array, with the next free slot C, the producer records:

- Kind `sk-local`, with the element's packed type
- Payload `C+N−1`, the deepest newly reserved slot
- Array length N through `cc-sym-set-array-len`
- New local count `C+N`

Why the last slot? Slot indexes increase downward in memory, while array element addresses increase upward. If C=0 and N=4, the claimed slots are 0, 1, 2, and 3. Their addresses are `RBP−8`, `RBP−16`, `RBP−24`, and `RBP−32`. Element zero must start at the lowest address, `RBP−32`, so adding 8 for each int element stays within the reservation.

| Element | Address | Slot containing it |
|---|---|---:|
| `w[0]` | `RBP−32` | 3 |
| `w[1]` | `RBP−24` | 2 |
| `w[2]` | `RBP−16` | 1 |
| `w[3]` | `RBP−8` | 0 |

This is the legacy integer-array trace. The declaration branch reserves N eight-byte slots even for its admitted char array spelling; that reservation rule is separate from C12's byte-width char indexing rule. Do not replace it with N times `ty-size` because that seems more general. Native layout uses its own provider.

There is no emitted initialization store in the uninitialized local-array branch. It reserves and records; the generated slots have no promised value until other code establishes one. A following assignment such as `w[r]=1+r*2` is a separate parser action, whose address/value work C14 already taught.

### The counter is shared and monotonic

The slot counter includes parameters and every local allocated across every block of the function. This small helper provides the bound:

```forth
[lit] 32 constant cc-frame-slots
: cc-fn-add-slots
  dup cc-fn-local-count @ +
  cc-target-lp64 @ if, cc-native-frame-limit @ else, cc-frame-slots then,
  [lit] 162 cc-check-cap
  cc-fn-local-count +! ;
```

Under the legacy profile, a claim is allowed through total count 32. A claim beyond it dies with 162 before this helper increments the counter. With count 30, claiming two reaches 32; claiming three would exceed the bound. This is a slot-capacity check, not a guarantee that an entire failed declaration rolls back: some callers have already appended their symbol by this point.

A scope pop does not lower `cc-fn-local-count`. It only changes which symbols are visible, as C08 showed. Sibling blocks therefore do not reuse each other's frame slots even when they reuse a symbol ID. The straightforward allocation policy trades storage for simple lifetime accounting. It does not require a search for whether two variables' executions overlap.

When `cc-target-lp64` is true, this helper consults `cc-native-frame-limit`, initialized to 131072 **slots**. Native frames are sized and patched after body parsing by later machinery. This number is not a byte count or a promise that every native frame uses all that space. C18 opens frame construction; C23 opens the richer target paths.

Sources: [slot counting and limits](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L20-L52), [array production](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L462-L485), and [scope restoration](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/070-cc-sym.fth#L152-L167).

## A local static changes storage, not scope bookkeeping

Now begin at local count five and parse the illustrative block declaration:

```c
static int saved = 3, buffer[4];
```

The prefix sets the static flag for the whole declaration. For `saved`, the declarator calls `cc-globals-alloc` for eight bytes. Let the returned data offset be S. It appends an `sk-global` row with payload S, evaluates `3` with `cc-parse-const`, and writes eight little-endian bytes to the compiler's globals buffer at S: `03 00 00 00 00 00 00 00`.

For `buffer`, it calls `cc-bss-alloc` for `4*8=32` bytes and records the returned tagged BSS slot plus array length four in another `sk-global` row. C10's storage/fixup contract explains how those encoded slots later acquire generated addresses. The declaration does not yet need a final address for either object.

Neither object consumes frame slots, so the local count remains five. Neither gets the ordinary local's emitted runtime initializer store. The scalar initializer becomes data while compiling; BSS is reserved as zero-filled generated storage. A scalar static without an initializer relies on the globals buffer having been cleared by `cc-globals-init`, not on this declarator emitting a zero store.

Both names are appended within the current lexical scope. When that scope closes, restoring the symbol count hides them. Their global allocations are not reclaimed by that operation. Thus “local static” combines local visibility with generated storage that persists between function calls. The compiler does not compile a new allocation each time the running program enters the block.

This example belongs to the scalar/array legacy path. Do not infer that all specialized legacy declarators inspect `cc-decl-static`: the function-pointer and struct-local words below have their own fixed local-storage behavior. Statement dispatch and provider choice determine which consumer receives the prefix facts.

Sources: [static array/scalar branches](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L475-L503) and [global initialization, allocation, and little-endian storage](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L1168-L1210).

## Function-pointer lookahead recognizes a bounded shape

After the base `int`, the ordinary name may start with `p`, `*p`, or a parenthesized function-pointer shape:

```c
int (*fp)(int);
```

The detector needs two tokens, `(` then `*`. C06's single-token putback cannot independently preserve two speculative reads. `cc-peek-fnptr?` instead marks the lexer state, reads ahead, and resets on either outcome:

```forth
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

Suppose `(` is already pending. The mark includes that flag and token state. The first read consumes the pending `(`; the second obtains `*`; reset reinstates the original pending `(`. The result flag is true, but the real parser still needs to consume both tokens. A false result likewise leaves the caller at its original reader state. Peeking has answered a question without taking ownership of those tokens.

This is token lookahead, so whitespace and comments between `(` and `*` do not require adjacent source bytes. The shared `cc-peek-mark` is scratch storage: finish and reset one use before another owner overwrites the mark. It is not a stack of arbitrary nested snapshots.

The branch is selected only when the caller's initial pointer depth is zero. The parser then expects `(`, `*`, an identifier, `)`, and `(`. It skips the parameter-list tokens with a parenthesis-depth counter starting at one. Each nested `(` increments it; each `)` decrements it. Reaching zero ends the scan; EOF before then dies with 184. This consumes balanced parentheses, including a nested function-pointer spelling, without constructing that nested signature.

The skipped list is **not a checked function signature**. The resulting symbol has kind `sk-local`, type `ty-func` with pointer depth one, and payload equal to the next slot. It claims one slot. An optional `= expression` emits an initializer store; this specialized word then requires its own semicolon and does not rejoin the ordinary comma loop. C14's legacy indirect-call path consumes that local function-pointer symbol.

One profile-dependent test exists even within the skipping helper: in LP64 mode, if `cc-native-float-types-fwd` is false, encountering `float` or `double` dies with 214. The default hook returns `cc-bootstrap-floatbits`. Allowing a type spelling through this gate does not establish executable floating arithmetic. Full signature descriptors, declarator precedence, and signature checking belong to the native provider lessons.

Source: [lookahead, balanced skipping, and the restricted local function-pointer producer](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L356-L446), with [the default floating-spelling hook](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L25-L30).

## Construct the records behind `tri`

Return to the declarations introduced in C01. After preprocessing replaces `ROWS` with 4, the relevant source fragments are:

```c
struct tri { int rows; int stars; };
struct tri t;
```

```c
int w[4];
int r;
```

The first fragment defines a type and declares a file-scope object. The second fragment belongs within `main`. Do not move `t` into the local trace: its global-object producer belongs to C19. We can close the earlier expression premises by constructing the descriptor here and reusing C08/C10's supplied global-object row for `t`.

### Allocate an identity before filling in its contents

`cc-parse-struct-def` enters with `struct` already current. It consumes the tag identifier and retains the tag's address/length pair on the builder data stack. After expecting `{`, it allocates a zeroed descriptor header D. Before reading either field, it appends the tag symbol:

```forth
  over over                                       ( tag-a tag-u tag-a tag-u )
  sk-struct
  [lit] 0
  cc-sd-build-desc @
  cc-sym-add drop                                 ( tag-a tag-u )
```

The five symbol arguments mean name span, kind `sk-struct`, type field zero, and payload D. The original name pair remains on the data stack for this parser's eventual cleanup. This code uses the ordinary append interface already taught in C08; it is not a separate tag database.

D is an address in the compiler's arena, not the generated address of a `tri` object. Its header initially reports zero fields and zero total object size. C07's header allocation has no field table yet. When append asks for the first record, the table grows to its initial capacity. The header's address remains D even if that separate table later moves.

### Append the two fields

The legacy builder keeps five scratch globals: the descriptor under construction, the field name address and length, the field type, and its associated descriptor. These are one active construction context. For each field it resets the associated descriptor to zero, reads a bounded base spelling, counts stars, expects an identifier and a semicolon, then appends the field.

For `rows`, it records int with pointer depth zero. For `stars`, it does the same. The append helper requests record index equal to the current field count, fills name/type/associated-descriptor, writes the **old total size** as the field offset, and only then increments count and total size.

| Construction state | Field just written | Field offset | Associated descriptor | D's count | D's size |
|---|---|---:|---|---:|---:|
| After pre-registration | None | — | — | 0 | 0 |
| After `int rows;` | Record 0 | 0 | 0 | 1 | 8 |
| After `int stars;` | Record 1 | 8 | 0 | 2 | 16 |

Every member on this legacy producer's path advances size by eight bytes. These numbers describe generated-object offsets. The compiler's field records are forty bytes each under this profile, and the descriptor header is fifty-six bytes; none of those metadata sizes is a member's object offset. A field table can take much more compiler storage than the object layout it describes.

The closing `}` is consumed by the field-loop test and is not put back. The parser then expects `;` and drops its saved tag span. The tag record still points to D, now with two fields and size sixteen.

The field spelling loop is narrower than the general local declaration loop. It handles one `base`, zero or more stars, one field name, and a semicolon. Its keyword branches are `int`, `char`, `void`, `enum`, and `struct TAG`; a type-position identifier is treated as int here rather than receiving full typedef resolution. It does not recursively parse a nested struct definition or reuse the local comma-list engine. Keep those bounds visible when choosing a new example.

### Add `w` and `r`

For `main`, start local count at zero. `int w[4];` evaluates the positive bound four, appends an int-array `sk-local` row with payload `0+4−1=3` and length four, then raises count to four. `int r;` appends a scalar int row at slot four and raises count to five. Neither declaration emits an initializer store.

We have now constructed the exact earlier local premises: `w` starts at `RBP−32`, and `r` is at `RBP−40`. D supplies `rows` offset zero and `stars` offset eight. For the separately produced global row `t`, take its global-storage slot and associated descriptor D from the C19 producer's contract. C12's `t.stars` can add eight to the generated object base; `w[r]` can combine slot-three base, runtime index, and int stride. No expression needs the compiler descriptor address to become a generated object address.

**Pause point.** Save these facts if you stop here: D has fields `(rows,0)` and `(stars,8)`, total size sixteen; `w` has slot three/length four; `r` has slot four; next free slot is five. The next question is how a field can store D while D is still being built.

Sources: [struct scratch state and append](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L196-L223), [pre-registration and the complete field loop](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L271-L354), [stable header/table allocation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/060-cc-types.fth#L204-L310), and [top-level definition/object discrimination](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/116-cc-prog.fth#L517-L558).

## One descriptor can refer to itself

Use a separate, small record example:

```c
struct Node { int value; struct Node *next; };
```

Call its descriptor N. Before any field, the parser registers `Node` with payload N. It appends `value` at offset zero, making N's current size eight. While parsing `struct Node *next`, it calls the soft tag lookup. That lookup finds the already-registered tag and returns N even though construction is unfinished.

The parser stores the following field facts for `next`: type `ty-struct` with pointer depth one, associated descriptor N, and offset eight. After append, N has two fields and total size sixteen. The descriptor's identity did not depend on knowing the final size first.

This is **recursive data**, not recursive invocation of the builder. The field refers to the same descriptor header; the parser does not enter `cc-parse-struct-def` again. That is why one set of `cc-sd-build-*` globals is sufficient for this path. Calling the builder recursively for a nested definition would require preserving a construction context that this legacy algorithm does not save.

Now supply an already-declared pointer local `struct Node *p` and valid live linked objects. For the paper expression `p->next->value`:

1. The local pointer row supplies descriptor N and a generated pointer value
2. The first arrow finds `next` at offset eight and carries the field's associated descriptor N onward
3. Before the second arrow selects a field, materialization loads the stored pointer from the `next` member's address
4. The next field lookup uses N, now completed, to find `value` at offset zero

The generated pointer may point to a different Node object at each step. The compiler descriptor is the same N because both objects have this described layout. A linked list can contain many objects without the compiler allocating one descriptor per object.

### Strict lookup and soft lookup promise different things

The strict `cc-lookup-struct-tag` requires an identifier (145), a successful tag lookup (146), and a resulting `sk-struct` record (147). It returns that row's descriptor payload. The soft variant still requires an identifier, with error 148, but returns zero if the tag is absent or the resolved row is not a struct.

Soft lookup does **not** allocate an incomplete descriptor or register a future fixup. This limits a different fragment:

```c
struct A { int x; struct B *b; };
struct B { int y; struct A *a; };
```

While A is built, B is absent. A's `b` record gets descriptor zero. While B is built, A exists, so B's `a` record gets descriptor A. Completing B later does not revisit the zero in A's field record.

Given valid, separately declared pointer locals `struct A *pa` and `struct B *pb`, the metadata chain for `pb->a->x` is B then A, so the second field lookup can find `x`. For `pa->b->y`, selecting `b` carries descriptor zero; the next field operation reaches the missing-descriptor check and error 100. This is a source-derived parser boundary, not an executed fault in an example.

The failure is not that all self-reference is impossible. It is that “no descriptor found” was stored as zero rather than as a stable identity awaiting completion. The native `cc-naggregate` provider in `115` follows the latter approach: for an unknown named tag it allocates/registers a descriptor, and a later body can reuse that descriptor. C23/G03 open its context management and completion rules. A stable-header representation enables that strategy; it does not retroactively make the legacy zero into a descriptor.

Sources: [strict and soft tag lookup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L235-L269), [field descriptor production](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L304-L348), [field consumption and error 100](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/100-cc-expr.fth#L1107-L1158), and [native named-aggregate identity](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/115-cc-native.fth#L446-L475).

## Value locals and pointer locals reserve different things

`cc-parse-struct-local-decl` enters after the `struct` keyword and uses **strict** tag lookup. A missing tag therefore stops this local-declaration path; it does not inherit the field builder's soft behavior. Four scratch globals retain descriptor, pointer depth, and name span while the word produces the symbol.

Suppose the completed Node descriptor has size sixteen and current local count is five:

```c
struct Node n;
struct Node *head = 0;
```

For `n`, pointer depth is zero. The parser requires the semicolon immediately; this branch has no initializer. It reserves `16/8=2` slots, records the deepest one `5+2−1=6` as payload, and associates descriptor N with the symbol. The new count is seven. Its base is `RBP−56`; `value` is there and `next` is eight bytes above it at `RBP−48`.

For `head`, depth is one. The object being stored is a pointer, so it needs one slot, index seven, at `RBP−64`. The row still associates descriptor N, now describing the pointed-to record. Count becomes eight. The optional initializer invokes the runtime expression parser, emits a store to slot seven, and expects a semicolon. No Node object is allocated by declaring `head`.

The distinction generalizes within this word: positive pointer depth reserves one slot; depth zero reserves descriptor-size divided by eight. It does not become a comma-list parser, and its value branch does not gain aggregate initialization from the pointer branch's scalar initializer. The same associated-descriptor accessor serves different consumers: dot uses the local object's base, while arrow uses the stored pointer value.

Source: [struct-local value and pointer branches](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L672-L738), with [profile-selected associated-descriptor storage](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/070-cc-sym.fth#L115-L127).

## Reuse the type-query interface; identify the dispatcher

C14 already opened the cross-file cast/`sizeof` handshake. Its interface remains available here:

- `cc-type-start?` asks whether the current token can begin a type name
- `cc-parse-type-name` consumes that type name, returns its packed type, publishes `cc-cast-desc`, and leaves the following token pending
- Native type queries additionally publish qualification and array-shape facts through `cc-type-name-qualified`, `cc-type-name-array`, and `cc-type-name-inner`
- The final `cc-native-sizeof-type` wrapper returns type and descriptor; the final bindings connect these queries to `sizeof`

A type query need not declare an object. A cast does not append a local merely because its syntax mentions `int*`. C14 owns the nested cast snapshots, conversions, null provenance, `sizeof` rollback, and evaluator closure; none must be rederived to allocate `w` here.

Several names at the start of `110` are handoff state rather than additional algorithms: `cc-native-return-type/desc` describe the enclosing function's result; `cc-pending-struct-desc` carries a parsed struct descriptor to later symbol producers; `cc-main-vaddr` and `cc-call-main-patch` are entry/finalization bookkeeping opened in C18/C19. They are not generated object storage or substitutes for the expression metadata cells.

The selected caller decides which declaration mechanism actually runs. `cc-parse-stmt` in `112` scans prefixes, reads the first token, and, under LP64, tests `cc-native-type-start-fwd` or `typedef` before the legacy cases. A match calls `cc-native-decl-fwd` and exits. With that route not selected, basic keywords, enum types, struct locals, and typedef identifiers reach the legacy words described here. Legacy block `struct` dispatch means a local object declaration; the definition parser is selected at top level.

The three declaration-provider hooks have concrete owners in `115`: `cc-native-type-start` supplies the current-token predicate; `cc-native-type-name` supplies type-query results; `cc-native-local-declaration` receives the current declaration token and collected prefix facts. Its context owns richer declarator metadata and restores the enclosing context when finished. Merely declaring the deferred hooks in `110` is not a default implementation of those providers. LP64 mode must be paired with the intended loaded providers.

At top level, `116` distinguishes `struct TAG {` from a use of `struct TAG`. Only the definition shape enters `cc-parse-struct-def`; other declarations are classified into function definition, prototype, or global object. That is the missing producer boundary for `struct tri t;`. Full native declarators and aggregates belong to C23/G03; complete file-scope production belongs to C19. These boundaries explain the present caller without claiming those later mechanisms are identical to the legacy ones.

Sources: [type queries and final bindings](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L573-L624), [the final `sizeof` adapter](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L805-L808), [statement dispatch](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/112-cc-stmt.fth#L865-L902), and [`115`'s type-name and local declaration providers](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/115-cc-native.fth#L478-L638).

## A short complete reading of return

The source file also defines `cc-parse-return`. Its placement does not make complete switch and frame construction prerequisites for declarations. Use this contract now: every lexically open switch has a generated saved-RBX obligation. `cc-switch-depth` counts them; `cc-loop-switch-depth` records the depth at the enclosing loop. The helper `cc-emit-switch-unwind ( n -- )` emits n `POP RBX` instructions by decrementing a builder counter. Calling it does not pop the compiler's own return stack.

`cc-parse-return` enters with `return` consumed and reads one token:

- If that token is `;`, it emits `RAX=0`, unwinds all open switches, then emits the epilogue. The semicolon is already consumed, so there is no second expectation
- Otherwise it puts the token back and parses the runtime expression. That interface materializes the expression result. Under LP64, it passes source type/descriptor and enclosing return type/descriptor to `cc-return-shape-fwd`, then emits conversion to the return type. It invokes `cc-value-return-fwd`, unwinds switches, emits the epilogue, and finally expects `;`

The default shape hook discards its four inputs; it adds no shape check. The default value-return hook emits a move from RDI to RAX. Later target providers may replace these, but the caller still owns the order: result work, switch unwind, epilogue. The shared epilogue calls the callee-restore hook, restores `RSP` from `RBP`, pops saved RBP, and emits `RET`.

For a bounded paper state with legacy result value seven and switch depth two, the valued path therefore predicts: make result seven available in RDI; move it to RAX; emit two RBX restores; emit the epilogue; consume the source semicolon. The two restores matter even though frame teardown resets RSP: register-restoration obligations must be met too. This is a sequence prediction, not a measured frame or a claim about an arbitrary return type.

C17 derives how switch obligations arise and how different exits choose counts: return uses the full depth, continue uses the difference from loop-entry depth, and the legacy goto rule targets labels outside switches. C18 joins parameters, locals, prologue, result, and epilogue into a full call/frame trace. Here the completed reading is deliberately local: every branch and callback in `cc-parse-return` has a stated job without importing those later lessons.

Sources: [switch-unwind helper and return parser](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/110-cc-decl.fth#L740-L803) and [shared epilogue](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/090-cc-emit.fth#L349-L359).

## Practice: construct, explain, then change one condition

These are paper tasks under the chapter's stated legacy profile unless a question selects another path. Do not compile or run them. Keep hints and answers closed for an independent attempt; opening a hint is also a valid route. [Graduated hints and checked solutions](../practice/15-solutions.md) include a next step for each likely mismatch.

### C15-01 — Prefix facts and token ownership

Starting with arbitrary old prefix state, parse the leading sequence `static const volatile unsigned char * const first, second;`. Stop the prefix skipper before the basic type. Report its four recorded facts and the next pending token. Then report each declarator's base and pointer depth under the legacy path. Which token is current when the first local declarator returns? Explain whether the outer comma loop should fetch a semicolon after the last declarator. Separately, which expectation-helper error applies when `;` is expected but the consumed token is `)`?

### C15-02 — Move the starting slot

Begin with three slots already claimed by parameters. Parse `int w[4]; int r;`. Give each row's kind, type, payload, array length, final count, and generated address relative to RBP. Show all four element addresses in increasing index order. Then leave the block containing these locals and enter a sibling block that declares `int other;`. What slot is claimed there, and why does symbol-scope restoration not settle that question by itself?

### C15-03 — Separate visibility from storage duration

At local count five, compare `int count=3;` with `static int count=3;` in two otherwise identical independent functions. For each, identify which parser calculates the initializer, what symbol kind/payload it produces, what instruction or data write initializes the object, and the next local count. Explain what a scope pop changes. Change the static scalar to `static int count[3];` and identify the storage interface and amount requested. Do not assume a particular global-buffer offset.

### C15-04 — Explain the two descriptor chains

Build the two independent fragments shown in “One descriptor can refer to itself”: Node, and the A-then-B pair. Record each field's type, byte offset, and associated descriptor. Given valid pointer locals `p`, `pa`, and `pb` of the matching types and valid pointed-to objects, trace metadata and materialization for `p->next->value`, `pa->b->y`, and `pb->a->x`. Then reverse the order of the A and B definitions and predict which metadata chain changes. Explain why table relocation and a missing descriptor are different problems.

### C15-05 — Allocate an object or allocate its pointer

A completed legacy descriptor `Link` has three eight-byte members. Start at local count four and parse `struct Link item; struct Link **owner; int tail;`. Give each payload slot, generated base/address, associated descriptor, and final count. State which bytes belong to `item` and why its first member is not placed at the shallowest new slot. Change only `item` to `struct Link *item;` and recalculate. What initializer form is available for that changed declaration that the original value branch lacks?

### C15-06 — A lookahead is not a signature checker

After the base type of `int ( /* gap */ *fp)(int (*nested)(int));`, suppose `(` is pending. Trace the two lookahead reads and reset, then the parenthesis-depth sequence while the outer parameter list is skipped. Describe the resulting symbol and storage, without assuming signatures were validated. Compare with `int *p;`, where the first lookahead token differs. Finally, explain the selected gate if the skip helper encounters `double` with LP64 true and floating spelling disabled.

### C15-07 — Finish the local contract

Under legacy defaults, compare `return;` and `return r;` at switch depth two, taking `r` to be a valid initialized int local whose runtime value is nine. List token ownership and emitted operations in order. Identify the extra shape/conversion work selected by LP64 without inventing its target-specific implementation. Explain which chapter must establish the saved-RBX obligations and which must establish the complete frame. Then choose the actual declaration path for `int x;` at statement scope with LP64 enabled and its native type predicate true.

## What this chapter established

A declaration's spelling, compiler metadata, generated storage, initialization phase, and lexical visibility are separate facts that must agree. You constructed the records earlier expressions consumed, rather than assuming them forever. You also saw the precise benefit of early registration: a stable descriptor can be named before its fields are complete. That benefit does not turn an absent descriptor into a future one without an actual producer that preserves such an identity.

Continue to the statement chapters with the expression and declaration interfaces available. You can now ask, for each branch of a statement dispatcher, which parser owns the next token and which compiler or generated state it is allowed to change.
