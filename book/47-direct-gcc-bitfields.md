# Chapter 47 — Integer record bitfields

## Goal and source coverage

You can compile the original GCC 4.0.4 Fibonacci heap implementation,
including its packed degree and mark fields, and execute its heap operations
with the Forth compiler, linker, and runtime. `129-cc-bitfield.fth` supplies
this target-specific capability. The shared descriptor, expression, member,
and initializer interfaces remain in Chapters 24, 27–28, 34, and 36.

Concepts carried in: scalar loads and stores, aggregate descriptors, integer
promotions, typed conversion, and static object patches. Concepts introduced:
a bit cursor, allocation-unit containment, signed extraction, and preservation
of neighboring bits. Deferred: enum, char, and short bitfields; packed-layout
attributes; extended-precision long bitfields; and atomic operations.

## 1. Start with the actual source requirement

The pinned `include/fibheap.h` declares an unsigned 31-bit degree and a
one-bit mark. Its configured C path uses unsigned int; another branch uses
unsigned long. `include/obstack.h` has three adjacent one-bit unsigned flags.
The configured `ENUM_BITFIELD` macro in GCC's `system.h` expands to unsigned
int for this compiler. `rtl.h` and `tree.h` add widths such as 2, 7, 8, 9,
16, and 30. None of these inputs is rewritten to ordinary integer fields.

Supported underlying types are int, unsigned int, long, and unsigned long,
including typedef aliases. Int fields accept widths 1–32. Long fields accept
widths 1–32 and 64. An unnamed zero-width declaration is also supported.
Long widths 33–63 are rejected: GCC gives those fields extended-precision
expression types, and using a plain 64-bit expression would silently change
some promotions and comparisons.

Enum provenance survives typedefs so an enum bitfield cannot accidentally
acquire signed-int semantics. Ordinary enum scalar storage is unchanged.
Named zero-width declarations, negative or oversized widths, unsupported base
types, pointers, and arrays are also errors. The `bitfield:` diagnostic prefix
distinguishes these error-248 failures from object-writer failures using the
same numeric exit code.

## 2. Allocate bits without changing the old targets

Descriptor-size hooks retain the legacy 16-byte header with 40-byte field
records and native LP64's 32-byte header with 48-byte records. Only explicit
SysV mode uses a 40-byte header and 72-byte records. Header offset 32 records
the next bit position. Field offsets 48 and 56 hold width and shift; zero
width in a stored record means an ordinary member. Anonymous aggregate
promotion copies the complete target-selected record, including this metadata.
The final cell at offset 64 retains an ordinary field's inner array bound;
zero means the field has no second dimension. The legacy/native accessor
returns zero and its setter still rejects a nonzero inner bound with error 213.

The underlying type selects a naturally aligned four- or eight-byte unit.
A field starts at the next available bit unless its width would cross that
unit's boundary, when the cursor advances to the next boundary. The field's
byte offset identifies the unit start; its shift counts from the least
significant bit. This is the AMD64 little-endian layout tested by the oracle.

Named fields raise aggregate alignment to the underlying type's alignment.
Unnamed fields consume bits but are absent from the member and initializer
list. A zero-width declaration advances to the underlying-type boundary
without raising aggregate alignment. Ordinary members resume at the next byte
with their usual alignment. Union members start at zero and contribute to the
maximum size. The aggregate parser rounds final size to aggregate alignment.

Two-dimensional inline arrays use the same element type and descriptor as
ordinary array fields, with both fixed bounds retained. Member expressions
carry those bounds into subscripting and `sizeof`: the first subscript scales
by one complete row and the second by one element. Direct subscripting keeps
qualification provenance without constructing a pointer-to-row. Qualified
array-pointer decay and address construction remain conservative errors;
this does not implement full C qualifier semantics. The initializer recursively
visits each row, including row strings and padded record elements. Static
addresses preserve both bounds and use actual ELF relocation addends.

