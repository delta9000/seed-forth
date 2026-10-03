# 42. Variadic lists across the System V boundary

## Goal

Compile INTEGER and binary64 variadic retrieval with the same list
representation used by other AMD64 System V compilers. The production proof compiles separate
C objects and constructs their executable with Forth. Host GCC and libc are
used only by a separate interoperability test.

**Source coverage:** `126-cc-varargs.fth`, with its canonical source below.
The public declarations live in `runtime/gcc-seed/include/stdarg.h`.

**Concepts carried in:** nominal aggregate descriptors and local storage from
[chapter 34](34-direct-tinycc.md), signatures and GP argument registers from
[chapter 36](36-direct-gcc-calls.md), and separate-object reconstruction from
[chapter 37](37-direct-gcc-linker.md).

**Concepts introduced:** array typedef identity, per-invocation register-save
areas, variadic cursors, checked compiler intrinsics, and list copying.

**Deferred:** floating call arguments and named parameters, float and
long-double retrieval, aggregate argument values, vector types, and a complete
GCC reconstruction. Binary64 expressions and returns use the value machinery
in [chapter 45](45-direct-gcc-binary64.md); incoming binary64 retrieval here
does not implement floating argument classification for calls.

## 1. The list is an array of one record

A System V `va_list` occupies 24 bytes. Its first two fields are four-byte
unsigned offsets, `gp_offset` and `fp_offset`. Two eight-byte pointers follow:
`overflow_arg_area` and `reg_save_area`. The public type is an array of one
record. A local list therefore needs all 24 bytes, while a parameter declared
`va_list` adjusts to a pointer to that record. Passing a list to another
function lets that function advance the original cursor.

These properties must survive `typedef` aliases. A pointer typedef would
allocate only eight bytes and change `sizeof`; dropping the array shape would
pass an aggregate value instead of the required pointer. Chapter 36's type
queries preserve the bounded array shape through aliases and distinguish
object declarations from adjusted parameter declarations.

The header names a reserved record tag. Each intrinsic checks the nominal tag
identity, pointer depth, complete record size, alignment, scalar field types,
and offsets before it emits a memory access. A different record with similar
field names is not accepted as a list. Type-name array metadata also prevents
`va_arg(list, va_list)` from quietly becoming a scalar access.

## 2. Save incoming registers before using them

For the supported INTEGER class, the first six arguments arrive in RDI, RSI,
RDX, RCX, R8, and R9. Remaining arguments are eight-byte stack slots. The
callee reserves 22 eight-byte local slots after its named parameters. Their
first 48 bytes save these six registers before the ordinary parameter-copy
code can overwrite RDI. Eight consecutive 16-byte slots then save XMM0 through
XMM7, giving the register-save area 176 bytes. All offsets increase with the
memory address, even though our local slot numbers increase downward. An
extra padding slot, when needed, keeps the area 16-byte aligned without
changing the named-parameter slots.

The reservation belongs to the callee's ordinary frame. Recursion and calls
back through a function pointer create independent copies. No global runtime
buffer stores arguments. The compiler's `cc-va-signature` is compile-time
metadata; it captures the definition's signature even when a block-scope
function declaration later changes other parser state.

