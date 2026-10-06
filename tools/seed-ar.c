/* seed-ar -- native replacement for tools/gcc-direct-ar.py.

   Deterministic GNU ar archives built entirely by seed Forth
   (141-archive.fth); this program only checks arguments, snapshots inputs
   and publishes.  Accepted operations:

     rc[u][s][D] ARCHIVE OBJECT...   create ARCHIVE when it does not exist
     r[u][s][D]  ARCHIVE OBJECT...   the same, saying "creating ARCHIVE"
     s[D] ARCHIVE                    validate the already-present index

   Fresh creation produces exactly the bytes gcc-direct-ar.py produces.
   Unlike the Python adapter, r on an existing archive updates it as GNU ar
   does: an input whose basename equals a member's name replaces the first
   such member in place, every other input is appended, and the whole
   archive (index included) is then rewritten by Forth.  Members carry no
   dates, so `u` (replace only newer files) always replaces, like GNU ar in
   its deterministic mode.  See tools/SEED-CC.md. */
#include "seed-tool.h"

static char *root;
static const char *layers[5] = {
    "010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth", "140-cc-link.fth", "141-archive.fth"
};

static void value_fail(const char *message) { st_fail(2, message); }

/* Path word with space separators, as gcc-direct-ar.py writes it. */
static void path_word(struct buf *b, const char *name, const char *path)
{
    unsigned long i, n = strlen(path);
    if (n == 0 || n > 4069)
        value_fail("invalid or overlong path");
    b_str(b, "create ");
    b_str(b, name);
    b_str(b, " ");
    for (i = 0; i < n; i = i + 1) {
        b_str(b, "[lit] ");
        b_dec(b, (unsigned char)path[i]);
        b_str(b, " c, ");
    }
    b_str(b, "[lit] 0 c,\n");
}

struct member {
    char *name;
    const char *data;
    unsigned long size;
    struct buf owned;
};

static unsigned long field(const char *p, int width)
{
    unsigned long v = 0;
    int i;
    for (i = 0; i < width && p[i] >= '0' && p[i] <= '9'; i = i + 1)
        v = v * 10 + (unsigned long)(p[i] - '0');
    for (; i < width; i = i + 1)
        if (p[i] != ' ')
            return (unsigned long)-1;
    return v;
}

/* Members of a regular GNU ar archive, without its "/" index. */
static struct member *archive_members(const char *path, const struct buf *a, unsigned long *count)
{
    struct member *m = 0;
    unsigned long n = 0, at = 8, cap = 0;
    const char *longs = 0;
    unsigned long nlongs = 0;
    char *bad = st_cat3("existing output is not a GNU ar archive: ", path, "");
    if (a->len < 8 || memcmp(a->data, "!<arch>\n", 8) != 0)
        value_fail(bad);
    while (at < a->len) {
        const char *h = a->data + at;
        unsigned long size;
        const char *body;
        if (at + 60 > a->len || h[58] != '`' || h[59] != '\n')
            value_fail(bad);
        size = field(h + 48, 10);
        if (size == (unsigned long)-1 || size > a->len - at - 60)
            value_fail(bad);
        body = h + 60;
        if (h[0] == '/' && h[1] == ' ')
            ; /* the symbol index is rebuilt */
        else if (h[0] == '/' && h[1] == '/' && h[2] == ' ') {
            longs = body;
            nlongs = size;
        } else {
            char *name;
            unsigned long len = 0;
            if (h[0] == '/') {
                unsigned long off = field(h + 1, 15);
                if (!longs || off == (unsigned long)-1 || off >= nlongs)
                    value_fail(bad);
                while (off + len + 1 < nlongs && !(longs[off + len] == '/' && longs[off + len + 1] == '\n'))
                    len = len + 1;
                if (off + len + 1 >= nlongs)
                    value_fail(bad);
                name = (char *)st_alloc(len + 1);
                memcpy(name, longs + off, len);
            } else {
                while (len < 16 && h[len] != '/')
                    len = len + 1;
                if (len == 0 || len == 16)
                    value_fail(bad);
                name = (char *)st_alloc(len + 1);
                memcpy(name, h, len);
            }
            name[len] = 0;
            if (n == cap) {
                struct member *p;
                unsigned long i;
                cap = cap ? cap * 2 : 16;
                p = (struct member *)st_alloc(cap * sizeof(struct member));
                for (i = 0; i < n; i = i + 1)
                    p[i] = m[i];
                if (m)
                    free(m);
                m = p;
            }
            m[n].name = name;
            m[n].data = body;
            m[n].size = size;
            b_init(&m[n].owned);
            n = n + 1;
        }
        at = at + 60 + size + (size & 1);
    }
    *count = n;
    return m;
}

