# Validation record

This manuscript checkpoint contains the first volume's complete draft paper
route: entry/motivation guides, nineteen teaching chapters, ninety-five
exercises with separate feedback, six mixed return checks and a compact
reference. The C volume now adds twenty-two teaching chapters, 167 exercises
with feedback and six four-question mixed checks. These are paper teaching
drafts, not validated execution guides or a completed multi-volume rewrite.

The [C16–C19 unit record](c-compiler/DRAFTS.md) describes its technical,
reading-flow and bounded reader checks. Earlier checkpoint records below
retain their original scope; the current control/program integration is
recorded separately near the end.

## Checks performed

The included checker is intentionally small and inspectable:

```sh
python3 books/check.py
```

It uses Python's standard library. It checks fifty-nine relevant source blob
identities, the static seed-byte count, selected excerpt tokens, all local
Markdown links and anchors, paired exercise IDs, complete original-chapter
inventory, and a bounded set of mathematical assertions for worked results.
The earlier C01–C15 document pass checked all local inline and reference-style links,
the 81-row source inventory, the prerequisite graph of all 77 teaching units
for cycles, 200 exercise pairs, thirty-five source blobs, all 63 library
colon-definition excerpts and bounded mathematical assertions. It also
checked all thirty-two primitive-reference names/body offsets and five complete
predicted capstone-entry byte strings. Those C additions checked the canonical
`tri.c` text, forty-nine complete named Forth excerpts, bounded C-unit paper calculations, all 444 infrastructure/representation/emission/parser definitions and the full 57-region /
325-declaration preprocessor source map, plus all 150 ELF/emitter declarations and 333 expression/declaration names. All preprocessor regions now have drafted explanatory homes; the
lexer and evaluator mechanisms have their own drafted chapters; later target
providers retain their separate teaching scope. The earlier units passed their smaller document passes. The exact source byte
sequence contains 1,772 bytes and has SHA-256
`697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e`.
That digest was calculated from source text; no executable was launched.

It does not execute source snippets. Run it in a checkout whose root files
match [the edition pin](EDITION.md); `--source-root PATH` allows a separately
materialized snapshot.

An independent document review compared the manuscript and solutions with
`000-seed.hex0` and `010-lib.fth`, concentrating on operand order, memory
widths, address/value roles, prerequisites and the scope of evidence. Findings
were corrected before the final checkpoint. Separate C-unit reviews checked
all 105 C exercises and changed cases, the mixed checks, actual
profile/load boundaries, all thirty-five infrastructure definitions and the
include-region, macro-lifetime, conditional/location, token, descriptor and
symbol/scope, encoding, fixup and runtime traces. The parser reviews checked
place identity, nine-cell metadata, recursive staging, precedence, short-circuit
phases, full expression/evaluator closure, declaration construction and partial
state at fatal boundaries. Reviews also verified local prerequisite bridges.
The source excerpts use plain
fences and do not add a second literate-source authority.

The canonical `book/` tree, root source, build scripts and `book.toml` are
unchanged. Remote tree comparison is the evidence for that boundary.

