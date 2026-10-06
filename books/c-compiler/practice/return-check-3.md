# Return check: restore the right state

These cases mix tokens, type descriptors and symbol visibility. Use the
chapter contracts with answers closed. All addresses are symbolic, valid,
nonoverlapping paper storage; all source spans remain owned and stable unless
a question explicitly changes that assumption. No compiler execution is
implied.

## Questions

### CR3-01

A caller saves the eight-cell lexer state in live buffer M. It then reads a
token, appends a symbol (raising symbol count from two to three), and emits
four output bytes. Finally it resets the lexer from M. Which state is restored,
and which changes remain? Why does the ordinary read-only lookahead contract
matter? This is a hypothetical misuse of a snapshot, not a claim that the
current lookahead callers perform these extra writes.

### CR3-02

Use legacy forty-byte field records. A live descriptor D has field count eight,
capacity eight and table T. Requesting record index eight causes growth to a
new table U of capacity sixteen. Which address identifies the descriptor
before and after? Which address is returned for the requested record? Has
that request published a ninth field? A cached old record-zero pointer T is
still readable; does a later store through it update the current descriptor's
record zero?

### CR3-03

The lexer reads `2147483648` and `0x80000000` in separate stable source spans.
Both have numeric payload 2,147,483,648. Under LP64 with bootstrap floatbits
off, what types and type words does `cc-integer-literal-type` choose, and
what are their scalar storage sizes? Why does the token retain spelling in
addition to numeric bits? Do equal Forth-cell payloads imply equal C types?

### CR3-04

A default-namespace symbol table initially contains only outer `x` at ID zero.
Push a scope, append inner `x` at ID one, then pop that scope. What does lookup
for `x` return before and after the pop? Append a new `y` afterward. What ID
does it receive, and what can a previously cached ID one now mean? Distinguish
record visibility from the lifetime of a separately allocated descriptor D
that the removed record had referenced.

## Hints

- CR3-01: name the exact eight cells in the snapshot before assuming another
  subsystem's state was included
- CR3-02: descriptor identity, table identity, field count and a record's
  address are separate quantities
- CR3-03: the source spelling's first byte affects the unsuffixed LP64 branch
- CR3-04: scope pop restores a count; the next add uses that count as its index

## Worked answers

### CR3-01

Reset restores reader position and line, the current token's kind and payload
cells, and the pending-token flag. It restores those eight cell values, not
arbitrary consequences of the work performed between mark and reset.

Symbol count remains three; the appended symbol remains visible under the
current count. Output retains the four emitted bytes and its advanced cursor.
The mark did not copy those arrays or counters. It also would not undo arena
allocation, source-buffer mutation, or a changed selected source buffer/length.

Read-only token lookahead keeps the operation inside the snapshot's intended
boundary. A parser that speculates by changing other subsystems would need
separate, correctly scoped state management; resetting the lexer alone does
not supply it. No replacement parser design is proposed here.

Changed case: one-token putback is narrower still. It sets pending so the next
keep call returns the current token record once without reading new bytes.
It does not rewind the reader position and does not roll back symbols or
output. A saved token span still relies on its source owner.

### CR3-02

D remains the descriptor identity. Its table-address cell changes from T to
U, and capacity becomes sixteen. Record index eight is at `U+8*40`, or
`U+320`. The growth operation copies the old records to the new table and
retains the old allocation; the arena does not free T.

Field count remains eight until the caller explicitly publishes another
field. Reserved capacity and an allocated record address do not make a field
part of the visible member sequence. The caller must fill its intended
metadata and update count through the appropriate producer contract.

A store through T writes retained old storage, not U's current record zero.
Reacquire the current record address through D and the selected record stride.
Continued readability is weaker than being the current owner of a value.

Changed case: explicitly switch the paper example to native LP64 from the
start, with its forty-eight-byte records. The new record address is `U+384`.
This is a separate profile example, not a proposal to reinterpret an existing
forty-byte table by changing its stride in place.

### CR3-03

The decimal spelling does not fit the signed-int selection branch and does
not start with zero. The helper selects signed long: base kind six, pointer
depth zero, type word `6*65536=393216`, size eight bytes.

The hexadecimal spelling starts with zero and its value remains below 2^32.
The helper selects unsigned int: base kind eleven, type word
`11*65536=720896`, size four bytes. Both token numeric payloads occupy a Forth
cell, but that builder representation does not make the generated C objects
or arithmetic types identical.

The retained span distinguishes the two spellings and preserves suffixes for
classification. Kind and numeric payload alone lose that information. Equal
lengths do not recover it either: both displayed spellings have ten bytes.

Changed case: in the legacy profile, this helper itself returns the int type
word `2*65536=131072`, with size eight, through its early branch. That does not
establish general acceptance of malformed numeric spellings by every caller
or turn legacy int into the LP64 int representation.

### CR3-04

After the inner append, newest-first lookup returns ID one. Scope pop restores
symbol count from two to its saved value one, hiding that row; lookup now
returns outer ID zero. The bytes of the hidden row need not be erased.

Appending `y` uses current count one as its new ID, stores the new fields,
clears reusable metadata and increments count to two. A cached numeric ID one
now designates `y`, not the former inner `x`. It is a reusable index, not a
permanent declaration identity.

Pop did not free descriptor D or reclaim its arena storage. If that storage
remains owned and its representation remains valid, D can still name the same
aggregate independently of whether a particular symbol record is visible.
That does not authorize treating a stale symbol ID as a reference to D.

Changed case: give the inner record a global kind. The same count truncation
still hides it; kind does not exempt a row from scope restoration. Generated
object storage and compiler symbol visibility are separate contracts.

## Choose the next repair

If two cases feel alike, name the exact state restored: eight lexer cells, a
descriptor's table pointer, or one symbol count. Then identify a state that is
*not* restored. That distinction is more useful than remembering that all
three examples contain an address. Return later to a changed case without
its answer; these opportunities do not by themselves establish retention,
transfer or compiler correctness.

[Back to the volume](../README.md)