/* Publish DATA at OUTPUT: exclusively for a fresh archive (a racing output
   is never replaced), by atomic rename for an update. */
static void publish(const char *output, const struct buf *data, int replace)
{
    long mask = st_umask_value(), fd = -17, r;
    char *parent = st_pparent(output);
    char *temporary = 0;
    int attempt;
    for (attempt = 0; attempt < 100 && fd == -17; attempt = attempt + 1) {
        char name[16];
        char *base;
        st_random_name(name, 8);
        base = st_cat3(".seed-ar-", name, "");
        temporary = st_cat3(parent, "/", base);
        free(base);
        fd = st_open(temporary, ST_O_RDWR | ST_O_CREAT | ST_O_EXCL | ST_O_CLOEXEC, 0600);
    }
    if (fd < 0)
        st_fail_os(fd, temporary, 0);
    st_clean_file = temporary;
    r = st_write_fd_all((int)fd, data->data, data->len);
    if (r == 0)
        r = st_fchmod((int)fd, 0666 & ~mask);
    if (r == 0)
        r = st_fsync((int)fd);
    st_close((int)fd);
    if (r < 0)
        st_fail_os(r, temporary, 0);
    r = replace ? st_rename(temporary, output) : st_link(temporary, output);
    if (r < 0)
        st_fail_os(r, temporary, output);
    if (replace)
        st_clean_file = 0;
    st_finish(0);
}

