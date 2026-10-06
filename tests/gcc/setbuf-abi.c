/* Public-call test doubles do not assume either implementation's FILE layout. */
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
extern void tested_setbuf(FILE *, char *);
static char stream_token;
static FILE *wanted;
static int calls;
static int invalid_stream;
int directory_fileno(FILE *stream)
{
    calls++;
    if (stream != wanted) _exit(41);
    return invalid_stream ? -1 : 9;
}
void directory_exit(int status)
{
    if (status != 127 || calls != invalid_stream) _exit(42);
    _exit(status);
}
int main(int argc, char **argv)
{
    wanted = (FILE *)&stream_token;
    errno = 97;
    if (argc > 1 && argv[1][0] == 'x') {
        /* A caller buffer is accepted after the same stream validation. */
        tested_setbuf(wanted, (char *)1);
        if (calls != 1 || errno != 97) return 43;
        puts("setbuf buffer ABI passed");
        return 0;
    }
    if (argc > 1 && argv[1][0] == 'i') {
        invalid_stream = 1;
        tested_setbuf(wanted, NULL);
        return 44;
    }
    tested_setbuf(wanted, NULL);
    if (calls != 1 || errno != 97) return 45;
    puts("setbuf public-call ABI passed");
    return 0;
}
