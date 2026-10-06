/* seed-cc -- native replacement for tools/gcc-direct-cc.py.

   A gcc-like command for the Forth C compiler.  Like the Python driver it
   only parses arguments, snapshots and hashes the compiler inputs, writes
   the Forth input stream and publishes outputs; the seed itself does all
   preprocessing, compilation, object writing, archiving and linking.  For
   every accepted command the seed receives byte-for-byte the stream the
   Python driver builds, so objects, archives, executables and -E output
   are identical.  See tools/SEED-CC.md.

   Compiled by the Forth C compiler only: tools/seed-cc-start.fth builds it
   from the seed, after which seed-cc can rebuild itself. */
#include "seed-tool.h"

#define VERSION "seed-forth direct C compiler (experimental)"
#define TARGET "x86_64-pc-linux-gnu"
#define RUNTIME "runtime/gcc-seed"
/* Fixed per-translation-unit arena, as in the Python driver: 21 MiB. */
#define ARENA_BYTES 22020096L

/* As in the Python driver, a source file and each -I directory reach the
   preprocessor as spelled on the command line, so __FILE__ is GCC's
   spelling; -Werror=implicit-function-declaration sets the compiler's
   implicit-call error (228) and the preprocessor line map. */

static char *root;

enum { MODE_LINK, MODE_COMPILE, MODE_PREPROCESS };
enum { LANG_NONE, LANG_C, LANG_LIBRARY };
enum { QUERY_NONE, QUERY_VERSION, QUERY_DUMPMACHINE, QUERY_HASH };
enum { KIND_C, KIND_O, KIND_A, KIND_STDIN, KIND_MATH };

struct arg_input {
    char *spelling;
    int language;
};

struct options {
    int mode;
    char *output;
    struct names includes;
    struct buf macros;
    int have_macros;
    struct arg_input *inputs;
    unsigned long ninputs;
    struct names libraries;
    int verbose, nostdinc, nostdlib, query, implicit_error;
};

static void add_input(struct options *o, char *spelling, int language)
{
    struct arg_input *p = (struct arg_input *)st_alloc((o->ninputs + 1) * sizeof(struct arg_input));
    unsigned long i;
    for (i = 0; i < o->ninputs; i = i + 1)
        p[i] = o->inputs[i];
    p[o->ninputs].spelling = spelling;
    p[o->ninputs].language = language;
    if (o->inputs)
        free(o->inputs);
    o->inputs = p;
    o->ninputs = o->ninputs + 1;
}

static void usage_fail(const char *message) { st_fail(2, message); }

