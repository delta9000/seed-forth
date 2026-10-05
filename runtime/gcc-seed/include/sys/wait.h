#ifndef SEED_GCC_SYS_WAIT_H
#define SEED_GCC_SYS_WAIT_H
/* Linux AMD64 child status; see ../../PROCESS-API.md. Each macro evaluates
   its int status argument once. Exit: status << 8. Signal death: the signal
   in bits 0-6 (bit 7 records a core dump). Stopped: signal << 8 | 0x7f. */
#include <sys/types.h>
#define WNOHANG 1
#define WUNTRACED 2
#define WEXITSTATUS(status) (((status) >> 8) & 255)
#define WTERMSIG(status) ((status) & 127)
#define WSTOPSIG(status) WEXITSTATUS(status)
#define WIFEXITED(status) (WTERMSIG(status) == 0)
#define WIFSTOPPED(status) (((status) & 255) == 127)
#define WIFSIGNALED(status) (((((status) & 127) + 1) & 127) > 1)
pid_t waitpid(pid_t process, int *status, int options);
pid_t wait(int *status);
#endif
