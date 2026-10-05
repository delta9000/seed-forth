#ifndef SEED_GCC_UNISTD_H
#define SEED_GCC_UNISTD_H
#include <sys/types.h>
/* Original seed-forth bounded interface; only implemented calls appear here. */
extern char **environ;
extern char *optarg;
extern int optind;
extern int opterr;
extern int optopt;
/* POSIX-style short options; stops at the first operand, no permutation. */
int getopt(int count, char *const arguments[], const char *options);
#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
#define F_OK 0
#define X_OK 1
#define W_OK 2
#define R_OK 4
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
/* Single kernel calls: partial reads, EOF and EINTR are returned directly.
   close never retries and does not change or own any FILE object. */
ssize_t read(int descriptor, void *bytes, size_t count);
int close(int descriptor);
off_t lseek(int descriptor, off_t offset, int whence);
/* A single kernel write; partial progress and EINTR are returned to the caller. */
ssize_t write(int descriptor, const void *bytes, size_t count);
int isatty(int descriptor);
/* Permission checks use real user/group IDs, with Linux access semantics. */
int access(const char *path, int mode);
pid_t getpid(void);
/* Caller buffer only; NULL/zero size fail EINVAL; kernel long-path bound. */
char *getcwd(char *buffer, size_t size);
int unlink(const char *path);
/* Single kernel calls; see ../DRIVER-RUNTIME.md. */
int chdir(const char *path);
int link(const char *existing, const char *name);
void _exit(int status);
/* Process API; see ../PROCESS-API.md. vfork is an ordinary fork. execv and
   execvp pass the current environ; execvp searches PATH (default
   /bin:/usr/bin) and does not retry ENOEXEC files with a shell. */
int pipe(int descriptors[2]);
int dup(int descriptor);
int dup2(int descriptor, int target);
pid_t fork(void);
pid_t vfork(void);
int execve(const char *path, char *const arguments[], char *const environment[]);
int execv(const char *path, char *const arguments[]);
int execvp(const char *file, char *const arguments[]);
/* Returns unslept whole seconds (a partial second rounds up) after EINTR. */
unsigned int sleep(unsigned int seconds);
#endif