The direct target checks each array product against its one-GiB object limit.
It also checks the enclosing record sum and tail alignment after each ordinary field
or bitfield, so individually valid fields cannot overflow the combined layout.
An incomplete outer matrix bound and dimensions beyond two remain unsupported.
Static member-array initializers use explicit addresses; implicit member-array
decay and extra nested braces around flattened anonymous aggregates retain their
existing rejection boundary.
The native/TinyCC profile still rejects multidimensional fields. The focused
matrix proof (`tests/gcc/multidimensional-record-README.md`) exercises both
host/Forth ABI directions, rejected inputs, and the original GCC `optabs.h`
declarations that first required this representation.


## 3. Preserve lvalue identity and neighboring bits

A field expression holds its address in RDI, with its field-record pointer
beside the existing lvalue metadata. Reading selects one unit load, shifts,
and masks or sign-extends the field. Assignment snapshots the field record
across recursive right-side parsing, performs the existing typed conversion,
then truncates to the field width. Prefix and postfix changes use the same
load/store seam. Postfix retains the old value; prefix and assignment produce
the stored value.

Narrow fields promote to int. Signed 32-bit long fields also promote to int;
unsigned 32-bit long fields promote to unsigned int. Full-width long fields
keep their long type. Materializing the right operand before choosing a
binary operator's common type applies promotion on both sides. Enabled
binary64 conversions reuse the scalar conversion hooks.

A preserving store reads the unit, clears only the destination mask, merges
the shifted new bits, and writes the unit. Other fields, ordinary members,
and padding retain their bits. The contract is ordinary, non-atomic memory
access. Volatile fields use the same unit loads and preserving stores. A
compound update can perform an operand load followed by the preserving
store's additional load. No atomicity or inter-thread synchronization is
promised. Address-of and sizeof on a bitfield are rejected, including the
separate static constant-address path.

## 4. Verify initialization and a real consumer

Brace traversal consumes only named members. Automatic initialization uses
the preserving store. Static object initialization evaluates an integer
constant and merges it into reserved bytes, preserving earlier members in
the same unit; it does not emit executable initialization into an ELF object.

`tests/gcc/bitfield-check.py` checks rejection without replacing existing output,
verifies original source/header hashes, compiles unchanged `libiberty/fibheap.c`,
and links it with a Forth-built entry and runtime. The harness inserts 144
nodes, unions two heaps, forces consolidation, decreases keys, deletes nodes,
and checks each extraction against an independent key model. The remaining
ordered extraction count is 131. Its small xcalloc adapter delegates to the
actual runtime calloc.

The optional host oracle consumes only Forth-produced test objects. O0 and
O2 check record and union bytes, mixed underlying types, zero-width alignment,
anonymous members, 5000 mutations, preservation of neighboring bytes, signed
reads, both operand positions, prefix/postfix results, static and automatic
braces, and enabled binary64 conversions. The original heap object also runs
against the host runtime as an interoperability check. Host C provides no
production artifact.

This is one bounded original GCC component proof. Obstack passes its field
declarations, but its full implementation also needs function-pointer casts.
The chapter does not claim a complete GCC bootstrap or C bitfield dialect.

## Try it

After placing the pinned GCC tree at
`build-out/direct-gcc-inputs/gcc-source`, run:

```sh
python3 tests/gcc/bitfield-check.py
python3 tests/gcc/bitfield-check.py --oracle
```

To use unchanged libiberty configure output, add
`--config-dir /path/to/build/libiberty`. The retained report records the
configuration hash and exact compile command. Host C runs only with `--oracle`.

## Canonical source

