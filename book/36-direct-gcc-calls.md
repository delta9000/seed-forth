# Chapter 36: Scalar calls across the System V boundary

Descriptor-backed fixed-array pointers preserve their element layout behind
pointer objects and function signatures. `sizeof(*p)`, row stepping, array
addressing and a genuine `va_list *` callback use the array's complete shape.
Qualified arrays decay to pointers to qualified rows, and implicitly
discarding a row qualifier fails closed. The source document `tests/gcc/array-pointer-README.md`
describes grouped declarators, null constants, supported aliases and rejection
checks. This extension does not establish a complete libcpp build.

## Goal

Compile integer and pointer functions whose callers and callees agree with
AMD64 System V. Chapter 34 deliberately used a private stack convention.
That remains the native TinyCC route; this chapter adds an explicit target
selection, `cc-sysv-enable`, for separately compiled scalar code.

This is new reconstruction work. Its tests establish the behavior of the
source shown here; they do not recover or validate an earlier unpublished
GCC bootstrap implementation. Completing this calling convention does not
by itself mean that this compiler can build GCC.

## Concepts carried in

You need the LP64 type and declaration machinery from Chapter 34, the
expression stack and machine encoders from Chapters 25–28, and the function
scopes and forward fixups from Chapter 31. Chapter 35 supplies the
relocatable object writer used at the separate-compilation boundary.

## 1. One signature, two places to use it

A function signature records a tag, return type and descriptor, fixed
parameter count, prototype flags, parameter type/descriptor pairs, and
parameter names for definitions.
The same record drives incoming parameters and outgoing calls. Narrow
integers are converted to their declared width before a call and after a
return; the existing typed local loads read the low bytes saved on entry.
Struct pointers retain their tag identity. Function-pointer descriptors
hold a tagged signature, and repeated declarations compare that signature
recursively instead of quietly replacing the first declaration's type.

C tags have a separate lookup path from ordinary identifiers. A function
named `stat` can coexist with `struct stat`; typedefs, objects, enumerators,
and function pointers likewise ignore tag entries. Both searches walk the
same scoped records backwards, and members stay in their own aggregate
descriptors. Native mode retains its existing lookup through the default
binding. `tests/gcc/sysv-namespaces-check.sh` covers both declaration orders,
ordinary local shadowing, static address initializers, and member names in
standalone ELF and relocatable objects.

Prototype parameters can omit the name inside a function-pointer
declarator, including pointer-returning callbacks such as
`FILE *(*)(struct buf *, struct stat *, int)`. The signature stores the
same nested type for named and unnamed forms. A definition still requires
names for its own parameters. The focused abstract-callback gate checks
compatible redeclarations, pointer sizes, an actual indirect call and
incompatible return/argument types.

Function-declared parameters, such as GCC's
`void (callback)(struct graph *, struct edge *)`, adjust to pointers to
functions in both prototypes and identifier-list definitions. Reparse the
saved function suffix with the same signature parser used by `(*callback)`;
then restore the enclosing parameter delimiter. The parameter is an
eight-byte pointer object, so `sizeof callback` and an indirect call behave
just as for the explicit pointer spelling. Names, nested signatures, return
types, and storage-specifier checks remain in the existing representation.
`tests/gcc/function-parameter-check.py` checks compatible spellings,
recursive callbacks, pointer and binary64 returns, eight arguments,
bidirectional GCC interoperability, and unchanged rejection boundaries.

Explicit function-pointer casts use that same signature parser in abstract
type names. For example, libiberty's
`(struct _obstack_chunk * (*)(void *, long)) chunkfun` restores a typed
allocator after storing its address through a generic callback type.
The cast leaves the address bits unchanged and replaces the expression's
signature descriptor. Casting back therefore preserves pointer equality,
while the next indirect call gets the selected parameter conversions,
return type, and nested return descriptor. A callback that returns another
callback retains both signatures; a callback returning a struct pointer
retains the struct tag needed by `->`.

This permission covers conversion and restoration, not calling a function
through a signature incompatible with its actual definition. The focused
`sysv-function-pointer-casts-check.sh` gate only calls restored matching
types. It exercises direct addresses, generic locals and record members,
narrow integer arguments, and callbacks returning callbacks through both
Forth-only executable paths. Optional `SF_GCC_CAST_ORACLE=1` runs separate
host `-O0` and `-O2` semantic oracles and a host-linked Forth object.