The repository's automatic push-triggered [Check run for the first milestone](https://github.com/delta9000/seed-forth/actions/runs/37416564070)
completed successfully at commit
`819de4d346c38623d8db741323bc92293273690a`. Both `check-all + verify` and
`mdbook build + links` passed. Those existing jobs exercise the canonical
repository and original literate book; they do not execute this new edition's
examples or render the separate `books/` tree. The six-chapter checkpoint also passed [its own Check run](https://github.com/delta9000/seed-forth/actions/runs/37417624921)
at commit `d63b29b3f7f563bafb0de6056309e70cc0964e41`. The ten-chapter
checkpoint passed [its separate Check run](https://github.com/delta9000/seed-forth/actions/runs/37419018142)
at `bff03516d3b7202bb2ecbb0457192ec61cb9d9eb`. The thirteen-chapter
checkpoint also passed [its Check run](https://github.com/delta9000/seed-forth/actions/runs/37420513780)
at `705e3f73a5f74c636b0f016d1e8f840acf6d747a`. The sixteen-chapter
checkpoint passed [its Check run](https://github.com/delta9000/seed-forth/actions/runs/37422538095)
at `030bb0c8e5c8805f889bc00c3f8bb165e3631bbf`. The complete first-volume
paper draft passed [its Check run](https://github.com/delta9000/seed-forth/actions/runs/37425847949)
at `e4ebf723dbe8a251e19906aaca90454c7b51aa57`. All 57 files of that
checkpoint were also retrieved and compared literally with the saved
manuscript text, in addition to Git-tree scope and blob-identity checks.
The C01–C03 checkpoint passed [its Check run](https://github.com/delta9000/seed-forth/actions/runs/37428414147)
at `b52175e665123da15bcef216a482daa471b4609f`; all 68 manuscript files
also passed literal remote-content comparison. Later checkpoints have their
own CI identity and must not inherit those results as a fresh run.
The C01–C05 preprocessor checkpoint passed [its Check run](https://github.com/delta9000/seed-forth/actions/runs/37429742852)
at `67d35652c230b0fe744be50b0f9fdb42977ccdd1`; all 73 manuscript files
also passed literal remote-content comparison.
The C01–C08 representation checkpoint passed [its Check run](https://github.com/delta9000/seed-forth/actions/runs/37432365973)
at `976f5a5fadbf49285ae800f61e217931a4848903`; all 80 manuscript files
also passed literal remote-content comparison.
The C01–C11 emission/runtime checkpoint passed [its Check run](https://github.com/delta9000/seed-forth/actions/runs/37436370123)
at `4ba55cabf64894a0a4b41149495ff04fb66006de`; all 88 manuscript files
also passed literal remote-content comparison.

The entry guide, motivation chapter, nineteen teaching chapters, reference,
solutions and mixed checks, plus the first fifteen C chapters and their feedback,
were converted from GitHub-flavored Markdown to
HTML with Pandoc 3.1.11.1 to check parseability. A local
headless Chromium layout check could not complete because the environment
refused its process-singleton socket. No browser screenshot inspection is
claimed; GitHub and published-book layout still need visual review.

The [byte audit ledger](seed-forth/AUDIT.md) partitions all 1,772 bytes into
76 source-checked regions. The audit manuscripts cover all 1,772 bytes:
S11 covers 186, S12 119, S13 70, S14 142, S15 816, S16 237, S17 34 and
S18 168. The displayed records include all 32 reconstructed dictionary
headers and all 338 decoded startup/body/helper instructions, along with the
ELF fields. The checker compares every displayed
byte to the pinned image and verifies exact, nonoverlapping coverage. GNU
readelf/objdump 2.44 independently supplied static decoding observations;
neither tool executed the seed. A complete region ledger does not establish
that the prose or program is correct on every input.

The C09 review independently composed and statically decoded nineteen selected
instruction groups totaling 433 bytes with GNU objdump 2.44. These groups are
data examples, not a coherent runnable program or a captured compiler dump.
All twenty-eight displayed ELF field rows were independently reconstructed
from the source append values and cover exactly 120 bytes. The runtime review
also checked every emitted-body length, the 376-byte eager block, five heap
RIP-relative targets and all supplied I/O cases. These observations complement
manual derivations; they do not execute the compiler or its output.

## Saved continuation draft checks

The separate C16–C18 save adds 25 paired main exercises, bringing the working
document check to 225 pairs. Local links and exercise IDs were checked across
the full saved tree. All six draft chapter/feedback files were converted from
GitHub-flavored Markdown to HTML with Pandoc and parsed, without a visual-layout
claim. Independent source/practice reviews passed for C16–C18, including all 25
main exercise sets and their changed cases. This is static manuscript evidence,
not compiler execution or proof that every possible input is handled correctly.

All three revised reading routes were independently checked for the
prerequisites of their assigned exercise parts. This does not establish
learning outcomes. The credited coverage inventory remains the reviewed
C01–C15 checkpoint until the later unit's review and integration are complete.
No implementation or canonical literate-source changes accompany this save.

## Continuous-story pilot

C01 and C18 were reorganized around a concrete prediction and its explanation,
with detailed profile/parser material afterward. Review compared the changed
prose with the pinned implementation, the previous numerical tables, source
excerpts and practice. The exact canonical `tri.c` remains present once;
the checker locates that full program independently of introductory C slices.
A newly added feedback sentence was corrected to distinguish a builder slot
claim from an emitted target instruction.

Two bounded simulated-reader roles attempted selected problems without their
solution files: a programmer without Forth background used C1-01–C1-03, and a
Forth reader new to C calling conventions used the C18 extra-local question,
C18-04 and C18-07. Their cited reasoning exposed no blocking missing premise
in those samples; minor terminology and premise clarifications followed.
These checks do not erase a model's prior knowledge, substitute for human
readers, or establish comprehension, retention, accessibility or transfer.

The saved C16–C18 checkpoint at `21d10f3cc33a6f114afa8b69e26cf219a7749f72`
passed its automatic [Check run](https://github.com/delta9000/seed-forth/actions/runs/37459033100).
The earlier C01–C15-only [run](https://github.com/delta9000/seed-forth/actions/runs/37458589506)
was cancelled when the next push superseded it, under the workflow's
cancel-in-progress policy. The successful run covers the canonical checks
already described; it does not execute these teaching exercises. Both saved
checkpoints were verified against complete file manifests and exact changed-file
remote readbacks, with no changes outside `books/`.

## Loop and switch reading-flow revision

C16 and C17 now place their first worked stories in reading order instead of
requiring jumps among reference sections. Independent checks compared the
reordered explanations with the pinned implementation and retained source
excerpts, tables, exercise prompts and numerical results. Corrections made
implementation choices explicit: C behavior constrains loop destinations but
does not force this compiler's physical layout; bodies-first switch emission
is one design; and C17's byte exercise stipulates replacement body regions,
rather than assigning those lengths to the introductory C statements.

C16's shared-lookahead counterexample is tied to the actual legacy `++r`
parser path, not assumed for the different `r = r + 1` fixture. Bounded
simulated-reader attempts covered loop destinations and a pending token,
then switch fallthrough, no-default behavior and cleanup. Post-correction
checks confirmed the cited premises were available. These model-assisted
checks are not fresh human trials or evidence of retention or transfer.

The preceding C01/C18 flow checkpoint at
`f4101d72fa5c7cf93d0bd015f03d63784e3a98af` passed its automatic
[Check run](https://github.com/delta9000/seed-forth/actions/runs/37464236418).
That run checks the canonical pipeline; it does not execute or render the
new teaching-book examples.

## Control, frames and complete paper-program integration

C16–C19 now form a continuous route through conditions and loops, switches
and labels, function frames, and translation-unit/process entry. Their 32
main exercises have separate hints, worked answers and changed cases. The
sixth mixed check contributes four further questions combining destinations,
cleanup, reader snapshots, unresolved uses and output placement.

Independent manuscript review checked all four chapters' mechanisms and
practice against the pinned source. For C19 this included all seven exercise
sets, hint-supplied intermediates and changed cases, not only the headline
556-byte result. A scope correction narrowed a question from every loop jump
to unresolved loop break/continue jumps; condition fields and known backward
jumps have different owners. Three out-of-range source locators were corrected,
and the checker now rejects source-line endpoints beyond their pinned files.

C19 begins with a complete small C program and derives its header, entry
stub, eager runtime prefix, 34-byte function, final patches and predicted
entry/return path. Detailed file-scope forms follow that first story. A bounded
simulated-reader attempt used only that story and an answer-free helper-before-
main problem; it obtained the changed coordinates without earlier-chapter
reading and identified an implicit source-order-emission premise. That premise
is now stated explicitly. This was a model-assisted dependency check, not a
human trial or an observed transfer outcome.

At the C19 checkpoint, the document checker covered 232 main exercise pairs, all 85 source-inventory
rows and the 77-unit prerequisite graph. The definition map accounts for 526
colon definitions across thirteen source files. The new control/program
companion adds all 160 declarations and ten top-level initialization, binding
or execution forms in `112`, `114`, `116` and `120`, with exact source spans
and current teaching anchors. Separate preprocessor, emission and expression/
declaration inventories retain their earlier complete counts. The checker also
compares C19's displayed entry/function bytes with an independent paper
construction and checks selected changed layouts. These are document and
arithmetic checks; no Forth word or generated instruction is executed.

The preceding loop/switch reading-flow checkpoint at
`764bdc4f4902d613145f361da6a7f33010dd37b4` passed its automatic
[Check run](https://github.com/delta9000/seed-forth/actions/runs/37474668625).
All 105 files in that saved checkpoint matched their complete manifest, all
seven changed contents were read back exactly, and the repository entries
outside `books/` were unchanged. Its CI covers the canonical pipeline, not the
new book's exercises or rendered layout.

## Stage-A recipe and evidence chapter

C20 follows the compiler executable into its next role as an M1 producer.
Independent review checked its complete recipe/reference account, eight main
tasks, 24 graduated hints, eight worked answers and eight answer-free changed
cases against actual pinned scripts and the identified CI record. Corrections
kept a nonzero comparison error distinct from a demonstrated byte difference,
separated the shell wrapper's removal from the Forth driver's open/truncate,
and specified a common hash algorithm for a digest-comparison exercise. A
Fibonacci locator was tightened to the exact nine source lines; the displayed
C block matches those lines.

A bounded simulated-reader attempt used only the continuous first story and
three changed records. It distinguished producer ELF sizes from output parity,
equal lengths from byte comparison, and acceptance of equal empty files from
useful compilation. Its questions led to an explicit absence of a nonempty-
output gate and simpler source-version language in the first story. This is
model-assisted text-dependency evidence, not a real-reader learning outcome.

The pipeline companion partitions all 273 lines of five pinned scripts into
33 source-annotated regions. This count is separate from the 526 Forth colon
definitions. At the C20 checkpoint, the document pass covered 240 main exercise pairs, 90
source-inventory rows, the 77-unit prerequisite graph, 48 project source blobs,
and 67 complete named C-compiler excerpts. The checker checks source-line
bounds and uses implementation `.fth` bodies, rather than historical narrative
fragments, as the authority for those Forth excerpts.

C20's observed comparison is explicitly attributed to
[run 37474668625](https://github.com/delta9000/seed-forth/actions/runs/37474668625)
and its [check-all + verify job](https://github.com/delta9000/seed-forth/actions/runs/37474668625/job/112306844449).
The surviving summary reports equality of `self-v1-amd64.M1` and
`self-ref-amd64.M1`, with 2,367,260 bytes. The relevant script contents match
the teaching pin. The chapter distinguishes that remote observation from
recipe inspection, old recorded hashes and new paper examples. Complete inner
transcripts and the compared binary/text artifacts were not retained in that
run's downloadable artifacts, so the book does not invent their measurements.
The later fixed-point summary also concerns M1 text, not equality of the v2
and v3 compiler ELFs. Separate cross-route ELF comparisons remain separately
named.

The preceding integrated C19 checkpoint at
`945282917f45cebf9e04d86492e7a64ef50393a8` passed its automatic
[Check run](https://github.com/delta9000/seed-forth/actions/runs/37478538502).
All 109 book files matched the saved manifest; all 15 changed contents were
read back exactly, with no repository changes outside `books/`. As before,
canonical CI builds the original `book/`, not these new teaching manuscripts.

## Assembler expansion and two-pass unit

C21/C22 follow one fragment from exact expanded text to label positions and
seven described output bytes, then derive the supplied 120-byte ELF envelope
and 148-byte long-jump fixture. The assembler does not manufacture that
envelope. Independent source/practice reviews checked all 99 declarations,
42 source regions, 22 main exercises, 66 graduated hints, their worked answers
and changed cases. C21 has ten answer-free changed prompts; C22 has four
separately listed changed reattempts alongside changes in its main tasks.

The reviews kept label-reference field-end subtraction separate from numeric
immediates, retained the unusual actual fit rules and four-byte bypass, and
separated the bootstrap source-built tool comparison from a different
GCC-default reference recipe. Recipe success was made conditional rather than
phrased as a newly witnessed event. The final source locators and correction
readbacks were checked before this checkpoint.

A bounded reader-role audit saved its C21 attempt before seeing C22. It
reconstructed both representations and identified prerequisites to make
explicit: character codes, the availability of only preceding definitions,
and the one-byte label range. These facts were added where needed. First-
session practice now stays with the one-byte puzzle; the absolute four-byte
exercise follows the sigil/emission session. This is model-assisted dependency
checking, not measured human learning, retention or transfer.

The C21/C22 snapshot's static checks covered 262 main exercise pairs, 91
source-inventory rows, 59 pinned project source blobs and 576 Forth definitions across fourteen files.
The new assembler companion verifies the complete 785-line partition, every
declaration, both initialization forms and current teaching anchors. The
checker also preserves the meaningful final space in the displayed expansion
and verifies selected raw slices, displacement/header arithmetic and the
thirteen-byte NUL-terminated output path. No Forth word, assembler, compiler
or generated instruction is executed by those checks.

The preceding C20 checkpoint at
`0549ca0e205d4eabc8386c5bac1de2013321e3ae` passed its automatic
[Check run](https://github.com/delta9000/seed-forth/actions/runs/37484530444).
All 112 book files matched its complete manifest and all twelve changed
contents were read back exactly; no repository entry outside `books/` changed.
That canonical CI result remains separate from the new assembler examples.

## Hybrid narrative and route plan

The hybrid plan maps all 77 stable teaching units to first stories, bridges,
retained depth, optional routes or capstones. It retains the 91 source
inventory rows and every current chapter/exercise. Direct GCC is the main
destination; M2/pnut/TinyCC executable ancestry is not imposed on it. Shared
native declaration/LP64 and initializer mechanisms remain in the direct
profile's planned teaching homes. The source pin is unchanged.

The initial hybrid-plan snapshot added a check of the narrative map against every declared
unit, draft status and current chapter path, in addition to the acyclic
full-depth prerequisite graph. Its nine additional pinned source blobs
brought that bounded identity check to 68 files. Those identity and line checks do
not establish complete implementation explanation or execution of those
newly linked scripts. Negative checks rejected an omitted unit, a planned
unit mislabeled drafted and a missing chapter path.

Separate read-only reviews checked the producer graph and the learning plan.
Corrections distinguished object-mode selection from initializer-queue
rejection, located musl-header installation before configuration, marked the
new H2 syntax bridge as planned and kept a supplied-length helper problem
separate from an existing fixture. That snapshot's route review accounted for all 77 units, including
42 drafted and 35 planned. These checks assess the plan's
consistency, not observed learner performance.

The C21/C22 checkpoint at
`0b7b2bd3fc64f2746249ac5194abf1506328fc0e` passed its automatic
[Check run](https://github.com/delta9000/seed-forth/actions/runs/37492966101).
All 117 manuscript files matched the saved manifest; all 15 changed contents
were read back exactly, and all 1,535 entries outside `books/` were unchanged.
The hybrid route's new setup cards and later fixtures are still planned;
that CI result does not execute them or assess the reading order.

## First-results and direct-profile entrances

The short [first-results entrance](FIRST-RESULTS.md) now supplies its Forth
stack/output and C function/return/process bridges, four prompts, graduated
hints, worked answers and separate changed checks. Source review verified
the exact Forth snippet, byte-store direction, output-versus-stack distinction,
exit-value boundary and supplied legacy layout calculations. A fresh-context
model-assisted attempt used only the page before feedback; its terminology
findings led to explicit displacement, byte and token bridges. These checks
do not establish actual novice learning.

[G01](gcc-toolchain/chapters/01-a-program-from-two-files.md) supplies a complete
bounded direct-profile entrance and seven original/changed exercise sets.
Its full source/practice review checked the selected 131 call provider,
LP64/scalar interfaces, explicit-addend relocation arithmetic, actual
runtime-aware startup, lazy archive inputs, driver options and failure phases.
The proposed two-file fixture and command card remain unexecuted. Qualitative
object records and the numerical placement model are identified as predictions
and illustration, rather than invented dumps or addresses of an observed file.

The G01 reader-role audit saved all seven page-only attempts before opening
feedback and then attempted two answer-free changes. It identified useful
local definitions for headers/preprocessing and hexadecimal byte pairs.
Those bridges are now in the chapter. Its successful model-based attempts
establish that the needed facts could be located in this text, not that
human readers will learn or retain them. The labeled changed cases are
supported application; a later mixed check must separately test selection
without naming the representation in its prompt.

Current document checks cover 269 chapter exercise pairs plus four entrance
pairs, 91 source rows, 77 stable units and 71 exact-pin project source blobs.
The 576-definition inventory retains its previous scope; G01's supplied
interfaces do not add complete implementation coverage for G02–G17. Static
checks also protect the exact new teaching inputs, selected displayed fields,
command spellings, and bounded relocation/alignment arithmetic. They do not
run the command card, its generated programs or the linker.

A separate local PDF layout pilot inspected all nine pages of FIRST-RESULTS
and its feedback. All 169 parsed text segments survived conversion, with no
clipped text, broken tables or missing glyphs found; the frozen manuscripts
were unchanged. This used Pandoc parsing plus a bounded ReportLab renderer
after the installed XeLaTeX path failed for missing format/configuration
files. It is not a validated general book-export pipeline. Relative Markdown
links were retained but are not portable PDF navigation, and the PDFs are
untagged. No G01 visual rendering or accessibility certification follows from
this limited pilot.

## Still unverified

- The seed and C teaching examples have not been executed for this edition
- No manual compiler, bootstrap, GCC-stage or Linux-boot reproduction was
  performed for the new chapters; the automatic canonical CI run above has
  its own narrower record
- Existing reported build comparisons remain attributed to their pinned
  source documentation, not newly reproduced observations
- No representative new reader has attempted the unit; learnability remains
  a reasoned design judgment awaiting reader feedback
- Screen-reader behavior, mobile presentation, complete PDF/EPUB export and
  published-book rendering have not been validated; the entrance-only local
  layout pilot above has a narrower scope
- Planned later chapters and volumes do not yet supply their promised entry
  artifacts, implementation walkthroughs or acceptance checks

## Next coherent unit

The next manuscript work opens G02's object records and complete writer
mechanisms, then the needed declaration, ABI, linker and runtime sessions
behind G01's supplied interfaces. The [hybrid narrative plan](HYBRID-NARRATIVE.md)
keeps the native/private-stack TinyCC application as an optional complete
route. Kernel work retains its own source, lineage and observed-boot
obligations. Fresh-start execution remains a separate validation task.
The [coverage map](COVERAGE.md) distinguishes that planned material from
the first volume's drafted mechanisms and its remaining verification work.
Execution checks need a named, authorized seed profile before their status
can change from derived to observed.
