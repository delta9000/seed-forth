# C20 hints and solutions

These are paper solutions to [C20's artifact and recipe questions](../chapters/20-complete-compiler-and-stage-a.md#practice-identify-the-artifact-before-judging-the-result). They do not report new executions. Try the task before revealing its solution if you want an independent check; use the hints one at a time when the artifact identities become hard to hold in view.

## C20-01 — Recover the missing invocation

**Hint 1.** A file that can run is not necessarily the file whose bytes are eventually compared.

**Hint 2.** Follow each producer one invocation beyond its creation. Both next invocations receive the self-source input.

**Hint 3.** The final pair begins `self-v1-` and `self-ref-`, and both filenames end `.M1`.

**Solution.** `seed-forth` running the Forth C compiler consumes the prepared monolith and produces the executable retained as `cc-out-v1`. The selected host C compiler builds the reference executable `m2-ref` from M2-Planet source. Under the default reference setting that host compiler is GCC.

Each newly built executable then runs on the same ordered eleven-source argument list, expanded includes, working directory, and amd64 output selection. v1 writes `self-v1-amd64.M1`; the reference writes `self-ref-amd64.M1`. Those are M1 text artifacts. The exact final comparison is:

```text
cmp $BUILDROOT/self-v1-amd64.M1 $BUILDROOT/self-ref-amd64.M1
```

This line names the operands schematically; the actual script quotes its paths. `--architecture`, `--expand-includes`, `-f`, and `-o` belong to the M2-Planet producers. `CC_OUT` belongs to the wrapper that retains the Forth compiler's fixed-path output.

Replacing the comparator operands with `cc-out-v1` and `m2-ref` asks whether the compiler implementations have identical executable bytes. Different implementations can emit the same text for this input, so behavioral agreement does not require compiler-byte identity. Both files being ELF gives no basis for predicting that their first bytes differ. No such ELF pair was inspected or compared by Stage A.

**Common wrong path.** Comparing the compiler files skips their second invocation. Saying “the Forth compiler emits M1” attaches M2-Planet's later output format to the wrong running producer.

**Answer-free reattempt.** Suppose a v1 compiler that runs on x86-64 is asked to emit x86 output while the reference is still asked for amd64. Identify the lost control condition, which executable's running architecture is unchanged, and why the resulting `cmp` is a different experiment.

## C20-02 — Complete the input stream

**Hint 1.** Numeric order and invocation order are different constraints.

**Hint 2.** The file that ends with bare `cc-main` must be the last Forth file, because that invocation reads the remaining stream as C.

**Hint 3.** The first gap follows 119; the second is after the library numbered 140.

**Solution.** The missing positions are 121 and 120:

```text
010, 020, ... 118, 119, 121, 122, ... 129, 131, 140, 120, prepared C
```

The selected definitions must be available before the final invocation starts input reading, compilation, output, and termination. Moving 120 before later libraries puts those libraries after an executing driver, where their text can become C input instead of Forth definitions.

`130-asm.fth` does not match the helper's three-digit-`-cc-` filename pattern, so inserting it changes the actual recipe. Optional native and System V definitions can be loaded without being selected: this driver still calls legacy `cc-parse-program` directly.

A new `135-cc-helper.fth` matches the pattern. Under the same filename ordering it appears after 131 and before 140, with 120 still held last. The resulting input stream differs from the original pinned census. To characterize a later result, retain the added file's content/identity and its place in the full stream, and record any effects on definitions or configuration. Merely saying “the same layer helper ran” cannot establish the same source input.

**Common wrong path.** Counting only files numbered below 120 misses loaded providers. Counting every numbered Forth file includes things the actual pattern excludes. Neither reconstruction follows the helper.

**Answer-free reattempt.** Keep all source contents fixed but change the helper's optional root argument to a different directory containing the same filenames. What evidence is still needed to call the selected input identical?

## C20-03 — Trace the preparation, not an imagined preprocessor

**Hint 1.** Decide which file group receives the filter before deciding whether its text matches a pattern.

**Hint 2.** A caret anchors the match to the start of the line. The macro-name deletion patterns are prefixes, not complete numeric-token checks.

**Hint 3.** H1 survives because it is in a header. C2 survives for a different reason.

**Solution.** The retained lines, in original order, are H1, H2, C2, C3, and C6:

```c
#include "cc_globals.h"
#define TRUE 1
  #include "cc.h"
#include <stdio.h>
int flag;
```

H1 and H2 are copied as part of the raw header prefix. C1 starts exactly with `#include`, permitted intervening whitespace, and a quote, so it is removed. C2 has leading spaces before `#`; the anchored quote-include pattern does not match it. C3 uses angle brackets rather than the required quote. C4 begins with the entire prefix `#define TRUE 1`, even though a zero follows; it is removed. C5 matches `#define FALSE 0` and is removed. C6 matches none of the patterns.

This is the preparation result, not a claim about subsequent acceptance or semantics of these illustrative files.

For the real residual include, the standalone helper's working directory is the repository root. The legacy lookup first tries literal `cc_globals.h`, then `tests/cc/cc_globals.h` if opening the literal path fails. Under the clean pinned-root assumptions the fallback fixture is reached, and its source blob matches the pinned upstream header.

If a different readable root `cc_globals.h` appears, the literal open can succeed first. The selected source identity changes. Whether generated bytes change requires inspecting the replacement content and the later processing; a changed path alone does not prove a changed executable.

**Common wrong path.** Removing H1 imagines that the filter processes all thirteen pieces. Retaining C4 imagines a parsed C directive where the recipe uses a textual prefix.

**Answer-free reattempt.** Add these two C-file lines, with their spacing exact: `#include"cc.h"` and `#define  FALSE 0`. Which preparation rule, if any, applies to each? Explain the role of the zero-or-more whitespace pattern separately from the literal spaces in the define pattern.

## C20-04 — Diagnose two different missing files

**Hint 1.** The caller needs only one reference executable, but its helper builds three.

**Hint 2.** Follow the path opened inside the Forth driver before the wrapper moves any output.

**Hint 3.** A private destination and a private temporary path are two separate properties.

**Solution.** Record A stops at a prerequisite of the reference helper. It requires mescc-tools and its own M2libc to build `M1-ref` and `hex2-ref`, even though standalone Stage A uses only `m2-ref`. With the sentinel absent, no final M1 parity result follows. This evidence does not diagnose a Forth translation fault. The appropriate missing information is the dependency's availability/identity and the helper's original diagnostic.

In B, a failed private-`/tmp` probe selects the shared fallback. Both shell wrappers can then remove the same `/tmp/cc-out`, and both Forth drivers can open and truncate that shared path, despite their distinct eventual `CC_OUT` destinations. Moving a result afterward does not undo interference during production. Successful statuses alone do not establish absence of a collision or the identity of the moved bytes.

If private temporary views work but `BUILDROOT` is shared, the runs can still share `cc-out-v1.tmp`, `cc-out-v1.monolith.c`, `cc-out-v1`, the M1 destinations, and the reference directory. Namespace support does not make every surrounding path independent.

**Common wrong path.** Treating `CC_OUT` as a Forth `-o` option would erase the very fixed-path operation that creates the fallback risk. Treating a successful probe as a record of the actual compiler mount would also overstate the evidence.

**Answer-free reattempt.** The preliminary namespace probe succeeds, but the actual mount at compiler launch fails. Which later fallback, if any, is specified by the inspected execution branch? Which wrapper check would reveal a failed pipeline? Read the branch rather than inferring retry behavior from the earlier probe.

## C20-05 — Attach the right evidence label

**Hint 1.** Identify who obtained each fact, from what operation, and on which occasion.

**Hint 2.** Source arithmetic, file predicates, documented old hashes, and a named remote run are not interchangeable evidence.

**Hint 3.** The later CI summary contains an M1 count but no Stage-A SHA-256 or output artifact download.

**Solution.** The classifications and corrections are:

| Record | Kind and bounded conclusion |
|---|---|
| 1 | Derivation: the output cursor predicts 556 bytes requested for C19's stated fixture/profile. The one-write routine ignores its write/close results, so a stored file of that length is not established |
| 2 | Limited status/file observation: the wrapper reports successful producer termination and an executable file predicate. The two subsequent M1 productions and their comparison remain separate work |
| 3 | Attributed historical result: the pinned document reports a hash. The later CI summary does not supply that hash measurement, so transferring it into the later run is unsupported |
| 4 | Reported remote execution result: the named job records finite byte equality of the standalone M1 pair and its count under that run's context |
| 5 | Unsupported conclusion: the book job targets the original `book/` tree. It does not establish execution of the new teaching examples |

In the changed empty-file record, `cmp` accepts because the two byte sequences are identical and empty. The Stage-A recipe has no separate nonempty check or required count. Under the prompt's trustworthy statuses and retained artifacts, we may conclude equality of these empty outputs. We may not conclude that the intended substantial self-compilation output was produced. That needs additional expected-content or workload evidence. In the real cited CI record, the reported 2,367,260-byte count rules out this particular empty-file case.

**Common wrong path.** Calling every fact “unverified” throws away a real execution observation. Calling every fact “proved” erases the input and artifact boundaries. The purpose of classification is to preserve useful evidence at its actual strength.

**Answer-free reattempt.** A new record retains both nonempty files with equal lengths and SHA-256 digests, computed correctly from each file, that differ, but contains no comparator status. What byte-identity claim can be rejected, and which producer-success claim is still unknown?

## C20-06 — Change one producer's preparation

**Hint 1.** Logical conjunction first asks whether each operand is nonzero. Bitwise AND compares bit positions.

**Hint 2.** Eight is binary `1000`; one is binary `0001`.

**Hint 3.** The compatibility edit changes v1's compiled source. It does not make the reference helper apply the same edit.

**Solution.** With the supplied operands:

```text
logical: 8 && 1 -> 1
bitwise: 8 & 1  -> 0
substitution: 0 -> 0
```

The recipe's documented default behavior selects certain short immediate forms under the logical guard, while the bitwise-family behavior does not. Replacing the guard with zero in the v1 monolith deliberately suppresses that selection. The original-source reference is still built using the host compiler's logical meaning. Consequently, the documented default-reference Stage-A equality expectation cannot be carried unchanged into this modified producer profile; the pinned record says that mode fails the default comparison by design.

Wider-chain F compares `self-v2-$ARCH.M1` with `self-v3-$ARCH.M1`, emitted from the same self-source recipe by v2 and v3. Its pass establishes that finite text-output equality. It does not compare either file to the default reference output, nor compare the producer ELFs `cc-out-v2-$ARCH` and `cc-out-v3-$ARCH` with each other.

**Common wrong path.** A fixed point of one producer lineage does not automatically equal the result from another lineage or profile. The words “v2 equals v3” are incomplete until the `.M1` operands are restored.

**Answer-free reattempt.** Use four instead of eight for the architecture-family value, keeping the register result one. Then change the register result to zero. Explain which comparisons are now numerically indistinguishable and why that smaller example alone would fail to expose the original difference.

## C20-07 — Change the compared representation

**Hint 1.** Raw comparison sees the comment bytes even when a later transformation ignores them.

**Hint 2.** Determinism forbids different outputs for the same complete input. It does not require different inputs to produce different outputs.

**Hint 3.** Keep the text pair and executable pair as four different files.

**Solution.** Raw `cmp L R` fails because R contains additional space/comment bytes. The executable comparison passes by the supplied hypothetical observation. This does not contradict determinism: a function can map different inputs to the same output.

The forward implication is: equal text, plus the same assembler implementation, all additional inputs, options, and relevant environment, under a deterministic transformation, gives equal executable outputs. Omitting the extra architecture definitions, runtime text, or base-address choice would weaken “same input” beyond what the real recipe requires.

The reverse implication is invalid in the supplied example because comment information is discarded. The example uses an invented assembler contract; it establishes no specific M1 comment syntax. Applied to Stage A, the lesson is about its comparison point: Stage A rejects unequal M1 bytes even if a later separately tested transformation could erase their difference. It does not perform that assembly or executable comparison.

**Common wrong path.** “Deterministic” does not mean “one-to-one.” It constrains repeatability for a complete input, rather than preservation of every distinction in the input.

**Answer-free reattempt.** Now hold the M1 text equal but give one assembly route a different runtime file. Can determinism alone predict equal ELF outputs? Identify precisely which premise of the forward implication was lost.

## C20-08 — Interpret the wider-suite counters

**Hint 1.** Only the both-zero branch reaches an emitted-file comparison.

**Hint 2.** Different statuses increment `differ`; matching nonzero statuses increment `both-fail` regardless of their cause.

**Hint 3.** Case A increments one counter even though it contributes no compared output.

**Solution.** The row-by-row increments are:

| Case | Counter change | Reason |
|---|---|---|
| A | `both-fail` +1 | Equal nonzero statuses; the prompt identifies both as timeout |
| B | `differ` +1 | Statuses seven and eight differ |
| C | `differ` +1 | Both return zero, then the emitted files differ |
| D | `identical` +1 | Both return zero and the emitted files compare equal |

The totals are `identical=1`, `both-fail=1`, `differ=2`, `total=4`. This suite portion fails because `differ` is nonzero. A and B supply no successful-compilation evidence. A does not establish syntax rejection: the supplied observation is timeout, not a parser diagnostic. Even an unexplained pair of equal nonzero statuses would require more evidence before identifying the failure's cause.

To reconstruct the real job's exercised inputs, obtain the selected filenames and source identities for that run, or an adequately retained checkout plus the exact selection order and relevant filesystem state. The summary's total 36 does not itself name those sources. The selection rule takes the first `.c` file listed in each qualifying directory; it is not a promise to compile every `.c` file there. The compared outputs are text, not executed test programs.

**Common wrong path.** Counting A as `identical` confuses equality of statuses with equality of emitted files. Counting all nonzero statuses as mismatches ignores the explicit `both-fail` branch. Outside the supplied case C, a nonzero comparator result can also mean a comparison error, such as unreadable output; `differ` alone does not identify its cause.

**Answer-free reattempt.** Replace A with two equal nonzero statuses whose cause is unknown, remove B, and leave C and D unchanged. Recompute the counters and write the strongest supported sentence about each result category without calling any case a language-level rejection.

## Choose the next attempt from the error

If you chose the wrong artifact, redraw only the producer-to-output arrows before adding more stages. If the artifact was right but a result was overclaimed, attach the input, predicate, and evidence source to one sentence. If the recipe step was unclear, return to its source region and distinguish file selection from file content, and file content from execution.

When those distinctions are secure, put this sheet aside and try one of the changed cases without the hints. That gives you a new attempt to inspect; reading a complete solution alone does not demonstrate independent transfer.