The explicit Linux AMD64 LP64 target also defines integer/function-pointer
representation casts. ISO C leaves the general mapping implementation-defined
([N1570, 6.3.2.3 paragraphs 3, 5, 6 and 8](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf));
the [AMD64 psABI scalar-type table](https://gitlab.com/x86-psABIs/x86-64-ABI/-/raw/master/x86-64-ABI/low-level-sys-info.tex)
represents LP64 function pointers as unsigned eightbytes. This target chooses
an explicit bit-preserving mapping, after normalizing the source integer's
width and signedness: signed 8/16/32-bit values sign-extend, unsigned values
zero-extend, and 64-bit values preserve all bits. Integer zero becomes the
all-zero null function pointer. A reverse cast to 64-bit `long` or
`unsigned long` preserves the same bits; `long` interprets them as two's
complement. `long long` and `unsigned long long` share that 64-bit
representation as distinct types, so they behave the same way.
Reverse casts to narrower integer types reject with 230.

This is necessary for actual source boundaries: Linux signal headers express
`SIG_DFL`, `SIG_IGN`, and `SIG_ERR` as function-pointer casts of 0, 1, and -1
([glibc definitions](https://raw.githubusercontent.com/bminor/glibc/master/bits/signum-generic.h)).
Original `oyacc` passes these sentinels to `signal`; the runtime must pass
through their representation rather than treating them as callable functions.
The same mapping lets an ABI test export a real function address as `long`
and restore its original signature. Arbitrary numeric values can be stored,
passed, returned, or compared as this target's representation; this gives no
permission to call a sentinel, a noncanonical address, or a function through
an incompatible signature.

Explicit casts between a function pointer and any object pointer, such as
`void *`, `char *`, a struct pointer, or a pointer to a function pointer,
keep the same 64-bit value in both directions. Strict C90 leaves this
conversion undefined, but POSIX requires it for `dlsym`
([dlsym rationale](https://pubs.opengroup.org/onlinepubs/9699919799/functions/dlsym.html))
and GCC accepts it on LP64, where both pointers are eight bytes. Original
binutils' `bfd/doc/chew.c` depends on it: its threaded interpreter stores a
dictionary pointer in a `void (*)()` code slot and recovers it with
`(dict_type *) (pc[1])`. Only explicit casts cross. Assignments, arguments,
and conditional operands that mix the two kinds keep their existing shape
diagnostics, and calling through a pointer-to-function-pointer still rejects
with 230. A function pointer cast to or from a floating type also rejects
with 230; a struct or union partner reaches Chapter 48's aggregate policy
first and rejects with 232.

The type policy in `cc-sysv-cast-types` is pure and is shared by runtime casts
and Chapter 41's static constant evaluator. The separate `cc-cast-value-fwd`
hook normalizes runtime integer operands and then uses the existing conversion
emitter. Its default preserves the native target's conversion path. Constants
normalize their integer source using the typed constant evaluator, without
emitting instructions. Both typedef and abstract casts keep the destination
signature descriptor, including callbacks returned from callbacks.
`sysv-function-integer-casts-check.sh` checks all supported integer widths,
null comparisons, static sentinels and address relocations, side effects once,
restored typed calls, and rejection of narrow and floating partners in both
output paths. `function-object-cast-check.py` runs object-pointer round trips,
static initializers, and a chew-style interpreter against host GCC `-O0` and
`-O2`, and checks the exact codes of the remaining rejections.
`SF_GCC_CAST_ORACLE=1` adds host `-O0`/`-O2` semantic and cross-compiler ABI
oracles; sentinels are never called.

Together with Chapter 47's bitfield layout, the pinned-source
`sysv-gcc-obstack-check.sh` gate compiles the unchanged original
`libiberty/obstack.c` and its original header. Its Forth-only executable
exercises both callback dispatch modes, copies an object into a grown chunk,
and checks allocation and release counts. Callback casts at the public
API boundary are restored to their actual definitions before invocation.
The fixture therefore tests the original allocator's control flow without
relying on incompatible function calls or a replacement allocator body.

The explicit-cast hook in Chapter 29 defaults to doing nothing. This target
rejects crossings between a function pointer and any other value type with
230, except a cast to `void` that discards the value. In particular,
function/object-pointer conversion remains unsupported: the configure
probe that casts a function address to `char **` still takes its
conservative false branch. A cast from an integer null
pointer constant, such as `(int (*)(void))0` or `(Callback)0`, is valid C
but is not implemented by this bounded restoration stage: it also rejects
with230. General integer/function-address casts remain outside this stage.
The original obstack unit does not need these conversions, and the negative
gate records their rejection explicitly. Supported function-pointer casts
do not skip call checks. Later chapters add scalar binary32/binary64 arguments and
INTEGER/MEMORY record values through the shared plan. Long-double values
and records containing floating members still reject with232; the negative
fixtures verify that rejected compilation preserves an existing output file.

A call to an undeclared ordinary identifier creates C90's implicit
`extern int name()` declaration. Its name is visible only in the current
block. A separate translation-unit record keeps the external identity,
unspecified signature, and pending call/address fixups after that block's
parser symbols are discarded. Later compatible declarations and definitions
reuse the identity; incompatible returns, non-promoted parameter types,
variadic prototypes, static linkage, and file-scope objects reject with237.
An unknown identifier used as a value still rejects with93.

The two fixup accessors in Ch24 are deferred so existing call and address
emitters can use that persistent record without changing the native default.
Object records retain the same identity in their final cell. Each unresolved
call therefore survives as a real relocation, even across nested blocks and
reused parser symbol IDs. A missing implementation remains a final link
failure; standalone ELF mode rejects unresolved records with206. The implicit
call gate covers scoped names, promoted arguments, function addresses, later
definitions and unresolved symbols. This also lets the unchanged configure
endianness probe call `exit` under its original C90 declaration rules.

C90 distinguishes `f()` from `f(void)`: the first leaves the parameter
list unspecified and applies default integer promotions, while the second
is a prototype requiring zero arguments. Identifier-list definitions
retain their parameter names, then bind the following declarations by
name. Parameters without a declaration become `int`. Comparing such a
definition with a prototype compares its promoted parameter types; a
later unspecified declaration does not erase an already visible prototype.

File-scope declarations and function definitions also admit C90's
omitted `int`; typedef names still introduce explicit types. This handles
the original configure probe `main(){return(0);}` through the ordinary
parser, without recognizing that spelling specially or rewriting source.

Function bodies install the finalized signature directly, avoiding a
second parameter parser with different type rules.

Every declaration context and type name accepts qualifiers between type
keywords, as C90 allows: `unsigned const char *q` in zlib's `gzread.c`,
`long const int`, and typedef names with a qualifier on either side
(`const size_t`, `size_t const`). The qualifier keeps the shared parser's
flag; the base comes from the counted keywords (Chapter 34). In this
target `cc-sysv-spec-check` then applies C90's constraint on that
keyword set in any order: only `long` may repeat (`long long`), at most
one of `signed` and `unsigned`, `void` and `float` stand alone, `double`
admits one `long`, `char` only a sign, `short` only `int` and a sign.
`unsigned signed int`, `long char`, `short long`, `unsigned double` and a
third `long` reject with error 233 instead of quietly selecting a type.

Parameter declaration specifiers accept one `register` in any order with
qualifiers and the base type, including `register const char *` from the
original Flex headers. Named parameters, abstract parameters and nested
callback signatures use the same parser as function definitions and K&R
parameter declarations. Other storage classes and repeated `register`
reject with error 233. A context guard keeps this policy out of aggregate
member declarations and ordinary type names.

File- and block-scope declarations accept their storage class anywhere
among the other specifiers too, as C90 6.5 sets no order: `int static x`,
`long static int y`, `char const static *p`, `unsigned extern long z`,
`int typedef T`, and after a typedef name or tag, `struct S static s`. 115's
`cc-native-declaration` names its own context in `cc-nstorage-context` while
it reads the base, and `cc-sysv-storage-specifier?` sets the same
`nc-static`, `nc-extern` and `nc-td` cells a leading keyword would. The
context's `nc-storage` counts every storage class, those read before the
base by `cc-skip-storage-quals` included, so `static extern int x` and
`int static static x` reject with 233. A storage class in a member or a type
name, even one nested in a declaration's enumerator, is 233 as well.
Qualifiers keep the shared
parser's existing behavior; they do not replace or weaken the recorded
base type, signedness, pointer depth, aggregate identity or callback signature.

`long long` and `unsigned long long` are LP64 eightbytes in the INTEGER
class, passed and returned exactly as `long` is. They remain distinct
types: redeclaring a `long` object or parameter as `long long`, or
selecting between `long *` and `long long *` arms of a conditional,
rejects with 237 like any other pair of distinct integer types.

GNU C's `__extension__` only suppresses pedantic diagnostics, which this
compiler never issues. The target's lexer seam, `cc-sysv-lex-extra`,
skips the reserved word wherever a token may begin, so original sources
may place it before declarations, `typedef`s, members and operands.
The preprocessed text keeps the word; Ch 45's number scanner plugs in
behind the seam through `cc-sysv-lex-number-fwd`.

The executable ABI admits integer and pointer values. Declarations may
record floating or aggregate parameter and return types without generating
code for them. Defining or calling a function across an unsupported value
boundary stops compilation. Scalar variadic *calls* set the vector argument
count to zero, while this layer defaults to rejecting variadic definitions
until the register-save-area and `va_list` hooks supplied by Chapter 42 are
installed. Parameter lists and call lists have a checked
bound; this is a diagnostic boundary, not permission to discard excess
arguments. Pointer-depth overflow is rejected too.

## 2. Keep expression temporaries alive

Expressions already save intermediate values on the machine stack. A
call nested inside another expression may therefore start with any number
of eight-byte temporaries below the frame. Counting pushes globally would
couple every expression operator, switch, and call to the alignment rule.
Instead, we finish evaluating this call's arguments, then construct a
fresh outgoing block below all those live values.

`r11` remembers the staged arguments. We reserve room for stack arguments
and alignment padding, then round `rsp` down to a multiple of sixteen.
Arguments zero through five go into `rdi`, `rsi`, `rdx`, `rcx`, `r8`, and
`r9`. Remaining arguments are copied in order to the bottom of the
outgoing block, so the seventh argument sits just above the return address
in the callee.

The caller's stack pointer and surviving expression values need a longer
lifetime than that outgoing block. A function such as `setjmp` can return
again after intervening calls have overwritten its former stack area.
Saving only `rsp` is insufficient: in `0 == setjmp(state)`, the zero was
also a live expression-stack value. Each call site therefore reserves
persistent slots in its fixed frame for the original `rsp` and the exact
surviving stack span. Compile-time push/pop accounting includes outer
argument staging; lexical switch depth accounts for saved `rbx` values.
This call's own arguments are excluded because they are discarded after
return. Every return restores the surviving span and `rsp`, discards the
staged arguments, and transfers the still-intact `rax` result to `rdi`.

Indirect targets remain staged alongside their arguments until the final
call sequence. We load the target into `r10`, leaving `al` available for
the System V vector-argument count. Caller-saved registers can all be
clobbered by the callee: recovery reads persistent frame slots. No function
name triggers this mechanism; it applies to every call, including nested
calls and callbacks. The price is a larger bounded frame in this
unoptimized compiler.

The accounting relies on the current fixed-frame contract. Variable-length
arrays and dynamic stack allocation are unsupported; implementing them
requires revisiting stack-span lifetime and restoration. The nonlocal
return oracle in `tests/gcc/sysv-setjmp-check.sh` checks both valid operand
orders, repeated returns, loops, callback recursion, switch re-entry, and
all callee-saved registers. It uses host libc only as an interoperability
oracle; a source-built `setjmp` runtime is a separate milestone.

## 3. Save the registers the caller owns

The existing emitter saves and restores `rbp`. This mode reserves the
first local slot for `rbx`, the only other callee-saved register used by
the expression backend, and restores it on every epilogue. The backend
does not use `r12` through `r15`. Register arguments are copied into local
slots before parsing the body; later stack arguments are copied from the
caller's incoming stack area. All parameters can then use the same typed
local load and store machinery as ordinary variables.

The opt-in hooks have native defaults. Merely loading this module does
not select System V or change the private native argument convention.
The tests must keep checking that property as both routes develop.

Floating type spelling is distinct from floating computation. A header may
legitimately declare an unused `double` function, or a pointer to a floating
object. We keep its real type, size, and alignment: local storage also
aligns long doubles and containing aggregates to sixteen bytes. Scalar
local lvalues materialize only when their value is needed, so taking
`&local_double` does not first perform an unsupported floating load.
Typed load, store, and conversion hooks reject unsupported value classes.
[Ch45](45-direct-gcc-binary64.md) adds binary32/binary64 computation and return values;
static floating initializers and unsupported function definitions/calls
also fail before publication.

Long double takes a different route. `cc-nbase-scalar-fwd` lets this target
replace the keyword-spelled `ty-ldouble` base with an opaque record: base
`ty-struct` and one shared, memberless sixteen-byte, sixteen-aligned
descriptor from `cc-ld-descriptor`. `cc-ld?` recognizes it. The value is then
carried by address and copied whole, like a record, and never loaded into a
register, so no x87 computation is ever needed to move it. The same
descriptor makes it one leaf for initializers (`cc-opaque-scalar-fwd`).
`cc-ld-mismatch` and `cc-ld-die` give every operation that would compute or
convert the prefixed error 249; [Ch48](48-direct-gcc-aggregate-abi.md) applies
them and gives the type its X87 calling convention. `sizeof` may inspect their types without
creating a call or a value operation. Existing aggregate byte copies remain
supported; aggregate values still cannot cross this scalar call boundary.

`tests/gcc/sysv-declaration-types-check.sh` checks that distinction against a
host layout/address oracle and tests failure-output preservation. These
rules admit real headers without pretending to implement SSE arithmetic,
rewriting their declarations, or treating floating values as integer bits.

## Try it

The first gate uses only the seed interpreter to produce its executables:

```sh
./build.sh
tests/gcc/sysv-check.sh
tests/gcc/sysv-knr-check.sh
tests/gcc/sysv-setjmp-check.sh
```

It checks direct and indirect calls, arguments on both sides of the
six-register boundary, nested argument evaluation, recursion, incoming
`argc`/`argv`, narrow integer results, and explicit rejection of unsupported
value classes and inconsistent prototypes. Host-compiler interoperability
is a separate boundary check added with the object adapter; a host-built
reference must never become a production bootstrap input.

## Canonical source

Grouped function-pointer declarators and abstract casts retain each star
in the type word. For example, `void (**)(rtx)` has depth two and the same
recursive signature as `void (*)(rtx)`. Its value points to a stored
function pointer; dereferencing loads that pointer before a call. Only
depth zero function designators and depth one function pointers are
callable. Calling a deeper pointer object is rejected with error 230, while a depth above
255 is rejected with error 231 instead of wrapping. The focused
`tests/gcc/nested-function-pointer-check.py` gate covers those boundaries,
object-pointer casts, load/store behavior and mixed GCC O0/O2 execution.

```forth file=121-cc-sysv.fth
\ 121-cc-sysv.fth — explicit scalar System V AMD64 target.
\ Loading this file changes no target. cc-sysv-enable opts in to LP64 and
\ INTEGER-class calls; floating and aggregate values fail closed.
variable cc-target-sysv
[lit] 0 cc-target-sysv !
[lit] 64 constant cc-sysv-arg-cap
[lit] 1398362966 constant cc-sysv-signature-tag
create cc-sysv-signatures cc-sym-cap [lit] 8 * allot

\ An ordinary identifier never resolves to a struct/union tag. The reverse
\ scan still chooses the innermost ordinary declaration; member names live
\ in their aggregate descriptors and enumerators remain ordinary names.
: cc-sysv-find-ordinary ( a u -- id|-1 )
  cc-target-sysv @ 0= if, cc-sym-find-default exit, then,
  cc-nf-u ! cc-nf-a ! cc-sym-count @
  begin, dup while,
    1-
    dup cc-sym-kind-of sk-struct <> if,
      dup cc-sym-name-len cell[] @ cc-nf-u @ = if,
        dup cc-sym-name-addr cell[] @ cc-nf-a @ cc-nf-u @ bytes-eq if,
          exit,
        then,
      then,
    then,
  repeat, drop true ;
: cc-sysv-find-tag ( a u -- id|-1 )
  cc-target-sysv @ if, cc-nfind-tag else, cc-sym-find-default then, ;
' cc-sysv-find-ordinary is cc-sym-find
' cc-sysv-find-tag is cc-sym-find-tag

\ GNU C's __extension__ only silences pedantic diagnostics, which this
\ compiler never issues. The SysV lexer drops the reserved word between
\ tokens, so it may precede declarations, members and operands alike;
\ the preprocessed text keeps it. Number scanning (127) plugs in behind.
create cc-sysv-extension-name s, __extension__
: cc-sysv-extension? ( -- flag )
  cc-src-pos @ [lit] 13 + dup cc-src-len @ > if, drop [lit] 0 exit, then,
  dup cc-src-len @ < if,
    cc-src-buf + c@ ident-cont? if, [lit] 0 exit, then,
  else, drop then,
  cc-src-buf cc-src-pos @ + cc-sysv-extension-name [lit] 13 bytes-eq ;
: cc-sysv-skip-extensions
  begin,
    cc-target-sysv @ cc-eof? 0= and if, cc-sysv-extension? else, [lit] 0 then,
  while,
    cc-src-pos @ [lit] 13 + cc-src-pos ! cc-skip-ws-and-comments
  repeat, ;
defer cc-sysv-lex-number-fwd
' cc-lex-extra-default is cc-sysv-lex-number-fwd
: cc-sysv-lex-extra ( -- handled? )
  cc-sysv-skip-extensions cc-sysv-lex-number-fwd ;
' cc-sysv-lex-extra is cc-lex-extra-fwd

\ Signature: tag, return type, return descriptor, count, variadic flag,
\ then 64 (type, descriptor) pairs and 64 (name, length, declared) records.
\ Flags: 1 variadic, 2 unspecified prototype, 4 identifier-list definition.
\ Function-pointer descriptors are tagged; names are compile-time metadata.
: cc-sysv-sig-return [lit] 8 + @ ;
: cc-sysv-sig-desc [lit] 16 + @ ;
: cc-sysv-sig-count [lit] 24 + @ ;
: cc-sysv-sig-varargs [lit] 32 + @ ;
: cc-sysv-sig-param [lit] 16 * [lit] 40 + + ;
: cc-sysv-sig-name [lit] 24 * [lit] 1064 + + ;
: cc-sysv-prototype? cc-sysv-sig-varargs [lit] 2 and 0= ;
: cc-sysv-known-params?
  dup cc-sysv-prototype? swap cc-sysv-sig-varargs [lit] 4 and or ;
: cc-sysv-check-signature
  dup 0= if, [lit] 230 cc-die then,
  dup @ cc-sysv-signature-tag <> if, [lit] 230 cc-die then, ;
: cc-sysv-check-scalar-default ( ty -- )
  dup [lit] 256 / [lit] 255 and if, [lit] 231 cc-die then,
  dup ty-ptr if, drop exit, then,
  ty-base
  dup ty-struct = over ty-float = or over ty-double = or
  over ty-ldouble = or swap ty-func = or if, [lit] 232 cc-die then, ;
defer cc-sysv-check-scalar
' cc-sysv-check-scalar-default is cc-sysv-check-scalar

\ Bound object-size arithmetic before multiplying. Explicit bounds are
\ distinct from the unsized-array sentinel inherited from the native parser.
[lit] 1073741824 constant cc-sysv-object-size-limit
: cc-sysv-size-product ( size count -- size' )
  dup 0< if, [lit] 245 cc-die then,
  over 0= if, [lit] 238 cc-die then,
  over cc-sysv-object-size-limit swap / over < if, [lit] 245 cc-die then, * ;
: cc-sysv-object-size
  nc-ty @ nc-desc @ cc-nsize
  nc-array @ [lit] 0 > if, nc-array @ cc-sysv-size-product then,
  nc-inner @ [lit] 0 > if, nc-inner @ cc-sysv-size-product then, ;
: cc-sysv-typedef-check
  cc-target-sysv @ if,
    dup cc-sym-qualified cell[] @ nc-qualified @ or nc-qualified !
    dup cc-sym-array-len-of nc-base-array !
    dup cc-sym-array-inner-of nc-base-inner !
  then, ;
' cc-sysv-typedef-check is cc-ntypedef-check-fwd
\ Preserve array typedef shape through aliases and ordinary declarations.
\ Two bounded dimensions can also be retained behind pointer constructors.
[lit] 64 constant cc-sysv-array-rank-limit
: cc-sysv-array-rank ( type descriptor -- dimensions )
  over ty-base ty-array = [lit] 2 cc-npick ty-ptr 0= and if,
    nip dup cc-ad-type swap cc-ad-desc cc-sysv-array-rank 1+
  else, 2drop [lit] 0 then, ;
: cc-sysv-array-node ( type descriptor count inner -- descriptor )
  [lit] 56 cc-alloc >r [lit] 0 r@ [lit] 48 + !
  r@ [lit] 24 + ! r@ [lit] 16 + ! r@ [lit] 8 + ! r@ !
  \ Canonical nodes hold one dimension, including legacy matrix pointers.
  \ Equivalent row shapes must not depend on how the declarator was spelled.
  r@ cc-ad-inner if,
    r@ cc-ad-type r@ cc-ad-desc r@ cc-ad-inner [lit] 0
    cc-sysv-array-node r@ [lit] 8 + !
    ty-array [lit] 0 ty-make r@ ! [lit] 0 r@ [lit] 24 + !
  then,
  r@ cc-ad-type r@ cc-ad-desc cc-sysv-array-rank
  cc-sysv-array-rank-limit >= if, [lit] 238 cc-die then,
  r@ cc-ad-count [lit] 0 <= if, [lit] 238 cc-die then,
  r@ cc-ad-type ty-ptr 0= if,
    r@ cc-ad-type ty-base dup ty-void = swap ty-func = or if, [lit] 238 cc-die then,
  then,
  r@ cc-ad-type r@ cc-ad-desc cc-expr-type-size
  r@ cc-ad-count cc-sysv-size-product
  r@ cc-ad-inner if, r@ cc-ad-inner cc-sysv-size-product then,
  r@ [lit] 32 + !
  r@ cc-ad-type r@ cc-ad-desc cc-nalignment r@ [lit] 40 + ! r> ;
\ A new node may be born qualified. An existing one may be shared by a
\ typedef or declaration, so qualifying it builds a qualified copy.  The
\ cell holds the row's qualifier set (110's cc-qualifier-bit), never a
\ flag: a const row and a volatile row are different types.
: cc-sysv-qualified-node ( type descriptor count inner set -- descriptor )
  >r cc-sysv-array-node r> over [lit] 48 + ! ;
: cc-sysv-qualify-node ( descriptor set -- descriptor )
  over cc-ad-qualified or
  over cc-ad-qualified over = if, drop exit, then,
  >r dup cc-ad-type over cc-ad-desc [lit] 2 cc-npick cc-ad-count
  [lit] 3 cc-npick cc-ad-inner r> cc-sysv-qualified-node nip ;
\ Additional fixed suffixes form real element-array types. The old outer
\ metadata stays intact for one/two dimensions and for the native target.
\ Depth is bounded independently of the checked 1 GiB size product.
: cc-sysv-array-tail ( depth -- descriptor )
  dup cc-sysv-array-rank-limit > if, [lit] 238 cc-die then,
  cc-parse-const dup [lit] 0 <= if, [lit] 238 cc-die then, >r
  [char] ] cc-expect-punct-c cc-next-token-keep
  [char] [ cc-tok-punct? if,
    1+ cc-sysv-array-tail ty-array [lit] 0 ty-make swap
  else, drop nc-ty @ nc-desc @ then,
  r> [lit] 0 cc-sysv-array-node ;
: cc-sysv-array-extra
  cc-target-sysv @ [char] [ cc-tok-punct? and if,
    nc-base-array @ if, [lit] 238 cc-die then,
    nc-inner @ [lit] 0 <= if, [lit] 238 cc-die then,
    [lit] 3 cc-sysv-array-tail
    ty-array [lit] 0 ty-make swap nc-inner @ [lit] 0
    cc-sysv-array-node nc-desc ! ty-array [lit] 0 ty-make nc-ty !
    [lit] 0 nc-inner ! nc-bound-mask @ [lit] 1 and nc-bound-mask !
  then, ;
' cc-sysv-array-extra is cc-narray-extra-fwd
\ A qualified array decays like any other (C90 6.2.2.1): the qualifier moves
\ onto the pointed-to type. A matrix's row node records it, and the value
\ keeps the expression's qualified flag, so `const T t[2][3]` gives a
\ pointer to qualified rows. A ranked array already points at its element
\ node; a qualified one points at a qualified copy.
: cc-sysv-array-decay
  cc-target-sysv @ cc-last-expr-array-len @ 0= 0= and
  cc-last-expr-type @ ty-base ty-array = and if,
    cc-last-struct-desc @ cc-last-expr-qualified @ cc-sysv-qualify-node
    cc-last-struct-desc !
  then,
  cc-target-sysv @ cc-last-expr-array-inner @ 0= 0= and if,
    cc-last-expr-qualified @ >r
    cc-last-expr-type @ [lit] 1 - cc-last-struct-desc @
    cc-last-expr-array-inner @ [lit] 0 r@ cc-sysv-qualified-node
    ty-array [lit] 1 ty-make swap cc-mark-typed-value
    r> cc-last-expr-qualified !
  then, ;
' cc-sysv-array-decay is cc-array-decay-fwd
\ Declared array pointers take the base type's qualifiers: in
\ `const long (*p)[3]` the rows are qualified, in `long (*const p)[3]` only p.
: cc-sysv-grouped-array ( stars -- )
  cc-target-sysv @ 0= if, cc-npointer-array-default exit, then,
  nc-array @ nc-inner @ or nc-base-array @ or if, [lit] 238 cc-die then,
  >r cc-narray-suffix
  nc-bound-mask @ [lit] 2 and nc-inner @ [lit] 0 <= and if, [lit] 238 cc-die then,
  nc-ty @ nc-desc @ nc-array @ nc-inner @ nc-base-qualified @
  cc-sysv-qualified-node nc-desc !
  ty-array r> ty-make nc-ty !
  [lit] 0 nc-array ! [lit] 0 nc-inner ! [lit] 0 nc-bound-mask ! ;
' cc-sysv-grouped-array is cc-npointer-array-fwd
: cc-sysv-array-address ( type descriptor count inner -- type descriptor )
  cc-target-sysv @ 0= if, cc-array-address-default exit, then,
  >r >r swap [lit] 1 - swap r> r> cc-last-expr-qualified @
  cc-sysv-qualified-node ty-array [lit] 1 ty-make swap ;
' cc-sysv-array-address is cc-array-address-fwd
: cc-sysv-inherit-array
  nc-base-array @ if,
    nc-ty @ nc-base @ <> if,
      nc-base @ nc-sdesc @ nc-base-array @ nc-base-inner @
      nc-base-qualified @ cc-sysv-qualified-node nc-desc !
      ty-array nc-ty @ nc-base @ - ty-make nc-ty ! exit,
    then,
    nc-func @ if, [lit] 238 cc-die then,
    nc-array @ if,
      nc-inner @ nc-base-inner @ or nc-base-array @ [lit] 0 < or if,
        [lit] 238 cc-die
      then,
      nc-base-array @ nc-inner !
    else,
      nc-base-array @ nc-array ! nc-base-inner @ nc-inner !
    then,
  then, ;
: cc-sysv-type-shape ( base-type stars -- type )
  cc-target-sysv @ 0= if, + exit, then,
  dup 0= 0= nc-base-array @ 0= 0= and if,
    >r cc-cast-desc @ nc-base-array @ nc-base-inner @
    nc-base-qualified @ cc-sysv-qualified-node cc-cast-desc !
    ty-array r> ty-make exit,
  then,
  nc-base-array @ cc-type-name-array ! nc-base-inner @ cc-type-name-inner ! + ;
' cc-sysv-type-shape is cc-native-type-shape-fwd
: cc-sysv-sizeof-type ( type descriptor -- bytes )
  cc-expr-type-size
  cc-target-sysv @ if,
    cc-type-name-array @ if,
      cc-type-name-array @ [lit] 0 < if, [lit] 238 cc-die then,
      cc-type-name-array @ cc-sysv-size-product
      cc-type-name-inner @ if, cc-type-name-inner @ cc-sysv-size-product then,
    then,
  then, ;
' cc-sysv-sizeof-type is cc-sizeof-type-size-fwd
\ Array expressions carry a pointer-shaped type before decay. A whole
\ matrix is not a record, and another subscript needs a pointer operand.
: cc-sysv-index-base
  cc-target-sysv @ if,
    cc-last-expr-type @ ty-ptr 0= if, [lit] 238 cc-die then,
  then, ;
' cc-sysv-index-base is cc-index-base-fwd
: cc-sysv-member-base ( op -- op )
  cc-target-sysv @ if,
    cc-last-expr-type @ ty-base ty-struct <> if, [lit] 238 cc-die then,
    dup [char] . = if,
      cc-last-expr-array-len @ cc-last-expr-type @ ty-ptr or if, [lit] 238 cc-die then,
    else,
      cc-last-expr-type @ ty-ptr [lit] 1 <>
      cc-last-expr-array-inner @ or if, [lit] 238 cc-die then,
    then,
  then, ;
' cc-sysv-member-base is cc-member-base-fwd

\ Real layouts are retained even when floating/aggregate value operations
\ are unsupported. Taking an address must not read that value first.
: cc-sysv-float-types cc-target-sysv @ cc-bootstrap-floatbits @ or ;
' cc-sysv-float-types is cc-native-float-types-fwd

\ Long double is the x87 80-bit extended format in sixteen bytes, aligned
\ to sixteen. This target moves its bytes and never computes with them:
\ the value is an opaque record with one shared, memberless descriptor, so
\ it travels by address as records do and every spelling has one identity.
\ Arithmetic, conversion, tests and casts reach error 249 instead (131).
variable cc-ld-desc
[lit] 0 cc-ld-desc !
: cc-ld-descriptor ( -- descriptor )
  cc-ld-desc @ dup if, exit, then, drop
  cc-sd-alloc [lit] 16 over cc-sd-set-total-size
  [lit] 16 over cc-sd-set-align dup cc-ld-desc ! ;
: cc-ld? ( type descriptor -- flag )
  dup 0= if, 2drop [lit] 0 exit, then,
  cc-ld-desc @ = swap ty-struct [lit] 0 ty-make = and ;
create cc-ld-error-prefix s, long-double: bl c,
: cc-ld-die cc-ld-error-prefix [lit] 13 cc-err-write [lit] 249 cc-die ;
\ ( t1 d1 t2 d2 -- )  A value crossing between long double and another
\ type would need an x87 conversion.
: cc-ld-mismatch
  cc-ld? >r cc-ld? r> <> if, cc-ld-die then, ;
: cc-sysv-scalar-base ( type descriptor -- type descriptor )
  cc-target-sysv @ 0= if, exit, then,
  over ty-ldouble [lit] 0 ty-make = if,
    2drop ty-struct [lit] 0 ty-make cc-ld-descriptor
  then, ;
' cc-sysv-scalar-base is cc-nbase-scalar-fwd
' cc-ld? is cc-opaque-scalar-fwd
: cc-sysv-value-type-check ( type -- type )
  cc-target-sysv @ cc-expr-unevaluated @ 0= and if,
    dup cc-sysv-check-scalar
  then, ;
' cc-sysv-value-type-check is cc-emit-type-check-fwd
: cc-sysv-local-load ( slot type -- )
  cc-target-sysv @ if,
    drop cc-emit-lea-rdi-local
    true cc-last-ident-slot ! lv-deref cc-last-lvalue-kind !
  else, cc-emit-load-local-typed then, ;
' cc-sysv-local-load is cc-native-local-load-fwd
: cc-sysv-local-layout ( -- slots slot )
  cc-target-sysv @ 0= if, cc-native-local-layout-default exit, then,
  cc-sysv-object-size dup 0= if, [lit] 238 cc-die then,
  cc-fn-local-count @ [lit] 8 * +
  nc-ty @ nc-desc @ cc-nalignment [lit] 8 cc-nmax cc-nalign
  [lit] 8 / dup cc-fn-local-count @ - swap 1- ;
' cc-sysv-local-layout is cc-native-local-layout-fwd

\ C90 permits an omitted int at file scope. A typedef name still starts
\ an explicit type; other identifiers remain pending for the declarator.
: cc-sysv-implicit-base ( -- type descriptor true | false )
  cc-target-sysv @ nc-top @ and 0= if, [lit] 0 exit, then,
  tok-kind @ tk-ident <> if, [lit] 0 exit, then,
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup 0< 0= if,
    dup cc-sym-kind-of sk-typedef = if, drop [lit] 0 exit, then,
  then, drop
  cc-putback-token ty-int [lit] 0 ty-make [lit] 0 true ;
' cc-sysv-implicit-base is cc-native-implicit-base-fwd

: cc-sysv-implicit-declarator-noop ;
defer cc-sysv-implicit-declarator-fwd
' cc-sysv-implicit-declarator-noop is cc-sysv-implicit-declarator-fwd

: cc-sysv-check-declarator
  cc-target-sysv @ if,
    nc-td @ nc-func @ and if, [lit] 238 cc-die then,
    cc-sysv-implicit-declarator-fwd
    cc-sysv-inherit-array
    nc-ty @ nc-desc @ cc-sysv-array-rank
    nc-array @ if, 1+ then, nc-inner @ if, 1+ then,
    cc-sysv-array-rank-limit > if, [lit] 238 cc-die then,
    nc-ty @ [lit] 256 / [lit] 255 and if, [lit] 231 cc-die then,
    nc-bound-mask @ [lit] 1 and if,
      nc-array @ [lit] 0 <= if, [lit] 238 cc-die then,
    then,
    nc-bound-mask @ [lit] 2 and if,
      nc-inner @ [lit] 0 <= if, [lit] 238 cc-die then,
    then,
    nc-array @ [lit] 0 > nc-inner @ [lit] 0 > or if,
      cc-sysv-object-size drop
    then,
  then, ;
' cc-sysv-check-declarator is cc-ndeclarator-check-fwd

: cc-sysv-adjust-array-parameter
  nc-array @ if,
    \ Ranked element nodes also construct a pointer-to-array at adjustment.
    nc-ty @ ty-base ty-array = nc-ty @ ty-ptr 0= and if,
      nc-desc @ nc-base-qualified @ cc-sysv-qualify-node nc-desc !
    then,
    nc-inner @ if,
      nc-ty @ nc-desc @ nc-inner @ [lit] 0 nc-base-qualified @
      cc-sysv-qualified-node nc-desc !
      ty-array [lit] 1 ty-make nc-ty !
      [lit] 0 nc-array ! [lit] 0 nc-inner ! exit,
    then,
    [lit] 1 nc-ty +! [lit] 0 nc-array !
  then, ;

\ Parameter signatures carry types independently of optional source names.
: cc-sysv-fnptr-name
  cc-target-sysv @ 0= if, cc-nfnptr-name-default exit, then,
  cc-next-token-keep
  tok-kind @ tk-ident = if,
    tok-str-addr @ nc-name ! tok-str-len @ nc-nlen !
  else, cc-putback-token then, ;
' cc-sysv-fnptr-name is cc-nfnptr-name-fwd

defer cc-sysv-signature-fwd
: cc-sysv-fnptr
  cc-target-sysv @ 0= if, cc-nfnptr-default exit, then,
  1+ dup [lit] 255 > if, [lit] 231 cc-die then, >r
  nc-base-array @ if,
    nc-ty @ nc-base @ = if, [lit] 238 cc-die then,
    cc-sysv-inherit-array
    [lit] 0 nc-base-array ! [lit] 0 nc-base-inner !
  then,
  nc-ty @ nc-desc @ cc-sysv-signature-fwd nc-desc !
  ty-func r> ty-make nc-ty ! ;
' cc-sysv-fnptr is cc-nfnptr-fwd

: cc-sysv-find-parameter ( sig name length -- index|-1 )
  [lit] 0 begin, [lit] 3 cc-npick cc-sysv-sig-count over > while,
    [lit] 3 cc-npick over cc-sysv-sig-name
    dup [lit] 8 + @ [lit] 3 cc-npick = if,
      @ [lit] 3 cc-npick [lit] 3 cc-npick bytes-eq if,
        >r drop 2drop r> exit,
      then,
    else, drop then,
    1+
  repeat, drop drop 2drop true ;
: cc-sysv-identifier-list ( sig -- sig )
  dup cc-sysv-sig-count if, [lit] 233 cc-die then,
  [lit] 6 over [lit] 32 + !
  begin,
    tok-kind @ tk-ident <> if, [lit] 233 cc-die then,
    dup cc-sysv-sig-count cc-sysv-arg-cap >= if, [lit] 234 cc-die then,
    dup tok-str-addr @ tok-str-len @ cc-sysv-find-parameter 0< 0= if,
      [lit] 233 cc-die
    then,
    dup dup cc-sysv-sig-count cc-sysv-sig-name
    tok-str-addr @ over ! tok-str-len @ swap [lit] 8 + !
    dup dup cc-sysv-sig-count cc-sysv-sig-param
    ty-int [lit] 0 ty-make swap !
    [lit] 1 over [lit] 24 + +!
    cc-next-token-keep [char] , cc-tok-punct? if,
      cc-next-token-keep
    else,
      [char] ) cc-tok-punct? 0= if, [lit] 233 cc-die then, exit,
    then,
  again, ;
\ C90 parameter declarations allow one register specifier, interleaved
\ with type keywords and qualifiers. Keep this policy in the parameter's
\ own declaration context: an aggregate member uses a different context.
\ Qualifiers retain the shared parser's existing representation; the base
\ type, signedness, pointer depth and descriptor still come from cc-nbase.
variable cc-sysv-parameter-context
variable cc-sysv-parameter-register
\ A file- or block-scope declaration's own base (cc-nstorage-context, 115)
\ also reads storage-class keywords between its type keywords and
\ qualifiers: `int static x`, `long static int y`, `char const static *p`,
\ `unsigned extern long z`, `int typedef T`.  They set the same nc-static,
\ nc-extern and nc-td cells as a leading keyword.  One storage class per
\ declaration, wherever it is written; a second is 233.  So is one in a
\ member or a type name, neither of which declares storage.
: cc-sysv-storage-note
  [lit] 1 nc-storage +! nc-storage @ [lit] 1 > if, [lit] 233 cc-die then, ;
: cc-sysv-storage-specifier? ( -- flag )
  kw-static cc-tok-kw? if, cc-sysv-storage-note true nc-static ! true exit, then,
  kw-extern cc-tok-kw? if, cc-sysv-storage-note true nc-extern ! true exit, then,
  kw-typedef cc-tok-kw? if, cc-sysv-storage-note true nc-td ! true exit, then,
  kw-auto cc-tok-kw? kw-register cc-tok-kw? or if,
    cc-sysv-storage-note true exit,
  then,
  kw-inline cc-tok-kw? ;
: cc-sysv-declaration-specifiers
  nc-storage @ [lit] 1 > if, [lit] 233 cc-die then,
  begin, cc-sysv-storage-specifier? while, cc-next-token-keep repeat, ;
: cc-sysv-storage-keyword? ( -- flag )
  kw-static cc-tok-kw? kw-extern cc-tok-kw? or kw-typedef cc-tok-kw? or
  kw-auto cc-tok-kw? or kw-register cc-tok-kw? or ;
: cc-sysv-parameter-specifiers
  cc-target-sysv @ 0= if, exit, then,
  cc-nctx @ cc-nstorage-context @ = if, cc-sysv-declaration-specifiers exit, then,
  cc-nctx @ cc-sysv-parameter-context @ <> if,
    cc-sysv-storage-keyword? if, [lit] 233 cc-die then, exit,
  then,
  begin,
    kw-static cc-tok-kw? kw-extern cc-tok-kw? or
    kw-auto cc-tok-kw? or kw-typedef cc-tok-kw? or
    kw-inline cc-tok-kw? or if, [lit] 233 cc-die then,
    kw-register cc-tok-kw? if,
      cc-sysv-parameter-register @ if, [lit] 233 cc-die then,
      true cc-sysv-parameter-register ! true
    else, cc-qualifier? dup if, cc-qual-note then, then,
  while, cc-next-token-keep repeat, ;
' cc-sysv-parameter-specifiers is cc-nbase-specifiers-fwd
\ After a typedef name, tag or implicit int, the same specifiers and
\ qualifiers may follow before the declarator: `struct S static s`.
: cc-sysv-base-trailing
  cc-target-sysv @ 0= if, exit, then,
  cc-next-token-keep cc-nbase-next-specifier cc-putback-token ;
' cc-sysv-base-trailing is cc-nbase-trailing-fwd
\ C90 constrains the multiset of type keywords, whatever their order and
\ any qualifiers between them. Only long may repeat (long long); one sign;
\ void and float stand alone; double admits one long; char admits a sign;
\ short admits int and a sign. Every declaration context rejects with 233.
variable cc-sysv-spec-bad
: cc-sysv-spec-fail ( flag -- ) cc-sysv-spec-bad @ or cc-sysv-spec-bad ! ;
: cc-sysv-spec-total ( -- n )
  [lit] 0 [lit] 0
  begin, dup cc-nspec-slots < while, dup cc-nspec-count rot + swap 1+ repeat, drop ;
\ Fail when any keyword outside the named slots' total is present.
: cc-sysv-spec-only ( allowed -- ) cc-sysv-spec-total swap - [lit] 0 > cc-sysv-spec-fail ;
: cc-sysv-spec-check
  cc-target-sysv @ 0= if, exit, then,
  [lit] 0 cc-sysv-spec-bad !
  [lit] 0
  begin, dup cc-nspec-slots < while,
    dup cc-nspec-count over kw-long = if, [lit] 2 else, [lit] 1 then, >
    cc-sysv-spec-fail 1+
  repeat, drop
  kw-unsigned cc-nspec-count kw-signed cc-nspec-count + dup >r
  [lit] 1 > cc-sysv-spec-fail
  kw-void cc-nspec-count if, kw-void cc-nspec-count cc-sysv-spec-only then,
  cc-nspec-float cc-nspec-count if,
    cc-nspec-float cc-nspec-count cc-sysv-spec-only
  then,
  cc-nspec-double cc-nspec-count if,
    kw-long cc-nspec-count [lit] 1 > cc-sysv-spec-fail
    cc-nspec-double cc-nspec-count kw-long cc-nspec-count + cc-sysv-spec-only
  then,
  kw-char cc-nspec-count if, kw-char cc-nspec-count r@ + cc-sysv-spec-only then,
  kw-short cc-nspec-count if,
    kw-short cc-nspec-count kw-int cc-nspec-count + r@ + cc-sysv-spec-only
  then,
  r> drop
  cc-sysv-spec-bad @ if, [lit] 233 cc-die then, ;
' cc-sysv-spec-check is cc-nspec-check-fwd
: cc-sysv-parameter-base ( -- type descriptor )
  cc-sysv-parameter-context @ >r cc-sysv-parameter-register @ >r
  cc-nctx @ cc-sysv-parameter-context !
  [lit] 0 cc-sysv-parameter-register !
  cc-nbase
  \ Aggregate, enum and typedef bases return before trailing specifiers.
  cc-next-token-keep cc-sysv-parameter-specifiers cc-putback-token
  r> cc-sysv-parameter-register ! r> cc-sysv-parameter-context ! ;

\ C adjusts a function-declared parameter to a pointer to that function.
\ Reparse its saved suffix through the same recursive signature parser as
\ an explicit (*callback) declarator, then restore the enclosing delimiter.
: cc-sysv-adjust-function-parameter
  nc-func @ if,
    cc-lex-state-size cc-alloc dup cc-lex-mark >r
    nc-params cc-lex-reset
    nc-ty @ nc-desc @ cc-sysv-signature-fwd nc-desc !
    r> cc-lex-reset
    ty-func [lit] 1 ty-make nc-ty ! [lit] 0 nc-func !
  then, ;

: cc-sysv-signature ( return-type return-desc -- signature )
  [lit] 2600 cc-alloc dup >r [lit] 2600 cc-nzero
  r@ [lit] 16 + ! r@ [lit] 8 + !
  cc-sysv-signature-tag r@ !
  nc-qualified @ r@ cc-field-set-qualified
  cc-nctx @ >r cc-ncontext
  begin,
    cc-next-token-keep
    [char] ) cc-tok-punct? if,
      r> cc-nctx ! r>
      dup cc-sysv-sig-count if, [lit] 233 cc-die then,
      [lit] 2 over [lit] 32 + ! exit,
    then,
    pt-ellipsis cc-tok-punct? if,
      r> cc-nctx ! r>
      dup cc-sysv-sig-count 0= if, [lit] 233 cc-die then,
      [lit] 1 over [lit] 32 + ! [char] ) cc-expect-punct-c exit,
    then,
    kw-void cc-tok-kw? if,
      cc-peek-mark cc-lex-mark cc-next-token-keep
      [char] ) cc-tok-punct? if,
        r> cc-nctx ! r> dup cc-sysv-sig-count if, [lit] 233 cc-die then, exit,
      then,
      cc-peek-mark cc-lex-reset
    then,
    tok-kind @ tk-ident = cc-native-type-start 0= and if,
      r> cc-nctx ! r> cc-sysv-identifier-list exit,
    then,
    cc-sysv-parameter-base nc-sdesc ! nc-base ! cc-ndeclarator
    cc-sysv-adjust-function-parameter
    cc-sysv-adjust-array-parameter
    nc-ty @ ty-size 0= if, [lit] 233 cc-die then,
    r> r> dup >r swap >r
    nc-nlen @ if,
      dup nc-name @ nc-nlen @ cc-sysv-find-parameter 0< 0= if,
        [lit] 233 cc-die
      then,
    then,
    dup cc-sysv-sig-count dup cc-sysv-arg-cap >= if, [lit] 234 cc-die then,
    over swap cc-sysv-sig-param
    nc-qualified @ over cc-field-set-qualified
    nc-ty @ over ! nc-desc @ swap [lit] 8 + !
    dup dup cc-sysv-sig-count cc-sysv-sig-name
    nc-name @ over ! nc-nlen @ over [lit] 8 + !
    true swap [lit] 16 + !
    [lit] 1 swap [lit] 24 + +!
    [char] , cc-tok-punct? 0= if,
      [char] ) cc-tok-punct? 0= if, [lit] 184 cc-die then,
      r> cc-nctx ! r> exit,
    then,
  again, ;
' cc-sysv-signature is cc-sysv-signature-fwd

\ Abstract function-pointer type names reuse the declaration signature parser.
\ Each grouped star is retained in the type word beside its signature.
\ Depth one is a function pointer; greater depths point to pointer objects.
\ The operand address is unchanged; loads occur when those objects are read.
: cc-sysv-type-name-raw
  cc-native-type-name
  cc-type-name-qualified @ nc-qualified !
  cc-target-sysv @ 0= if, exit, then,
  cc-next-token-keep
  lparen cc-tok-punct? if,
    cc-type-name-array @ if, [lit] 238 cc-die then,
    [char] * cc-expect-punct-c
    cc-skip-qualifiers cc-count-stars 1+
    dup [lit] 255 > if, [lit] 231 cc-die then, >r
    [char] ) cc-expect-punct-c cc-next-token-keep
    [char] [ cc-tok-punct? if,
      cc-type-name-qualified @ cc-nctx @ >r cc-ncontext >r
      cc-narray-suffix
      nc-bound-mask @ [lit] 2 and nc-inner @ [lit] 0 <= and if, [lit] 238 cc-die then,
      cc-cast-desc @ nc-array @ nc-inner @ r> cc-sysv-qualified-node
      cc-cast-desc !
      r> cc-nctx ! ty-array r> ty-make cc-putback-token
    else,
      lparen cc-tok-punct? 0= if, [lit] 238 cc-die then,
      cc-cast-desc @ cc-sysv-signature cc-cast-desc !
      ty-func r> ty-make
    then,
  else, cc-putback-token then, ;
\ A type name shares its enclosing declaration's context but is never a
\ declaration: a storage class inside one, as in an enumerator's
\ sizeof (int static), is 233 (cc-sysv-parameter-specifiers).
: cc-sysv-type-name
  cc-nctx @ 0= if, cc-ncontext then,
  cc-nstorage-context @ >r [lit] 0 cc-nstorage-context !
  nc-qualified @ >r nc-base-qualified @ >r nc-prefix-qualified @ >r
  [lit] 0 nc-prefix-qualified ! cc-sysv-type-name-raw
  nc-qualified @ cc-type-name-qualified !
  r> nc-prefix-qualified ! r> nc-base-qualified ! r> nc-qualified !
  r> cc-nstorage-context ! ;
' cc-sysv-type-name is cc-native-type-name-fwd

\ C permits function-pointer conversions and a round trip back to the
\ original signature. A call still uses its actual selected signature and
\ the normal ABI class checks. Only explicit casts cross to object pointers.
: cc-sysv-function-pointer? ( type -- flag )
  dup ty-base ty-func = swap ty-ptr [lit] 1 = and ;
: cc-sysv-integral? ( type -- flag )
  dup ty-ptr if, drop [lit] 0 exit, then,
  ty-base
  dup ty-char = over ty-uchar = or over ty-short = or
  over ty-ushort = or over ty-int = or over ty-uint = or
  over ty-long = or over ty-ulong = or
  over ty-llong = or swap ty-ullong = or ;
\ Explicit LP64 integer/function-pointer representation conversions use
\ all 64 bits. Only pointer-width integral destinations preserve a function
\ address. Explicit function/object pointer casts keep all 64 bits too, as
\ POSIX dlsym and GCC allow; any other function-pointer partner rejects.
\ The policy is pure so constant and runtime casts share it.
\ This permits signal sentinels and address round trips, not arbitrary calls.
: cc-sysv-cast-types ( source destination -- )
  cc-target-sysv @ 0= if, 2drop exit, then,
  dup ty-void [lit] 0 ty-make = if, 2drop exit, then,
  over cc-sysv-integral? over cc-sysv-function-pointer? and if,
    2drop exit,
  then,
  over cc-sysv-function-pointer? over cc-sysv-integral? and if,
    ty-size [lit] 8 <> if, [lit] 230 cc-die then, drop exit,
  then,
  over cc-sysv-function-pointer? over cc-sysv-function-pointer? = if,
    2drop exit,
  then,
  ty-ptr 0= swap ty-ptr 0= or if, [lit] 230 cc-die then, ;
' cc-sysv-cast-types is cc-cast-types-fwd
\ Normalize an integral operand before replacing its type with a pointer:
\ signed narrow values extend their sign and unsigned ones extend zero.
: cc-sysv-cast-value ( source destination -- )
  cc-target-sysv @ if,
    over cc-sysv-integral? over cc-sysv-function-pointer? and if,
      over cc-emit-convert-rdi
    then,
  then,
  cc-emit-convert-value ;
' cc-sysv-cast-value is cc-cast-value-fwd
\ Qualified void pointees do not form null pointer constants. The flattened
\ qualifier flag also conservatively excludes top-level-qualified void*.
\ Read the cast target's saved flag, never metadata left by a nested cast.
: cc-sysv-cast-null ( source destination null qualified -- null )
  swap >r >r
  dup cc-sysv-integral? swap ty-void [lit] 1 ty-make = r> 0= and or
  swap cc-sysv-integral? and r> and cc-target-sysv @ and ;
' cc-sysv-cast-null is cc-cast-null-fwd
: cc-sysv-ternary-split cc-target-sysv @ ;
' cc-sysv-ternary-split is cc-value-ternary-split-fwd


\ Type identity is checked at redeclarations. Struct pointers retain tag
\ identity; function-pointer signatures compare recursively by shape.
\ A row reached through a pointer carries its qualifier set on its node;
\ a nested array element's rows share the outer node's set, so only
\ pointer-to-row types have a set of their own to compare.
: cc-sysv-row-set ( type descriptor -- set )
  over ty-base ty-array = [lit] 2 cc-npick ty-ptr 0= 0= and over 0= 0= and if,
    nip cc-ad-qualified exit,
  then, 2drop [lit] 0 ;
\ cc-sysv-compatible-types compares shape, and below the outermost level,
\ qualifier sets exactly: `const long (*a[2])[3]` and `long (*b[2])[3]` are
\ incompatible.  The outermost row's set is left to the caller, since an
\ assignment may add a qualifier there (cc-sysv-row-qualifier-check).
defer cc-sysv-compatible-signatures-fwd
: cc-sysv-compatible-types ( ty1 desc1 ty2 desc2 -- flag )
  >r swap >r
  2dup <> if, 2drop r> drop r> drop [lit] 0 exit, then,
  drop ty-base
  dup ty-func = if,
    drop r> r> cc-sysv-compatible-signatures-fwd exit,
  then,
  dup ty-array = if,
    drop r> r>
    2dup 0= swap 0= or if, [lit] 237 cc-die then,
    2dup cc-ad-count swap cc-ad-count <> if, 2drop [lit] 0 exit, then,
    2dup cc-ad-inner swap cc-ad-inner <> if, 2drop [lit] 0 exit, then,
    dup cc-ad-type swap cc-ad-desc >r >r
    dup cc-ad-type swap cc-ad-desc r> r>
    [lit] 3 cc-npick [lit] 3 cc-npick cc-sysv-row-set
    [lit] 2 cc-npick [lit] 2 cc-npick cc-sysv-row-set <> if,
      2drop 2drop [lit] 0 exit,
    then,
    cc-sysv-compatible-types exit,
  then,
  ty-struct = if, r> r> = else, r> drop r> drop true then, ;
\ cc-sysv-same-types also requires equal outermost row sets: redeclared
\ objects and prototype parameters and results must match exactly, so
\ `extern const long (*p)[3]; extern volatile long (*p)[3];` is 237.
: cc-sysv-same-types ( ty1 desc1 ty2 desc2 -- flag )
  [lit] 3 cc-npick [lit] 3 cc-npick cc-sysv-row-set
  [lit] 2 cc-npick [lit] 2 cc-npick cc-sysv-row-set <> if,
    2drop 2drop [lit] 0 exit,
  then,
  cc-sysv-compatible-types ;
\ Implicit conversion may add a row qualifier but never discard one:
\ `long (*p)[3] = t` with `const long t[2][3]` needs an explicit cast
\ (238), and so does `const long (*q)[3] = v` from volatile rows.  Below
\ the first pointer the sets must be equal (C90 6.3.16.1: the pointed-to
\ types must be compatible), so `const long (**q)[3] = &p` from
\ `long (*p)[3]` is 237.
: cc-sysv-row-qualifier-check ( source descriptor destination descriptor -- same )
  [lit] 3 cc-npick ty-base ty-array = [lit] 2 cc-npick ty-base ty-array = and
  [lit] 3 cc-npick 0= 0= and over 0= 0= and if,
    [lit] 3 cc-npick [lit] 3 cc-npick cc-sysv-row-set
    [lit] 2 cc-npick [lit] 2 cc-npick cc-sysv-row-set
    [lit] 3 cc-npick ty-ptr [lit] 1 > if,
      <> if, [lit] 237 cc-die then,
    else,
      cc-invert and if, [lit] 238 cc-die then,
    then,
  then, ;
: cc-sysv-value-shape ( source descriptor destination descriptor -- )
  cc-target-sysv @ 0= if, 2drop 2drop exit, then,
  [lit] 3 cc-npick ty-base ty-array = [lit] 2 cc-npick ty-base ty-array = or
  [lit] 4 cc-npick ty-base ty-func = [lit] 3 cc-npick ty-base ty-func = or or if,
    [lit] 3 cc-npick ty-ptr 0= [lit] 2 cc-npick ty-ptr 0= or if,
      cc-last-expr-null @ 0= if, [lit] 237 cc-die then,
      2drop 2drop exit,
    then,
    [lit] 3 cc-npick ty-void [lit] 1 ty-make =
    [lit] 2 cc-npick ty-void [lit] 1 ty-make = or if, 2drop 2drop exit, then,
    [lit] 3 cc-npick [lit] 3 cc-npick [lit] 3 cc-npick [lit] 3 cc-npick
    cc-sysv-compatible-types 0= if, [lit] 237 cc-die then,
    cc-sysv-row-qualifier-check 2drop 2drop
  else, 2drop 2drop then, ;
' cc-sysv-value-shape is cc-value-shape-fwd
: cc-sysv-array-operands?
  cc-target-sysv @ if,
    cc-expr-left-type @ ty-base ty-array = cc-expr-right-type @ ty-base ty-array = or
  else, [lit] 0 then, ;
: cc-sysv-array-pair-check
  cc-expr-left-type @ cc-expr-left-desc @ cc-expr-right-type @ cc-expr-right-desc @
  cc-sysv-compatible-types 0= if, [lit] 237 cc-die then, ;
: cc-sysv-array-binop
  cc-sysv-array-operands? 0= if, exit, then,
  cc-expr-left-type @ ty-ptr cc-expr-right-type @ ty-ptr and if,
    cc-expr-op-row @ bo-op + @ [char] - =
    cc-expr-op-row @ bo-level + @ dup level-rel = swap level-eq = or or
    0= if, [lit] 237 cc-die then,
    cc-sysv-array-pair-check exit,
  then,
  cc-expr-op-row @ bo-level + @ level-add = if,
    cc-expr-left-type @ ty-ptr if,
      cc-expr-right-type @ cc-sysv-integral? 0= if, [lit] 237 cc-die then,
    else,
      cc-expr-op-row @ bo-op + @ [char] + <>
      cc-expr-left-type @ cc-sysv-integral? 0= or if, [lit] 237 cc-die then,
    then, exit,
  then,
  cc-expr-op-row @ bo-level + @ level-eq = if,
    cc-expr-left-type @ ty-ptr if, cc-expr-right-null @ else, cc-expr-left-null @ then,
    if, exit, then,
  then,
  [lit] 237 cc-die ;
' cc-sysv-array-binop is cc-array-binop-fwd
: cc-sysv-array-compound
  cc-sysv-array-operands? if,
    cc-expr-left-type @ ty-ptr 0= cc-expr-right-type @ cc-sysv-integral? 0= or
    if, [lit] 237 cc-die then,
  then, ;
' cc-sysv-array-compound is cc-array-compound-fwd
: cc-sysv-array-ternary
  cc-target-sysv @ 0= if, exit, then,
  cc-expr-left-type @ ty-void [lit] 0 ty-make =
  cc-expr-right-type @ ty-void [lit] 0 ty-make = or if,
    cc-expr-left-type @ cc-expr-right-type @ <> if, [lit] 237 cc-die then,
    ty-void [lit] 0 ty-make cc-expr-common ! exit,
  then,
  cc-expr-left-type @ ty-ptr cc-expr-right-type @ ty-ptr or 0= if, exit, then,
  \ A null pointer constant adopts the other arm's pointer type. A void*
  \ variable, including one whose runtime value is zero, is not such a constant.
  cc-expr-left-null @ cc-expr-right-type @ ty-ptr and if,
    cc-expr-right-type @ cc-expr-common ! exit,
  then,
  cc-expr-right-null @ cc-expr-left-type @ ty-ptr and if,
    cc-expr-left-type @ cc-expr-common ! exit,
  then,
  cc-expr-left-type @ ty-ptr 0= cc-expr-right-type @ ty-ptr 0= or
  if, [lit] 237 cc-die then,
  cc-expr-left-type @ ty-void [lit] 1 ty-make =
  cc-expr-right-type @ ty-void [lit] 1 ty-make = or if,
    cc-expr-left-type @ cc-sysv-function-pointer?
    cc-expr-right-type @ cc-sysv-function-pointer? or if, [lit] 237 cc-die then,
    ty-void [lit] 1 ty-make cc-expr-common ! exit,
  then,
  cc-sysv-array-pair-check
  \ Either arm's row qualifier qualifies the result, which takes the left
  \ arm's node.
  cc-expr-left-type @ ty-base ty-array = if,
    cc-expr-left-desc @ cc-expr-right-desc @ cc-ad-qualified
    cc-sysv-qualify-node cc-expr-left-desc !
  then, ;
' cc-sysv-array-ternary is cc-array-ternary-fwd
: cc-sysv-signature-result dup cc-sysv-sig-return swap cc-sysv-sig-desc ;
: cc-sysv-parameter-type cc-sysv-sig-param dup @ swap [lit] 8 + @ ;
\ Default promotions matter to prototype compatibility even for types
\ whose executable calling convention is deliberately unsupported.
: cc-sysv-default-type ( type -- promoted-type )
  dup ty-ptr 0= over ty-base ty-float = and if,
    drop ty-double [lit] 0 ty-make
  else, cc-unary-type then, ;
: cc-sysv-comparison-param ( sig index -- type desc )
  over cc-sysv-prototype? >r cc-sysv-parameter-type
  r> 0= if, swap cc-sysv-default-type swap then, ;
: cc-sysv-default-compatible? ( sig -- flag )
  dup cc-sysv-sig-varargs [lit] 1 and if, drop [lit] 0 exit, then,
  [lit] 0 begin, over cc-sysv-sig-count over > while,
    2dup cc-sysv-sig-param @ dup cc-sysv-default-type <> if,
      2drop [lit] 0 exit,
    then, 1+
  repeat, 2drop true ;
: cc-sysv-compatible-signatures ( sig1 sig2 -- flag )
  2dup cc-sysv-check-signature drop cc-sysv-check-signature drop
  2dup >r cc-sysv-signature-result r> cc-sysv-signature-result
  cc-sysv-same-types 0= if, 2drop [lit] 0 exit, then,
  over cc-sysv-known-params? 0= if,
    nip dup cc-sysv-prototype? if, cc-sysv-default-compatible?
    else, drop true then, exit,
  then,
  dup cc-sysv-known-params? 0= if,
    drop dup cc-sysv-prototype? if, cc-sysv-default-compatible?
    else, drop true then, exit,
  then,
  2dup cc-sysv-sig-count swap cc-sysv-sig-count <> if, 2drop [lit] 0 exit, then,
  2dup cc-sysv-sig-varargs [lit] 1 and
  swap cc-sysv-sig-varargs [lit] 1 and <> if, 2drop [lit] 0 exit, then,
  [lit] 0 begin, over cc-sysv-sig-count over > while,
    [lit] 2 cc-npick over cc-sysv-comparison-param
    [lit] 3 cc-npick [lit] 3 cc-npick cc-sysv-comparison-param
    cc-sysv-same-types 0= if, drop 2drop [lit] 0 exit, then,
    1+
  repeat, drop 2drop true ;
' cc-sysv-compatible-signatures is cc-sysv-compatible-signatures-fwd

\ C90 implicit externs keep scoped visibility but persistent declaration
\ identity and fixups: a block's symbol IDs may be reused after it exits.
\ Record: next, name, length, unspecified-int signature, calls, addresses.
variable cc-sysv-implicit-head
variable cc-sysv-implicit-count
: cc-sysv-implicit-find ( name length -- record|0 )
  cc-nf-u ! cc-nf-a ! cc-sysv-implicit-head @
  begin, dup while,
    dup [lit] 16 + @ cc-nf-u @ = if,
      dup [lit] 8 + @ cc-nf-a @ cc-nf-u @ bytes-eq if, exit, then,
    then, @
  repeat, ;
: cc-sysv-implicit-symbol ( id -- record|0 )
  dup cc-sym-kind-of sk-func <> if, drop [lit] 0 exit, then,
  dup cc-sym-name-addr cell[] @ swap cc-sym-name-len cell[] @ cc-sysv-implicit-find ;
: cc-sysv-call-fixups ( id -- cell )
  cc-target-sysv @ if,
    dup cc-sysv-implicit-symbol dup if, nip [lit] 32 + exit, then, drop
  then, cc-sym-call-fixups-default ;
: cc-sysv-address-fixups ( id -- cell )
  cc-target-sysv @ if,
    dup cc-sysv-implicit-symbol dup if, nip [lit] 40 + exit, then, drop
  then, cc-sym-addr-fixups-default ;
' cc-sysv-call-fixups is cc-sym-call-fixups
' cc-sysv-address-fixups is cc-sym-addr-fixups
: cc-sysv-implicit-record ( name length -- record )
  2dup cc-sysv-implicit-find dup if, nip nip exit, then, drop
  cc-sysv-implicit-count @ 1+ cc-sym-cap [lit] 60 cc-check-cap
  [lit] 1 cc-sysv-implicit-count +!
  [lit] 48 cc-alloc dup >r [lit] 48 cc-nzero
  r@ [lit] 16 + ! r@ [lit] 8 + !
  cc-sysv-implicit-head @ r@ ! r@ cc-sysv-implicit-head !
  [lit] 2600 cc-alloc dup [lit] 2600 cc-nzero
  cc-sysv-signature-tag over !
  ty-int [lit] 0 ty-make over [lit] 8 + !
  [lit] 2 over [lit] 32 + ! r@ [lit] 24 + ! r> ;
: cc-sysv-implicit-declared-noop drop ;
defer cc-sysv-implicit-declared-fwd
' cc-sysv-implicit-declared-noop is cc-sysv-implicit-declared-fwd
: cc-sysv-unknown-ident ( -- id|-1 )
  cc-target-sysv @ 0= if, true exit, then,
  cc-peek-mark cc-lex-mark cc-next-token-keep
  lparen cc-tok-punct? cc-peek-mark cc-lex-reset 0= if, true exit, then,
  tok-str-addr @ tok-str-len @ cc-sysv-implicit-record >r
  tok-str-addr @ tok-str-len @ sk-func ty-int [lit] 0 ty-make [lit] 0 cc-sym-add
  r> [lit] 24 + @ over cc-sysv-signatures cell[] !
  dup cc-sysv-implicit-declared-fwd ;
' cc-sysv-unknown-ident is cc-native-unknown-ident-fwd
: cc-sysv-check-implicit-signature ( signature -- )
  nc-name @ nc-nlen @ cc-sysv-implicit-find dup if,
    nc-static @ if, [lit] 237 cc-die then,
    [lit] 24 + @ cc-sysv-compatible-signatures 0= if, [lit] 237 cc-die then,
  else, 2drop then, ;
\ A file-scope object cannot replace an earlier implicit external function;
\ a typedef or a block-local object has no conflicting external linkage.
: cc-sysv-implicit-declarator
  nc-top @ nc-func @ 0= and nc-td @ 0= and if,
    nc-name @ nc-nlen @ cc-sysv-implicit-find if, [lit] 237 cc-die then,
  then, ;
' cc-sysv-implicit-declarator is cc-sysv-implicit-declarator-fwd
: cc-sysv-check-implicit-defined
  cc-sysv-implicit-head @ begin, dup while,
    dup [lit] 32 + @ over [lit] 40 + @ or if, [lit] 206 cc-die then, @
  repeat, drop ;

: cc-sysv-symbol-signature ( id -- signature )
  dup cc-sym-kind-of sk-func = if,
    cc-sysv-signatures cell[] @
  else,
    dup cc-sym-type-of cc-sysv-function-pointer? 0= if, [lit] 230 cc-die then,
    cc-sym-struct-desc-of
  then, cc-sysv-check-signature ;
: cc-sysv-call-qualified
  cc-target-sysv @ if, cc-sysv-symbol-signature cc-field-qualified
  else, drop [lit] 0 then, ;
' cc-sysv-call-qualified is cc-native-call-qualified-fwd

: cc-sysv-function-desc
  cc-target-sysv @ if, cc-sysv-symbol-signature
  else, cc-native-function-desc then, ;
' cc-sysv-function-desc is cc-native-function-desc-fwd
: cc-sysv-call-result
  cc-target-sysv @ if,
    cc-sysv-symbol-signature dup cc-sysv-sig-return swap cc-sysv-sig-desc
  else, cc-native-call-result then, ;
' cc-sysv-call-result is cc-native-call-result-fwd

\ Stage each argument in an eight-byte temporary, converting fixed arguments
\ to the prototype's actual width before the register/stack split.
: cc-sysv-argument-check-default ( signature index -- ) 2drop ;
defer cc-sysv-argument-check-fwd
' cc-sysv-argument-check-default is cc-sysv-argument-check-fwd
: cc-sysv-parse-args ( signature -- count )
  [lit] 0 cc-next-token-keep
  [char] ) cc-tok-punct? 0= if,
    cc-putback-token
    begin,
      dup cc-sysv-arg-cap >= if, [lit] 234 cc-die then,
      cc-parse-assign-fwd cc-emit-materialize
      2dup cc-sysv-argument-check-fwd
      cc-expr-unevaluated @ 0= if, cc-last-expr-type @ cc-sysv-check-scalar-default then,
      over cc-sysv-sig-count over > [lit] 2 cc-npick cc-sysv-prototype? and if,
        2dup cc-sysv-sig-param @
        cc-expr-unevaluated @ 0= if, dup cc-sysv-check-scalar-default then,
        cc-last-expr-type @ swap cc-emit-convert-value
      else,
        over cc-sysv-sig-varargs [lit] 3 and 0= if, [lit] 235 cc-die then,
        cc-last-expr-type @ cc-unary-type cc-emit-convert-rdi
      then,
      cc-emit-push-rdi 1+
      cc-next-token-keep [char] , cc-tok-punct? 0=
    until,
    [char] ) cc-tok-punct? 0= if, [lit] 121 cc-die then,
  then,
  over cc-sysv-prototype? if,
    over cc-sysv-sig-count over > if, [lit] 235 cc-die then,
  then,
  nip dup cc-native-reverse-args ;

\ Count actual expression/argument pushes, separately from lexical switch
\ saves. A call snapshots the complete surviving span, including outer-call
\ arguments and switch RBX saves; its own argument vector is transient.
variable cc-sysv-stack-depth
: cc-sysv-track-push
  cc-target-sysv @ if, [lit] 1 cc-sysv-stack-depth +! then, ;
: cc-sysv-track-pop
  cc-target-sysv @ if,
    cc-sysv-stack-depth @ 0= if, [lit] 239 cc-die then,
    [lit] 1 cc-sysv-stack-depth -!
  then, ;
' cc-sysv-track-push is cc-emit-track-push-fwd
' cc-sysv-track-pop is cc-emit-track-pop-fwd

: cc-sysv-stack-count [lit] 6 - dup 0< if, drop [lit] 0 then, ;
: cc-sysv-load-staged ( index modrm -- )
  cc-emit-byte [lit] 8 * cc-emit-4le ;
: cc-sysv-load-gp ( index -- )
  dup [lit] 4 < if, [lit] 73 else, [lit] 77 then, cc-emit-byte
  [lit] 139 cc-emit-byte
  dup [lit] 0 = if, [lit] 187 else,
  dup [lit] 1 = if, [lit] 179 else,
  dup [lit] 2 = if, [lit] 147 else,
  dup [lit] 3 = if, [lit] 139 else,
  dup [lit] 4 = if, [lit] 131 else, [lit] 139
  then, then, then, then, then, cc-sysv-load-staged ;
: cc-sysv-store-outgoing ( offset -- )
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 132 cc-emit-byte [lit] 36 cc-emit-byte cc-emit-4le ;
\ Call record: RSP frame slot, surviving cell count, staged cell count.
: cc-sysv-save-live ( record -- )
  >r
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  r@ @ [lit] 101 cc-emit-local-ea                \ mov [rbp+slot],rsp
  [lit] 0 begin, dup r@ [lit] 8 + @ < while,
    [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
    [lit] 188 cc-emit-byte [lit] 36 cc-emit-byte
    dup r@ [lit] 16 + @ + [lit] 8 * cc-emit-4le
    dup r@ @ + 1+ cc-emit-store-local
    1+
  repeat, drop r> drop ;
: cc-sysv-restore-live ( record -- )
  >r
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  r@ @ [lit] 101 cc-emit-local-ea                \ mov rsp,[rbp+slot]
  [lit] 0 begin, dup r@ [lit] 8 + @ < while,
    dup r@ @ + 1+ cc-emit-load-local
    [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
    [lit] 188 cc-emit-byte [lit] 36 cc-emit-byte
    dup r@ [lit] 16 + @ + [lit] 8 * cc-emit-4le
    1+
  repeat, drop r> drop ;
: cc-sysv-prepare-call ( count indirect? -- record )
  >r dup r> if, 1+ then,
  [lit] 24 cc-alloc dup >r [lit] 16 + !
  cc-sysv-stack-depth @ r@ [lit] 16 + @ -
  dup 0< if, [lit] 239 cc-die then,
  cc-switch-depth @ + dup r@ [lit] 8 + !
  cc-expr-unevaluated @ if,
    drop [lit] 0 r@ ! [lit] 0 r@ [lit] 8 + !
  else,
    cc-fn-local-count @ r@ ! 1+ cc-fn-add-slots
  then,
  r@ cc-sysv-save-live
  \ Align a fresh outgoing block below every staged and surviving value.
  [lit] 73 cc-emit-byte [lit] 137 cc-emit-byte [lit] 227 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 129 cc-emit-byte [lit] 236 cc-emit-byte
  dup cc-sysv-stack-count [lit] 8 * [lit] 15 + cc-emit-4le
  [lit] 72 cc-emit-byte [lit] 131 cc-emit-byte
  [lit] 228 cc-emit-byte [lit] 240 cc-emit-byte
  [lit] 6 begin, 2dup > while,
    [lit] 73 cc-emit-byte [lit] 139 cc-emit-byte
    dup [lit] 131 cc-sysv-load-staged
    dup [lit] 6 - [lit] 8 * cc-sysv-store-outgoing
    1+
  repeat, drop
  [lit] 0 begin, 2dup > over [lit] 6 < and while,
    dup cc-sysv-load-gp 1+
  repeat, 2drop r> ;
: cc-sysv-finish-call ( count indirect? record -- )
  >r 2drop r@ cc-sysv-restore-live
  r@ [lit] 16 + @ dup cc-sysv-stack-depth @ swap - cc-sysv-stack-depth !
  cc-native-drop-args r> drop
  cc-emit-mov-rdi-rax ;
: cc-sysv-zero-vector-count
  [lit] 49 cc-emit-byte [lit] 192 cc-emit-byte ;
: cc-sysv-call-staged-target ( count -- )
  \ r10 is independent of AL, which reports zero vector arguments.
  [lit] 77 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 147 cc-sysv-load-staged
  cc-sysv-zero-vector-count
  [lit] 65 cc-emit-byte [lit] 255 cc-emit-byte [lit] 210 cc-emit-byte ;
defer cc-sysv-result-value-fwd
' cc-emit-convert-rdi is cc-sysv-result-value-fwd

: cc-sysv-call ( id -- )
  cc-target-sysv @ 0= if, cc-parse-native-call exit, then,
  cc-check-static-init
  dup cc-sysv-symbol-signature >r
  dup cc-sym-kind-of sk-func <> if,
    dup cc-sym-kind-of sk-local = if,
      cc-sym-val-of cc-emit-load-local
    else, cc-sym-val-of cc-emit-global-ref cc-emit-load-via-rdi then,
    cc-emit-push-rdi
    r@ cc-sysv-parse-args dup true cc-sysv-prepare-call >r
    dup cc-sysv-call-staged-target true r> cc-sysv-finish-call
  else,
    r@ cc-sysv-parse-args dup [lit] 0 cc-sysv-prepare-call >r >r
    cc-sysv-zero-vector-count
    dup cc-sym-val-of 0= if,
      cc-emit-call-rel32-placeholder
      cc-expr-unevaluated @ if, 2drop
      else, swap cc-sym-call-fixups cc-add-fixup-to-list then,
    else, cc-sym-val-of cc-emit-call-vaddr then,
    r> [lit] 0 r> cc-sysv-finish-call
  then,
  r> cc-sysv-sig-return cc-sysv-result-value-fwd ;
' cc-sysv-call is cc-native-call-fwd
: cc-sysv-check-callable ( type -- )
  dup ty-base ty-func <> swap ty-ptr [lit] 1 > or if, [lit] 230 cc-die then, ;
: cc-sysv-indirect-call
  cc-target-sysv @ 0= if, cc-parse-indirect-call exit, then,
  cc-check-static-init
  cc-last-expr-type @ cc-sysv-check-callable
  cc-last-struct-desc @ cc-sysv-check-signature >r
  cc-emit-materialize cc-emit-push-rdi
  r@ cc-sysv-parse-args dup true cc-sysv-prepare-call >r
  dup cc-sysv-call-staged-target true r> cc-sysv-finish-call
  r@ cc-sysv-sig-return dup cc-sysv-result-value-fwd
  r> dup cc-field-qualified >r cc-sysv-sig-desc cc-mark-typed-value
  r> cc-last-expr-qualified ! ;
' cc-sysv-indirect-call is cc-native-indirect-fwd

\ RBX is the only callee-saved expression register. RBP is saved by090;
\ R12..R15 are never touched. Reserve local slot0 before any parameters.
: cc-sysv-restore-callee
  cc-target-sysv @ if,
    [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
    [lit] 93 cc-emit-byte [lit] 248 cc-emit-byte
  then, ;
' cc-sysv-restore-callee is cc-emit-restore-callee-fwd
: cc-sysv-save-callee
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 93 cc-emit-byte [lit] 248 cc-emit-byte ;
: cc-sysv-store-gp ( index -- )
  dup 1+ swap
  dup [lit] 0 = if, drop cc-emit-store-local exit, then,
  dup [lit] 1 = if, drop cc-emit-store-local-from-rsi exit, then,
  dup [lit] 2 = if, drop cc-emit-store-local-from-rdx exit, then,
  dup [lit] 3 = if, drop cc-emit-store-local-from-rcx exit, then,
  dup [lit] 4 = if, drop cc-emit-store-local-from-r8 exit, then,
  drop cc-emit-store-local-from-r9 ;
\ K&R declarations refine the identifier list by name, preserving order.
\ Undeclared parameters keep C90's implicit int. Only register storage is
\ permitted here; a declaration outside the identifier list is an error.
: cc-sysv-abi-type-default ( type descriptor -- ) drop cc-sysv-check-scalar-default ;
defer cc-sysv-abi-type-fwd
' cc-sysv-abi-type-default is cc-sysv-abi-type-fwd
: cc-sysv-old-parameters ( sig -- )
  cc-nctx @ >r cc-ncontext
  begin, [char] { cc-tok-punct? 0= while,
    cc-sysv-parameter-base nc-sdesc ! nc-base !
    begin,
      cc-ndeclarator
      cc-sysv-adjust-function-parameter
      cc-sysv-adjust-array-parameter
      nc-ty @ nc-desc @ cc-sysv-abi-type-fwd
      nc-ty @ ty-size 0= if, [lit] 233 cc-die then,
      dup nc-name @ nc-nlen @ cc-sysv-find-parameter
      dup 0< if, [lit] 233 cc-die then,
      2dup cc-sysv-sig-name dup [lit] 16 + @ if, [lit] 233 cc-die then,
      true swap [lit] 16 + !
      over swap cc-sysv-sig-param
      nc-qualified @ over cc-field-set-qualified
    nc-ty @ over ! nc-desc @ swap [lit] 8 + !
      [char] , cc-tok-punct?
    while, repeat,
    [char] ; cc-tok-punct? 0= if, [lit] 233 cc-die then,
    cc-next-token-keep
  repeat, drop r> cc-nctx ! ;
: cc-sysv-params ( sig -- )
  dup cc-sysv-sig-count cc-native-param-count !
  [lit] 0 begin, over cc-sysv-sig-count over > while,
    2dup cc-sysv-sig-name dup @ nc-name ! [lit] 8 + @ nc-nlen !
    nc-nlen @ 0= if, [lit] 233 cc-die then,
    2dup cc-sysv-sig-param cc-field-qualified nc-qualified !
    2dup cc-sysv-parameter-type nc-desc ! nc-ty !
    nc-ty @ cc-sysv-check-scalar-default
    [lit] 0 nc-array ! [lit] 0 nc-inner !
    sk-local over 1+ cc-ninstall-symbol drop
    [lit] 1 cc-fn-add-slots 1+
  repeat, 2drop ;

\ Later target layers may implement variadic definitions; the default
\ remains a checked rejection until their register-save machinery exists.
: cc-sysv-varargs-prepare-default ( signature -- )
  cc-sysv-sig-varargs [lit] 1 and if, [lit] 236 cc-die then, ;
: cc-sysv-varargs-save-default ;
defer cc-sysv-varargs-prepare-fwd
defer cc-sysv-varargs-save-fwd
' cc-sysv-varargs-prepare-default is cc-sysv-varargs-prepare-fwd
' cc-sysv-varargs-save-default is cc-sysv-varargs-save-fwd

defer cc-sysv-params-fwd
' cc-sysv-params is cc-sysv-params-fwd
: cc-sysv-store-params-default
  [lit] 0 begin, dup cc-native-param-count @ < while,
    dup [lit] 6 < if, dup cc-sysv-store-gp else,
      [lit] 0 over [lit] 3 - - cc-emit-load-local
      dup 1+ cc-emit-store-local
    then, 1+
  repeat, drop ;
defer cc-sysv-store-params-fwd
' cc-sysv-store-params-default is cc-sysv-store-params-fwd
: cc-sysv-return-check-default ( type descriptor -- ) drop cc-sysv-check-scalar ;
defer cc-sysv-return-check-fwd
' cc-sysv-return-check-default is cc-sysv-return-check-fwd

variable cc-sysv-frame-patch
variable cc-sysv-function-signature
: cc-sysv-function
  cc-target-sysv @ 0= if, cc-native-function exit, then,
  cc-lex-state-size cc-alloc dup cc-lex-mark >r
  nc-params cc-lex-reset
  nc-ty @ nc-desc @ cc-sysv-signature cc-sysv-function-signature !
  r> cc-lex-reset
  cc-sysv-function-signature @ cc-sysv-sig-varargs [lit] 4 and if,
    cc-sysv-function-signature @ cc-sysv-old-parameters
  then,
  cc-sysv-function-signature @ cc-sysv-check-implicit-signature
  nc-name @ nc-nlen @ cc-sym-find
  dup 0< 0= if,
    dup cc-sym-kind-of sk-func <> if, [lit] 237 cc-die then,
    dup cc-sysv-symbol-signature cc-sysv-function-signature @
    cc-sysv-compatible-signatures 0= if, [lit] 237 cc-die then,
  then,
  dup 0< if,
    drop nc-name @ nc-nlen @ sk-func nc-ty @ [lit] 0 cc-sym-add
    nc-desc @ over cc-sym-set-struct-desc
    [lit] 0 over cc-sysv-signatures cell[] !
  then,
  nc-id !
  nc-id @ cc-sysv-signatures cell[] @ dup if,
    cc-sysv-prototype? cc-sysv-function-signature @ cc-sysv-prototype? 0= and
  else, drop [lit] 0 then, 0= if,
    cc-sysv-function-signature @ nc-id @ cc-sysv-signatures cell[] !
  then,
  nc-ty @ nc-id @ cc-sym-type cell[] !
  nc-desc @ nc-id @ cc-sym-set-struct-desc
  [char] { cc-tok-punct? 0= if, exit, then,
  nc-ty @ nc-desc @ cc-sysv-return-check-fwd
  nc-id @ cc-sym-val-of if, [lit] 211 cc-die then,
  cc-here-vaddr nc-id @ cc-sym-val cell[] !
  nc-id @ cc-sym-call-fixups @ cc-here-vaddr cc-walk-and-patch-to-vaddr
  [lit] 0 nc-id @ cc-sym-call-fixups !
  nc-id @ cc-sym-addr-fixups @ cc-here-vaddr cc-walk-and-patch-imm64-to-vaddr
  [lit] 0 nc-id @ cc-sym-addr-fixups !
  nc-name @ nc-nlen @ cc-is-main? if, cc-here-vaddr cc-main-vaddr ! then,
  nc-ty @ cc-native-return-type ! nc-desc @ cc-native-return-desc !
  cc-nctx @ >r cc-ncontext cc-scope-push
  [lit] 1 cc-fn-local-count ! [lit] 0 cc-label-count !
  [lit] 0 cc-sysv-stack-depth !
  [lit] 0 cc-break-stack-head ! [lit] 0 cc-continue-stack-head !
  [lit] 0 cc-switch-depth ! [lit] 0 cc-loop-switch-depth !
  cc-sysv-function-signature @ cc-sysv-params-fwd
  cc-sysv-function-signature @ cc-sysv-varargs-prepare-fwd
  [lit] 0 cc-emit-prologue
  cc-out-pos @ [lit] 4 - cc-sysv-frame-patch ! cc-sysv-save-callee
  cc-sysv-varargs-save-fwd
  cc-sysv-store-params-fwd
  begin,
    cc-next-token-keep [char] } cc-tok-punct? 0= while,
    cc-putback-token cc-parse-stmt
  repeat,
  cc-sysv-stack-depth @ if, [lit] 239 cc-die then,
  cc-emit-xor-rax-rax cc-emit-epilogue cc-native-finish-gotos
  cc-fn-local-count @ [lit] 8 * [lit] 16 cc-nalign
  cc-sysv-frame-patch @ cc-out-patch-4le
  cc-scope-pop r> cc-nctx ! ;
' cc-sysv-function is cc-native-function-fwd

: cc-sysv-enable
  [lit] 0 cc-qualified-fields ! [lit] 0 cc-ld-desc !
  [lit] 0 cc-sysv-implicit-head ! [lit] 0 cc-sysv-implicit-count !
  true cc-target-sysv ! true cc-target-lp64 ! true cc-prep-direct !
  [lit] 0 cc-bootstrap-floatbits ! ;
: cc-sysv-translation-unit
  begin,
    cc-skip-storage-quals cc-next-token-keep tok-kind @ tk-eof = 0= while,
    true cc-native-declaration
  repeat, ;
: cc-sysv-entry
  cc-native-init-entry-fwd
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte [lit] 60 cc-emit-byte [lit] 36 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte [lit] 116 cc-emit-byte [lit] 36 cc-emit-byte [lit] 8 cc-emit-byte
  cc-sysv-zero-vector-count cc-emit-call-rel32-placeholder cc-call-main-patch !
  cc-emit-mov-rdi-rax [lit] 184 cc-emit-byte [lit] 60 cc-emit-4le
  [lit] 15 cc-emit-byte [lit] 5 cc-emit-byte ;
: cc-sysv-program
  cc-sysv-entry cc-sysv-translation-unit
  cc-native-init-finish-fwd cc-sysv-check-implicit-defined
  cc-check-fns-defined cc-patch-call-main ;
```

## 4. Carry code and storage into a relocatable object

The object adapter uses the same parser and emitter. It leaves out the
kernel entry stub and private runtime, copies generated function code
into the object writer's text section, and exports each function's name,
binding, start, and size. Calls resolved within that text remain valid
because moving caller and callee together preserves their relative
distance. Calls to declarations without a definition become explicit
`R_X86_64_PLT32` relocations with an addend of minus four.

An object needs identities that last longer than a parser scope. The
symbol table reuses IDs when a block ends, but a static local must survive
for the entire program. The adapter therefore maintains separate stable
object records. Every global reference names a record; only final
serialization translates records to ELF symbol IDs. Two static locals
with the same spelling retain distinct records even when their parser
slots were reused. An `extern` declaration stays undefined until a real
definition appears, while a tentative definition receives zeroed BSS at
the end of the translation unit. Completing a tentative array updates its
record, so earlier references keep naming the final object.

Initialized objects reserve aligned data storage. The adapter reuses
Chapter 34's recursive initializer traversal and replaces only its scalar
and string leaves. Chapter 41's typed constant evaluator returns a value,
type, descriptor, and optional symbolic target. Absolute values write the
destination's low bytes. A symbolic pointer writes an `R_X86_64_64`
relocation with its explicit addend. This handles function pointers,
array elements, and aggregate fields without executing an initializer at
startup. Unsigned intermediate arithmetic follows the same width rules
as ordinary expressions, rather than using an untyped host-sized result.

String literals live in read-only object storage; character-array
initializers copy their decoded bytes into the array's own data or local
storage. Function addresses and global addresses materialized in code
also receive `R_X86_64_64` relocations. The current emitter uses absolute
addresses, so these objects target the bounded static executable path;
they do not claim position-independent code generation.

Object bounds are checked before multiplication, and explicit zero or
negative bounds are rejected separately from an unsized `[]`. Repeated
object declarations must agree on scalar versus array shape. Array
typedefs retain their shape through aliases, declarations, and `sizeof`.
A one-dimensional alias can be an element of an outer array; the existing
object representation holds at most two dimensions. A parameter declared
with a one-dimensional array alias decays to its element pointer, while a
local object keeps the array's full size. This is the ordinary type rule
used by Chapter 42's real `va_list[1]` representation, not a special size
attached to that typedef name. Type-name queries preserve the enclosing
declaration's shape, and casting to an array type is rejected.

The constant type representation does not yet encode a pointer to an
array. Address constants such as `&rows[i][j]` are supported, while a bare
`&array` or unindexed multidimensional-array decay is rejected. Multidimensional array parameters, block-scope function declarations, and
narrow integer relocations are also rejected.
Unsupported forms must stop before publication, rather than preserving an
absolute address that happened to work inside the old executable image.

Run the interoperability and storage gates with:

```sh
tests/gcc/sysv-interop-check.sh
tests/gcc/sysv-storage-check.sh
```

The first gate crosses the host ABI in both directions. The storage gate
checks globals, tentative arrays, strings, aggregate-field and array
element addends, external providers, and static-local identity. It first
uses a host harness, then repeats the storage checks with independently
Forth-compiled objects, a Forth-emitted startup object, and the Forth
linker. Host oracle bytes never enter the production proof.

```forth file=123-cc-object-program.fth
\ 123-cc-object-program.fth — shared scalar C parser to ELF64 ET_REL.
\ Stable object records outlive parser scopes: static locals never inherit
\ an unrelated object when cc-sym IDs are reused. All relocations name these
\ records until081 assigns its own stable symbol IDs at serialization.
variable cc-sysv-object-mode
[lit] 0 cc-sysv-object-mode !
[lit] 4096 constant cc-om-default-cap
create cc-om-default-records cc-om-default-cap [lit] 128 * allot
variable cc-om-limit
variable cc-om-buffer
cc-om-default-cap cc-om-limit !
cc-om-default-records cc-om-buffer !
: cc-om-cap ( -- entries ) cc-om-limit @ ;
: cc-om-records ( -- address ) cc-om-buffer @ ;
\ Complete original insn-output.c needs 10,559 stable records; round to 10,752.
\ Keep the default table and opt in explicitly to a fixed mapped table.
[lit] 10752 constant cc-om-direct-cap
variable cc-om-direct-base
: cc-om-default-workspace ( -- )
  cc-om-default-records cc-om-buffer ! cc-om-default-cap cc-om-limit ! ;
: cc-om-direct-workspace ( -- )
  cc-om-direct-base @ 0= if,
    cc-om-direct-cap [lit] 128 * [lit] 245 cc-workspace-map
    cc-om-direct-base !
  then,
  cc-om-direct-base @ cc-om-buffer ! cc-om-direct-cap cc-om-limit ! ;
variable cc-om-count
\ Reject invalid IDs before subtraction or multiplication in either workspace.
: cc-om-record ( id -- address )
  dup [lit] 1 < if, [lit] 245 cc-die then,
  dup cc-om-cap [lit] 245 cc-check-cap
  1- [lit] 128 * cc-om-records + ;
: om-name cc-om-record ;
: om-nlen cc-om-record [lit] 8 + ;
: om-bind cc-om-record [lit] 16 + ;
: om-kind cc-om-record [lit] 24 + ;
: om-section cc-om-record [lit] 32 + ;
: om-offset cc-om-record [lit] 40 + ;
: om-size cc-om-record [lit] 48 + ;
: om-align cc-om-record [lit] 56 + ;
: om-type cc-om-record [lit] 64 + ;
: om-desc cc-om-record [lit] 72 + ;
: om-array cc-om-record [lit] 80 + ;
: om-inner cc-om-record [lit] 88 + ;
: om-flags cc-om-record [lit] 96 + ;
: om-output cc-om-record [lit] 104 + ;
: om-symbol cc-om-record [lit] 112 + ;
\ Flags:1 extern-only,2 tentative,4 initialized,8 block static,
\ 16 referenced,32 anonymous. A later definition replaces extern-only.
: cc-om-flag ( flag record -- ) om-flags dup @ rot or swap ! ;
: cc-om-new ( name length binding kind -- record )
  cc-om-count @ 1+ cc-om-cap [lit] 245 cc-check-cap
  [lit] 1 cc-om-count +! cc-om-count @ >r
  r@ cc-om-record [lit] 128 cc-nzero
  r@ om-kind ! r@ om-bind ! r@ om-nlen ! r@ om-name !
  [lit] 1 r@ om-align ! r> ;
variable cc-om-find-name
variable cc-om-find-length
: cc-om-find ( name length -- record|0 )
  cc-om-find-length ! cc-om-find-name !
  [lit] 1 begin, dup cc-om-count @ <= while,
    dup om-flags @ [lit] 40 and 0= if,
      dup om-nlen @ cc-om-find-length @ = if,
        dup om-name @ cc-om-find-name @ cc-om-find-length @ bytes-eq if, exit, then,
      then,
    then, 1+
  repeat, drop [lit] 0 ;
: cc-om-from-symbol ( symbol -- record )
  dup cc-sym-kind-of sk-global = if, cc-sym-val-of exit, then,
  dup cc-sym-name-addr cell[] @ swap cc-sym-name-len cell[] @ cc-om-find
  dup 0= if, [lit] 238 cc-die then, ;

\ The unused final record cell retains an implicit declaration's stable
\ identity even after its block-scoped parser symbol has disappeared.
: om-implicit cc-om-record [lit] 120 + ;
: cc-sysv-object-implicit ( id -- )
  cc-sysv-object-mode @ 0= if, drop exit, then,
  dup cc-sym-name-addr cell[] @ over cc-sym-name-len cell[] @ cc-om-find
  dup 0= if,
    drop dup cc-sym-name-addr cell[] @ over cc-sym-name-len cell[] @
    cc-obj-global cc-obj-func cc-om-new
  then,
  dup om-kind @ cc-obj-func <> if, [lit] 237 cc-die then,
  swap cc-sysv-implicit-symbol swap om-implicit ! ;
' cc-sysv-object-implicit is cc-sysv-implicit-declared-fwd

variable cc-om-relocations
: cc-om-reloc ( section offset kind record addend -- )
  [lit] 48 cc-alloc >r
  r@ [lit] 40 + ! dup [lit] 16 swap cc-om-flag
  r@ [lit] 32 + ! r@ [lit] 24 + ! r@ [lit] 16 + ! r@ [lit] 8 + !
  cc-om-relocations @ r@ ! r> cc-om-relocations ! ;
: cc-om-reference ( record -- )
  >r cc-obj-text cc-out-pos @ [lit] 2 + cc-obj-r64 r> [lit] 0 cc-om-reloc
  [lit] 0 cc-emit-movabs-rdi-imm64 ;
: cc-sysv-object-function-desc
  cc-sysv-object-mode @ cc-expr-unevaluated @ 0= and if,
    dup cc-om-from-symbol >r
    cc-obj-text cc-out-pos @ [lit] 2 + cc-obj-r64 r> [lit] 0 cc-om-reloc
  then, cc-sysv-function-desc ;
' cc-sysv-object-function-desc is cc-native-function-desc-fwd

create cc-om-string-name s, .Lstring
: cc-om-string-piece ( address length -- )
  begin, dup while,
    over c@ backslash = over [lit] 1 > and if,
      over 1+ cc-decode-escape swap cc-obj-byte 1+
      >r swap r@ + swap r> -
    else,
      over c@ cc-obj-byte swap 1+ swap 1-
    then,
  repeat, 2drop ;
: cc-om-string ( -- record )
  cc-obj-current @ >r cc-obj-rodata cc-obj-use
  cc-om-string-name [lit] 8 cc-obj-local cc-obj-object cc-om-new
  [lit] 32 over om-flags ! cc-obj-rodata over om-section !
  cc-obj-here over om-offset !
  begin, tok-kind @ tk-str = while,
    tok-str-addr @ tok-str-len @ cc-om-string-piece cc-next-token-keep
  repeat,
  [lit] 0 cc-obj-byte
  cc-obj-here over om-offset @ - over om-size !
  r> cc-obj-use ;
: cc-sysv-object-string
  cc-sysv-object-mode @ cc-expr-unevaluated @ 0= and if,
    cc-om-string dup om-size @ cc-last-expr-array-len !
    cc-putback-token cc-om-reference
  else, cc-parse-native-string-literal then, ;
' cc-sysv-object-string is cc-native-string-fwd

: cc-sysv-object-function
  cc-sysv-object-mode @ 0= if, cc-sysv-function exit, then,
  nc-top @ 0= if, [lit] 238 cc-die then,
  nc-name @ nc-nlen @ cc-om-find
  dup 0= if,
    drop nc-name @ nc-nlen @ cc-obj-global cc-obj-func cc-om-new
  else,
    dup om-kind @ cc-obj-func <> if, [lit] 237 cc-die then,
  then,
  nc-static @ if, cc-obj-local over om-bind ! then,
  >r cc-out-pos @ >r cc-sysv-function
  nc-id @ r> r> rot over om-symbol !
  >r cc-out-pos @ over - dup if,
    r@ om-size ! r@ om-offset ! cc-obj-text r@ om-section !
  else, 2drop then, r> drop ;
' cc-sysv-object-function is cc-native-function-fwd

: cc-om-compatible-object ( record -- )
  dup om-kind @ cc-obj-object <> if, [lit] 237 cc-die then,
  dup om-type @ over om-desc @ nc-ty @ nc-desc @
  cc-sysv-same-types 0= if, [lit] 237 cc-die then,
  dup om-array @ 0= nc-array @ 0= <> if, [lit] 237 cc-die then,
  dup om-array @ [lit] 0 > nc-array @ [lit] 0 > and if,
    dup om-array @ nc-array @ <> if, [lit] 237 cc-die then,
  then,
  dup om-inner @ nc-inner @ <> if, [lit] 237 cc-die then, drop ;
: cc-om-size-from-declaration ( record -- )
  nc-ty @ over om-type ! nc-desc @ over om-desc !
  nc-array @ [lit] 0 < over om-array @ [lit] 0 > and if,
    dup om-array @ nc-array !
  then,
  nc-array @ over om-array ! nc-inner @ over om-inner !
  cc-sysv-object-size over om-size !
  nc-ty @ nc-desc @ cc-nalignment swap om-align ! ;
: cc-om-install-object ( record -- )
  dup nc-slot !
  nc-top @ if, nc-name @ nc-nlen @ cc-sym-find else, true then,
  dup 0< if,
    drop sk-global over cc-ninstall-symbol
  else,
    dup cc-sym-kind-of sk-global <> if, [lit] 237 cc-die then,
    nc-qualified @ over cc-sym-qualified cell[] !
    nc-ty @ over cc-sym-type cell[] !
    nc-desc @ over cc-sym-set-struct-desc
    nc-array @ over cc-sym-set-array-len nc-inner @ over cc-sym-set-array-inner
    over over cc-sym-val cell[] !
  then,
  dup nc-id ! cc-sysv-object-size swap cc-sym-set-object-size drop ;
: cc-om-initializer
  true cc-ni-static ! cc-next-token-keep
  nc-ty @ nc-desc @ nc-array @ nc-inner @ [lit] 0 [lit] 0 cc-ni-value ;
: cc-sysv-object-declaration
  cc-sysv-object-mode @ 0= if, cc-nobject exit, then,
  nc-top @ 0= nc-extern @ 0= and nc-array @ [lit] 0 < and
  [char] = cc-tok-punct? 0= and if, [lit] 238 cc-die then,
  nc-top @ nc-static @ or nc-extern @ or 0= if, cc-nobject exit, then,
  [char] = cc-tok-punct? if, cc-native-init-prepare-fwd then,
  nc-top @ 0= nc-static @ and if, [lit] 0
  else, nc-name @ nc-nlen @ cc-om-find then,
  dup if, dup cc-om-compatible-object else,
    drop nc-name @ nc-nlen @ cc-obj-global cc-obj-object cc-om-new
    nc-top @ 0= nc-static @ and if, [lit] 8 over cc-om-flag then,
  then,
  nc-static @ if, cc-obj-local over om-bind ! then,
  dup cc-om-size-from-declaration dup cc-om-install-object
  [char] = cc-tok-punct? if,
    dup om-flags @ [lit] 4 and if, [lit] 237 cc-die then,
    cc-obj-current @ >r cc-obj-data cc-obj-use
    dup om-align @ cc-obj-align dup om-size @ cc-obj-reserve over om-offset !
    cc-obj-data over om-section ! [lit] 4 over cc-om-flag
    r> cc-obj-use drop cc-om-initializer
  else,
    nc-extern @ if, [lit] 1 else, [lit] 2 then, swap cc-om-flag
  then, ;
' cc-sysv-object-declaration is cc-nobject-fwd

\ Reuse118's recursive aggregate/array traversal; only static leaves differ.
: cc-om-scalar-initializer
  cc-sysv-object-mode @ cc-ni-static @ and 0= if, cc-ni-scalar exit, then,
  cc-ni-aggregate? if, [lit] 219 cc-die then,
  ni-type @ cc-sysv-check-scalar-default
  cc-putback-token cc-parse-static-const-fwd
  dup 0= [lit] 4 cc-npick 0= and cc-last-expr-null !
  >r 2dup ni-type @ ni-desc @ cc-value-shape-fwd r>
  dup if,
    ni-type @ ty-size [lit] 8 <> if, [lit] 238 cc-die then,
    >r 2drop
    cc-obj-data nc-slot @ om-offset @ ni-offset @ + cc-obj-r64 r> [lit] 4 cc-npick cc-om-reloc
    drop
  else,
    drop 2drop cc-obj-data nc-slot @ om-offset @ ni-offset @ +
    ni-type @ ty-size cc-obj-patch
  then,
  cc-next-token-keep ;
' cc-om-scalar-initializer is cc-ni-scalar-fwd
: cc-om-string-initializer
  cc-sysv-object-mode @ 0= if, cc-ni-string exit, then,
  cc-om-string
  dup om-size @ 1- ni-array @ > if, [lit] 223 cc-die then,
  dup om-size @ ni-array @ cc-nmax drop
  dup om-size @ ni-array @ > if, ni-array @ else, dup om-size @ then,
  cc-ni-static @ if,
    [lit] 0 begin, 2dup > while,
      [lit] 2 cc-npick om-offset @ over + cc-obj-rodata cc-obj-base + c@
      cc-obj-data nc-slot @ om-offset @ ni-offset @ + [lit] 3 cc-npick +
      [lit] 1 cc-obj-patch 1+
    repeat, 2drop drop
  else,
    swap cc-om-reference cc-ni-mov-rsi-rdi
    ni-offset @ cc-ni-address cc-ni-copy-bytes
  then, ;
' cc-om-string-initializer is cc-ni-string-fwd

\ Symbolic constant leaves feed125's typed expression grammar. Record IDs
\ are never addresses; arithmetic only changes an explicit RELA addend.
: cc-om-const-ident
  cc-sysv-object-mode @ 0= if, cc-const-unsupported then,
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup 0< if, cc-const-unsupported then,
  dup cc-sym-kind-of sk-func = if,
    dup cc-sysv-symbol-signature >r cc-om-from-symbol >r
    [lit] 0 ty-func [lit] 1 ty-make r> r> swap exit,
  then,
  dup cc-sym-kind-of sk-global <> if, cc-const-unsupported then,
  dup cc-sym-array-len-of 0= if, cc-const-unsupported then,
  dup cc-om-from-symbol >r
  dup cc-sym-array-inner-of if,
    dup cc-sym-type-of over cc-expr-symbol-desc
    [lit] 2 cc-npick cc-sym-array-inner-of [lit] 0
    [lit] 4 cc-npick cc-sym-qualified cell[] @ cc-sysv-qualified-node
    nip ty-array [lit] 1 ty-make swap
  else,
    dup cc-sym-type-of 1+ swap
    dup cc-sym-qualified cell[] @ >r cc-expr-symbol-desc
    over ty-base ty-array = if, r@ cc-sysv-qualify-node then, r> drop
  then, [lit] 0 rot rot r> ;
: cc-om-const-string
  cc-sysv-object-mode @ 0= if, cc-const-unsupported then,
  cc-cx-skip @ if,
    begin, cc-next-token-keep tok-kind @ tk-str <> until,
    [lit] 0
  else, cc-om-string then,
  >r cc-putback-token [lit] 0 ty-char [lit] 1 ty-make [lit] 0 r> ;
\ An address operand carries an lvalue category separately from its type.
\ Parentheses preserve it; casts produce values. Arrow and subscripting may
\ consume a constant pointer value, but must never load a pointer object.
variable cc-const-qualified
variable cc-om-address-frame
: oa-value cc-om-address-frame @ ;
: oa-type cc-om-address-frame @ [lit] 8 + ;
: oa-desc cc-om-address-frame @ [lit] 16 + ;
: oa-record cc-om-address-frame @ [lit] 24 + ;
: oa-array cc-om-address-frame @ [lit] 32 + ;
: oa-inner cc-om-address-frame @ [lit] 40 + ;
: oa-lvalue cc-om-address-frame @ [lit] 48 + ;
: oa-qualified cc-om-address-frame @ [lit] 56 + ;
defer cc-om-address-cast-fwd
defer cc-om-address-unary-fwd
defer cc-om-address-index-fwd
' cc-const-unsupported is cc-om-address-cast-fwd
' cc-const-unsupported is cc-om-address-unary-fwd
' cc-const-unsupported is cc-om-address-index-fwd
: cc-om-address-value ( value type descriptor symbol -- )
  oa-record ! oa-desc ! oa-type ! oa-value !
  [lit] 0 oa-array ! [lit] 0 oa-inner ! [lit] 0 oa-lvalue !
  cc-const-qualified @ oa-qualified ! ;
: cc-om-address-ident
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup 0< if, cc-const-unsupported then,
  dup cc-sym-qualified cell[] @ oa-qualified !
  dup cc-sym-kind-of sk-func = if,
    dup cc-sysv-symbol-signature oa-desc ! cc-om-from-symbol oa-record !
    ty-func [lit] 0 ty-make oa-type !
  else,
    dup cc-sym-kind-of sk-global <> if, cc-const-unsupported then,
    dup cc-om-from-symbol oa-record ! dup cc-sym-type-of oa-type !
    dup cc-expr-symbol-desc oa-desc !
    dup cc-sym-array-len-of oa-array ! cc-sym-array-inner-of oa-inner !
  then,
  true oa-lvalue ! ;
: cc-om-address-array
  oa-array @ 0= oa-type @ ty-base ty-array = and
  oa-type @ ty-ptr 0= and if,
    oa-desc @ dup cc-ad-type oa-type !
    dup cc-ad-count oa-array ! dup cc-ad-inner oa-inner !
    cc-ad-desc oa-desc !
  then, ;
: cc-om-address-deref
  oa-lvalue @ oa-type @ ty-ptr 0= or if, cc-const-unsupported then,
  oa-type @ 1- oa-type ! true oa-lvalue !
  oa-type @ ty-base ty-array = oa-type @ ty-ptr 0= and if,
    oa-desc @ dup cc-ad-type oa-type !
    dup cc-ad-count oa-array ! dup cc-ad-inner oa-inner !
    cc-ad-desc oa-desc ! exit,
  then,
  oa-type @ ty-ptr 0= oa-type @ ty-base ty-void = and if,
    cc-const-unsupported
  then, ;
: cc-om-address-member
  oa-lvalue @ 0= oa-array @ or oa-type @ ty-ptr or if,
    cc-const-unsupported
  then,
  oa-type @ ty-base ty-struct <> oa-desc @ 0= or if,
    cc-const-unsupported
  then,
  cc-expect-ident
  tok-str-addr @ tok-str-len @ oa-desc @ cc-find-field oa-value +!
  cc-ff-result-record @ cc-field-qualified oa-qualified @ or oa-qualified !
  cc-ff-result-record @ cc-field-use-fwd
  cc-ff-result-type @ oa-type ! cc-ff-result-desc @ oa-desc !
  cc-ff-result-array @ oa-array !
  cc-ff-result-record @ cc-sf-array-inner oa-inner ! ;
: cc-om-address-index
  oa-array @ if,
    cc-om-address-index-fwd
    dup 0< over oa-array @ > or if, cc-const-unsupported then,
    oa-type @ oa-desc @ cc-nsize
    oa-inner @ if, oa-inner @ * then, * oa-value +!
    oa-inner @ oa-array ! [lit] 0 oa-inner ! cc-om-address-array
  else,
    oa-type @ oa-desc @ cc-expr-pointee-size >r
    cc-om-address-deref
    oa-type @ ty-ptr 0= oa-type @ ty-base ty-func = and if,
      cc-const-unsupported
    then,
    cc-om-address-index-fwd r> * oa-value +!
  then,
  [char] ] cc-expect-punct-c ;
: cc-om-address-operand
  cc-next-token-keep
  tok-kind @ tk-ident = if,
    cc-om-address-ident
  else,
    lparen cc-tok-punct? if,
      cc-next-token-keep
      cc-type-start? if,
        cc-parse-type-name
        cc-type-name-array @ if, cc-const-unsupported then,
        cc-type-name-qualified @ >r
        cc-cast-desc @ >r >r [char] ) cc-expect-punct-c
        r> r> cc-om-address-cast-fwd cc-om-address-value
        r> oa-qualified ! exit,
      then,
      cc-putback-token cc-om-address-operand [char] ) cc-expect-punct-c
    else,
      [char] * cc-tok-punct? if,
        cc-om-address-unary-fwd cc-om-address-value cc-om-address-deref exit,
      then,
      cc-const-unsupported
    then,
  then,
  begin,
    cc-next-token-keep
    [char] [ cc-tok-punct? if,
      cc-om-address-index
    else,
      [char] . cc-tok-punct? if,
        cc-om-address-member
      else,
        pt-arrow cc-tok-punct? if,
          cc-om-address-deref cc-om-address-member
        else, cc-putback-token exit, then,
      then,
    then,
  again, ;
: cc-om-const-address
  cc-sysv-object-mode @ 0= if, cc-const-unsupported then,
  cc-om-address-frame @ >r
  [lit] 64 cc-alloc dup cc-om-address-frame ! [lit] 64 cc-nzero
  cc-om-address-operand
  oa-lvalue @ 0= if, cc-const-unsupported then,
  oa-value @
  oa-array @ if,
    oa-type @ oa-desc @ oa-array @ oa-inner @ oa-qualified @
    cc-sysv-qualified-node
    ty-array [lit] 1 ty-make swap
  else, oa-type @ 1+ oa-desc @ then,
  oa-record @
  r> cc-om-address-frame ! ;
' cc-om-const-ident is cc-const-ident-fwd
' cc-om-const-address is cc-const-address-fwd
' cc-om-const-string is cc-const-string-fwd

: cc-om-finalize-storage ( record -- )
  dup om-kind @ cc-obj-object = over om-section @ 0= and if,
    dup om-flags @ [lit] 2 and if,
      cc-obj-bss cc-obj-use dup om-align @ cc-obj-align
      dup om-size @ cc-obj-reserve over om-offset ! cc-obj-bss over om-section !
    then,
  then, drop ;
: cc-om-export ( record -- )
  dup >r om-name @ r@ om-nlen @ r@ om-bind @ r@ om-kind @ cc-obj-default
  r@ om-section @ r@ om-offset @
  r@ om-section @ if, r@ om-size @ else, [lit] 0 then,
  cc-obj-symbol r> om-output ! ;
: cc-om-export-needed? ( record -- flag )
  dup om-section @ swap om-flags @ [lit] 16 and or ;
: cc-om-function-calls ( record -- )
  dup om-kind @ cc-obj-func <> if, drop exit, then,
  dup om-implicit @ dup if, [lit] 32 + @
  else, drop dup om-symbol @ cc-sym-call-fixups @ then,
  begin, dup while,
    cc-obj-text over @ cc-obj-plt32 [lit] 4 cc-npick [lit] 0 [lit] 4 - cc-om-reloc
    [lit] 8 + @
  repeat, 2drop ;
: cc-sysv-object-enable
  cc-sysv-enable true cc-sysv-object-mode !
  [lit] 0 cc-om-count ! [lit] 0 cc-om-relocations ! ;
: cc-sysv-object-program
  cc-obj-init cc-sysv-translation-unit
  cc-ni-head @ if, [lit] 238 cc-die then,
  cc-obj-text cc-obj-use cc-out-buf cc-out-pos @ cc-obj-bytes
  [lit] 1 begin, dup cc-om-count @ <= while,
    dup cc-om-finalize-storage dup cc-om-function-calls 1+
  repeat, drop
  [lit] 0 begin, dup cc-gfixup-count @ < while,
    cc-obj-text over cc-gfixup-out-pos cell[] @ cc-obj-r64
    [lit] 3 cc-npick cc-gfixup-slot cell[] @ [lit] 0 cc-om-reloc 1+
  repeat, drop
  [lit] 1 begin, dup cc-om-count @ <= while,
    dup cc-om-export-needed? if, dup cc-om-export then, 1+
  repeat, drop
  cc-om-relocations @ begin, dup while,
    dup [lit] 8 + @ over [lit] 16 + @ [lit] 2 cc-npick [lit] 24 + @
    [lit] 3 cc-npick [lit] 32 + @ om-output @ [lit] 4 cc-npick [lit] 40 + @
    cc-obj-reloc @
  repeat, drop ;
```

## 5. Compile an unchanged GCC source unit

GCC 4.0.4's `libiberty/ffs.c` is a useful first source boundary: it has no
headers, uses an identifier-list definition and a `register` parameter,
and returns the position of the first set bit. We compile the original
file from the pinned archive without changing its bytes. This is one
source unit from GCC, not evidence that the complete GCC compiler builds.

```sh
tests/gcc/sysv-gcc-ffs-check.sh
```

The gate requires the original source at its prepared path, or accepts
its path as an argument. It verifies the file's exact hash before parsing
it. Its first executable consists of the Forth-compiled GCC function, a
Forth-compiled comparison harness, the Forth-emitted startup object, and
the Forth linker. A second executable links the same Forth object into a
host-compiled harness as a separate interoperability oracle. Each runs
100,032 comparisons, including zero, signed inputs, and every single-bit
position. The upstream revision and archive hash remain in `gcc64/SOURCES`.

A second unchanged source unit exercises declarations and initialized data:

```sh
tests/gcc/sysv-gcc-hex-check.sh
```

This compiles GCC's original `libiberty/hex.c` together with its original
`libiberty.h`, `safe-ctype.h`, and `ansidecl.h`. Their exact hashes are checked,
and the runtime supplies its real standard headers. The resulting object
contains the complete 256-entry hexadecimal lookup table and `hex_init`.
A Forth-built/Forth-linked executable checks every entry and the original
header macros, including single evaluation of a side-effectful argument.
A separately host-built harness repeats the checks against the Forth
object. Unused floating declarations in the original header remain typed
metadata; they neither require fake ABI code nor become unresolved calls.

## Exercises

- **★** Draw the outgoing stack block for a call with eight integer arguments
- **★★** Add a boundary case where a nested call runs while a switch scrutinee is saved
- **★★★** Design the signature extension needed for System V aggregate classification

## Takeaways

- One tagged signature controls both sides of a scalar call
- A separate aligned outgoing block preserves arbitrary expression temporaries
- Explicit target selection keeps the existing private native ABI available

The object adapter connects these calls to the ELF symbols and relocations
introduced in Chapter 35.

## Ranked fixed-array descriptors

The original GCC induction-variable optimizer contains a local static
`unsigned costs[2][2][2][2]`. Two count cells cannot represent its row types.
In direct System V mode, further dimensions therefore become recursive
`ty-array` element descriptors. Each descriptor retains a positive count, its
element type and descriptor, checked byte size and actual element alignment.
Pointer-to-array construction normalizes two-dimensional count metadata into
the same single-dimension nodes, so spelling does not change type identity.

Indexing consumes one real dimension at a time. Array `sizeof`, static address
addends and recursive initializer descent follow those same element types.
Record ABI classification descends to the leaf, preserving unsupported
floating-member rejection and integer-record transport.

A qualified array decays like any other (C90 6.2.2.1): the qualifier moves
onto the pointed-to type. Scalar element types carry no qualifier bits, so a
decay to `const T *` keeps only the expression's `cc-last-expr-qualified`
provenance, exactly as an ordinary `const T *` variable does. A row, however,
is an array node, and the node's last cell, `cc-ad-qualified`, records the
set of qualifiers on its elements: bits for `const`, `volatile` and
`restrict` from Ch 29's `cc-qualifier-bit`, which the declaration parser's
qualifier notes, `cc-prefix-qualified` and field qualification (Ch 24) all
carry instead of a yes/no flag. `cc-sysv-array-decay` gives a qualified matrix a
qualified row node; `cc-sysv-array-address` does the same for `&a`, and a
ranked array's existing element node is replaced by a qualified copy
(`cc-sysv-qualify-node`), since typedefs and declarations share nodes.
Declared array pointers take the base type's qualifiers (`nc-base-qualified`):
`const long (*p)[3]` points at qualified rows, `long (*const p)[3]` does not.
Static address constants, parameters adjusted from `const long a[2][3]`, and
abstract type names such as `(const long (*)[3])` build their nodes the same
way, and a conditional's result row is qualified when either arm's is.

Implicit conversion may add that qualifier but never discard it.
`cc-sysv-row-qualifier-check`, run by `cc-sysv-value-shape` for initializers,
assignments, arguments and returns, rejects `long (*p)[3] = t` for a
`const long t[2][3]` with 238; an explicit cast or a qualified destination
accepts. This covers binutils' elflink.c, which reads
`&((const Elf32_External_Rel *) p)->r_offset`, and zlib's
`(const z_crc_t FAR *)crc_table`. Because the cell is a set, a `const`
row converts implicitly to a `const volatile` row but not to a `volatile`
one (238), and `cc-sysv-same-types` makes redeclarations and prototypes
compare sets exactly: `extern const long (*p)[3]; extern volatile long
(*p)[3];` is 237. Below the first pointer the sets must be equal, as
C90 6.3.16.1 requires compatible pointed-to types, so
`const long (**q)[3] = &p` for `long (*p)[3]` is 237. Like GCC without
`-pedantic`, this target lets the first level add a qualifier to an array
row; strict C90 counts that as an incompatible conversion too, since the
qualifier belongs to the element type, not to the pointed-to array.

Element pointers follow the existing
scalar policy: `char *q = a` from a `const char a[3]`, or a store through it,
is not diagnosed, because nothing records whether a scalar pointer's pointee
or the pointer itself is qualified.

The direct profile checks a maximum of 64 written suffixes and a total rank of
64 after typedef composition. It also checks the existing 1 GiB complete-object
limit before multiplying. Rank 65, invalid positive bounds and oversized
products fail before output publication. The legacy/native parser keeps its
previous suffix boundary. See `tests/gcc/ranked-arrays-README.md` and its executable test for the original
source witness, mixed ABI checks, and declaration-only boundary proofs.
