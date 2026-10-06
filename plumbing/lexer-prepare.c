/* Bootstrap text operations for the pinned parser-generator recipe.
 * Built by seed-cc; no shell, sed, patch, or pre-generated C required.
 * patch: apply each complete unified hunk at its unique exact context,
 * permitting line offsets but never fuzz. The stage pins inputs and outputs.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

static void fail(const char *s) { fprintf(stderr, "lexer-prepare: %s\n", s); exit(1); }
static char *readfile(const char *path) {
    FILE *f = fopen(path, "rb"); long n; char *p;
    if (!f) fail(path);
    if (fseek(f, 0, SEEK_END)) fail("seek");
    n = ftell(f); if (n < 0 || n > 16000000) fail("input size");
    rewind(f); p = malloc(n + 1); if (!p) fail("allocation");
    if (fread(p, 1, n, f) != n || fclose(f)) fail("read");
    p[n] = 0; if (strlen(p) != n) fail("NUL in text"); return p;
}
static void writefile(const char *path, const char *p) {
    FILE *f = fopen(path, "wb"); if (!f) fail(path);
    if (fwrite(p, 1, strlen(p), f) != strlen(p) || fclose(f)) fail("write");
}
static char *replace(char *p, const char *old, const char *new, int expected) {
    size_t a = strlen(old), b = strlen(new), n = strlen(p); int count = 0;
    char *s = p, *hit, *q, *out;
    if (!a) fail("empty replacement");
    while ((hit = strstr(s, old))) { count++; s = hit + a; }
    if (!count || (expected >= 0 && count != expected)) fail("replacement count");
    out = malloc(n + count * b + 1); if (!out) fail("allocation"); q = out; s = p;
    while ((hit = strstr(s, old))) {
        memcpy(q, s, hit - s); q += hit - s; memcpy(q, new, b); q += b; s = hit + a;
    }
    strcpy(q, s); free(p); return out;
}
static void patch(const char *payload) {
    char *p = readfile(payload), *line = p, *end, *file = NULL, *text = NULL;
    char *old = malloc(16000001), *new = malloc(16000001);
    int hunks = 0;
    if (!old || !new) fail("allocation");
    while (*line) {
        end = strchr(line, '\n'); if (!end) fail("patch missing newline");
        if (!strncmp(line, "--- ", 4)) {
            char *slash = memchr(line + 4, '/', end - line - 4);
            if (!slash) fail("patch needs -p1 path");
            if (text) { writefile(file, text); free(text); free(file); }
            file = malloc(end - slash); if (!file) fail("allocation");
            memcpy(file, slash + 1, end - slash - 1); file[end - slash - 1] = 0;
            if (strchr(file, '/') || strstr(file, "..")) fail("patch path");
            text = readfile(file);
        } else if (!strncmp(line, "@@ ", 3)) {
            int os, oc, ns, nc, seen_old = 0, seen_new = 0;
            size_t a = 0, b = 0;
            if (!text || sscanf(line, "@@ -%d,%d +%d,%d @@", &os, &oc, &ns, &nc) != 4)
                fail("unsupported hunk header");
            line = end + 1;
            while (seen_old < oc || seen_new < nc) {
                size_t n;
                end = strchr(line, '\n'); if (!end) fail("short hunk"); n = end - line;
                if (*line != ' ' && *line != '-' && *line != '+') fail("hunk marker");
                if (*line != '+') { memcpy(old + a, line + 1, n); a += n; seen_old++; }
                if (*line != '-') { memcpy(new + b, line + 1, n); b += n; seen_new++; }
                if (seen_old > oc || seen_new > nc) fail("hunk counts");
                line = end + 1;
            }
            old[a] = 0; new[b] = 0; text = replace(text, old, new, 1); hunks++;
            continue;
        }
        line = end + 1;
    }
    if (!text || !hunks) fail("no patch hunks");
    writefile(file, text); free(text); free(file); free(p); free(old); free(new);
}
static void skeleton(const char *in, const char *out) {
    char *p = readfile(in), *s = p; FILE *f = fopen(out, "wb");
    if (!f) fail(out);
    fputs("/* File created from flex.skl via mkskel.sh */\n\n#include \"flexdef.h\"\n\nconst char *skel[] = {\n", f);
    while (*s) {
        fputs("  \"", f);
        while (*s && *s != '\n') {
            if (*s == '\\' || *s == '"') fputc('\\', f);
            fputc(*s++, f);
        }
        if (*s) s++;
        fputs("\",\n", f);
    }
    fputs("  0\n};\n", f); if (ferror(f) || fclose(f)) fail("skeleton write"); free(p);
}
int main(int argc, char **argv) {
    char *p; size_t i;
    char cwd[4096]; FILE *f;
    if (argc == 2 && !strcmp(argv[1], "ungenerated")) {
        const char *names[4] = {"parse.c", "parse.h", "scan.c", "skel.c"};
        for (i = 0; i < 4; i++) if (unlink(names[i]) && errno != ENOENT) fail(names[i]);
    } else if (argc == 3 && !strcmp(argv[1], "lexconfig")) {
        if (!getcwd(cwd, sizeof cwd) || strchr(cwd, '"') || strchr(cwd, '\\')) fail("lex source path");
        f = fopen(argv[2], "wb"); if (!f) fail(argv[2]);
        fprintf(f, "/* Build path for upstream lex form files. */\n#define unix 1\n#define FORMPATH \"%s\"\n", cwd);
        if (ferror(f) || fclose(f)) fail("config write");
    } else if (argc == 3 && !strcmp(argv[1], "patch")) patch(argv[2]);
    else if (argc == 4 && !strcmp(argv[1], "skeleton")) skeleton(argv[2], argv[3]);
    else if (argc == 4 && !strcmp(argv[1], "ascii")) {
        p = replace(readfile(argv[2]), "\305\240", "S", 1);
        for (i = 0; p[i]; i++) if ((unsigned char)p[i] > 127) fail("non-ASCII scanner");
        writefile(argv[3], p); free(p);
    } else if (argc == 4 && !strcmp(argv[1], "scanner")) {
        p = replace(readfile(argv[2]), "yylex", "flexscan", -1); writefile(argv[3], p); free(p);
    } else fail("usage: patch PAYLOAD | skeleton/ascii/scanner INPUT OUTPUT | lexconfig OUTPUT | ungenerated");
    return 0;
}
