# Linux I/O contracts: hints and solutions

Return to [Chapter 7](../chapters/07-linux-io-contracts.md). These are checked paper derivations under the chapter's Linux/x86-64 contracts, not executed observations. Stack tops are at the right; `M=2^64`, `H=2^63`, and `U=M-1`. Model addresses do not establish usable memory in a live seed.

Choose a hint when useful, then compare the first differing state rather than only the final answer. After feedback, close the worked solution before attempting its changed case.

## S7-01 — Complete the bridge

**Hint 1.** `write` contributes three unused argument slots, followed by its syscall number. The caller has already supplied all three meaningful arguments.

**Hint 2.** Label from the right: the last value is `n`, not `f`. Argument `a` is the deepest of the six argument cells, not the deepest value on the entire stack.

**Worked solution.** Expand the source wrapper:

| Completed operation | Data stack |
|---|---|
| Start | `[99, 1, 5000, 3]` |
| First `[lit] 0` | `[99, 1, 5000, 3, 0]` |
| Second `[lit] 0` | `[99, 1, 5000, 3, 0, 0]` |
| Third `[lit] 0` | `[99, 1, 5000, 3, 0, 0, 0]` |
| `[lit] 1` | `[99, 1, 5000, 3, 0, 0, 0, 1]` |

Thus `a=1`, `b=5000`, `c=3`, `d=e=f=0`, and `n=1`. The kernel-entry registers are:

```text
rax = 1       syscall number
rdi = 1       descriptor
rsi = 5000    buffer address
rdx = 3       requested byte count
r10 = 0       unused argument 4
r8  = 0       unused argument 5
r9  = 0       unused argument 6
```

Assuming the kernel returns one, `syscall6` leaves `[99, 1]`. The last one is now an **actual transfer count**. The memory bytes at 5000–5002 remain `65 66 67`. The request reports accepting A; the remaining suffix is BC.

The descriptor's one refers to this process's output entry. The syscall number's one chooses the operation. Changing the descriptor does not change which syscall is selected; changing the syscall number does not redirect a write to another output.

**Common wrong path.** `[99, 1, 5000, 3, 1]` lacks padding. It is not a shorter valid spelling of the same seven-input contract. `syscall6` still expects all six argument cells plus the number.

**Changed case.** Assume descriptor 7 is an already-open writable destination in the paper model. Use `[99, 7, 5000, 3] write` and assume result three. Only `a` and kernel-entry `rdi` change to seven; `rax` remains one. The final stack is `[99, 3]`. Nothing in that result identifies the destination as a terminal or guarantees durable storage.

## S7-02 — Repair missing padding

**Hint 1.** There happens to be enough total stack depth in this example to supply seven cells. Count which seven the primitive will consume.

**Hint 2.** Four zeros, descriptor 7, and number 3 provide only six intended inputs. The older 99 becomes the unintended seventh input.

**Worked solution.** The proposed body produces:

```text
start               [99, 7]
first zero          [99, 7, 0]
second zero         [99, 7, 0, 0]
third zero          [99, 7, 0, 0, 0]
fourth zero         [99, 7, 0, 0, 0, 0]
number 3            [99, 7, 0, 0, 0, 0, 3]
roles               [ a, b, c, d, e, f, n]
```

Argument `a` becomes 99, so the request is to close descriptor 99. Seven becomes unused argument `b`. The older value is consumed, and a returning call leaves only `[result]`, not `[99, result]`. The mistake can affect an unintended external resource. We have no evidence about whether descriptor 99 is open, so we do not invent a kernel outcome.

Repair the body by adding the fifth padding zero:

```forth
: demo-close
  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 3 syscall6 ;
```

This teaching name duplicates the existing `close` wrapper. Its entry stack becomes `[99, 7, 0, 0, 0, 0, 0, 3]`, with `a=7` and five unused arguments. If the requested close succeeds, the returning stack is `[99, 0]`.

For `open`, the three meaningful arguments already occupy `a`, `b`, and `c`:

```text
start               [99, PATH, FLAGS, MODE]
first zero          [99, PATH, FLAGS, MODE, 0]
second zero         [99, PATH, FLAGS, MODE, 0, 0]
third zero          [99, PATH, FLAGS, MODE, 0, 0, 0]
number 2            [99, PATH, FLAGS, MODE, 0, 0, 0, 2]
```

The three zeros fill `d`, `e`, and `f`. `PATH`, `FLAGS`, and `MODE` are role labels in the trace, not newly defined Forth words. A returning call leaves `[99, result]`; the caller must classify that result before using it as a descriptor.

**Changed case.** An overpadded `write` adds four zeros and number one. Starting with `[99, 7, 5000, 3]`, its final input stack is `[99, 7, 5000, 3, 0, 0, 0, 0, 1]`. Now `a=5000`, `b=3`, `c=0`, and `d=e=f=0`. Descriptor 7 remains underneath as unwanted leftover data. A returning call leaves `[99, 7, result]`. More padding is not safer: exact positions determine the request.

## S7-03 — Interpret an error cell

**Hint 1.** Subtract the returned unsigned value from `M`. That difference gives the magnitude of its signed-negative interpretation.

**Hint 2.** `dup` keeps a copy of the result; `0<` consumes only the new top copy and replaces it with a flag. Review the unsigned division by `H` inside `0<`.

**Worked solution.** Let `E=18446744073709551607`. Since `M-E=9`, this cell represents signed -9. Its error number is nine, `EBADF`. Under the chapter's write contract, this is an error, not a count.

With the chapter's older value 99, the expanded trace is:

