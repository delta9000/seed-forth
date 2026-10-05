# Grouped direct declarators

Original binutils 2.30 `binutils/nm.c` declares its sorter table as

```c
static int (*(sorters[2][2])) (const void *, const void *) = { ... };
```

The bounded declarator profile (`cc-ngrouped-declarator`, book chapter 34)
read stars after a group's `(` and then expected the name, so the inner `(`
left the declarator without a name: error 203 at the table. Parentheses with
no star inside only group, so C gives this exactly the type of
`(*sorters[2][2])(...)`: a 2x2 array of function pointers.

`cc-ngroup-name` (`115-cc-native.fth`) reads such an inner group: an
identifier that is not a typedef name, its array suffixes, and `)`. The outer
group then continues as though those tokens had followed the name directly,
so every existing shape rule and signature record applies unchanged. It is
used by file-scope, local, parameter, member and typedef declarators alike.
Outside the profile, still rejected:

- a star inside the inner group, `int (*(*p))(void)` (238): a pointer to a
  function pointer needs the general nested declarator;
- array suffixes both inside and after the inner group,
  `int (*(s[2])[3])(void)` (238);
- a typedef name or non-identifier as the inner name (203), which in C would
  start an abstract parameter list instead.

`python3 tests/gcc/grouped-declarator-check.py`, registered in
`tests/gcc/check.sh`, builds `grouped-declarator.c` with the Forth driver and
with host GCC/glibc at `-O0`/`-O2` (strict C90, `-Werror`); the outputs must be
identical. The program covers the exact nm.c table with its initializer and
calls through every element, a file-scope array of grouped function pointers,
`int ((plain))`, `int *(pointers[2])`, a grouped 2x3 `long` matrix, a grouped
typedef, a grouped struct member, a function returning a pointer written
`*(locate)(int)`, a grouped array parameter, a grouped local and local array,
and `sizeof` of each table. The three rejected shapes must fail with their
codes. The original `nm.c` then compiles in the binutils stage-B build.
