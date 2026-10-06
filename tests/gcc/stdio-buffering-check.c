/* Observable stdio buffering behaviour. Built by the Forth compiler against
   runtime/gcc-seed (production) and by host GCC against glibc (oracle
   only); stdio-buffering-check.py runs both under pipes, files and a
   pseudo-terminal and requires identical bytes. Usage: prog MODE [FILE]. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

static char line[256];

static void interleave(void)
{
    printf("out1\n");
    fprintf(stderr, "err1\n");
    printf("out2 %d", 2);
    fputs("err2\n", stderr);
    putchar('\n');
    fputs("out3 no newline", stdout);
    fprintf(stderr, "err3 %s\n", "end");
}

static void update(const char *path)
{
    FILE *stream = fopen(path, "w+");
    int c;
    long position;
    if (!stream) { printf("open failed\n"); return; }
    fputs("hello world\nsecond line\n", stream);
    printf("ftell after write %ld\n", ftell(stream));
    rewind(stream);
    printf("fgets [%s]", fgets(line, sizeof line, stream));
    printf("ftell after fgets %ld\n", ftell(stream));
    fseek(stream, 0L, SEEK_CUR);
    fputs("SECOND", stream);
    printf("ftell after overwrite %ld\n", ftell(stream));
    fseek(stream, 0L, SEEK_SET);
    c = getc(stream);
    printf("getc %c ftell %ld\n", c, ftell(stream));
    ungetc('X', stream);
    printf("after ungetc ftell %ld\n", ftell(stream));
    c = getc(stream);
    printf("getc %c", c);
    c = getc(stream);
    printf(" %c\n", c);
    ungetc('1', stream);
    ungetc('2', stream);
    c = getc(stream);
    printf("double ungetc %c", c);
    c = getc(stream);
    printf("%c", c);
    c = getc(stream);
    printf("%c\n", c);
    fseek(stream, -4L, SEEK_END);
    printf("tail [%s]\n", fgets(line, sizeof line, stream));
    printf("eof %d", feof(stream) != 0);
    c = getc(stream);
    printf(" getc %d eof %d\n", c, feof(stream) != 0);
    fseek(stream, 6L, SEEK_SET);
    position = ftell(stream);
    printf("position %ld\n", position);
    fprintf(stream, "%s", "WORLD");
    fflush(stream);
    fseek(stream, 0L, SEEK_SET);
    while ((c = getc(stream)) != EOF) putchar(c == '\n' ? '|' : c);
    putchar('\n');
    fclose(stream);
    stream = fopen(path, "a+");
    fputs("appended\n", stream);
    printf("append ftell %ld\n", ftell(stream));
    fseek(stream, 0L, SEEK_SET);
    printf("append read [%s]", fgets(line, sizeof line, stream));
    fclose(stream);
}

/* Input streams give unread bytes back on fflush and fclose. */
static void input_sync(const char *path)
{
    FILE *stream;
    int descriptor;
    char buffer[16];
    long amount;
    stream = fopen(path, "w");
    fputs("abcdefghijklmnopqrstuvwxyz\n0123456789\n", stream);
    fclose(stream);
    descriptor = open(path, O_RDONLY);
    stream = fdopen(dup(descriptor), "r");
    printf("getc %c", getc(stream));
    printf("%c\n", getc(stream));
    printf("fflush %d\n", fflush(stream));
    amount = read(descriptor, buffer, 4);
    printf("shared offset read [%.*s]\n", (int)amount, buffer);
    printf("getc after fflush %c\n", getc(stream));
    fclose(stream);
    amount = read(descriptor, buffer, 4);
    printf("after fclose read [%.*s]\n", (int)amount, buffer);
    close(descriptor);
}

/* One setvbuf before any other operation, as C requires. A caller buffer
   of at least 128 bytes avoids glibc's direct-write path for tiny buffers. */
static void modes(int mode)
{
    static char user[512];
    if (mode == _IOLBF) setvbuf(stdout, user, _IOLBF, sizeof user);
    else setvbuf(stdout, NULL, mode, 0);
    printf("line1 ");
    fprintf(stderr, "e1\n");
    printf("rest\n");
    fprintf(stderr, "e2\n");
    printf("partial ");
    fflush(stdout);
    fprintf(stderr, "e3\n");
    printf("%s", "tail ");
    fprintf(stderr, "e4\n");
    printf("end\n");
}

int main(int argc, char **argv)
{
    const char *mode = argc > 1 ? argv[1] : "";
    if (!strcmp(mode, "interleave")) interleave();
    else if (!strcmp(mode, "exit")) {
        printf("before exit");
        fprintf(stderr, "stderr\n");
        exit(5);
    } else if (!strcmp(mode, "_exit")) {
        printf("lost by _exit");
        fprintf(stderr, "kept\n");
        _exit(6);
    } else if (!strcmp(mode, "return")) {
        printf("returned");
        return 7;
    } else if (!strcmp(mode, "update") && argc > 2) update(argv[2]);
    else if (!strcmp(mode, "sync") && argc > 2) input_sync(argv[2]);
    else if (!strcmp(mode, "lbf")) modes(_IOLBF);
    else if (!strcmp(mode, "nbf")) modes(_IONBF);
    else if (!strcmp(mode, "fbf")) modes(_IOFBF);
    else if (!strcmp(mode, "prompt")) {
        printf("name? ");
        if (fgets(line, sizeof line, stdin)) printf("hello %s", line);
    } else if (!strcmp(mode, "copy")) {
        int c;
        while ((c = getchar()) != EOF) putchar(c);
    } else if (!strcmp(mode, "many")) {
        long index;
        for (index = 0; index < 100000; index++) putchar('a' + (int)(index % 26));
        putchar('\n');
    } else if (!strcmp(mode, "headroom")) {
        int pushed = 0;
        while (pushed < 8 && ungetc('0' + pushed, stdin) != EOF) pushed++;
        printf("pushed %d:", pushed);
        while (pushed-- > 0) putchar(getchar());
        putchar('\n');
    } else return 2;
    return 0;
}