int main(int argc, char **argv)
{
    const char *flags;
    int create, check, update = 0, has_r = 0, has_c = 0, has_s = 0, has_u = 0, i;
    char *output, *work, *seed, *private_output;
    struct buf snapshot[9];
    const char *names[9];
    int nnames = 0;
    struct buf code, out, err, result;
    struct member *members = 0;
    unsigned long nmembers = 0, k;
    struct buf *payloads;
    char **payload_names;
    int ninputs = argc - 3 > 0 ? argc - 3 : 0;
    long status;
    st_prog = "gcc-direct-ar";
    st_os_status = 2;
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        st_puts(1, "gcc-direct-ar: Forth indexed archive adapter 1\n");
        return 0;
    }
    if (argc < 3)
        value_fail("usage: gcc-direct-ar.py rc[s][D] ARCHIVE OBJECT... | s[D] ARCHIVE");
    flags = argv[1];
    if (flags[0] == '-')
        flags = flags + 1;
    for (i = 0; flags[i]; i = i + 1) {
        int *seen = flags[i] == 'r' ? &has_r : flags[i] == 'c' ? &has_c : flags[i] == 's' ? &has_s
                  : flags[i] == 'u' ? &has_u : 0;
        if (strchr(flags + i + 1, flags[i]) || (!seen && flags[i] != 'D'))
            value_fail("supported operations: rc[u][s][D] fresh creation, s[D] index validation");
        if (seen)
            *seen = 1;
    }
    if (has_u && !has_r)
        value_fail("supported operations: rc[u][s][D] fresh creation, s[D] index validation");
    create = has_r;
    check = has_s && !has_r && !has_c;
    if (!create && !check)
        value_fail("fresh creation requires both r and c");
    root = st_find_root();
    output = st_pabs(argv[2]);
    if (check && ninputs)
        value_fail("index validation accepts one archive and no objects");
    if (create && st_lexists(output))
        update = 1;
    names[nnames++] = "000-seed.hex0";
    names[nnames++] = "seed-forth";
    names[nnames++] = "tools/seed-ar.c";
    names[nnames++] = "tools/seed-tool.h";
    for (i = 0; i < 5; i = i + 1)
        names[nnames++] = layers[i];
    for (i = 0; i < nnames; i = i + 1) {
        char *path = st_cat3(root, "/", names[i]);
        st_read_file(path, &snapshot[i]);
        free(path);
    }
    for (i = 0; i < nnames; i = i + 1) {
        char *path = st_cat3(root, "/", names[i]);
        struct buf again;
        st_read_file(path, &again);
        if (again.len != snapshot[i].len || memcmp(again.data, snapshot[i].data, again.len) != 0)
            value_fail("archive tool inputs changed during snapshot; retry");
        b_free(&again);
        free(path);
    }
    st_check_seed(&snapshot[0], &snapshot[1], "");
    /* Payloads: the objects to add (create) or the archive (check). */
    if (!create)
        ninputs = 1;
    payloads = (struct buf *)st_alloc((unsigned long)(ninputs + 1) * sizeof(struct buf));
    payload_names = (char **)st_alloc((unsigned long)(ninputs + 1) * sizeof(char *));
    for (i = 0; i < ninputs; i = i + 1) {
        payload_names[i] = create ? st_pabs(argv[3 + i]) : output;
        st_read_file(payload_names[i], &payloads[i]);
    }
    for (i = 0; i < ninputs; i = i + 1) {
        struct buf again;
        st_read_file(payload_names[i], &again);
        if (again.len != payloads[i].len || memcmp(again.data, payloads[i].data, again.len) != 0)
            value_fail("archive inputs changed during snapshot; retry");
        b_free(&again);
    }
    /* An update merges the existing members with the new inputs. */
    if (update) {
        struct buf existing, again;
        unsigned long nnew = 0;
        struct member *merged;
        char *replaced;
        st_read_file(output, &existing);
        members = archive_members(output, &existing, &nmembers);
        st_read_file(output, &again);
        if (again.len != existing.len || memcmp(again.data, existing.data, again.len) != 0)
            value_fail("archive inputs changed during snapshot; retry");
        merged = (struct member *)st_alloc((nmembers + (unsigned long)ninputs + 1) * sizeof(struct member));
        replaced = (char *)st_alloc(nmembers + 1);
        memset(replaced, 0, nmembers + 1);
        for (k = 0; k < nmembers; k = k + 1)
            merged[k] = members[k];
        for (i = 0; i < ninputs; i = i + 1) {
            const char *base = st_pname(payload_names[i]);
            for (k = 0; k < nmembers; k = k + 1)
                if (!replaced[k] && strcmp(members[k].name, base) == 0)
                    break;
            if (k < nmembers) {
                replaced[k] = 1;
                merged[k].data = payloads[i].data;
                merged[k].size = payloads[i].len;
            } else {
                merged[nmembers + nnew].name = (char *)base;
                merged[nmembers + nnew].data = payloads[i].data;
                merged[nmembers + nnew].size = payloads[i].len;
                nnew = nnew + 1;
            }
        }
        members = merged;
        nmembers = nmembers + nnew;
    } else if (create) {
        if (!has_c)
            st_puts(2, st_cat3("gcc-direct-ar: creating ", argv[2], "\n"));
        members = (struct member *)st_alloc((unsigned long)(ninputs + 1) * sizeof(struct member));
        for (i = 0; i < ninputs; i = i + 1) {
            members[i].name = (char *)st_pname(payload_names[i]);
            members[i].data = payloads[i].data;
            members[i].size = payloads[i].len;
        }
        nmembers = (unsigned long)ninputs;
    } else {
        members = (struct member *)st_alloc(sizeof(struct member));
        members[0].name = (char *)st_pname(output);
        members[0].data = payloads[0].data;
        members[0].size = payloads[0].len;
        nmembers = 1;
    }
    work = st_mkdtemp("seed-ar-");
    st_track_dir(work);
    seed = st_cat3(work, "/", "seed-forth");
    st_write_file(seed, snapshot[1].data, snapshot[1].len, 0600);
    st_chmod(seed, 0700);
    private_output = st_cat3(work, "/", "archive.a");
    b_init(&code);
    for (i = 0; i < 5; i = i + 1) {
        if (i)
            b_chr(&code, '\n');
        b_add(&code, snapshot[4 + i].data, snapshot[4 + i].len);
    }
    b_str(&code, "\narc-init\n");
    path_word(&code, "archive-output", private_output);
    for (k = 0; k < nmembers; k = k + 1) {
        struct buf number, word;
        char *folder, *captured;
        long r;
        b_init(&number);
        b_dec(&number, (long)k);
        folder = st_cat3(work, "/", number.data);
        r = st_mkdir(folder, 0777);
        if (r < 0)
            st_fail_os(r, folder, 0);
        captured = st_cat3(folder, "/", members[k].name);
        st_write_file(captured, members[k].data, members[k].size, 0666);
        b_init(&word);
        b_str(&word, "archive-input-");
        b_str(&word, number.data);
        path_word(&code, word.data, captured);
        b_str(&code, word.data);
        b_str(&code, create ? " arc-add-object\n" : " arc-check\n");
        b_free(&number);
        b_free(&word);
    }
    if (create)
        b_str(&code, "archive-output arc-write\n");
    b_str(&code, "bye\n");
    status = st_run_seed(work, seed, &code, &out, &err);
    if (out.len)
        st_write_all(2, out.data, out.len);
    if (err.len)
        st_write_all(2, err.data, err.len);
    if (status || out.len)
        st_finish(status > 0 ? (int)status : 1);
    if (create) {
        st_read_file(private_output, &result);
        publish(output, &result, update);
    }
    st_finish(0);
    return 0;
}
