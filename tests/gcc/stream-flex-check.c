/* Original seed-forth regression fixture; see LICENSE. */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#ifndef STREAM_HOST_ORACLE
#include <seed-syscall.h>
#endif
int main(int argc, char **argv)
{
    static int counts[6] = {2,3,7,32,129,300};
    FILE *stream;
    FILE *same;
    char buffer[300];
    char *result;
    int descriptor;
    int i;
    int j;
    long before;
    long after;
    if (argc != 6) return 1;
    stream = fopen(argv[1],"r");
    if (stream == NULL) return 2;
    for (i = 0; i < 6; i++) {
        if (fseek(stream,0,SEEK_SET) || feof(stream)) return 3;
        for (;;) {
            memset(buffer,'Z',sizeof(buffer)); before = ftell(stream);
            result = fgets(buffer,counts[i],stream); after = ftell(stream);
            if (result == NULL) {
                if (!feof(stream) || ferror(stream) || before != after || buffer[0] != 'Z') return 4;
                break;
            }
            if (result != buffer || after <= before || after-before >= counts[i] || buffer[after-before] != 0) return 5;
            printf("%d %ld ",counts[i],after-before);
            for (j = 0; j < after-before; j++) printf("%02x",(unsigned int)(unsigned char)buffer[j]);
            putchar('\n');
        }
    }
    if (fseek(stream,0,SEEK_SET)) return 6;
    buffer[0] = 'Z';
    if (fgets(buffer,1,stream) != buffer || buffer[0] || ftell(stream)) return 7;
#ifndef STREAM_HOST_ORACLE
    buffer[0] = 'Z'; errno = 0;
    if (fgets(buffer,0,stream) != NULL || buffer[0] != 'Z' || errno != EINVAL || ftell(stream)) return 8;
#endif
    if (fgetc(stream) != 0 || ungetc('X',stream) != 'X' || ftell(stream) != 0) return 9;
    if (fseek(stream,0,SEEK_CUR) || fgetc(stream) != 0) return 10;
    if (ungetc('Y',stream) != 'Y') return 11;
    errno = 0;
    if (fseek(stream,0,99) == 0 || errno != EINVAL || fgetc(stream) != 'Y') return 12;
    if (fseek(stream,-4,SEEK_END) || fgets(buffer,5,stream) != buffer || strcmp(buffer,"tail")) return 13;
    if (fgetc(stream) != EOF || !feof(stream)) return 14;
    errno = 0;
    if (fputc('!',stream) != EOF || errno != EBADF || !ferror(stream)) return 15;
    if (fseek(stream,0,SEEK_SET) || feof(stream) || !ferror(stream)) return 16;
    if (fgets(buffer,3,stream) != buffer || buffer[0] != 0 || buffer[1] != 1 || !ferror(stream)) return 17;
    descriptor = fileno(stream); same = stream;
    if (freopen(argv[2],"w+",stream) != same || fileno(stream) != descriptor || feof(stream) || ferror(stream)) return 18;
    if (fputs("hello\n",stream) < 0 || fseek(stream,0,SEEK_SET) || fgets(buffer,sizeof(buffer),stream) != buffer || strcmp(buffer,"hello\n")) return 19;
    if (freopen(argv[2],"a+",stream) != same || fileno(stream) != descriptor || fseek(stream,0,SEEK_SET)) return 20;
    if (fputs("tail",stream) < 0 || fflush(stream) || fseek(stream,-4,SEEK_END) || fgets(buffer,5,stream) != buffer || strcmp(buffer,"tail")) return 21;
    errno = 0;
    if (freopen(argv[3],"r",stream) != NULL || errno != ENOENT) return 22;
    errno = 0;
    if (write(descriptor,"!",1) != -1 || errno != EBADF) return 23;
    stream = fopen(argv[1],"r");
    if (stream == NULL) return 24;
    descriptor = fileno(stream);
#ifndef STREAM_HOST_ORACLE
    errno = 0;
    if (freopen(NULL,"r",stream) != NULL || errno != EINVAL) return 25;
    errno = 0;
    if (write(descriptor,"!",1) != -1 || errno != EBADF) return 26;
    if (__seed_syscall6(3,0,0,0,0,0,0) != 0) return 27;
#else
    if (fclose(stream)) return 26;
    if (close(0)) return 27;
#endif
    if (freopen(argv[4],"w+",stdout) != stdout || fileno(stdout) != 1) return 28;
    if (printf("line\n") != 5 || fseek(stdout,0,SEEK_SET) || fgets(buffer,sizeof(buffer),stdout) != buffer || strcmp(buffer,"line\n")) return 29;
    if (fseek(stdout,0,SEEK_END) || write(1,"tail",4) != 4 || fclose(stdout)) return 30;
    /* errno ownership after a missing path is measured independently. */
    if (fopen(argv[5],"r") != NULL || errno != ENOENT) return 31;
    return 0;
}
