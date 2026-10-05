/* Original seed-forth test; see LICENSE and runtime/gcc-seed/FILE-METADATA.md.
   Run with TZ=UTC0 in a fresh directory that holds "file" (contents "abc\n"),
   "dir/inner" and a symbolic link "link" to "file". Prints one line per
   observation; the Forth-built and host GCC/glibc builds must agree. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <wchar.h>
#include <wctype.h>
#include <unistd.h>
#include <utime.h>
#include <sys/types.h>
#include <sys/stat.h>

static void show(const char *what, int result)
{
    printf("%s: %d errno=%d\n", what, result, result < 0 ? errno : 0);
}

static void mode_of(const char *path)
{
    struct stat status;
    if (stat(path, &status) != 0) printf("mode %s: missing errno=%d\n", path, errno);
    else printf("mode %s: %o\n", path, (unsigned)(status.st_mode & 07777));
}

static void permission_macros(void)
{
    printf("S_I*: %o %o %o %o %o %o %o %o %o %o %o %o %o %o %o\n",
           S_ISUID, S_ISGID, S_ISVTX, S_IRWXU, S_IRUSR, S_IWUSR, S_IXUSR,
           S_IRWXG, S_IRGRP, S_IWGRP, S_IXGRP, S_IRWXO, S_IROTH, S_IWOTH, S_IXOTH);
}

static void directories(void)
{
    mode_t old = umask(022);
    printf("umask old %o\n", (unsigned)old);
    printf("umask again %o\n", (unsigned)umask(0777 | 07000));
    printf("umask masked %o\n", (unsigned)umask(022));
    show("mkdir new", mkdir("made", 0777));
    mode_of("made");
    show("mkdir existing", mkdir("made", 0700));
    show("mkdir missing parent", mkdir("none/made", 0700));
    show("mkdir under file", mkdir("file/made", 0700));
    show("rmdir non-empty", rmdir("dir"));
    show("rmdir file", rmdir("file"));
    show("rmdir made", rmdir("made"));
    show("rmdir missing", rmdir("made"));
    umask(old);
}

static void permissions(void)
{
    struct stat status;
    show("chmod 640", chmod("file", 0640));
    mode_of("file");
    show("chmod 4755 via link", chmod("link", 04755));
    mode_of("file");
    show("chmod missing", chmod("missing", 0600));
    show("chown unchanged", chown("file", (uid_t)-1, (gid_t)-1));
    show("chown missing", chown("missing", (uid_t)-1, (gid_t)-1));
    show("chown own ids", stat("file", &status) == 0
         ? chown("file", status.st_uid, status.st_gid) : -2);
    show("chmod 600", chmod("file", 0600));
    show("lstat link", lstat("link", &status));
    printf("lstat link: lnk %d reg %d\n", S_ISLNK(status.st_mode), S_ISREG(status.st_mode));
    show("stat link", stat("link", &status));
    printf("stat link: lnk %d reg %d size %ld\n", S_ISLNK(status.st_mode),
           S_ISREG(status.st_mode), (long)status.st_size);
    show("lstat file", lstat("file", &status));
    printf("lstat file: reg %d nlink %ld\n", S_ISREG(status.st_mode), (long)status.st_nlink);
    show("lstat missing", lstat("missing", &status));
    show("lstat under file", lstat("file/x", &status));
}

static void times(void)
{
    struct utimbuf stamp;
    struct stat status;
    time_t now;
    stamp.actime = 1000000000L;
    stamp.modtime = 1234567890L;
    show("utime set", utime("file", &stamp));
    if (stat("file", &status) == 0)
        printf("times %ld %ld\n", (long)status.st_atime, (long)status.st_mtime);
    stamp.actime = -86400L;
    stamp.modtime = 0;
    show("utime pre-epoch", utime("file", &stamp));
    if (stat("file", &status) == 0)
        printf("times %ld %ld\n", (long)status.st_atime, (long)status.st_mtime);
    show("utime now", utime("file", NULL));
    now = time(NULL);
    if (stat("file", &status) == 0)
        printf("now within 5s %d %d\n", status.st_mtime >= now - 5 && status.st_mtime <= now,
               status.st_atime >= now - 5 && status.st_atime <= now);
    show("utime missing", utime("missing", &stamp));
}

static void rewinding(void)
{
    FILE *stream = fopen("file", "r");
    int c;
    if (!stream) {
        printf("fopen failed\n");
        return;
    }
    while (getc(stream) != EOF)
        ;
    printf("before rewind eof %d error %d\n", feof(stream) != 0, ferror(stream) != 0);
    rewind(stream);
    printf("after rewind eof %d error %d tell %ld\n", feof(stream) != 0,
           ferror(stream) != 0, ftell(stream));
    c = getc(stream);
    printf("first byte again %c\n", c);
    c = getc(stream);
    ungetc('Z', stream);
    rewind(stream);
    printf("after pushback rewind %c\n", getc(stream));
    fclose(stream);
    stream = fopen("file", "r");
    if (!stream) return;
    putc('x', stream);
    printf("write to read stream error %d\n", ferror(stream) != 0);
    rewind(stream);
    printf("rewind cleared error %d\n", ferror(stream) != 0);
    fclose(stream);
}

static int alnum_tail(const char *name, size_t length)
{
    size_t index;
    for (index = length - 6; index < length; index++) {
        char c = name[index];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')))
            return 0;
    }
    return strcmp(name + length - 6, "XXXXXX") != 0;
}

static void temporary_names(void)
{
    char name[32];
    char *result;
    struct stat status;
    int round;
    for (round = 0; round < 3; round++) {
        strcpy(name, round == 2 ? "dir/tmpXXXXXX" : "ccXXXXXX");
        result = mktemp(name);
        printf("mktemp %d: same %d length %d prefix %d tail %d free %d\n", round,
               result == name, (int)strlen(name), round == 2
               ? strncmp(name, "dir/tmp", 7) == 0 : strncmp(name, "cc", 2) == 0,
               alnum_tail(name, strlen(name)), lstat(name, &status) != 0 && errno == ENOENT);
        /* binutils make_tempdir: mktemp, then mkdir with mode 0700. */
        if (round == 0) {
            show("mkdir temp", mkdir(name, 0700));
            show("rmdir temp", rmdir(name));
        }
    }
    strcpy(name, "shortXXXXX");
    errno = 0;
    result = mktemp(name);
    printf("mktemp short: same %d empty %d errno %d\n", result == name, name[0] == '\0', errno);
    strcpy(name, "XXXXXXy");
    errno = 0;
    result = mktemp(name);
    printf("mktemp suffix: empty %d errno %d\n", name[0] == '\0', errno);
    strcpy(name, "missing/ccXXXXXX");
    result = mktemp(name);
    printf("mktemp missing dir: empty %d\n", name[0] == '\0');
}