```forth file=129-cc-bitfield.fth
\ 129-cc-bitfield.fth -- AMD64 little-endian integer record bitfields.
\ Only the explicit SysV target changes descriptor or member semantics.
\ Named int/unsigned/long/unsigned long fields use their natural 4/8-byte
\ allocation units. Stores preserve every bit outside the destination.
\ Volatile accesses use ordinary unit loads and RMW stores; no atomicity
\ or inter-thread synchronization is provided, and compound updates can
\ perform an operand load plus the preserving RMW load.
create cc-bf-error-prefix s, bitfield: bl c,
: cc-bf-die cc-bf-error-prefix [lit] 10 cc-err-write [lit] 248 cc-die ;
: cc-bf-header-bytes
  cc-target-sysv @ if, [lit] 40 else, cc-sd-header-bytes-default then, ;
: cc-bf-record-bytes
  cc-target-sysv @ if, [lit] 72 else, cc-sd-record-bytes-default then, ;
' cc-bf-header-bytes is cc-sd-header-bytes
' cc-bf-record-bytes is cc-sd-record-bytes

\ The final SysV field cell retains the second fixed array dimension.
\ Bitfield slots stay at48/56; anonymous promotion copies the entire record.
: cc-bf-array-inner ( rec -- n )
  cc-target-sysv @ if, [lit] 64 + @ else, cc-sf-array-inner-default then, ;
: cc-bf-set-array-inner ( n rec -- )
  cc-target-sysv @ if, [lit] 64 + ! else, cc-sf-set-array-inner-default then, ;
' cc-bf-array-inner is cc-sf-array-inner
' cc-bf-set-array-inner is cc-sf-set-array-inner

: cc-sd-bit-end [lit] 32 + ;
: cc-sf-bit-width [lit] 48 + @ ;
: cc-sf-bit-shift [lit] 56 + @ ;
: cc-bf? ( rec -- flag )
  cc-target-sysv @ over [lit] 0 <> and if, cc-sf-bit-width else, drop [lit] 0 then, ;
\ Enum representation is a separate capability. Preserve provenance through
\ typedefs so enum fields cannot silently acquire signed-int bit semantics.
create cc-bf-enum-origin [lit] 0 ,
: cc-bf-enum-desc
  cc-target-sysv @ if, cc-bf-enum-origin else, [lit] 0 then, ;
' cc-bf-enum-desc is cc-nenum-desc-fwd

: cc-bf-type? ( ty -- flag )
  dup ty-ptr if, drop [lit] 0 exit, then,
  ty-base dup ty-int = over ty-uint = or over ty-long = or swap ty-ulong = or ;

variable cc-bf-desc
variable cc-bf-width
variable cc-bf-unit
variable cc-bf-position
variable cc-bf-record
: cc-bf-add ( desc -- )
  cc-bf-desc !
  nc-desc @ cc-bf-enum-origin = if, cc-bf-die then,
  nc-ty @ cc-bf-type? 0= nc-array @ [lit] 0 <> or
  nc-inner @ [lit] 0 <> or nc-func @ [lit] 0 <> or if, cc-bf-die then,
  cc-parse-const cc-bf-width !
  nc-ty @ ty-size [lit] 8 * cc-bf-unit !
  cc-bf-width @ [lit] 0 < cc-bf-width @ cc-bf-unit @ > or if, cc-bf-die then,
  cc-bf-width @ [lit] 32 > cc-bf-width @ [lit] 64 < and if, cc-bf-die then,
  cc-bf-width @ 0= nc-nlen @ [lit] 0 <> and if, cc-bf-die then,
  cc-bf-desc @ cc-sd-union? if, [lit] 0 else, cc-bf-desc @ cc-sd-bit-end @ then,
  cc-bf-position !
  cc-bf-width @ 0= if,
    cc-bf-position @ cc-bf-unit @ cc-nalign cc-bf-position !
  else,
    cc-bf-position @ cc-bf-unit @ cc-mod cc-bf-width @ + cc-bf-unit @ > if,
      cc-bf-position @ cc-bf-unit @ cc-nalign cc-bf-position !
    then,
    nc-nlen @ if,
      cc-bf-desc @ cc-sd-field-count cc-bf-desc @ swap cc-sd-field-rec cc-bf-record !
      nc-name @ cc-bf-record @ cc-sf-set-name-addr
      nc-nlen @ cc-bf-record @ cc-sf-set-name-len
      nc-ty @ cc-bf-record @ cc-sf-set-type
      cc-bf-position @ cc-bf-unit @ / cc-bf-unit @ * [lit] 8 /
      cc-bf-record @ cc-sf-set-offset
      cc-bf-width @ cc-bf-record @ [lit] 48 + !
      cc-bf-position @ cc-bf-unit @ cc-mod cc-bf-record @ [lit] 56 + !
      cc-bf-desc @ dup cc-sd-field-count 1+ swap cc-sd-set-field-count
      cc-bf-desc @ cc-sd-align nc-ty @ ty-align cc-nmax cc-bf-desc @ cc-sd-set-align
    then,
    cc-bf-width @ cc-bf-position +!
  then,
  cc-bf-position @ [lit] 7 + [lit] 8 /
  cc-bf-desc @ cc-sd-total-size cc-nmax cc-bf-desc @ cc-sd-set-total-size
  cc-bf-position @ cc-bf-desc @ cc-sd-bit-end !
  cc-next-token-keep ;
\ Products are checked by the declarator; sums and final tail padding
\ must also fit, including when a bitfield follows a maximal matrix.
: cc-bf-layout-check ( desc -- )
  dup cc-sd-total-size swap cc-sd-align cc-nalign
  cc-sysv-object-size-limit > if, [lit] 245 cc-die then, ;
: cc-bf-member ( desc -- )
  cc-target-sysv @ 0= if, cc-nmember-default exit, then,
  [char] : cc-tok-punct? if, dup >r cc-bf-add r> cc-bf-layout-check exit, then,
  \ An incomplete outer dimension cannot describe an inline matrix.
  nc-inner @ nc-array @ [lit] 0 <= and if, [lit] 238 cc-die then,
  dup >r cc-nmember-default
  r@ cc-bf-layout-check
  r@ cc-sd-total-size [lit] 8 * r> cc-sd-bit-end ! ;
' cc-bf-member is cc-nmember-fwd

: cc-bf-shift-rdi ( count opcode -- )
  over if,
    [lit] 72 cc-emit-byte [lit] 193 cc-emit-byte cc-emit-byte cc-emit-byte
  else, 2drop then, ;
: cc-bf-truncate ( rec -- )
  dup cc-sf-bit-width [lit] 64 swap - [lit] 231 cc-bf-shift-rdi
  dup cc-sf-bit-width [lit] 64 swap -
  swap cc-sf-type ty-unsigned? if, [lit] 239 else, [lit] 255 then, cc-bf-shift-rdi ;
: cc-bf-load ( ty rec -- )
  dup cc-bf? 0= if, cc-field-load-default exit, then,
  swap cc-emit-load-typed-via-rdi
  dup cc-sf-bit-shift [lit] 239 cc-bf-shift-rdi
  cc-bf-truncate ;
' cc-bf-load is cc-field-load-fwd

: cc-bf-mask ( width -- mask )
  dup [lit] 64 = if, drop true else, [lit] 1 swap cc-shl 1- then, ;
: cc-bf-shift-r8 ( count opcode -- )
  over if,
    [lit] 73 cc-emit-byte [lit] 193 cc-emit-byte cc-emit-byte cc-emit-byte
  else, 2drop then, ;
: cc-bf-store ( ty rec -- )
  dup cc-bf? 0= if, cc-field-store-default exit, then,
  nip dup cc-bf-truncate
  [lit] 73 cc-emit-byte [lit] 137 cc-emit-byte [lit] 248 cc-emit-byte \ mov r8,rdi
  dup cc-sf-bit-width [lit] 64 swap - [lit] 224 cc-bf-shift-r8
  dup cc-sf-bit-width [lit] 64 swap - [lit] 232 cc-bf-shift-r8
  dup cc-sf-bit-shift [lit] 224 cc-bf-shift-r8
  dup cc-sf-type ty-size [lit] 8 = if, [lit] 72 cc-emit-byte then,
  [lit] 139 cc-emit-byte [lit] 1 cc-emit-byte  \ mov eax/rax,[rcx]
  [lit] 73 cc-emit-byte [lit] 185 cc-emit-byte \ movabs r9,preserving mask
  dup cc-sf-bit-width cc-bf-mask over cc-sf-bit-shift cc-shl dup nand cc-emit-8le
  [lit] 76 cc-emit-byte [lit] 33 cc-emit-byte [lit] 200 cc-emit-byte \ and rax,r9
  [lit] 76 cc-emit-byte [lit] 9 cc-emit-byte [lit] 192 cc-emit-byte  \ or rax,r8
  cc-sf-type ty-size [lit] 8 = if, [lit] 72 cc-emit-byte then,
  [lit] 137 cc-emit-byte [lit] 1 cc-emit-byte ; \ mov [rcx],eax/rax
' cc-bf-store is cc-field-store-fwd

: cc-bf-value-type ( ty rec -- promoted-ty )
  dup cc-bf? if,
    cc-sf-bit-width dup [lit] 32 < if,
      drop drop ty-int [lit] 0 ty-make
    else,
      [lit] 32 = if,
        ty-unsigned? if, ty-uint else, ty-int then, [lit] 0 ty-make
      then,
    then,
  else, drop then, ;
' cc-bf-value-type is cc-field-value-type-fwd
: cc-bf-use ( rec -- )
  cc-bf? if, cc-bf-die then, ;
' cc-bf-use is cc-field-use-fwd

\ Initializer records contain only named members; unnamed and zero-width
\ declarations affect layout but consume no initializer element.
variable cc-bf-init-record
variable cc-bf-init-offset
: cc-bf-static-initializer ( rec -- )
  cc-bf-init-record !
  cc-putback-token cc-parse-static-const-fwd
  if, cc-bf-die then, 2drop
  cc-bf-init-record @ cc-sf-bit-width cc-bf-mask and
  cc-bf-init-record @ cc-sf-bit-shift cc-shl
  nc-slot @ om-offset @ ni-offset @ + cc-bf-init-record @ cc-sf-offset + cc-bf-init-offset !
  cc-obj-data cc-obj-base cc-bf-init-offset @ + @
  cc-bf-init-record @ cc-sf-bit-width cc-bf-mask
  cc-bf-init-record @ cc-sf-bit-shift cc-shl dup nand and or
  cc-obj-data cc-bf-init-offset @ cc-bf-init-record @ cc-sf-type ty-size cc-obj-patch ;

: cc-bf-initializer ( rec -- handled? )
  dup cc-bf? 0= if, drop [lit] 0 exit, then,
  >r
  [char] { cc-tok-punct? dup >r if, cc-next-token-keep then,
  r> r> swap >r >r
  cc-sysv-object-mode @ cc-ni-static @ and if,
    r> cc-bf-static-initializer
  else,
    r@ cc-sf-offset ni-offset @ + cc-ni-address cc-emit-push-rdi
    cc-putback-token cc-parse-assign cc-emit-materialize
    cc-last-expr-type @ r@ cc-sf-type cc-value-init-fwd
    cc-emit-pop-rcx r@ cc-sf-type r> cc-field-store-fwd
  then,
  cc-next-token-keep
  r> if,
    [char] , cc-tok-punct? if, cc-next-token-keep then,
    [char] } cc-tok-punct? 0= if, [lit] 227 cc-die then,
    cc-next-token-keep
  then,
  true ;
' cc-bf-initializer is cc-ni-field-fwd
```

## Exercises

1. **★** Explain why a three-bit unsigned field compared with -1 uses signed int arithmetic.
2. **★★** Add a guarded-byte oracle for an ordinary char between two runs of bitfields.
3. **★★★** Design an extended-precision type representation before accepting long widths 33–63.

## Takeaways

- A field needs width and shift metadata in addition to an address and scalar type.
- Allocation, value promotion, and preserving stores are separate obligations.
- A real consumer and an independent byte-layout oracle expose different failures.

Next: retain these member interfaces while expanding the next measured original-source capability.
