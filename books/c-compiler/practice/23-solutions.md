# C23 hints and solutions

These are source-derived paper solutions to [C23's practice](../chapters/23-the-direct-tinycc-profile.md#practice-predict-the-slot-before-the-byte), not new executions. Use one hint at a time. The answer-free changed cases at the end alter a meaningful condition without placing an answer beside the prompt.

## C23-01 — Complete the image map

**Hint 1.** The header is still 120 bytes, and the stub is 31.

**Hint 2.** A kernel body with k arguments is `23+5k` bytes. Each refusal body is its message followed by 41 bytes of code.

**Hint 3.** The dispatcher is emitted after the last declaration. With nothing queued, it is one byte.

**Solution.** The stub occupies 120–150. The thirteen kernel bodies occupy 151–584 (434 bytes). The refusal bodies occupy 585–833 (249 bytes). `main` occupies 834–870 (37 bytes). The dispatcher `C3` is at 871, and the file has 872 bytes.

The dispatcher CALL's field is 121–124, so its next instruction is at 125: `871−125=746=0x2EA`, stored as `EA 02 00 00`. The `main` CALL's field is 137–140, next instruction 141: `834−141=693=0x2B5`, stored as `B5 02 00 00`.

**Common wrong path.** Subtracting the opcode's offset, 120, gives 751; subtracting the field's start, 121, gives 750. Both forget that the processor has consumed the whole five-byte instruction before applying the displacement. The rule is always the field's end.

## C23-02 — Turn floatbits off

**Hint 1.** Only `cc-native-runtime` looks at floatbits among the bytes we counted.

**Hint 2.** `main` contains no relative or absolute address fields.

**Hint 3.** Everything after offset 585 moves down by 249.

**Solution.** The three refusal bodies (249 bytes) disappear. `main` starts at 585 and ends at 621; the dispatcher is at 622; the file has 623 bytes. The dispatcher field holds `622−125=497=0x1F1`, or `F1 01 00 00`; the `main` field holds `585−141=444=0x1BC`, or `BC 01 00 00`.

No byte inside `main` changes. Its frame field, immediate and conversion do not depend on where it sits. Turning floatbits off also changes what the program may *declare*: a floating type now fails with 214, and the three refusal names no longer exist, so a call to `ldexp` is an unknown name.

**Common wrong path.** Expecting the two CALL fields to change by the same amount as the targets is correct; expecting the entry stub to change length is not. The stub has no floatbits branch.

## C23-03 — Read a kernel door

**Hint 1.** `mkdir` has two arguments.

**Hint 2.** Leaf functions have no saved RBP, so the first argument is just above the return address.

**Hint 3.** As unsigned numbers, −4095 is `0xFFFFFFFFFFFFF001`.

**Solution.** `23+5×2=33` bytes. The loads are `48 8B 7C 24 08` (`mov rdi,[rsp+8]`) and `48 8B 74 24 10` (`mov rsi,[rsp+16]`).

| Raw result | Below −4095 as unsigned? | Returned |
|---:|---|---:|
| −2 | No | −1 |
| −4095 | No (equal) | −1 |
| −4096 | Yes | −4096 |
| 3 | Yes | 3 |

The replacement is `48 C7 C0 FF FF FF FF`, seven bytes, so `jb +7` lands exactly on the `ret`. Signed comparison would treat every negative result alike; the unsigned comparison isolates exactly the 4,095 values Linux uses for errors.

**Common wrong path.** Concluding that every negative result becomes −1. Only −4095 through −1 do.

## C23-04 — Stage four arguments

**Hint 1.** Evaluation and pushing are left to right.

**Hint 2.** With n=4 the loop runs for i=0 and i=1.

**Hint 3.** Parameter index 3 has slot −6.

**Solution.** After the pushes, S−8:1, S−16:2, S−24:3, S−32:4, with RSP=S−32. The first swap exchanges offsets 0 and 24 (S−32 and S−8); the second exchanges 8 and 16 (S−24 and S−16). Afterward S−32:1, S−24:2, S−16:3, S−8:4. In the callee, `d` is at `rbp−8×(−6+1)=RBP+40`. After the call, `add rsp,32` discards the slots.

**Common wrong path.** Stopping after one swap. For an even count, the middle pair must be exchanged as well.

## C23-05 — Narrow reads from wide slots

**Hint 1.** The callee's load width comes from the parameter's type.

**Hint 2.** `300=0x12C`; `4294967298=0x100000002`.

**Hint 3.** `cc-native-parse-args` never reads a parameter list.

**Solution.** `c(300)`: the byte load reads `0x2C`, which sign-extends to 44. `c(-1)`: the slot is all ones, the byte is `0xFF`, and sign extension gives −1. `w(v)`: the dword load reads 2, so the comparison yields 1. Each result is decided by the callee's typed load (`movsx` byte or `movsxd` dword).

The caller emits no conversion because its argument parser only parses, materializes and pushes each expression; nothing connects an argument position to a parameter type. With one argument for a two-parameter function, the program still compiles. The callee reads its second parameter from the slot above the first, which belongs to the caller's own stack contents. Nothing predicts that value.

**Common wrong path.** Reasoning that C's rules for converting arguments are applied here. They happen to agree for values that fit, which is why the source can rely on them for the pinned TinyCC and libc sources. The mechanism is the narrow load.

## C23-06 — Frame accounting

**Hint 1.** Slots per object are `ceil(size/8)`.

**Hint 2.** The returned slot is `count + slots − 1`, and its address is the object's lowest address.

**Hint 3.** `struct rec` is 16 bytes.

**Solution.**

| Local | Slots | Slot | Address | Count afterward |
|---|---:|---:|---|---:|
| `long t` | 1 | 0 | RBP−8 | 1 |
| `char s[9]` | 2 | 2 | RBP−24 | 3 |
| `struct rec r` | 2 | 4 | RBP−40 | 5 |
| `short h` | 1 | 5 | RBP−48 | 6 |

The frame is `round16(6×8)=48`. Without `h` the count is 5, giving `round16(40)=48`: the same frame size.

**Common wrong path.** Placing `s` at RBP−16 as if it took one slot. Nine bytes need two.

## C23-07 — Records and failures

**Hint 1.** A prototype creates a function record with address zero.

**Hint 2.** A call to an address-zero function emits a CALL placeholder and records its field.

**Hint 3.** A definition patches before parsing its body.

**Solution.** The prototype adds `g` (type int, address 0). In `main`, the call emits `E8 00 00 00 00` and adds that field to `g`'s call list. The definition stores `g`'s address, patches the waiting field to it, clears the list, and then parses the body. At the end, no list is pending and `main` exists.

(a) Without the definition, the list is still pending: `g` is written to standard error, then 206. (b) Without the prototype, the use in `main` is an unknown identifier: 93. (c) A second definition finds a nonzero address: 211. (d) `close` was defined by the runtime before any source was read: 211. (e) A by-value struct result fails at the prototype: 212.

**Common wrong path.** Expecting (b) to work because the definition appears later. Only declared names can be called; the fixup mechanism handles later *definitions*, not later *declarations*.

## C23-08 — Declarations at the boundary

**Hint 1.** Keyword order is irrelevant; counts decide.

**Hint 2.** A star inside an inner declarator group is outside the profile.

**Hint 3.** A larger redeclaration moves the object.

**Solution.** `long unsigned long a`: unsigned long long, 8 bytes. `unsigned long long int b`: the same type, 8 bytes. `int (*(*p))(void)`: 238. `int m[2][3]`: accepted, 24 bytes. `int a[1]; int a[4];`: accepted; the second declaration allocates 16 BSS bytes and redirects earlier references, so `sizeof a` is 16. `double d` with floatbits 0: 214.

**Common wrong path.** Treating `long unsigned long` as an error because the keywords are “out of order.” This parser never sees an order.

## C23-09 — Which convention is in force?

**Hint 1.** Ask which compiler produced the caller and the callee.

**Hint 2.** `tcc-boot0` was produced by TinyCC's code generator running inside `tcc-seed`.

**Hint 3.** A kernel body is a leaf.

**Solution.** (a) Private: the first argument is at `[rsp+8]` on entry, `[rbp+16]` after `malloc`'s prologue. The Forth compiler produced both. (b) TinyCC's System V output: RDI. TinyCC running inside `tcc-seed` produced both `tcc-boot0`'s code and the `boot0-lib` library it links. (c) Legacy register sequence: RDI; the legacy Forth compiler produced both the call and the eager runtime body. (d) Private, at the kernel boundary: `[rsp+8]`, since the body has no frame. The Forth compiler produced libc's call and the runtime emitted the body.

A GCC-compiled System V object would disagree about argument location in both directions. Its functions would read arguments from registers that a private caller never loads, and its calls would place arguments in registers that a private callee never reads. The result register happens to agree, which is not enough.

**Common wrong path.** Answering (b) as private because `tcc-seed` is involved. The private convention describes the code inside `tcc-seed`, not the code it emits.

## C23-10 — Return without the tables

**Hint 1.** Name the profile before any byte count.

**Hint 2.** Separate the final layout from the order of evaluation.

**Hint 3.** Local layout reserves whole slots.

**Solution.** The 872-byte file has a 31-byte stub, 434 bytes of kernel bodies and 249 of refusal bodies before `main`, while C19's had a 26-byte stub and 376 bytes of legacy runtime. Its 37-byte `main` has no fixed frame but one more conversion, and a one-byte dispatcher follows it.

“Right to left” describes the final layout: the first argument ends nearest the return address. Evaluation is left to right; the slots are then reversed.

A `char` parameter costs the callee nothing. It occupies a caller-owned slot, which the callee reads in place. A `char` local costs the callee one eight-byte slot of frame.

No. LP64 selects object widths. The private convention is the default bound to the native call hooks, used because this file list loads no System V provider. The System V target, when its file is loaded and selected, supplies different call providers for the same LP64 widths (G04).

**Common wrong path.** Explaining the 872 bytes only by “bigger runtime.” The stub, the frame field and the return conversion each changed for their own reason.

## Answer-free changed cases

Choose one after using feedback. State the governing rule first, then keep your calculation separate from the previous solution.

- Change C23-01's program to `int main(int argc, char **argv) { return argc; }`. Which parameter slots does `main` read, which entry instructions supply them, and which offsets in the image change?
- Change C23-04 to five arguments. List the swaps, the untouched slot and the cleanup instruction
- Change C23-06 by adding `char z[17];` after `short h`. Recompute the slot, address and frame size, and decide whether removing `h` would change the frame now
- Suppose a source prototype `int lseek(int fd, long off, int whence);` appears after the runtime has registered `lseek`. Which record does the prototype change, which field stays the same, and what would a later definition of `lseek` produce?
