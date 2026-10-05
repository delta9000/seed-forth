# Lexer source inputs

The exact scan.lex.l, scan_l.patch and yyin.patch bytes under recipe-reference/
come from fosslinux/live-bootstrap commit
b1ceced7ea8a819a26f23796f6dd7ae8496a33a4, at the matching paths:
https://github.com/fosslinux/live-bootstrap/tree/b1ceced7ea8a819a26f23796f6dd7ae8496a33a4/steps/flex-2.5.11

Their existing copyright and BSD-2-Clause headers are preserved verbatim.
The upstream license text is retained under recipe-reference/LICENSES/.
The SHA-256 pins in sources.json verify exact bytes, including those headers.
No extra header is inserted into scan.lex.l: its line numbers affect generated
C. This document supplies its commit provenance without changing the input.

scan.lex.l is live-bootstrap's restricted adaptation of the original scan.l,
not a claim of equivalent scanner behavior. It expands start-condition blocks,
uses explicit C-locale ranges, replaces push/pop states with BEGIN, drops
caseless/stack options and some REJECT/YYMORE detection, and adjusts actions
and the BOL interface. Its sole purpose here is to generate the temporary
scanner; flex-tmp then regenerates the patched original scan.l.

The build preserves scan.lex.l and writes scan-ascii.l with exactly one
change: U+0160 (Š) in Andrius Štikonas's copyright attribution becomes ASCII S.
Heirloom's wide I/O under LC_ALL=C rejects that UTF-8 character. Only the
attribution comment changes; scanner rules do not. The recipe verifies that
there is exactly one such letter and that the resulting bytes are ASCII,
and records both hashes and this rationale in report.json.

The two patch payloads are unchanged and applied with --fuzz=0. The historical
scan_l.patch applies with a minus-one-line offset; patch output is recorded.
The skeleton is derived from original flex.skl by original mkskel.sh and
checked against an independent Python escaping transform. No shipped parser
or scanner C is used as an input.

Preparation and build logic were transcribed from the read-only 2026-10-03
lexer-input-evidence/prepare-inputs.py, prepare-flex-source.py and
lexer-build/build-heirloom.py, build-flex.py. The source archives retain their
own notices and licenses. Heirloom's ordinary scanner library contains only
allprint, libmain, reject, yyless and yywrap; wide/EUC variants are untested.