static int ident_char(int c, int first)
{
    if (c == '_' || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'))
        return 1;
    return !first && c >= '0' && c <= '9';
}

/* Python re \s for str patterns, over UTF-8: ASCII whitespace, the
   information separators, and the Unicode spaces str.isspace() accepts. */
static int space_at(const char *s, unsigned long *n)
{
    const unsigned char *p = (const unsigned char *)s;
    if ((p[0] >= 9 && p[0] <= 13) || p[0] == ' ' || (p[0] >= 28 && p[0] <= 31)) {
        *n = 1;
        return 1;
    }
    if (p[0] == 0xc2 && (p[1] == 0x85 || p[1] == 0xa0)) {
        *n = 2;
        return 1;
    }
    if (p[0] == 0xe1 && p[1] == 0x9a && p[2] == 0x80) {
        *n = 3;
        return 1;
    }
    if (p[0] == 0xe2 && p[1] == 0x80 && ((p[2] >= 0x80 && p[2] <= 0x8a) || p[2] == 0xa8 || p[2] == 0xa9 || p[2] == 0xaf)) {
        *n = 3;
        return 1;
    }
    if (p[0] == 0xe2 && p[1] == 0x81 && p[2] == 0x9f) {
        *n = 3;
        return 1;
    }
    if (p[0] == 0xe3 && p[1] == 0x80 && p[2] == 0x80) {
        *n = 3;
        return 1;
    }
    return 0;
}

static const char *skip_space(const char *s)
{
    unsigned long n;
    while (space_at(s, &n))
        s = s + n;
    return s;
}

static const char *skip_ident(const char *s)
{
    if (!ident_char((unsigned char)*s, 1))
        return 0;
    s = s + 1;
    while (ident_char((unsigned char)*s, 0))
        s = s + 1;
    return s;
}

/* IDENT(?:\(\s*(?:IDENT(?:\s*,\s*IDENT)*)?\s*\))?\Z */
static int macro_spelling(const char *s)
{
    s = skip_ident(s);
    if (!s)
        return 0;
    if (*s == 0)
        return 1;
    if (*s != '(')
        return 0;
    s = skip_space(s + 1);
    if (*s != ')') {
        s = skip_ident(s);
        if (!s)
            return 0;
        for (;;) {
            const char *t = skip_space(s);
            if (*t != ',')
                break;
            t = skip_ident(skip_space(t + 1));
            if (!t)
                return 0;
            s = t;
        }
        s = skip_space(s);
        if (*s != ')')
            return 0;
    }
    return s[1] == 0;
}

static int all_ident(const char *s)
{
    const char *e = skip_ident(s);
    return e && *e == 0;
}

/* checked_path: the preprocessor's path buffer bounds. */
static char *checked_path(char *path, int directory)
{
    if (strlen(path) > (unsigned long)(directory ? 253 : 254))
        st_fail2(1, "path exceeds the Forth preprocessor limit: ", path);
    return path;
}

static void parse(int argc, char **argv, struct options *o)
{
    int mode_seen = 0;
    int index = 1;
    int language = LANG_NONE;
    memset(o, 0, sizeof *o);
    o->mode = MODE_LINK;
    b_init(&o->macros);
    while (index < argc) {
        char *arg = argv[index];
        index = index + 1;
        if (strcmp(arg, "--") == 0) {
            while (index < argc) {
                add_input(o, argv[index], language);
                index = index + 1;
            }
            break;
        }
        if (strcmp(arg, "-c") == 0 || strcmp(arg, "-E") == 0) {
            int m = arg[1] == 'c' ? MODE_COMPILE : MODE_PREPROCESS;
            if (mode_seen && o->mode != m)
                usage_fail("-c and -E cannot be combined");
            mode_seen = 1;
            o->mode = m;
        } else if (strcmp(arg, "--version") == 0 || strcmp(arg, "-dumpmachine") == 0
                   || strcmp(arg, "--print-source-hash") == 0) {
            int q = arg[2] == 'v' ? QUERY_VERSION : arg[1] == 'd' ? QUERY_DUMPMACHINE : QUERY_HASH;
            if (o->query && o->query != q)
                usage_fail("conflicting information options");
            o->query = q;
        } else if (strcmp(arg, "-v") == 0)
            o->verbose = 1;
        else if (strcmp(arg, "-static") == 0 || strcmp(arg, "-O0") == 0 || strcmp(arg, "-g0") == 0)
            ; /* These describe the actual static, unoptimized, no-debug output. */
        else if (strcmp(arg, "-nostdinc") == 0)
            o->nostdinc = 1;
        else if (strcmp(arg, "-nostdlib") == 0)
            o->nostdlib = 1;
        else if (strcmp(arg, "-Werror=implicit-function-declaration") == 0)
            o->implicit_error = 1;
        else if (arg[0] == '-' && arg[1] == 'x') {
            char *value;
            if (arg[2] == 0) {
                if (index == argc)
                    usage_fail("missing argument to -x");
                value = argv[index];
                index = index + 1;
            } else
                value = arg + 2;
            if (strcmp(value, "c") == 0)
                language = LANG_C;
            else if (strcmp(value, "none") == 0)
                language = LANG_NONE;
            else
                st_fail2(2, "unsupported language: ", value);
        } else if (arg[0] == '-' && (arg[1] == 'o' || arg[1] == 'I' || arg[1] == 'D'
                                     || arg[1] == 'U' || arg[1] == 'L' || arg[1] == 'l')) {
            char flag[3];
            char *value = arg + 2;
            flag[0] = '-';
            flag[1] = arg[1];
            flag[2] = 0;
            if (!*value) {
                if (index == argc)
                    st_fail2(2, "missing argument to ", flag);
                value = argv[index];
                index = index + 1;
            }
            if (strchr(value, '\n') || strchr(value, '\r'))
                st_fail(2, st_cat3("invalid newline or NUL in ", flag, " argument"));
            if (flag[1] == 'o') {
                if (o->output)
                    usage_fail("multiple output options");
                o->output = value;
            } else if (flag[1] == 'I') {
                if (strcmp(value, "-") == 0)
                    usage_fail("-I- is unsupported");
                /* Keep the spelling: it prefixes __FILE__ for headers found here. */
                n_add(&o->includes, checked_path(value, 1));
            } else if (flag[1] == 'L')
                n_add(&o->libraries, st_pabs(value));
            else if (flag[1] == 'l')
                add_input(o, value, LANG_LIBRARY);
            else {
                char *equals = strchr(value, '=');
                unsigned long n = equals ? (unsigned long)(equals - value) : strlen(value);
                char *name = (char *)st_alloc(n + 1);
                memcpy(name, value, n);
                name[n] = 0;
                if (flag[1] == 'U') {
                    if (equals || !all_ident(name))
                        st_fail2(2, "invalid -U argument: ", value);
                    b_str(&o->macros, "#undef ");
                    b_str(&o->macros, name);
                    b_str(&o->macros, "\n");
                } else {
                    if (!macro_spelling(name))
                        st_fail2(2, "unsupported -D macro spelling: ", name);
                    b_str(&o->macros, "#define ");
                    b_str(&o->macros, name);
                    b_str(&o->macros, " ");
                    b_str(&o->macros, equals ? equals + 1 : "1");
                    b_str(&o->macros, "\n");
                }
                o->have_macros = 1;
            }
        } else if (arg[0] == '-' && arg[1] != 0)
            st_fail2(2, "unsupported option: ", arg);
        else
            add_input(o, arg, language);
    }
    if (o->query) {
        if (o->ninputs)
            usage_fail("information options cannot be combined with inputs");
        return;
    }
    if (o->mode != MODE_LINK) {
        unsigned long i, j = 0;
        for (i = 0; i < o->ninputs; i = i + 1)
            if (o->inputs[i].language != LANG_LIBRARY) {
                o->inputs[j] = o->inputs[i];
                j = j + 1;
            }
        o->ninputs = j;
    }
    if (!o->ninputs) {
        if (o->verbose)
            return;
        usage_fail("no input files");
    }
    if (o->mode != MODE_LINK && o->output && o->ninputs != 1)
        usage_fail("a single -o requires one input with -c or -E");
    if (o->mode != MODE_PREPROCESS && o->output && strcmp(o->output, "-") == 0)
        usage_fail("binary output to standard output is unsupported");
}

/* ------------------------------------------------------------- inputs */

static int layer_name(const char *n)
{
    unsigned long len = strlen(n);
    return len >= 11 && n[0] >= '0' && n[0] <= '9' && n[1] >= '0' && n[1] <= '9'
        && n[2] >= '0' && n[2] <= '9' && memcmp(n + 3, "-cc-", 4) == 0
        && st_ends(n, ".fth");
}

static void runtime_walk(const char *relative, struct names *out)
{
    char *dir = st_cat3(root, "/", relative);
    struct names entries;
    unsigned long i;
    if (st_list_dir(dir, &entries) < 0) {
        free(dir);
        return;
    }
    for (i = 0; i < entries.count; i = i + 1) {
        char *rel = st_cat3(relative, "/", entries.items[i]);
        char *full = st_cat3(root, "/", rel);
        struct st_stat s;
        const char *suffix = st_psuffix(rel);
        if (st_lstat(full, &s) == 0 && (s.mode & ST_S_IFMT) == ST_S_IFDIR)
            runtime_walk(rel, out);
        else if (st_is_file(full) && (strcmp(suffix, ".c") == 0 || strcmp(suffix, ".h") == 0))
            n_add(out, st_strdup(rel));
        free(full);
    }
}

/* input_names(): the sorted compiler, seed, driver and runtime sources. */
static void input_names(struct names *out)
{
    struct names top, all;
    unsigned long i;
    char *archive;
    memset(&all, 0, sizeof all);
    n_add(&all, "000-seed.hex0");
    n_add(&all, "seed-forth");
    n_add(&all, "010-lib.fth");
    n_add(&all, "tools/seed-cc.c");
    n_add(&all, "tools/seed-tool.h");
    if (st_list_dir(root, &top) == 0)
        for (i = 0; i < top.count; i = i + 1)
            if (layer_name(top.items[i]) && strcmp(top.items[i], "120-cc-main.fth") != 0)
                n_add(&all, top.items[i]);
    archive = st_cat3(root, "/", "141-archive.fth");
    if (st_is_file(archive))
        n_add(&all, "141-archive.fth");
    free(archive);
    runtime_walk(RUNTIME, &all);
    n_sort(&all);
    memset(out, 0, sizeof *out);
    for (i = 0; i < all.count; i = i + 1)
        if (i == 0 || strcmp(all.items[i], all.items[i - 1]) != 0)
            n_add(out, all.items[i]);
}

/* JSON string as json.dumps(ensure_ascii=True) writes it. */
static void b_json(struct buf *b, const char *s)
{
    const unsigned char *p = (const unsigned char *)s;
    const char *hex = "0123456789abcdef";
    b_chr(b, '"');
    while (*p) {
        unsigned long c = *p, extra = 0, k;
        if (c == '"' || c == '\\') {
            b_chr(b, '\\');
            b_chr(b, (int)c);
            p = p + 1;
            continue;
        }
        if (c >= 32 && c < 127) {
            b_chr(b, (int)c);
            p = p + 1;
            continue;
        }
        if (c == '\n') { b_str(b, "\\n"); p = p + 1; continue; }
        if (c == '\r') { b_str(b, "\\r"); p = p + 1; continue; }
        if (c == '\t') { b_str(b, "\\t"); p = p + 1; continue; }
        if (c == 8) { b_str(b, "\\b"); p = p + 1; continue; }
        if (c == 12) { b_str(b, "\\f"); p = p + 1; continue; }
        if (c >= 0xc2 && c < 0xe0) { extra = 1; c = c & 31; }
        else if (c >= 0xe0 && c < 0xf0) { extra = 2; c = c & 15; }
        else if (c >= 0xf0 && c < 0xf5) { extra = 3; c = c & 7; }
        for (k = 1; k <= extra; k = k + 1)
            if ((p[k] & 0xc0) != 0x80)
                extra = 0;
        if (c < 128 && extra == 0 && *p < 128) {
            /* Control character. */
        } else if (extra == 0) {
            c = 0xdc00 + *p; /* surrogateescape */
        } else {
            for (k = 1; k <= extra; k = k + 1)
                c = c * 64 + (p[k] & 63);
        }
        if (c >= 0x10000) {
            unsigned long v = c - 0x10000, hi = 0xd800 + (v >> 10), lo = 0xdc00 + (v & 1023);
            b_str(b, "\\u");
            b_chr(b, hex[(hi >> 12) & 15]); b_chr(b, hex[(hi >> 8) & 15]);
            b_chr(b, hex[(hi >> 4) & 15]); b_chr(b, hex[hi & 15]);
            c = lo;
        }
        b_str(b, "\\u");
        b_chr(b, hex[(c >> 12) & 15]); b_chr(b, hex[(c >> 8) & 15]);
        b_chr(b, hex[(c >> 4) & 15]); b_chr(b, hex[c & 15]);
        p = p + 1 + extra;
    }
    b_chr(b, '"');
}

/* ---------------------------------------------------------- toolchain */

struct toolchain {
    struct names names;
    struct buf *data;
    char (*hashes)[65];
    char identity[65];
    char *work;
    char *seed;
    char *runtime;
    struct names compiler;
};

static struct toolchain tc;

static long input_index(const char *name)
{
    unsigned long i;
    for (i = 0; i < tc.names.count; i = i + 1)
        if (strcmp(tc.names.items[i], name) == 0)
            return (long)i;
    return -1;
}

static struct buf *input_data(const char *name)
{
    long i = input_index(name);
    if (i < 0)
        st_fail2(1, "missing compiler input: ", name);
    return &tc.data[i];
}

static int is_compiler_layer(const char *n)
{
    return layer_name(n) && strcmp(n, "140-cc-link.fth") != 0;
}

static void mkdirs_for(const char *path)
{
    char *parent = st_pparent(path);
    if (!st_is_dir(parent)) {
        long r;
        mkdirs_for(parent);
        r = st_mkdir(parent, 0777);
        if (r < 0 && r != -17)
            st_fail_os(r, parent, 0);
    }
    free(parent);
}

static void toolchain_init(char *work)
{
    struct names again;
    struct buf json;
    unsigned long i;
    long r;
    input_names(&tc.names);
    tc.data = (struct buf *)st_alloc(tc.names.count * sizeof(struct buf));
    tc.hashes = (char (*)[65])st_alloc(tc.names.count * 65);
    for (i = 0; i < tc.names.count; i = i + 1) {
        char *path = st_cat3(root, "/", tc.names.items[i]);
        st_read_file(path, &tc.data[i]);
        free(path);
    }
    input_names(&again);
    if (again.count != tc.names.count)
        st_fail(1, "compiler inputs changed while taking the snapshot; retry");
    for (i = 0; i < tc.names.count; i = i + 1) {
        char *path;
        struct buf now;
        if (strcmp(again.items[i], tc.names.items[i]) != 0)
            st_fail(1, "compiler inputs changed while taking the snapshot; retry");
        path = st_cat3(root, "/", tc.names.items[i]);
        st_read_file(path, &now);
        if (now.len != tc.data[i].len || memcmp(now.data, tc.data[i].data, now.len) != 0)
            st_fail(1, "compiler inputs changed while taking the snapshot; retry");
        b_free(&now);
        free(path);
    }
    /* Verify the existing executable against hex0 source. */
    st_check_seed(input_data("000-seed.hex0"), input_data("seed-forth"), "");
    b_init(&json);
    b_chr(&json, '{');
    for (i = 0; i < tc.names.count; i = i + 1) {
        st_sha256(tc.data[i].data, tc.data[i].len, tc.hashes[i]);
        if (i)
            b_str(&json, ", ");
        b_json(&json, tc.names.items[i]);
        b_str(&json, ": \"");
        b_str(&json, tc.hashes[i]);
        b_chr(&json, '"');
    }
    b_chr(&json, '}');
    st_sha256(json.data, json.len, tc.identity);
    b_free(&json);
    tc.work = work;
    tc.seed = st_cat3(work, "/", "seed-forth");
    {
        struct buf *seed = input_data("seed-forth");
        st_write_file(tc.seed, seed->data, seed->len, 0600);
        r = st_chmod(tc.seed, 0700);
        if (r < 0)
            st_fail_os(r, tc.seed, 0);
    }
    tc.runtime = st_cat3(work, "/", "runtime");
    for (i = 0; i < tc.names.count; i = i + 1) {
        const char *name = tc.names.items[i];
        if (strncmp(name, RUNTIME "/", strlen(RUNTIME) + 1) == 0) {
            char *path = st_cat3(tc.runtime, "/", name + strlen(RUNTIME) + 1);
            mkdirs_for(path);
            st_write_file(path, tc.data[i].data, tc.data[i].len, 0666);
            free(path);
        }
    }
    memset(&tc.compiler, 0, sizeof tc.compiler);
    n_add(&tc.compiler, "010-lib.fth");
    for (i = 0; i < tc.names.count; i = i + 1)
        if (is_compiler_layer(tc.names.items[i]))
            n_add(&tc.compiler, tc.names.items[i]);
}

/* Encode data as Forth bytes; never interpolate a pathname as source. */
static void encoded(struct buf *b, const char *name, const char *data, unsigned long n)
{
    unsigned long i;
    b_str(b, "create ");
    b_str(b, name);
    b_str(b, "\n");
    for (i = 0; i < n; i = i + 1) {
        b_str(b, "[lit] ");
        b_dec(b, (unsigned char)data[i]);
        b_str(b, " c,\n");
    }
}

static void path_word(struct buf *b, const char *name, const char *path)
{
    encoded(b, name, path, strlen(path) + 1);
}

static void indexed_name(char *out, const char *prefix, unsigned long i)
{
    struct buf t;
    b_init(&t);
    b_str(&t, prefix);
    b_dec(&t, (long)i);
    memcpy(out, t.data, t.len + 1);
    b_free(&t);
}

/* Run the seed on the named modules, the driver text and SOURCE. */
static void forth(struct names *modules, const struct buf *driver, const char *source, unsigned long nsource)
{
    struct buf program, out, err;
    unsigned long i;
    long status;
    b_init(&program);
    for (i = 0; i < modules->count; i = i + 1) {
        struct buf *m = input_data(modules->items[i]);
        if (i)
            b_chr(&program, '\n');
        b_add(&program, m->data, m->len);
    }
    b_chr(&program, '\n');
    b_add(&program, driver->data, driver->len);
    b_add(&program, source, nsource);
    status = st_run_seed(tc.work, tc.seed, &program, &out, &err);
    b_free(&program);
    if (err.len)
        st_write_all(2, err.data, err.len);
    if (out.len)
        st_write_all(2, out.data, out.len);
    if (status)
        st_fail(status > 0 ? (int)status : 1, "Forth compilation/link failed");
    if (out.len)
        st_fail(1, "unexpected Forth output; no result published");
    b_free(&out);
    b_free(&err);
}

static void compile_unit(const char *source, unsigned long nsource, char *source_name,
                         const char *output, struct names *includes, struct buf *macros,
                         int preprocess, int implicit_error)
{
    struct buf d;
    unsigned long i;
    checked_path(source_name, 0);
    b_init(&d);
    b_str(&d, "cc-sysv-object-enable\n[lit] ");
    b_dec(&d, ARENA_BYTES);
    b_str(&d, " cc-arena-map\n");
    if (implicit_error)
        b_str(&d, "true cc-sysv-implicit-error ! true cc-pp-line-map-on !\n");
    b_str(&d, "cc-io-direct-workspace cc-prep-direct-workspace\n"
              "cc-om-direct-workspace cc-label-direct-workspace\n"
              "cc-obj-direct-workspace cc-gfixup-direct-workspace\n");
    path_word(&d, "driver-output", output);
    path_word(&d, "driver-source", source_name);
    b_str(&d, "driver-source [lit] ");
    b_dec(&d, (long)strlen(source_name));
    b_str(&d, " cc-prep-source-name\n");
    for (i = 0; i < includes->count; i = i + 1) {
        char name[40];
        checked_path(includes->items[i], 1);
        indexed_name(name, "driver-inc-", i);
        path_word(&d, name, includes->items[i]);
        b_str(&d, name);
        b_str(&d, " [lit] ");
        b_dec(&d, (long)strlen(includes->items[i]));
        b_str(&d, " cc-prep-add-include\n");
    }
    if (macros && macros->len) {
        encoded(&d, "driver-macros", macros->data, macros->len);
        /* Forth processes real directives after target predefines. Reset
           the output/line counters so command-line options add no lines. */
        b_str(&d, ": driver-predefines cc-target-predefines\n");
        b_str(&d, "driver-macros cc-prep-src-addr !\n");
        b_str(&d, "[lit] ");
        b_dec(&d, (long)macros->len);
        b_str(&d, " cc-prep-src-len !\n");
        b_str(&d, "[lit] 0 cc-prep-src-pos ! true cc-prep-in-file !\n");
        b_str(&d, "cc-pp-scan [lit] 0 cc-pp-out-pos ! [lit] 1 cc-src-line ! ;\n");
        b_str(&d, "' driver-predefines is cc-prep-target-fwd\n");
    }
    if (preprocess) {
        b_str(&d, "variable driver-fd variable driver-done\n");
        b_str(&d, ": driver-main cc-load-stdin cc-preprocess\n");
        b_str(&d, "driver-output [lit] 577 [lit] 384 open dup 0< if, [lit] 22 cc-die then, driver-fd !\n");
        b_str(&d, "begin, driver-done @ cc-src-len @ < while,\n");
        b_str(&d, "driver-fd @ cc-src-buf driver-done @ + cc-src-len @ driver-done @ - write\n");
        b_str(&d, "dup [lit] 0 [lit] 4 - = if, drop else, dup [lit] 0 <= if, [lit] 22 cc-die then, driver-done +! then, repeat,\n");
        b_str(&d, "driver-fd @ close if, [lit] 22 cc-die then, bye ;\n");
    } else {
        b_str(&d, ": driver-main cc-load-stdin cc-preprocess cc-out-init cc-globals-init\n");
        b_str(&d, "cc-sysv-object-program driver-output cc-obj-write bye ;\n");
    }
    b_str(&d, "driver-main\n");
    forth(&tc.compiler, &d, source, nsource);
    b_free(&d);
}

static void base_modules(struct names *m)
{
    memset(m, 0, sizeof *m);
    n_add(m, "010-lib.fth");
    n_add(m, "020-cc-arena.fth");
    n_add(m, "030-cc-io.fth");
}

/* ---------------------------------------------------- runtime objects */

static const char *sysrt_names[7] = { "syscall", "errno", "start", "frame", "sigreturn", "setjmp", "longjmp" };
static const char *sysrt_builders[7] = {
    "cc-sysrt-object", "cc-sysrt-errno-object", "cc-sysrt-runtime-start-object",
    "cc-sysrt-frame-object", "cc-sysrt-sigreturn-object", "cc-sysrt-setjmp-object",
    "cc-sysrt-longjmp-object"
};

/* Top-level runtime C sources except math.c, sorted. */
static void runtime_sources(struct names *out)
{
    unsigned long i;
    memset(out, 0, sizeof *out);
    for (i = 0; i < tc.names.count; i = i + 1) {
        const char *name = tc.names.items[i];
        const char *rest = name + strlen(RUNTIME) + 1;
        if (strncmp(name, RUNTIME "/", strlen(RUNTIME) + 1) == 0 && !strchr(rest, '/')
            && strcmp(st_psuffix(rest), ".c") == 0 && strcmp(rest, "math.c") != 0)
            n_add(out, (char *)rest);
    }
}

static void runtime_object_names(struct names *out)
{
    struct names sources;
    unsigned long i;
    runtime_sources(&sources);
    memset(out, 0, sizeof *out);
    for (i = 0; i < sources.count; i = i + 1) {
        char *stem = st_pstem(sources.items[i]);
        n_add(out, st_cat3(stem, ".o", ""));
        free(stem);
    }
    for (i = 0; i < 7; i = i + 1)
        n_add(out, st_cat3(sysrt_names[i], ".o", ""));
}

/* Cache manifest: "seed-cc runtime cache 1\nidentity ID\n" then one
   "SHA256 NAME\n" line per object, in link order. */
static void manifest_text(struct buf *m, struct names *names, char (*hashes)[65])
{
    unsigned long i;
    b_init(m);
    b_str(m, "seed-cc runtime cache 1\nidentity ");
    b_str(m, tc.identity);
    b_str(m, "\n");
    for (i = 0; i < names->count; i = i + 1) {
        b_str(m, hashes[i]);
        b_str(m, " ");
        b_str(m, names->items[i]);
        b_str(m, "\n");
    }
}

/* Parse a manifest; fills HASHES for NAMES.  Returns 1 when it matches. */
static int manifest_read(const char *cache, struct names *names, char (*hashes)[65])
{
    char *path = st_cat3(cache, "/", "manifest");
    struct buf m, expect;
    unsigned long i, at;
    int ok = 0;
    if (st_try_read(path, &m) < 0) {
        free(path);
        return 0;
    }
    free(path);
    /* Recover the hashes from the fixed layout, then require that the whole
       manifest re-renders byte-identically. */
    at = 0;
    while (at < m.len && m.data[at] != '\n')
        at = at + 1;
    at = at + 1;
    while (at < m.len && m.data[at] != '\n')
        at = at + 1;
    at = at + 1;
    for (i = 0; i < names->count; i = i + 1) {
        if (at + 65 > m.len)
            break;
        memcpy(hashes[i], m.data + at, 64);
        hashes[i][64] = 0;
        while (at < m.len && m.data[at] != '\n')
            at = at + 1;
        at = at + 1;
    }
    if (i == names->count) {
        manifest_text(&expect, names, hashes);
        ok = expect.len == m.len && memcmp(expect.data, m.data, m.len) == 0;
        b_free(&expect);
    }
    b_free(&m);
    return ok;
}

static int cache_verified(const char *cache, struct names *names, char (*hashes)[65])
{
    unsigned long i;
    if (!manifest_read(cache, names, hashes))
        return 0;
    for (i = 0; i < names->count; i = i + 1) {
        char *path = st_cat3(cache, "/", names->items[i]);
        struct buf data;
        char h[65];
        long r = st_try_read(path, &data);
        free(path);
        if (r < 0)
            return 0;
        st_sha256(data.data, data.len, h);
        b_free(&data);
        if (strcmp(h, hashes[i]) != 0)
            return 0;
    }
    return 1;
}

static void runtime_build(const char *build)
{
    struct names sources, modules;
    struct buf d;
    unsigned long i;
    struct names includes;
    runtime_sources(&sources);
    memset(&includes, 0, sizeof includes);
    n_add(&includes, st_cat3(tc.runtime, "/", "include"));
    for (i = 0; i < sources.count; i = i + 1) {
        char *source = st_cat3(tc.runtime, "/", sources.items[i]);
        char *stem = st_pstem(sources.items[i]);
        char *object = st_cat3(build, "/", stem);
        char *output = st_cat3(object, ".o", "");
        struct buf *data = input_data(st_cat3(RUNTIME, "/", sources.items[i]));
        compile_unit(data->data, data->len, source, output, &includes, 0, 0, 0);
        free(source);
        free(stem);
        free(object);
        free(output);
    }
    b_init(&d);
    for (i = 0; i < 7; i = i + 1) {
        char *word = st_cat3(sysrt_names[i], "-path", "");
        char *object = st_cat3(build, "/", sysrt_names[i]);
        char *output = st_cat3(object, ".o", "");
        path_word(&d, word, output);
        b_str(&d, sysrt_builders[i]);
        b_str(&d, " ");
        b_str(&d, word);
        b_str(&d, " cc-obj-write\n");
        free(word);
        free(object);
        free(output);
    }
    b_str(&d, "bye\n");
    base_modules(&modules);
    n_add(&modules, "081-cc-object.fth");
    n_add(&modules, "122-cc-sysv-runtime.fth");
    forth(&modules, &d, "", 0);
    b_free(&d);
}

/* Copy verified objects into WORK/runtime-objects, checking each copy. */
static void runtime_copy(const char *from, struct names *names, char (*hashes)[65], const char *private_dir)
{
    unsigned long i;
    long r = st_mkdir(private_dir, 0777);
    if (r < 0)
        st_fail_os(r, private_dir, 0);
    for (i = 0; i < names->count; i = i + 1) {
        char *path = st_cat3(from, "/", names->items[i]);
        char *copy = st_cat3(private_dir, "/", names->items[i]);
        struct buf data;
        char h[65];
        st_read_file(path, &data);
        st_sha256(data.data, data.len, h);
        if (strcmp(h, hashes[i]) != 0)
            st_fail(1, "runtime cache changed during read; retry");
        st_write_file(copy, data.data, data.len, 0666);
        b_free(&data);
        free(path);
        free(copy);
    }
}

/* Content-addressed cache in ROOT/build-out/seed-cc-cache/IDENTITY.
   A verified entry is copied privately and verified again.  Otherwise the
   objects are rebuilt in a private .build-* staging directory, copied
   privately, and the staging directory is renamed into place; a concurrent
   winner, or a damaged entry, is never overwritten. */
static struct names *runtime_objects(struct names *paths)
{
    char *build_out = st_cat3(root, "/", "build-out");
    char *cache_root = st_cat3(build_out, "/", "seed-cc-cache");
    char *cache = st_cat3(cache_root, "/", tc.identity);
    char *private_dir = st_cat3(tc.work, "/", "runtime-objects");
    struct names names;
    char (*hashes)[65];
    unsigned long i;
    long r;
    r = st_mkdir(build_out, 0777);
    if (r < 0 && !(r == -17 && st_is_dir(build_out)))
        st_fail_os(r, build_out, 0);
    r = st_mkdir(cache_root, 0777);
    if (r < 0 && !(r == -17 && st_is_dir(cache_root)))
        st_fail_os(r, cache_root, 0);
    runtime_object_names(&names);
    hashes = (char (*)[65])st_alloc(names.count * 65);
    if (cache_verified(cache, &names, hashes))
        runtime_copy(cache, &names, hashes, private_dir);
    else {
        long error = 0;
        char *build = st_mkdtemp_in(cache_root, ".build-", &error);
        struct buf manifest;
        if (!build)
            st_fail_os(error, cache_root, 0);
        st_track_dir(build);
        runtime_build(build);
        for (i = 0; i < names.count; i = i + 1) {
            char *path = st_cat3(build, "/", names.items[i]);
            struct buf data;
            st_read_file(path, &data);
            st_sha256(data.data, data.len, hashes[i]);
            b_free(&data);
            free(path);
        }
        manifest_text(&manifest, &names, hashes);
        {
            char *path = st_cat3(build, "/", "manifest");
            st_write_file(path, manifest.data, manifest.len, 0666);
            free(path);
        }
        b_free(&manifest);
        runtime_copy(build, &names, hashes, private_dir);
        r = st_rename(build, cache);
        if (r < 0) {
            if (!st_exists(cache))
                st_fail_os(r, build, cache);
            st_rm_rf(build);
        }
        st_untrack_dir(build);
    }
    memset(paths, 0, sizeof *paths);
    for (i = 0; i < names.count; i = i + 1)
        n_add(paths, st_cat3(private_dir, "/", names.items[i]));
    return paths;
}

/* Keep startup eager so its main reference precedes user archives. All
   remaining runtime members are selected by the Forth linker only when an
   unresolved symbol needs them. */
static char *runtime_archive(struct names *objects, const char *name)
{
    char *output = st_cat3(tc.work, "/", name);
    struct names modules;
    struct buf d;
    unsigned long i;
    b_init(&d);
    b_str(&d, "arc-init\n");
    path_word(&d, "driver-runtime-archive", output);
    for (i = 0; i < objects->count; i = i + 1) {
        char word[48];
        if (strcmp(st_pname(objects->items[i]), "start.o") == 0)
            continue;
        indexed_name(word, "driver-runtime-member-", i);
        path_word(&d, word, objects->items[i]);
        b_str(&d, word);
        b_str(&d, " arc-add-object\n");
    }
    b_str(&d, "driver-runtime-archive arc-write bye\n");
    base_modules(&modules);
    n_add(&modules, "140-cc-link.fth");
    n_add(&modules, "141-archive.fth");
    forth(&modules, &d, "", 0);
    b_free(&d);
    return output;
}

/* Fallback after explicit -L search; never search host directories. */
static char *math_archive(void)
{
    char *archive = st_cat3(tc.work, "/", "libm.a");
    char *source = st_cat3(tc.runtime, "/", "math.c");
    char *header = st_cat3(tc.runtime, "/", "include/math.h");
    char *output = st_cat3(tc.work, "/", "math.o");
    struct names includes, objects;
    struct buf data;
    if (st_exists(archive))
        return archive;
    if (!st_is_file(source) || !st_is_file(header))
        st_fail(2, "-lm requires the source-built math.c and math.h");
    memset(&includes, 0, sizeof includes);
    n_add(&includes, st_cat3(tc.runtime, "/", "include"));
    st_read_file(source, &data);
    compile_unit(data.data, data.len, source, output, &includes, 0, 0, 0);
    b_free(&data);
    memset(&objects, 0, sizeof objects);
    n_add(&objects, output);
    return runtime_archive(&objects, "libm.a");
}

static void link_objects(struct names *objects, const char *output)
{
    struct names modules;
    struct buf d;
    unsigned long i;
    int archives = 0;
    for (i = 0; i < objects->count; i = i + 1)
        if (strcmp(st_psuffix(objects->items[i]), ".a") == 0)
            archives = 1;
    if (archives && input_index("141-archive.fth") < 0)
        st_fail(2, "archive input requires the Forth 141-archive.fth layer");
    b_init(&d);
    b_str(&d, "lnk-init\n");
    for (i = 0; i < objects->count; i = i + 1) {
        char word[40];
        indexed_name(word, "driver-obj-", i);
        path_word(&d, word, objects->items[i]);
        b_str(&d, word);
        b_str(&d, strcmp(st_psuffix(objects->items[i]), ".a") == 0 ? " lnk-add-archive\n" : " lnk-add-object\n");
    }
    b_str(&d, "create driver-entry s, _start\ndriver-entry [lit] 6 lnk-entry\n");
    path_word(&d, "driver-output", output);
    b_str(&d, "driver-output lnk-link bye\n");
    base_modules(&modules);
    n_add(&modules, "140-cc-link.fth");
    if (archives)
        n_add(&modules, "141-archive.fth");
    forth(&modules, &d, "", 0);
    b_free(&d);
}

/* Sibling private temporary plus rename: preserve an existing destination
   on errors, and do not follow destination symlinks during publication. */
static void publish(const char *source, const char *destination, long mode)
{
    long mask = st_umask_value(), fd = -17, r;
    char *parent = st_pparent(destination);
    char *temporary = 0;
    struct buf data;
    int attempt;
    st_read_file(source, &data);
    for (attempt = 0; attempt < 100 && fd == -17; attempt = attempt + 1) {
        char name[16];
        char *base;
        st_random_name(name, 8);
        base = st_cat3(".seed-cc-", name, "");
        if (temporary)
            free(temporary);
        temporary = st_cat3(parent, "/", base);
        free(base);
        fd = st_open(temporary, ST_O_RDWR | ST_O_CREAT | ST_O_EXCL | ST_O_CLOEXEC, 0600);
    }
    if (fd < 0)
        st_fail_os(fd, temporary, 0);
    st_clean_file = temporary;
    r = st_write_fd_all((int)fd, data.data, data.len);
    if (r == 0)
        r = st_fchmod((int)fd, mode & ~mask);
    if (r == 0)
        r = st_fsync((int)fd);
    if (r < 0) {
        st_close((int)fd);
        st_fail_os(r, temporary, 0);
    }
    st_close((int)fd);
    r = st_rename(temporary, destination);
    if (r < 0)
        st_fail_os(r, temporary, destination);
    st_clean_file = 0;
    free(temporary);
    free(parent);
    b_free(&data);
}

/* ------------------------------------------------------------------ main */

struct input {
    char *path;
    char *spelling;
    int kind;
    struct buf data;
};

int main(int argc, char **argv)
{
    struct options o;
    struct input *inputs;
    unsigned long ninputs = 0, i, j;
    int stdin_seen = 0;
    struct names destinations, protected_paths, names, includes, objects, results;
    char *work;
    st_prog = "seed-forth-cc";
    st_os_status = 1;
    parse(argc, argv, &o);
    if (o.query == QUERY_VERSION) {
        st_puts(1, VERSION "\nTarget: " TARGET "\nStatic Linux AMD64 LP64; bounded C/runtime subset\n");
        return 0;
    }
    if (o.query == QUERY_DUMPMACHINE) {
        st_puts(1, TARGET "\n");
        return 0;
    }
    if (o.verbose) {
        st_puts(2, VERSION "\nTarget: " TARGET "\n");
        if (!o.ninputs && !o.query)
            return 0;
    }
    root = st_find_root();
    inputs = (struct input *)st_alloc((o.ninputs + 1) * sizeof(struct input));
    for (i = 0; i < o.ninputs; i = i + 1) {
        char *spelling = o.inputs[i].spelling;
        int language = o.inputs[i].language;
        struct input *in = &inputs[ninputs];
        b_init(&in->data);
        if (language == LANG_LIBRARY) {
            char *file = st_cat3("lib", spelling, ".a");
            char *found = 0;
            for (j = 0; j < o.libraries.count && !found; j = j + 1) {
                char *candidate = st_pjoin(o.libraries.items[j], file);
                if (st_is_file(candidate))
                    found = candidate;
                else
                    free(candidate);
            }
            if (!found) {
                struct buf m;
                if (strcmp(spelling, "m") == 0) {
                    in->path = st_cat3(root, "/" RUNTIME "/", "math.c");
                    in->kind = KIND_MATH;
                    ninputs = ninputs + 1;
                    continue;
                }
                b_init(&m);
                b_str(&m, "library -l");
                b_str(&m, spelling);
                b_str(&m, " (lib");
                b_str(&m, spelling);
                b_str(&m, ".a) not found; searched directories: ");
                if (!o.libraries.count)
                    b_str(&m, "(none)");
                for (j = 0; j < o.libraries.count; j = j + 1) {
                    if (j)
                        b_str(&m, ", ");
                    b_str(&m, o.libraries.items[j]);
                }
                st_fail(2, m.data);
            }
            in->path = found;
            in->kind = KIND_A;
            st_read_file(found, &in->data);
        } else if (strcmp(spelling, "-") == 0) {
            char *cwd;
            if (stdin_seen || (language != LANG_C && o.mode != MODE_PREPROCESS))
                st_fail(2, "stdin requires -x c (or -E), and can occur only once");
            stdin_seen = 1;
            cwd = st_cwd();
            in->path = st_pjoin(cwd, "<stdin>");
            in->kind = KIND_STDIN;
            st_read_fd(0, &in->data);
        } else {
            char *path = st_pabs(spelling);
            const char *suffix = st_psuffix(path);
            if (language == LANG_C || strcmp(suffix, ".c") == 0)
                in->kind = KIND_C;
            else if (strcmp(suffix, ".o") == 0)
                in->kind = KIND_O;
            else if (strcmp(suffix, ".a") == 0)
                in->kind = KIND_A;
            else
                st_fail(2, st_cat3("unsupported input type: ", spelling, "; use -x c for C"));
            if ((in->kind == KIND_O || in->kind == KIND_A) && o.mode != MODE_LINK)
                st_fail(2, "object/archive inputs require link mode");
            in->path = path;
            in->spelling = spelling;
            st_read_file(path, &in->data);
        }
        ninputs = ninputs + 1;
    }
    memset(&destinations, 0, sizeof destinations);
    if (o.mode == MODE_LINK && ninputs)
        n_add(&destinations, st_pabs(o.output ? o.output : "a.out"));
    else if (o.mode == MODE_COMPILE)
        for (i = 0; i < ninputs; i = i + 1) {
            if (o.output)
                n_add(&destinations, st_pabs(o.output));
            else {
                char *stem = st_pstem(inputs[i].path);
                n_add(&destinations, st_pabs(st_cat3(stem, ".o", "")));
                free(stem);
            }
        }
    else if (o.output && strcmp(o.output, "-") != 0)
        n_add(&destinations, st_pabs(o.output));
    memset(&protected_paths, 0, sizeof protected_paths);
    for (i = 0; i < ninputs; i = i + 1)
        n_add(&protected_paths, inputs[i].path);
    input_names(&names);
    for (i = 0; i < names.count; i = i + 1)
        n_add(&protected_paths, st_cat3(root, "/", names.items[i]));
    {
        char *self = st_self_exe();
        if (self)
            n_add(&protected_paths, self);
    }
    for (i = 0; i < destinations.count; i = i + 1) {
        char *destination = destinations.items[i];
        char *resolved = st_resolve(destination);
        char *parent;
        for (j = 0; j < i; j = j + 1) {
            char *earlier = st_resolve(destinations.items[j]);
            if (strcmp(earlier, resolved) == 0)
                st_fail(2, "multiple inputs select the same output pathname");
            free(earlier);
        }
        for (j = 0; j < protected_paths.count; j = j + 1) {
            char *other = st_resolve(protected_paths.items[j]);
            if (strcmp(resolved, other) == 0
                || (st_exists(destination) && st_exists(protected_paths.items[j])
                    && st_samefile(destination, protected_paths.items[j])))
                st_fail2(2, "output aliases an input: ", destination);
            free(other);
        }
        parent = st_pparent(destination);
        if (!st_is_dir(parent) || st_is_dir(destination))
            st_fail2(1, "output directory is missing or output is a directory: ", destination);
        free(parent);
        free(resolved);
    }
    work = st_mkdtemp("seed-gcc-");
    st_track_dir(work);
    toolchain_init(work);
    if (o.query == QUERY_HASH) {
        st_puts(1, tc.identity);
        st_puts(1, "\n");
        st_finish(0);
    }
    includes = o.includes;
    if (!o.nostdinc)
        n_add(&includes, st_cat3(tc.runtime, "/", "include"));
    memset(&objects, 0, sizeof objects);
    memset(&results, 0, sizeof results);
    for (i = 0; i < ninputs; i = i + 1) {
        struct input *in = &inputs[i];
        struct buf name;
        char *output;
        if (in->kind == KIND_MATH) {
            n_add(&objects, math_archive());
            continue;
        }
        b_init(&name);
        b_str(&name, "input-");
        b_dec(&name, (long)i);
        b_str(&name, in->kind == KIND_A ? ".a" : ".o");
        output = st_cat3(work, "/", name.data);
        b_free(&name);
        if (in->kind == KIND_O || in->kind == KIND_A)
            st_write_file(output, in->data.data, in->data.len, 0666);
        else
            compile_unit(in->data.data, in->data.len, in->kind == KIND_STDIN ? "" : in->spelling,
                         output, &includes, o.have_macros ? &o.macros : 0,
                         o.mode == MODE_PREPROCESS, o.implicit_error);
        n_add(&objects, output);
        n_add(&results, output);
    }
    if (o.mode == MODE_LINK) {
        char *program = st_cat3(work, "/", "program");
        if (!o.nostdlib) {
            struct names runtime, ordered;
            runtime_objects(&runtime);
            memset(&ordered, 0, sizeof ordered);
            for (i = 0; i < runtime.count; i = i + 1)
                if (strcmp(st_pname(runtime.items[i]), "start.o") == 0)
                    n_add(&ordered, runtime.items[i]);
            for (i = 0; i < objects.count; i = i + 1)
                n_add(&ordered, objects.items[i]);
            n_add(&ordered, runtime_archive(&runtime, "libseed.a"));
            objects = ordered;
        }
        link_objects(&objects, program);
        memset(&results, 0, sizeof results);
        n_add(&results, program);
    }
    if (o.mode == MODE_PREPROCESS && !destinations.count) {
        for (i = 0; i < results.count; i = i + 1) {
            struct buf data;
            st_read_file(results.items[i], &data);
            st_write_all(1, data.data, data.len);
            b_free(&data);
        }
    } else
        for (i = 0; i < results.count && i < destinations.count; i = i + 1)
            publish(results.items[i], destinations.items[i], o.mode == MODE_LINK ? 0777 : 0666);
    st_finish(0);
    return 0;
}
