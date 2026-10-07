# C24 hints and solutions

These are source-derived paper solutions to [C24's practice](../chapters/24-tinycc-initialization-runtime-and-closure.md#practice-follow-the-value-to-its-store), not new executions. The route answers read the recipe; they do not report a run of it. Use one hint at a time. The answer-free changed cases at the end alter a meaningful condition without placing an answer beside the prompt.

## C24-01 — Rebuild the image map

**Hint 1.** Each routine is preceded by its own five-byte `jmp`.

**Hint 2.** The dispatcher follows `main`, and data follows the dispatcher.

**Hint 3.** A field's displacement is measured from the field's end.

**Solution.** `jmp` 834–838; `n`'s routine 839–860; `jmp` 861–865; `p`'s routine 866–891; `main` 892–961; dispatcher 962–972 (two five-byte CALLs and `C3`); data 973–988, with `n` at 973 and `p` at `973+8=981`. The file has 989 bytes.

| Field | Ends at | Target | Value | Stored |
|---|---:|---:|---:|---|
| first `jmp` | 839 | 861 | 22 | `16 00 00 00` |
| second `jmp` | 866 | 892 | 26 | `1A 00 00 00` |
| first CALL | 967 | 839 | −128 | `80 FF FF FF` |
| second CALL | 972 | 866 | −106 | `96 FF FF FF` |
| stub dispatcher CALL | 125 | 962 | 837 | `45 03 00 00` |
| stub `main` CALL | 141 | 892 | 751 | `EF 02 00 00` |

**Common wrong path.** Placing the data at 962, straight after `main`. The dispatcher is emitted after the last declaration and before `cc-finalize-globals` appends the data.

## C24-02 — Add a third global

**Hint 1.** The new routine is `10+1+7+1+3+1` bytes.

**Hint 2.** Everything after `p`'s routine moves by the new `jmp` and routine; the data moves by that plus one more CALL.

**Hint 3.** A `char` needs no alignment.

**Solution.** `jmp` 892–896 (field `17 00 00 00`), routine 897–919. `main` starts at 920 and ends at 989. The dispatcher is 990–1005: its CALL fields are `839−995=−156` (`64 FF FF FF`), `866−1000=−134` (`7A FF FF FF`) and `897−1005=−108` (`94 FF FF FF`), then `C3`. Data begins at 1006: `n` at 1006 (`0x4003EE`), `p` at 1014 (`0x4003F6`), `c` at 1022 (`0x4003FE`). The file has 1,023 bytes. The stub fields become `990−125=865` (`61 03 00 00`) and `920−141=779` (`0B 03 00 00`).

In `n`'s routine only the `movabs` immediate changes, from `CD 03 40 00…` to `EE 03 40 00…`. Both immediates in `p`'s routine change. The `jmp` fields do not: they measure distances within code that did not change. The data moved 33 bytes because all of it follows the code, which grew by 28 bytes of routine and 5 of CALL.

**Common wrong path.** Expecting no byte of the earlier routines to change because their source lines did not. Their immediates are addresses of objects whose position depends on everything emitted later.

## C24-03 — Accepted or 219?

**Hint 1.** The guard asks what kind of operation is about to be emitted, not what value it would compute.

**Hint 2.** Naming a global or a function emits an address; reading the global emits a load.

**Hint 3.** `sizeof` parses its operand with the guard suspended.

**Solution.** `int *a = &n + 1;` accepted: the routine stores `n`'s address plus 4. `int b = n;` fails with 219 (a load). `long c = (long)&n;` accepted: the address, converted. `int d = sizeof(f());` accepted: stores 4, and no CALL is emitted. `int *e = arr + 2;` accepted: the array decays to its address, plus 8. `int g = (3, 4);` fails with 219: the comma operator is guarded even between constants. `int (*h)(void) = f;` accepted: stores `f`'s address through an ordinary function-address fixup. `int k = 7 / 0;` compiles; its routine executes `idiv` with a zero divisor before `main`, so the process dies with `SIGFPE`.

The rule: a static initializer may compute with addresses and integer constants, and may not load memory, call, refer to a local, increment, assign, or use a comma.

**Common wrong path.** Calling `7 / 0` a 219. The guard never inspects values, and no step folds the division at compile time.

## C24-04 — Name the code

**Hint 1.** An unsized array is counted before it is allocated.

**Hint 2.** In an inferred array, a nested aggregate must have braces.

**Hint 3.** A string's count is decoded bytes plus the NUL, capped at the array's length.

**Solution.** `int a[] = {1, 2, 3};` has 12 bytes. `int m[][2] = {{1,2},{3,4},{5,6}};` has three rows, 24 bytes. `int m[][2] = {1,2,3,4};` fails with 222. `int m[2][3] = {{1},{4,5}};` gives `m[0][1]=0` and `m[1][1]=5`: each inner brace starts a new row, and omitted elements stay zero. `char s[2] = "hi";` is accepted and holds no NUL. `char t[] = "a\n";` has three bytes. `int a[2] = {1,2,3};` fails with 226. `int x = {4 5};` fails with 227. `w.c[1]` is 1, because the union initializes its first member and `258=0x102` stores bytes `02 01 00 00`.

**Common wrong path.** Counting `"a\n"` as four bytes. The lexer keeps the backslash, but `cc-ni-string-size` counts the decoded newline as one.

## C24-05 — A local array

**Hint 1.** `r` takes three slots, and the returned slot is its lowest address.

**Hint 2.** A local array is zeroed before any element is stored.

**Hint 3.** Only listed elements get stores.

**Solution.** `r` is at RBP−24 (slots 0–2, slot 2 returned). The zeroing is `lea rdi,[rbp-24]`; `mov ecx,24`; `xor rax,rax`; `rep stosb`. One element store follows, `r[0]=7`, an eight-byte `mov [rcx], rdi`. The frame is `round16(3×8)=32`, and the program exits with 7.

If `r` is `static`, the zeroing disappears, the store moves into a queued routine that the dispatcher runs before `main`, `r` lives in the data area, and the function has no locals, so its frame field is 0. The exit status is still 7.

**Common wrong path.** Expecting stores of zero to `r[1]` and `r[2]`. Zeroing is one bulk instruction; there is no per-element store for omitted elements.

## C24-06 — A redirected initializer

**Hint 1.** `q`'s routine contains a `movabs rdi, address` whose field was recorded as a global-address fixup.

**Hint 2.** A larger redeclaration redirects existing fixups for the old slot.

**Hint 3.** A name must be declared before it is used, whatever follows.

**Solution.** The `movabs` immediate in `q`'s routine is patched. Before the third line it named `a`'s original four-byte BSS object; afterward it names the new 12-byte BSS object that the third line allocated. `a`'s own routine stores 1, 2 and 3 there, so `q[2]` is 3.

Deleting the first line makes `int *q = a;` a use of an undeclared name: 93. Swapping the second and third lines also gives `q[2]=3`, but nothing is redirected: `q`'s routine is emitted after the enlargement and names the new storage directly.

**Common wrong path.** Expecting `q` to keep the old, one-element address, as a data initializer written at that moment would. The redirect reaches every recorded fixup, inside routines as well as in function bodies.

## C24-07 — Through the kernel door

**Hint 1.** The comparison is unsigned.

**Hint 2.** Portable libc tests for exactly −1.

**Hint 3.** `5368709120 = 0x140000000`.

**Solution.** `open` leaves −2 (`ENOENT`) in RAX. That is in −4095…−1, so the body returns −1, and `fopen` returns `NULL`. With the old pnut boundary, the body returned −2. `fopen`'s `fd == -1` test did not fire, and it returned a `FILE` holding descriptor −2.

`0x140000000` is far below `0xFFFFFFFFFFFFF001`, so the body returns it unchanged. Registered as `long`, the caller sees 5368709120. Registered as `int`, only the low 32 bits would be the value: `0x40000000`, or 1073741824. That is why `lseek` is pre-registered as `long`.

**Common wrong path.** Expecting −1 for every negative raw result, or expecting the body to set `errno`. Neither happens.

## C24-08 — Which refusal, and what happens?

**Hint 1.** The message is a 34-byte prefix, the name and a newline.

**Hint 2.** Every `run` line in the recipe names the exit status it requires.

**Hint 3.** Think about what the next step would do with a wrong answer.

**Solution.** (a) `ldexp`, `34+5+1=40` bytes. (b) `localtime`, 44 bytes. (c) `longjmp`, 42 bytes: TinyCC reports the error and then jumps back to `tcc_compile`. In each case the step exits 125, which is not the 0 its `run` line requires, so the recipe stops at that line. (d) None. The `tcc-boot0` compile must exit 0, and the repository reports that the recipe passes, so that compile reached none of them.

A body that returned zero would let the build continue with a wrong value: a hexadecimal literal would become 0, and a `longjmp` would return into code that assumed it never returns. The result could still be a compiler, wrong in a way that a later hash mismatch would report without naming its cause. A named exit stops the build at the cause.

**Common wrong path.** Treating the three names as proven unreachable. The audit found them unimplemented; malformed input can reach `longjmp`.

## C24-09 — Who built it?

**Hint 1.** Before line 59 every compiler run is `./seed-forth`.

**Hint 2.** Patching is done by a helper, but the helper was compiled by Forth.

**Hint 3.** The last library pins come after `tcc-boot2` rebuilt `build/boot2-lib`.

**Solution.**

| File | Produced by | Check |
|---|---|---|
| the runner | the seed, running the Forth compiler from the ladder launcher | `artifact`, `363b…18e6` |
| bootstrap `simple-patch` | the seed, Forth compiler on raw `libc.c` plus `simple-patch.c` | empty stdout (`same`), then `artifact`, `9578…1fc7` |
| patched `tccgen.c` | the Forth-built `simple-patch`, from the kit manifest | before and after hashes in the manifest, then the 440 `stage` pins |
| `tcc-seed` | the seed, Forth compiler on the 25-line unit | `artifact`, `7411…fc3a` |
| `build/boot0-lib/libc.a` | `tcc-seed` (`-c`, then `-ar`) | exit status only |
| `tcc-boot1` | `tcc-boot0` | `artifact`, `c382…a886` |
| `tcc-boot3` | `tcc-boot2` | `same` as `tcc-boot2` |
| final `build/boot2-lib/libc.a` | `tcc-boot2` | `artifact`, `6f35…c86a` |
| last `bintools` | `tcc-boot2`, after the LP64 patch | `artifact`, `26f7…67c0` |

**Common wrong path.** Saying bintools or simple-patch came from pnut. The historical `PNUT_*` macros select code paths in the portable libc; no pnut executable runs in this recipe.

## C24-10 — Return without the tables

**Hint 1.** Ask when the object's bytes are first read.

**Hint 2.** Ask which strings are compiled into TinyCC.

**Hint 3.** Ask which compiler needs to see every caller and callee.

**Solution.** The data bytes are zero because static initialization is code. The entry stub calls the dispatcher before `main`, and nothing runs earlier that reads the objects, so their file contents are never observed. Writing values into the data area would need a second evaluator for relocations; the routines reuse the existing fixups.

`tcc-boot3` reuses `build/boot2-lib` because the library paths are compiled into TinyCC as strings. Different directory names would make the executables differ in those bytes, whatever else matched.

The fixed point establishes that TinyCC, compiled by itself, reproduces itself, both as an object and as an executable, with every generation pin matching the independent control. It is strong evidence that `tcc-seed` compiled TinyCC correctly on the paths this route uses. It does not prove the Forth compiler correct on other inputs, and it compares only generations 2 and 3.

`tcc-seed` must be one unit because the private convention works only when one compiler run produces every caller and callee; the Forth profile also has no object format or linker. `tcc-boot0` is produced by TinyCC, which uses the System V convention, writes objects and links them, so libc can be compiled separately into `libc.a`.

**Common wrong path.** Answering that `tcc-boot3` reuses the directory only to save space. Equality of the executables is the purpose.

## Answer-free changed cases

Choose one after using feedback. State the governing rule first, then keep your calculation separate from the previous solution.

- Change the opening program to `int *p = &n; int n = 5;` with `extern int n;` as a new first line. Is `extern` accepted by this profile, how many routines are queued, and which fixup makes `p`'s routine name the right object?
- Change C24-05 to `struct pair { int a; long b; } r = {1};` as a local. Give the zeroing count, the one store's width, and the frame size
- Suppose the recipe built `tcc-boot3` with `build/boot3-lib`. Which comparison would fail, which pins would still pass, and what would you change to restore the fixed point without removing a check?
- Suppose `cc-native-syscall` compared signed instead of unsigned. Give the result returned for raw −2, for raw 3, and for `lseek`'s `0x8000000000000000`, and say which caller would be affected
