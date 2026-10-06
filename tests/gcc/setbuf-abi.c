/* Public-call test doubles do not assume either implementation's FILE layout.
   setbuf must be exactly setvbuf(stream, buffer, buffer ? _IOFBF : _IONBF,
   BUFSIZ); the double records each forwarded call. */
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
extern void tested_setbuf(FILE *, char *);
static char stream_token;
static char buffer_token[BUFSIZ];
static FILE *wanted;
static char *wanted_buffer;
static int wanted_mode;
static int calls;
int directory_setvbuf(FILE *stream, char *buffer, int mode, size_t size)
{
    calls++;
    if (stream != wanted || buffer != wanted_buffer || mode != wanted_mode || size != BUFSIZ) _exit(41);
    return 0;
}
int main(void)
{
    wanted = (FILE *)&stream_token;
    errno = 97;
    wanted_mode = _IONBF;
    tested_setbuf(wanted, NULL);
    if (calls != 1 || errno != 97) return 45;
    wanted_buffer = buffer_token;
    wanted_mode = _IOFBF;
    tested_setbuf(wanted, buffer_token);
    if (calls != 2 || errno != 97) return 46;
    puts("setbuf public-call ABI passed");
    return 0;
}
