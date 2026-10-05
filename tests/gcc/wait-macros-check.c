/* Prints every W* macro for each 16-bit status word and selected wider ones.
   The Forth build (runtime sys/wait.h) must match host glibc byte for byte. */
#include <sys/wait.h>
#include <stdio.h>

static int calls;

/* Counts evaluations so single evaluation of the argument is visible. */
static int counted(int status)
{
    calls++;
    return status;
}

static void show(int status)
{
    printf("%d %d %d %d %d %d %d\n", status, WIFEXITED(status) != 0, WEXITSTATUS(status),
           WIFSIGNALED(status) != 0, WTERMSIG(status), WIFSTOPPED(status) != 0,
           WSTOPSIG(status));
}

int main(void)
{
    static const int wide[] = { 65536, 65536 + 0x7f, 0x12345678, 0x7fffffff,
                                -1, -256, -32768, -2147483647 - 1 };
    int status, i, single = 1;
    for (status = 0; status <= 0xffff; status++) show(status);
    for (i = 0; i < (int)(sizeof(wide) / sizeof(wide[0])); i++) show(wide[i]);
    calls = 0; i = WIFEXITED(counted(0x0100)); single &= calls == 1 && i;
    calls = 0; i = WEXITSTATUS(counted(0x0300)); single &= calls == 1 && i == 3;
    calls = 0; i = WIFSIGNALED(counted(9)); single &= calls == 1 && i;
    calls = 0; i = WTERMSIG(counted(0x89)); single &= calls == 1 && i == 9;
    calls = 0; i = WIFSTOPPED(counted(0x137f)); single &= calls == 1 && i;
    calls = 0; i = WSTOPSIG(counted(0x137f)); single &= calls == 1 && i == 19;
    printf("single evaluation %d; WNOHANG %d WUNTRACED %d\n", single, WNOHANG, WUNTRACED);
    return 0;
}
