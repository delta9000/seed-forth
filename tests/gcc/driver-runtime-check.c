/* Original seed-forth test; see LICENSE and runtime/gcc-seed/DRIVER-RUNTIME.md.
   Run in a fresh empty directory containing sub/ (with sub/inner) and with
   SEED_START=startup in the environment. Prints one line per observation;
   the Forth-built and host GCC/glibc builds must print identical bytes. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/param.h>

static void show(const char *what, int result)
{
    printf("%s: %d errno=%d\n", what, result, result < 0 ? errno : 0);
}

static void write_file(const char *path, const char *text)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0 || write(fd, text, strlen(text)) != (ssize_t)strlen(text) || close(fd)) {
        printf("cannot write %s\n", path);
        exit(2);
    }
}

static long links(const char *path)
{
    struct stat status;
    if (stat(path, &status) != 0) return -1;
    return (long)status.st_nlink;
}

static int count_environ(void)
{
    int count = 0;
    while (environ[count]) count++;
    return count;
}

static void child(const char *script)
{
    char *arguments[4];
    pid_t pid;
    int status = 0;
    arguments[0] = "sh";
    arguments[1] = "-c";
    arguments[2] = (char *)script;
    arguments[3] = NULL;
    fflush(stdout);
    pid = fork();
    if (pid == 0) {
        execv("/bin/sh", arguments);
        _exit(127);
    }
    if (pid < 0 || waitpid(pid, &status, 0) != pid) {
        printf("child failed\n");
        exit(2);
    }
    printf("child status %d\n", WIFEXITED(status) ? WEXITSTATUS(status) : -1);
}

static void descriptors(void)
{
    int fd = open("dup.txt", O_WRONLY | O_CREAT | O_TRUNC, 0600);
    int copy;
    int lowest;
    char buffer[16];
    printf("fd opened %d\n", fd >= 3);
    copy = dup(fd);
    printf("dup distinct %d\n", copy > fd);
    /* dup returns the lowest free descriptor. */
    close(copy);
    lowest = dup(fd);
    printf("dup lowest reused %d\n", lowest == copy);
    printf("write via copy %d\n", (int)write(lowest, "ab", 2));
    printf("write via original %d\n", (int)write(fd, "cd", 2));
    close(fd);
    printf("copy survives close %d\n", (int)write(lowest, "ef", 2));
    close(lowest);
    fd = open("dup.txt", O_RDONLY);
    memset(buffer, 0, sizeof buffer);
    printf("shared offset read %d %s\n", (int)read(fd, buffer, sizeof buffer - 1), buffer);
    printf("cloexec clear %d\n", fcntl(copy = dup(fd), F_GETFD));
    close(copy);
    close(fd);
    show("dup closed", dup(fd));
    show("dup negative", dup(-1));
    show("dup2 same", dup2(1, 1) == 1 ? 0 : -2);
    show("dup2 closed source", dup2(fd, 20));
    unlink("dup.txt");
}

static void paths(void)
{
    char here[MAXPATHLEN];
    char start[MAXPATHLEN];
    printf("MAXPATHLEN %d\n", MAXPATHLEN);
    if (!getcwd(start, sizeof start)) { printf("getcwd failed\n"); exit(2); }
    show("chdir sub", chdir("sub"));
    getcwd(here, sizeof here);
    printf("cwd is start/sub %d\n",
           strncmp(here, start, strlen(start)) == 0 && strcmp(here + strlen(start), "/sub") == 0);
    printf("relative open after chdir %d\n", access("inner", F_OK));
    show("chdir parent", chdir(".."));
    getcwd(here, sizeof here);
    printf("cwd is start %d\n", strcmp(here, start) == 0);
    show("chdir missing", chdir("missing"));
    write_file("plain", "x");
    show("chdir file", chdir("plain"));
    show("chdir empty", chdir(""));
    show("chdir absolute", chdir(start));

    write_file("a", "alpha\n");
    show("link a b", link("a", "b"));
    printf("links a %ld b %ld\n", links("a"), links("b"));
    show("link existing", link("a", "b"));
    show("link missing", link("nothere", "c"));
    show("link into missing dir", link("a", "nodir/c"));
    show("link directory", link("sub", "subcopy"));

    show("rename b c", rename("b", "c"));
    printf("after rename b %d c %d links %ld\n", access("b", F_OK), access("c", F_OK), links("c"));
    write_file("d", "delta\n");
    show("rename over existing", rename("d", "c"));
    printf("c is delta links %ld a links %ld d gone %d\n", links("c"), links("a"), access("d", F_OK));
    show("rename to itself", rename("a", "a"));
    show("rename missing", rename("nothere", "e"));
    show("rename file onto directory", rename("c", "sub"));
    show("rename below a file", rename("plain", "sub/inner/x"));
    show("rename directory", rename("sub", "sub2"));
    show("rename directory back", rename("sub2", "sub"));
    unlink("a");
    unlink("c");
    unlink("plain");
}