| Operation | Data stack afterward |
|---|---|
| Returned result | `[99, E]` |
| `dup` | `[99, E, E]` |
| `2^63`, first word inside `0<` | `[99, E, E, H]` |
| `/` | `[99, E, 1]` |
| First `0=` | `[99, E, 0]` |
| Second `0=` | `[99, E, U]` |

The true flag is the all-ones cell `U`; the original error cell remains below it. Detecting the sign has neither repaired the I/O failure nor converted E into a valid count. Using E as a count would ask for vastly more than the three-byte buffer's capacity. Using it to advance the buffer pointer would likewise be an invalid interpretation.

For a positive-count read from the chapter's ordinary file model, a returned zero indicates EOF: no new input bytes. With a zero-count request, zero may merely report that no bytes were requested. It does not establish that the file is at EOF. The request's count is necessary context for interpreting the same numeric result.

**Common wrong path.** Replacing the result with nine discards the sign distinction without handling it. Error number nine is a description of failure, not permission to claim that nine bytes moved.

**Changed case.** Construct the error-shaped cell for -4 with `[lit] 0 [lit] 4 -`. Its unsigned representation is 18446744073709551612; `dup 0<` again leaves the original cell and `U`. This is an arithmetic test, not evidence that a syscall failed. For result zero, the same classification produces `[99, 0, 0]`: preserved result zero and false negative-result flag. Zero still needs operation-specific interpretation.

## S7-04 — Finish a partial transfer on paper

**Hint 1.** A positive result advances the address and reduces the remaining count by the same number of bytes.

**Hint 2.** After result one, the next request begins at 5001 and asks for two bytes. Keep the descriptor unchanged.

**Worked solution.** Here is one defensible design for the stated buffer. It uses English control steps, not seed code:

1. Retain descriptor 1, current address 5000, and remaining count 3
2. If no bytes remain, report completion of the requested transfer
3. Otherwise make one write request using those retained values
4. If the result is negative, report the error and incomplete transfer; apply any recovery only under a separate, suitable policy
5. If the result is zero, report no progress and stop this attempt, rather than claiming completion or repeating without a plan
6. For a positive result within the requested count, add that result to the current address, subtract it from remaining, and reconsider step 2

Stopping and reporting is a valid error/no-progress policy for this exercise. A more elaborate design may wait or retry where appropriate, but must say when and why. It must not reinterpret errors as progress. A result larger than requested violates the expected count contract and should not be silently accepted by the design.

Trace the specified positive outcomes:

| Moment | Descriptor | Current/next address | Remaining | Accepted prefix |
|---|---:|---:|---:|---|
| Before first request | 1 | 5000 | 3 | Empty |
| After result 1 | 1 | 5001 | 2 | A |
| After result 2 | 1 | 5003 | 0 | ABC |

The requests are `(1, 5000, 3)` and `(1, 5001, 2)`. Address 5003 is the one-past-end cursor, not a byte to access in this three-byte model. At zero remaining, no further request is needed. The caller's retained state is separate from each wrapper call's consumed inputs.

Resending the original request would include A again. If that repeated request then accepted all three bytes, the combined accepted sequence would be AABC. The first successful byte was not undone when the first call returned early.

**Changed case.** Replace the second result with zero. The state remains descriptor 1, address 5001, remaining 2, accepted prefix A. Apply the no-progress decision; do not advance to 5003. If the second result is a negative error instead, the task is still incomplete and the earlier accepted A still counts as prior progress. Neither result authorizes claiming ABC was transferred.

## S7-05 — Keep status, count, and byte distinct

**Hint 1.** For exit status, separate the status argument from the low eight bits visible to the parent. For `key`, separate the syscall result from the scratch byte loaded afterward.

**Hint 2.** `key` tests equality with zero, not negativity. `emit` returns without checking the write result.

**Worked solution.** The independent cases are:

| Case | Derived outcome | Reason |
|---|---|---|
| `die` supplied 259 | Parent-visible status 3; no Forth return | Low eight bits retain `259-256` |
| `bye` | Parent-visible status 0; no Forth return | Primitive supplies status zero |
| `key` successfully reads NUL | Pushes 0 | Read count is one, then the loaded byte is zero |
| `key` gets a negative result; scratch remains 65 | Pushes 65 | Negative is nonzero, so it takes the scratch-load path |
| `emit` completes | No result cell certifies delivery | It discards the kernel result and restores the older data-stack top |

For the NUL case, the read's count one establishes a successful one-byte read, but `key` does not preserve that count. Its final zero is indistinguishable from the zero it supplies on EOF. For the error case, the specified scratch value 65 is an old byte; the returned character-shaped cell is not evidence of a new A arriving.

`die` and `bye` also do not leave an exit status on the Forth data stack for the next word. Successful termination prevents that next word from executing in this process. The parent-visible status is a different observation channel.

**Common wrong path.** “No result means no error” invents a guarantee. A word can omit a result precisely because its implementation ignored information the caller might have needed.

**Changed case.** With status 256, `die` reports zero to the parent because its low byte is zero. With status 511, it reports 255. For `key` with a read result of zero and scratch still containing 65, it pushes zero rather than 65: the zero-result branch does not load scratch. Contrast that with the specified negative-result case before reopening the source.

## Return to a contract

For a roles mistake, relabel the seven input cells before tracing registers. For a result mistake, write three separate labels: requested count, returned count or error, and stored byte. For a partial-transfer mistake, preserve the accepted prefix and derive the remaining suffix.

At a later session, try the zero-progress changed case and the NUL-versus-error comparison without these answers. A correct supported trace and an independent later explanation are different checks. Neither this solution sheet nor a paper prediction claims that the examples have been executed or that reader learning has been measured.
