# Final mixed return check

These tasks revisit the volume after [the capstone](../chapters/19-audit-synthesis-and-capstone.md).
They ask you to choose between similar-looking contracts: valid decimal text
and preserved integer value, a reported token and a rejected definition,
a jump and a return, and file bytes and process memory. Use the local
reference when needed; the answers are available below.

All results are paper derivations under the pinned seed profile. No command
or malformed program is executed by this check.

## R6-01 Valid digits can lose the mathematical value

The decimal token is `18446744073709551616`, exactly `2^64`. What value/flag
pair does the inspected parser return? What does `[lit]` do with that pair
in interpret mode and in compile mode? Is the token rejected as invalid
syntax, and has its exact unbounded integer value been preserved?

## R6-02 Reporting an unknown word is not rollback

An enclosing definition is being compiled: STATE is one, HERE is P, and
the compiling data stack is `[F]`, an older pending fixup. The outer loop
reads an unknown token. Trace what `find` contributes, what `report_token`
may clobber, and how the REPL restores the old data top. What happens to
STATE, HERE and F? If EOF arrives next, does exit status zero establish a
complete, validated definition?

## R6-03 Jump to the return instruction or jump past it

A word X has return destination K on its native return stack:
`R=[…,K]`. Its final RET instruction is stored at address T. Compare two
otherwise valid branch call sites: one has inline target T, the other has
inline target K. Follow the branch primitive's completed R state, then the
next instruction. Why is directly branching to K not equivalent to executing
X's RET? Assume the caller does not contain special code to compensate for
the extra frame; do not predict a particular crash.

## R6-04 A generated word is not saved in the seed file

In one process, the capstone creates `inc` and uses it successfully under
the stated contracts. That process ends. A fresh process then loads the
unchanged 1,772-byte seed file and receives `[lit] 5 inc`. Is `inc` present?
Which part of the earlier work lived only in process memory? What does
matching the original file's digest establish, and what does it fail to
establish about the generated word?

## Hints

- R6-01: Acceptance checks the digits; the accumulator still has only
  64 bits. Keep value and success flag separate
- R6-02: The miss path restores one old cached value after the reporting
  helper. Find the checks it does not perform
- R6-03: `branch` replaces only its own temporary return address; it does
  not consume X's older return destination
- R6-04: Distinguish the ELF file, its mapped bytes, and new dictionary
  entries created in the zero-filled memory beyond that file

## Answers and changed checks

### R6-01 answer

The parser returns `[0,U]`, where U is the all-ones success flag. Every
character is an accepted decimal digit, but the accumulator wraps at `2^64`.
Interpret-mode `[lit]` consumes the success flag and leaves zero. Compile
mode emits the ordinary call-to-`lit` plus an eight-byte zero cell, consuming
its temporary number. It does not reject the token or preserve the exact
unbounded integer.

For a changed check, use `18446744073709551615`. The returned value is U
and the returned success flag is also U: `[U,U]`. Equal bit patterns have
different roles in those two stack positions. The consumer still removes
only the flag.

### R6-02 answer

The reader adds its address/length pair, and `find` replaces that pair with
zero, leaving logical `[F,0]`. `report_token` requests a stdout diagnostic
and clobbers `rdi`; the REPL then explicitly reloads the older value from
`[rbp]` and advances `rbp` by eight. C is again `[F]`.
STATE stays one, HERE stays P, and the pending fixup is neither completed
nor discarded. The unknown word has been reported and skipped, not compiled
or rolled back. EOF then takes the `bye_code` path without validating STATE
or unresolved compilation work. A zero process status is not evidence of
a complete definition.

For a changed check, suppose valid remaining input supplies the matching
`then,` and semicolon. Those operations may close the existing structure,
but they still do not supply the unknown operation's intended behavior.
Checking only structural completion would miss that semantic omission.

### R6-03 answer

After either branch primitive completes, R is again `[…,K]`: the primitive
has consumed its own inline-slot return address and the replacement target.
With target T, execution reaches X's RET. That instruction removes K and
resumes the caller at K with the older R state restored.

With target K, execution instead resumes the caller directly while K still
remains on R. The control address looks right, but the call-state invariant
is wrong. A later action may expose the stale frame; an immediate process
exit might conceal it. Those possibilities do not make the two state
transitions equivalent.

For a changed check, add an owned temporary above K before either branch.
Even targeting T is now insufficient: that temporary must be removed before
X's RET, or it will be used as a return destination instead of K.

### R6-04 answer

The fresh process starts from the original dictionary and initial HERE.
The earlier `inc` header and body lived in runtime dictionary memory; they
were not written into the seed file. The new input pushes 5, then the
lookup of `inc` misses unless this new process has separately defined it.
Under the ordinary miss path, the older five survives the diagnostic and
no increment occurs.

Matching file digests provide strong evidence that the compared file bytes
match. A digest comparison alone is not a literal bytewise comparison. It does not serialize process memory, establish
that `inc` was created in this new process, or prove an execution result.
For a changed check, supply the definition and use in the same new input
stream. Now the later lookup can find the runtime entry; its predicted
behavior still depends on the compiler and execution contracts traced in
the capstone.

## Decide what the evidence says

For each answer, name the object and the property: token syntax, integer
representation, compilation state, call-state restoration, file identity or
execution behavior. Evidence about one is not automatically evidence about
the others. If a distinction failed, return to its first differing state and
try a changed case. A later independent attempt can check retention; this
book does not infer it merely because the explanation felt clear.
