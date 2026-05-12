# Bootstrap notes

Notes on how the hex0 → seed-forth → Forth C compiler → M2-Planet self-host chain got built, and which AI tools mattered.

Written by Claude Sonnet 4.6 from chat transcripts, git history, and log files. Ben Sandbrook guided the reconstruction and corrected what the model got wrong. Everything below is the AI's account of what the human actually did.

## Models that left commits

| Model | Harness | Where it showed up |
|-------|---------|--------------------|
| Claude Opus 4.7 (1M ctx) | Claude Code | Most of the C compiler, gate progression, M2-Planet self-host |
| Claude Sonnet 4.6 | Claude Code | Seed primitives, earlier phases |
| Gemini 3 Pro | Gemini CLI | Struct descriptor plumbing, handed off mid-session |
| DeepSeek 4 Pro / Flash | OpenCode | Autonomous C compiler patches |
| Qwen 3.6 35B-A3B | Custom swarm | Tournament judge, MoA aggregation |
| Gemma 4 31B-it | Custom swarm | Bulk parallel workers on local vLLM |
| MiniMax 2.7 | Ralph | The 4-iteration assembly loop for phases 1–7 |
| Kimi K2.6 | Various | Exploration |
| GPT-5.5 | Codex CLI | Exploration |

Harnesses, briefly:

- **Claude Code** did the load-bearing work: every gate, the bootstrap chain, the verification runs.
- **Ralph** ran four autonomous iterations on the assembly phases, carrying `.ralph-progress.md` forward across runs.
- **OpenCode, Codex CLI, Gemini CLI** were used for cross-model passes that Claude then reviewed.
- **The swarm** was a custom Python harness around 20 Gemma workers in isolated worktrees, with a Qwen judge running tournaments and MoA on top.
- **harness-cpp** existed but didn't ship anything for this project.

## The thing that actually settled it

The chain is verified end-to-end by a script that rebuilds the compiler with itself and checks that the output stops changing:

1. seed-forth compiles the M2-Planet monolith → v1, an ELF compiler binary.
2. v1 and a GCC-built reference both self-compile M2-Planet; their .M1 outputs must be byte-identical. Two different compilers, same output on the same input.
3. M1 + hex2 assemble v1's output into v2 — no GCC in v2's provenance.
4. v2 self-compiles M2-Planet. Assemble that into v3.
5. v3 self-compiles M2-Planet; its output must equal v2's. Fixed-point closure.
6. Every M2-Planet test source produces byte-identical assembly from v1 versus the GCC reference.

If any byte drifts, the script fails. `REPRODUCIBLE.md` froze the checksums on the day it closed.

"It compiles" doesn't mean much for a bootstrap. The signals that count are parity (your compiler agrees with the reference on the same input) and fixed-point closure (your compiler agrees with itself across rebuilds). Both are byte-level. Neither can be faked by a model writing plausible-looking code.

## Gates as the unit of work

The gate discipline wasn't the model's idea. After a few false starts on the C subset, Ben asked for "a plan for the C subset capable of compiling m2planet — gated so you can build incrementally." That framing held for the rest of the project.

The C compiler was built one feature at a time, each behind a passing test. No gate opened until the previous one's test was green.

```
G0   int main() { return N; }
G1   locals, arithmetic, precedence
G2   if/else, comparisons
G3   user functions, SysV ABI calls
G4   while/for
G5   arrays
G6   struct member access
G7   pointers, address-of
G8   string literals
G9   enum
G10  typedef
G11  function pointers
G12  hex literals
G13  nested includes
G14  switch/case/default with fall-through
M1a  built-in constants (__FILE__, __LINE__, …)
M1b  forward decls, globals, prototypes
M1   full struct/enum/typedef — nested, pointer fields
     + byte-identical M2-Planet self-host
```

G = compiler gate. M = milestone toward the M2-Planet self-host. Tracked
gate fixtures live in `tests/cc/G*.c` and `tests/cc/M1*.c`; the final
self-host milestone has no per-feature `.c` fixture — it is verified
end-to-end by `tests/cc/stage-a-check.sh`.

The swarm executor enforced this at the harness layer: every agent worked in its own git worktree, with `stage-a-check.sh` (a 5-second parity check against the GCC reference) gating each commit. Outputs that passed got merged; everything else was discarded silently. The Claude Code sessions worked on the main checkout and ran the same check on demand — same oracle, no automatic enforcement.

## Phase specs as memory

Each phase of the Forth base (1–7) got a markdown spec written up before any assembly. A new agent could read the spec and start producing useful work without the previous session's context.

This was tooling, not magic. LLMs forget. Putting intent in a file the next agent reads is the boring version of persistent memory, and it just works.

## What was tried and is harder to grade

**Parallel agent swarms.** Twenty Gemma 4 workers on local vLLM, each in its own worktree. Good for bulk "write more Forth" work that was already fully specified. The first swarm returned almost instantly and Ben caught it: "are the agents actually exploring at all?" They weren't — most were dying on a 2-minute timeout before producing anything useful. Fix was "switch to streaming mode and timeout only if they don't give you anything for more than 5 minutes, sometimes these things like to think." The pattern recurred: the swarm needed someone watching it to confirm it was actually doing work, not just returning.

**Tournament + MoA.** When the swarm produced 20 candidates, a Qwen judge ran round-robin to pick a winner, sometimes followed by Mixture-of-Agents synthesis (20 Gemma → 4 Qwen → 1 Gemma). Cleaner than reading 20 candidates by hand. Whether it produced commits that wouldn't have happened otherwise — probably some, hard to say which.

**Multi-model handoffs.** Sessions passed between models when one got stuck. Gemini started the struct descriptor work and Claude Opus finished it. DeepSeek ran autonomous passes that Claude reviewed. Different models, different blind spots — switching was usually a practical unsticking move rather than a planned strategy.

**Semantic workspace indexing.** `index_workspace.py`, `semantic_search.py`, `forth_outline.py`. Useful so agents didn't have to read every file. Not a strategy, just infrastructure.

(The per-phase markdown specs, the Ralph progress file, and the indexing scripts mentioned in this document lived in the working tree during development and aren't checked into this repo — they belong to the build process, not the artifact.)

## What it cost

The swarm/tournament/MoA stack took real effort to build and run. Looking back, it's not clear how much the chain actually needed it. The frontier-model work on Claude Opus was where the hard semantic problems got solved — ELF layout, fixup chains, byte-identical divergence — and the swarms handled bulk that was already well-specified, which turned out to be a smaller fraction of the work than expected.

## What it comes down to

Frontier model capability set the ceiling on what was possible. Gate tests and byte-identical fixed-point set the floor on what shipped.

The verification regime is the part worth stealing. The point isn't "have tests" — every project has tests. It's that byte-identical fixed-point is an oracle the agent cannot game. That converts AI output from a trust problem into a verification problem, and you don't need to trust the model if you can check the answer.

The swarms were fine. The handoffs were practical. The gates plus the bootstrap script are what made it real.