If a function has `n` named INTEGER arguments, `va_start` sets `gp_offset` to
`min(n,6)*8`. The first unnamed stack argument is at
`rbp + 16 + max(n-6,0)*8`: eight bytes account for the saved frame pointer and
eight for the return address. `reg_save_area` addresses the saved RDI slot.
`fp_offset` is initialized to 48, the start of the saved XMM region. This is
the register layout specified by the [AMD64 System V ABI](https://gitlab.com/x86-psABIs/x86-64-ABI/-/blob/master/x86-64-ABI/low-level-sys-info.tex).

Each XMM store uses `movups` to copy all 128 bits without interpreting them
as floating values. The allocator also preserves 16-byte save-area alignment
for host consumers. We save all
eight registers unconditionally, so every permitted incoming AL value from
zero through eight works, including an upper bound larger than the number
of actual vector arguments. No AL-dependent branch or runtime trap is needed.

The resulting list can be passed to a host consumer that knows its argument
types. That consumer can retrieve incoming doubles from the XMM slots and
use the unchanged overflow pointer for arguments passed on the stack. This
also lets an integer-only callee ignore unused floating arguments. It does
not make the Forth compiler classify or emit floating call arguments: all
named parameters must still use the supported INTEGER class. Its own
`va_arg` now retrieves binary64 values as well as the integer and pointer types
described below; a caller and consumer must still agree on every argument type.

## 3. Four intrinsics with ordinary C spelling

The header maps `va_start`, `va_arg`, `va_copy`, and `va_end` to reserved
compiler intrinsics. It also supplies `__gnuc_va_list` and `__va_copy` for
existing GNU-oriented C source. Each list expression is evaluated once.

`va_start` requires a variadic definition and its actual last named parameter.
Changing that parameter's value does not affect cursor initialization. A
subsequent `va_start` after `va_end` resets the same list from the current
invocation's saved registers and incoming stack slots.

`va_arg` tests whether `gp_offset` is below 48. If so, it chooses
`reg_save_area + gp_offset` and advances the offset by eight. Otherwise it
uses `overflow_arg_area` and advances that pointer by eight. The requested
value is then loaded with its declared signedness and width. Four-byte `int`
and `unsigned int` therefore do not expose the unused upper half of a GP slot.
Pointers and the LP64 long types use all eight bytes.

For `double`, we instead test whether `fp_offset` is below 176. A register
value uses `reg_save_area + fp_offset`, then advances only `fp_offset` by 16.
The low eight bytes of that XMM save slot hold the binary64 payload; its upper
eight bytes are not another argument. After all eight XMM slots are consumed,
the same overflow pointer supplies an eight-byte stack value and advances by
eight. The 176 comparison uses a full immediate, avoiding the signed imm8
encoding that would compare against a negative value.

GP and XMM exhaustion are independent. A GP access never advances the FP
cursor, and a double access never advances the GP cursor. Both classes share
the overflow cursor in argument order once their own register bank is full.
A System V stack double needs eight-byte alignment, already guaranteed by the
incoming stack area and every supported overflow access. This does not claim
the sixteen-byte alignment or special classification needed by long double.
The existing typed load carries the double bits in RDI for chapter 45 to
store, compute with, cast, discard, or return through XMM0.

The caller already applies default promotions to unnamed arguments. Reading
an `int` is appropriate for promoted `char` and `short` values; asking
`va_arg` for either narrow type is rejected. Unnamed `float` is promoted to
`double` by a conforming caller; `va_arg(list, float)` therefore stays rejected.
Long-double and aggregate requests also fail rather than consuming a slot
under the wrong ABI. Opaque forwarding can still leave those operations to
a host consumer.

`va_copy` copies the entire three-word record, producing an independent cursor
that shares the immutable saved arguments. `va_end` evaluates and checks its
operand; no runtime resource needs releasing on this target. As in C, using
an ended list or a list whose owning invocation has returned is outside its
valid lifetime. This implementation does not attempt runtime detection of
those invalid programs.

## 4. Keep diagnostics and proofs specific

The intrinsic layer prefixes its diagnostics with `varargs:`. Error 246 means
an invalid list, invocation, named-parameter reference, or start context.
Error 247 means an unsupported requested result type. The numbers overlap
errors in other bounded compiler components, so the prefix identifies the
phase. Unsupported floating types can be named, so `va_arg(list, float)` and
`va_arg(list, long double)` reach the intrinsic's error 247. Binary64 retrieval
is accepted. The negative checks require exit status 247, exactly one
`varargs: cc: line N: error 247`
diagnostic, empty stdout, and preservation of an existing output file.
Pointers to floating objects still belong to the INTEGER class and can be
retrieved without loading a floating value.

`varargs-intrinsic-check.sh` isolates lowering with a direct declaration of
the genuine record array. Its copied list expression also calls a function,
checking that temporary cursor addresses survive calls.

`varargs-check.py` builds the provider and caller as separate Forth-compiled
objects, adds Forth-generated process entry, and links with the Forth linker.
Its cases cross both register and stack boundaries, use five, six, and seven
named parameters, preserve signed and unsigned values, copy active cursors,
restart lists, recurse, and forward lists through callbacks. Negative cases
also verify the exact diagnostic shape and that a failed compilation leaves
an existing output intact. The report records source and artifact hashes.

`varargs-interop-check.sh` compiles the same provider with Forth and uses GCC
at `-O0` and `-O2` for the other side. It checks both directions of variadic
calls and list forwarding, then gives a Forth-initialized list to the host's
`vsnprintf`. Its separate forwarding fixture never evaluates a floating C
expression: host callers supply floating arguments, and host consumers read
them from the forwarded lists. The oracle covers ignored floating extras,
every AL count from zero through eight, ten doubles overflowing the XMM
registers, interleaved GP overflow, seven named parameters, stack-aligned
`long double`, recursive reentry, and copies retained across intervening
calls. A host assembly fixture supplies AL=8 with only a GP argument, checking
the permitted upper-bound case. The formatter comparison mixes ten doubles,
ten longs, and a long double, comparing both bytes and return length. None of
those host-built objects enters the production proof.

`varargs-binary64-check.py` independently calls Forth-built typed consumers at
host `-O0` and `-O2`. It checks interleaved banks and both exhaustion orders,
twelve doubles, stack-passed named parameters, host-initialized lists with
named floating arguments, copied cursors before and after overflow, list
restart, and nested callbacks. Signed zero, infinities, a NaN payload and a
subnormal are compared as bits. It also verifies the existing XMM0 result
ABI and checked rejection of floating call arguments.

`varargs-vasprintf-check.py` compiles the unmodified GCC 4.0.4
`libiberty/vasprintf.c` with the original configured headers. Its sizing pass
contains `(void) va_arg(ap, double)` even for integer/string-only uses;
accepting that actual source is the motivating dependency. A separate-object
executable uses the Forth-built `abs`, `strtoul`, allocation, string and
`vsprintf` implementations. The exercised formats cover integer/string
generator messages, constant and star widths/precisions, copied lists and GP
overflow. Original-source and Forth-object host executions are separate
oracles. Floating formatting remains unsupported by this bounded runtime;
compiling the sizing branch does not imply implementing `%f` output.

## Canonical source

```forth file=126-cc-varargs.fth
\ 126-cc-varargs.fth — INTEGER/binary64 System V AMD64 variadic callees.
\ va_list is the real 24-byte record array[1], declared by stdarg.h.
\ Six GP and eight XMM slots belong to each invocation below named parameters.
\ Binary64 retrieval consumes XMM or overflow slots; named FP parameters remain unsupported.
create cc-va-error-prefix s, varargs: bl c,
: cc-va-die cc-va-error-prefix [lit] 9 cc-err-write cc-die ;

variable cc-va-signature
variable cc-va-register-slot

: cc-va-prepare ( signature -- )
  dup cc-va-signature !
  cc-sysv-sig-varargs [lit] 1 and if,
    cc-fn-local-count @ [lit] 1 and if, [lit] 1 cc-fn-add-slots then,
    cc-fn-local-count @ [lit] 21 + cc-va-register-slot !
    [lit] 22 cc-fn-add-slots
  then, ;
: cc-va-save-xmm ( index -- )
  [lit] 15 cc-emit-byte [lit] 17 cc-emit-byte
  dup [lit] 8 * [lit] 133 + cc-emit-byte \ movups [rbp+disp32], xmmN
  [lit] 16 * [lit] 48 +
  cc-va-register-slot @ 1+ [lit] 8 * - cc-emit-4le ;
: cc-va-save-registers
  cc-va-signature @ cc-sysv-sig-varargs [lit] 1 and if,
    cc-va-register-slot @ dup cc-emit-store-local
    1- dup cc-emit-store-local-from-rsi
    1- dup cc-emit-store-local-from-rdx
    1- dup cc-emit-store-local-from-rcx
    1- dup cc-emit-store-local-from-r8
    1- cc-emit-store-local-from-r9
    [lit] 0 begin, dup [lit] 8 < while,
      dup cc-va-save-xmm 1+
    repeat, drop
  then, ;

create cc-va-tag-name s, __seed_va_list_tag
: cc-va-field ( descriptor index offset type -- )
  >r >r cc-sd-field-rec
  dup cc-sf-offset r> <> if, [lit] 246 cc-va-die then,
  dup cc-sf-type r> <> if, [lit] 246 cc-va-die then,
  cc-sf-array-len if, [lit] 246 cc-va-die then, ;
: cc-va-descriptor ( -- descriptor )
  cc-va-tag-name [lit] 18 cc-nfind-tag
  dup 0< if, [lit] 246 cc-va-die then, cc-sym-val-of
  dup cc-sd-total-size [lit] 24 <> if, [lit] 246 cc-va-die then,
  dup cc-sd-align [lit] 8 <> if, [lit] 246 cc-va-die then,
  dup cc-sd-field-count [lit] 4 <> if, [lit] 246 cc-va-die then,
  dup cc-sd-union? if, [lit] 246 cc-va-die then,
  dup [lit] 0 [lit] 0 ty-uint [lit] 0 ty-make cc-va-field
  dup [lit] 1 [lit] 4 ty-uint [lit] 0 ty-make cc-va-field
  dup [lit] 2 [lit] 8 ty-void [lit] 1 ty-make cc-va-field
  dup [lit] 3 [lit] 16 ty-void [lit] 1 ty-make cc-va-field ;
: cc-va-expect ( punctuation -- )
  cc-next-token-keep cc-tok-punct? 0= if, [lit] 246 cc-va-die then, ;
: cc-va-operand
  cc-parse-assign-fwd
  cc-last-expr-type @ ty-struct [lit] 1 ty-make <> if,
    [lit] 246 cc-va-die
  then,
  cc-last-struct-desc @ cc-va-descriptor <> if, [lit] 246 cc-va-die then,
  cc-last-expr-array-inner @ if, [lit] 246 cc-va-die then,
  cc-emit-materialize ;
: cc-va-void-result
  [lit] 0 cc-emit-mov-rdi-int
  ty-void [lit] 0 ty-make [lit] 0 cc-mark-typed-value ;

\ rdi addresses the list. These helpers do not move that address.
: cc-va-store-u32 ( value displacement -- )
  [lit] 199 cc-emit-byte
  dup if, [lit] 71 cc-emit-byte cc-emit-byte
  else, drop [lit] 7 cc-emit-byte then,
  cc-emit-4le ;
: cc-va-store-frame-address ( frame-offset list-offset -- )
  >r [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte
  [lit] 133 cc-emit-byte cc-emit-4le       \ lea rax, [rbp+disp32]
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 71 cc-emit-byte r> cc-emit-byte ; \ mov [rdi+disp8], rax
: cc-va-last-named
  cc-va-signature @ dup 0= if, [lit] 246 cc-va-die then,
  dup cc-sysv-sig-varargs [lit] 1 and 0= if, [lit] 246 cc-va-die then,
  dup cc-sysv-sig-count 1- cc-sysv-sig-name
  cc-next-token-keep
  tok-kind @ tk-ident <> if, [lit] 246 cc-va-die then,
  dup [lit] 8 + @ tok-str-len @ <> if, [lit] 246 cc-va-die then,
  @ tok-str-addr @ tok-str-len @ bytes-eq 0= if, [lit] 246 cc-va-die then,
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup 0< if, [lit] 246 cc-va-die then,
  dup cc-sym-kind-of sk-local <> if, [lit] 246 cc-va-die then,
  cc-sym-val-of cc-va-signature @ cc-sysv-sig-count <> if,
    [lit] 246 cc-va-die
  then, ;
: cc-va-start
  cc-va-operand [char] , cc-va-expect
  cc-va-last-named [char] ) cc-va-expect
  cc-va-signature @ cc-sysv-sig-count dup [lit] 6 > if,
    drop [lit] 6
  then, [lit] 8 * [lit] 0 cc-va-store-u32
  [lit] 48 [lit] 4 cc-va-store-u32
  cc-va-signature @ cc-sysv-sig-count cc-sysv-stack-count
  [lit] 8 * [lit] 16 + [lit] 8 cc-va-store-frame-address
  [lit] 0 cc-va-register-slot @ 1+ [lit] 8 * -
  [lit] 16 cc-va-store-frame-address
  cc-va-void-result ;

\ Choose the next eight-byte INTEGER slot, updating only that list's cursor.
\ The caller then loads the requested four- or eight-byte value from rdi.
: cc-va-next-address
  [lit] 139 cc-emit-byte [lit] 7 cc-emit-byte         \ mov eax, [rdi]
  [lit] 131 cc-emit-byte [lit] 248 cc-emit-byte [lit] 48 cc-emit-byte
  [lit] 15 cc-emit-byte [lit] 131 cc-emit-byte        \ jae overflow
  cc-out-pos @ [lit] 0 cc-emit-4le >r
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 79 cc-emit-byte [lit] 16 cc-emit-byte         \ mov rcx, [rdi+16]
  [lit] 72 cc-emit-byte [lit] 1 cc-emit-byte [lit] 193 cc-emit-byte
  [lit] 131 cc-emit-byte [lit] 7 cc-emit-byte [lit] 8 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 207 cc-emit-byte
  cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 71 cc-emit-byte [lit] 8 cc-emit-byte          \ mov rax, [rdi+8]
  [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 8 cc-emit-byte          \ lea rcx, [rax+8]
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 79 cc-emit-byte [lit] 8 cc-emit-byte          \ mov [rdi+8], rcx
  cc-emit-mov-rdi-rax r> cc-patch-rel32-to-here ;
\ Choose the next SSE slot for double, preserving gp_offset. Only the low
\ eight bytes of each sixteen-byte XMM save slot are the binary64 payload.
\ A stack double requires eight-byte alignment, already maintained by every
\ supported INTEGER/double overflow access and the incoming ABI stack area.
: cc-va-next-double-address
  [lit] 139 cc-emit-byte [lit] 71 cc-emit-byte [lit] 4 cc-emit-byte
  [lit] 61 cc-emit-byte [lit] 176 cc-emit-4le        \ cmp eax, 176
  [lit] 15 cc-emit-byte [lit] 131 cc-emit-byte        \ jae overflow
  cc-out-pos @ [lit] 0 cc-emit-4le >r
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 79 cc-emit-byte [lit] 16 cc-emit-byte         \ mov rcx, [rdi+16]
  [lit] 72 cc-emit-byte [lit] 1 cc-emit-byte [lit] 193 cc-emit-byte
  [lit] 131 cc-emit-byte [lit] 71 cc-emit-byte
  [lit] 4 cc-emit-byte [lit] 16 cc-emit-byte         \ add dword [rdi+4],16
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 207 cc-emit-byte
  cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 71 cc-emit-byte [lit] 8 cc-emit-byte          \ mov rax, [rdi+8]
  [lit] 72 cc-emit-byte [lit] 141 cc-emit-byte
  [lit] 72 cc-emit-byte [lit] 8 cc-emit-byte          \ lea rcx, [rax+8]
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 79 cc-emit-byte [lit] 8 cc-emit-byte          \ mov [rdi+8], rcx
  cc-emit-mov-rdi-rax r> cc-patch-rel32-to-here ;
: cc-va-check-result-type ( type -- )
  dup [lit] 256 / [lit] 255 and if, [lit] 247 cc-va-die then,
  dup ty-ptr if, drop exit, then,
  ty-base dup ty-int = over ty-uint = or
  over ty-long = or over ty-ulong = or swap ty-double = or 0= if, [lit] 247 cc-va-die then, ;
: cc-va-arg
  cc-va-operand [char] , cc-va-expect
  cc-next-token-keep cc-native-type-name-fwd
  cc-type-name-array @ cc-type-name-inner @ or if, [lit] 247 cc-va-die then,
  dup cc-va-check-result-type cc-cast-desc @ >r >r
  [char] ) cc-va-expect
  r@ ty-double [lit] 0 ty-make = if,
    cc-va-next-double-address
  else, cc-va-next-address then,
  r@ cc-emit-load-typed-via-rdi
  r> r> cc-mark-typed-value ;
: cc-va-copy-word ( displacement -- )
  [lit] 72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit] 71 cc-emit-byte dup cc-emit-byte             \ mov rax, [rdi+disp8]
  [lit] 72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 65 cc-emit-byte cc-emit-byte ;               \ mov [rcx+disp8], rax
: cc-va-copy
  cc-va-operand cc-emit-push-rdi [char] , cc-va-expect
  cc-va-operand [char] ) cc-va-expect cc-emit-pop-rcx
  [lit] 0 cc-va-copy-word [lit] 8 cc-va-copy-word [lit] 16 cc-va-copy-word
  cc-va-void-result ;
: cc-va-end
  cc-va-operand [char] ) cc-va-expect cc-va-void-result ;

create cc-va-start-name s, __builtin_va_start
create cc-va-arg-name s, __builtin_va_arg
create cc-va-copy-name s, __builtin_va_copy
create cc-va-end-name s, __builtin_va_end
: cc-va-name? ( name length -- flag )
  dup tok-str-len @ <> if, 2drop [lit] 0 exit, then,
  tok-str-addr @ swap bytes-eq ;
: cc-va-intrinsic ( -- handled? )
  cc-target-sysv @ 0= if, [lit] 0 exit, then,
  cc-va-start-name [lit] 18 cc-va-name? if, [lit] 1 else,
  cc-va-arg-name [lit] 16 cc-va-name? if, [lit] 2 else,
  cc-va-copy-name [lit] 17 cc-va-name? if, [lit] 3 else,
  cc-va-end-name [lit] 16 cc-va-name? if, [lit] 4 else,
    [lit] 0 exit,
  then, then, then, then,
  cc-check-static-init lparen cc-va-expect
  dup [lit] 1 = if, drop cc-va-start else,
  dup [lit] 2 = if, drop cc-va-arg else,
  [lit] 3 = if, cc-va-copy else, cc-va-end then, then, then,
  true ;
' cc-va-prepare is cc-sysv-varargs-prepare-fwd
' cc-va-save-registers is cc-sysv-varargs-save-fwd
' cc-va-intrinsic is cc-native-intrinsic-fwd
```

## Try it

The production command needs the seed executable and the project sources:

```sh
python3 tests/gcc/varargs-check.py
```

When host GCC and libc are available, run their independent oracle:

```sh
bash tests/gcc/varargs-interop-check.sh
```

## Exercises

- **★** Trace `gp_offset` through five and then six unnamed integer arguments
  after one named parameter
- **★★** Add a test that copies a cursor after it has entered the overflow area
- **★★★** Explain why sharing the overflow cursor still works when twelve
  integers are followed by twelve doubles, then reverse their order

## Takeaways

- The array typedef and the 24-byte record are both observable parts of the ABI
- Register saves and cursor state belong to each active invocation
- Typed binary64 retrieval and opaque list forwarding have distinct proofs;
  neither implements floating call arguments or runtime floating formatting

The next runtime component can consume these lists through ordinary C headers.