static void environment(void)
{
    static char first[] = "SEEDX=one";
    static char second[] = "SEEDX=two";
    static char remove_name[] = "SEEDX";
    static char child_value[] = "SEEDCHILD=visible";
    static char replace_start[] = "SEED_START=replaced";
    static char many[40][16];
    static char *custom[3];
    static char custom_entry[] = "SEEDCUSTOM=yes";
    int base;
    int i;
    base = count_environ();
    printf("startup %s\n", getenv("SEED_START") ? getenv("SEED_START") : "(null)");
    printf("absent %d\n", getenv("SEEDX") == NULL);
    show("putenv first", putenv(first));
    printf("getenv %s same storage %d count +%d\n", getenv("SEEDX"),
           getenv("SEEDX") == first + 6, count_environ() - base);
    first[6] = 'O';
    printf("in-place edit visible %s\n", getenv("SEEDX"));
    show("putenv replace", putenv(second));
    printf("replaced %s count +%d\n", getenv("SEEDX"), count_environ() - base);
    show("putenv startup replace", putenv(replace_start));
    printf("startup now %s count +%d\n", getenv("SEED_START"), count_environ() - base);
    show("putenv remove", putenv(remove_name));
    printf("removed %d count +%d\n", getenv("SEEDX") == NULL, count_environ() - base);
    show("putenv remove absent", putenv(remove_name));
    for (i = 0; i < 40; i++) {
        sprintf(many[i], "SEEDM%02d=%d", i, i * 3);
        if (putenv(many[i]) != 0) { printf("putenv many failed\n"); exit(2); }
    }
    printf("many count +%d SEEDM00 %s SEEDM39 %s\n", count_environ() - base,
           getenv("SEEDM00"), getenv("SEEDM39"));
    printf("startup still %s\n", getenv("SEED_START"));
    putenv(child_value);
    child("test \"$SEEDCHILD\" = visible && test \"$SEEDM39\" = 117 && test \"$SEED_START\" = replaced");
    child("test -z \"$SEEDX\"");

    /* A program-assigned vector is copied, never written. */
    custom[0] = custom_entry;
    custom[1] = replace_start;
    custom[2] = NULL;
    environ = custom;
    printf("custom getenv %s\n", getenv("SEEDCUSTOM"));
    show("putenv over custom", putenv(first));
    printf("custom untouched %d %d moved %d count %d\n", custom[0] == custom_entry,
           custom[2] == NULL, environ != custom, count_environ());
    child("test \"$SEEDCUSTOM\" = yes && test \"$SEEDX\" = One && test -z \"$SEEDCHILD\"");
    /* glibc reallocates its earlier vector here, so restoring the old one
       is not portable; the runtime's documented choice is not compared. */
}

static void scanning(void)
{
    FILE *stream;
    char c;
    char d;
    char line[64];
    int number;
    unsigned int hex;
    unsigned int octal;
    int result;
    /* tlink.c's .rpo reading loop: "%c " then the rest of the line. */
    write_file("x.rpo", "M main\nA -O2 -g\nD /tmp/dir\nO \tfoo.o\nC\n\n  P sym\n");
    stream = fopen("x.rpo", "r");
    while ((result = fscanf(stream, "%c ", &c)) == 1) {
        if (!fgets(line, sizeof line, stream)) strcpy(line, "(eof)\n");
        printf("record %c: %s", c, line);
    }
    printf("loop end %d feof %d\n", result, feof(stream) != 0);
    printf("again %d\n", fscanf(stream, "%c ", &c));
    fclose(stream);

    write_file("n.txt", "  42 0x1f 017 -7 abc%z\n12,  ab");
    stream = fopen("n.txt", "r");
    result = fscanf(stream, "%d %x %o", &number, &hex, &octal);
    printf("numbers %d: %d %u %u\n", result, number, hex, octal);
    result = fscanf(stream, "%d%c%c", &number, &c, &d);
    printf("number and chars %d: %d [%c][%c]\n", result, number, c, d);
    result = fscanf(stream, "%c%%", &c);
    printf("char then percent %d: [%c] next %c\n", result, c, fgetc(stream));
    result = fscanf(stream, "%d", &number);
    printf("mismatch %d next %c\n", result, fgetc(stream));
    result = fscanf(stream, "%c%d,", &c, &number);
    printf("newline char %d: %d %d\n", result, c == '\n', number);
    result = fscanf(stream, " %c%c", &c, &d);
    printf("skip then chars %d: [%c][%c]\n", result, c, d);
    result = fscanf(stream, "%c", &c);
    printf("eof %d\n", result);
    fclose(stream);
    write_file("empty", "");
    stream = fopen("empty", "r");
    printf("empty %d\n", fscanf(stream, "%c ", &c));
    fclose(stream);
    printf("sscanf chars %d", sscanf(" xy 5", "%c%c %d", &c, &d, &number));
    printf(" [%c][%c] %d\n", c, d, number);
    unlink("x.rpo");
    unlink("n.txt");
    unlink("empty");
}

int main(void)
{
    descriptors();
    paths();
    environment();
    scanning();
    printf("done\n");
    return 0;
}