static void wide(void)
{
    static const wint_t probes[] = { 0, 'A', 'M', 'Z', '@', '[', 'a', 'z', '0', 0x7f, 0x80,
                                     0xc0, 0xc9, 0xde, 0x100, 0x391, 0x410, 0xff21,
                                     0x7fffffff, 0x80000000U, WEOF };
    wchar_t buffer[8];
    unsigned long sum = 0;
    size_t index;
    wint_t value;
    for (value = 0; value < 0x3000; value++) sum = sum * 31 + towlower(value);
    printf("towlower checksum %lu\n", sum);
    for (index = 0; index < sizeof probes / sizeof probes[0]; index++)
        printf("towlower %x -> %x\n", (unsigned)probes[index], (unsigned)towlower(probes[index]));
    printf("mbstowcs count %ld\n", (long)mbstowcs(NULL, "symbol", 2));
    printf("mbstowcs empty %ld\n", (long)mbstowcs(NULL, "", 0));
    /* glibc's C locale leaves errno alone; this runtime sets EILSEQ as
       POSIX requires. "runtime-only" lines are not compared with the host. */
    errno = 0;
    printf("mbstowcs high %ld\n", (long)mbstowcs(NULL, "ab\xc3\xa9", 4));
    printf("runtime-only mbstowcs errno %d\n", errno);
    for (index = 0; index < 8; index++) buffer[index] = 0x55;
    printf("mbstowcs full %ld", (long)mbstowcs(buffer, "abc", 8));
    for (index = 0; index < 5; index++) printf(" %x", (unsigned)buffer[index]);
    printf("\n");
    for (index = 0; index < 8; index++) buffer[index] = 0x55;
    printf("mbstowcs bounded %ld", (long)mbstowcs(buffer, "abcdef", 3));
    for (index = 0; index < 5; index++) printf(" %x", (unsigned)buffer[index]);
    printf("\n");
    for (index = 0; index < 8; index++) buffer[index] = 0x55;
    printf("mbstowcs exact %ld", (long)mbstowcs(buffer, "abc", 3));
    for (index = 0; index < 5; index++) printf(" %x", (unsigned)buffer[index]);
    printf("\n");
    errno = 0;
    printf("mbstowcs high into buffer %ld\n", (long)mbstowcs(buffer, "a\x80", 8));
    printf("runtime-only mbstowcs errno %d\n", errno);
}

static void calendar(void)
{
    static const long stamps[] = { 0L, 1L, 59L, 86399L, 86400L, -1L, -86401L, 951782400L,
                                   951868800L, 1234567890L, 2147483647L, 2147483648L,
                                   4102444800L, 253402300799L, -2208988800L, -62135596800L };
    char text[64];
    size_t index;
    time_t stamp;
    struct tm *value;
    char *line;
    for (index = 0; index < sizeof stamps / sizeof stamps[0]; index++) {
        stamp = (time_t)stamps[index];
        value = gmtime(&stamp);
        printf("gmtime %ld: %d %d %d %d:%d:%d wday %d yday %d dst %d\n", stamps[index],
               value->tm_year, value->tm_mon, value->tm_mday, value->tm_hour, value->tm_min,
               value->tm_sec, value->tm_wday, value->tm_yday, value->tm_isdst);
        printf("strftime %d [%s]\n",
               (int)strftime(text, sizeof text, "%Y-%m-%dT%H:%M:%S.000%z", value), text);
        printf("strftime %d [%s]\n",
               (int)strftime(text, sizeof text, "%F %T %e %j %y %%", value), text);
        line = ctime(&stamp);
        printf("ctime %s", line ? line : "NULL\n");
    }
    stamp = 1234567890L;
    value = localtime(&stamp);
    printf("listing %d [", (int)strftime(text, 30, "%Y-%m-%dT%H:%M:%S.000%z", value));
    printf("%s]\n", text);
    printf("short buffer %d\n", (int)strftime(text, 10, "%Y-%m-%dT%H", value));
    printf("exact fit %d [%s]\n", (int)strftime(text, 11, "%Y-%m-%d", value), text);
    printf("literal %d [%s]\n", (int)strftime(text, sizeof text, "at noon", value), text);
    printf("gmtime and localtime share %d\n", gmtime(&stamp) == localtime(&stamp));
}

int main(void)
{
    permission_macros();
    directories();
    permissions();
    times();
    rewinding();
    temporary_names();
    wide();
    calendar();
    printf("done\n");
    return 0;
}
