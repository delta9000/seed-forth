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
/* Single kernel calls; see ../FILE-METADATA.md. chown follows a final
   symbolic link; (uid_t)-1 or (gid_t)-1 leaves that ID unchanged. */
int chown(const char *path, uid_t owner, gid_t group);
int rmdir(const char *path);
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
/* POSIX identification; values match Linux glibc. See ../SYSINFO.md. */
#define _POSIX_VERSION 200809L
#define _POSIX2_VERSION 200809L
#define _POSIX_JOB_CONTROL 1
#define _POSIX_SAVED_IDS 1
#define _POSIX_NO_TRUNC 1
#define _POSIX_CHOWN_RESTRICTED 0
#define _POSIX_VDISABLE '\0'
/* Alarm and pause; see ../SIGNALS.md. alarm cannot fail. */
unsigned int alarm(unsigned int seconds);
int pause(void);
/* Identity and sessions; see ../IDENTITY.md. The get* calls cannot fail. */
uid_t getuid(void);
uid_t geteuid(void);
gid_t getgid(void);
gid_t getegid(void);
pid_t getppid(void);
pid_t getpgrp(void);
pid_t getpgid(pid_t process);
int setpgid(pid_t process, pid_t group);
pid_t setsid(void);
pid_t getsid(pid_t process);
int setuid(uid_t user);
int setgid(gid_t group);
int seteuid(uid_t user);
int setegid(gid_t group);
int setreuid(uid_t real, uid_t effective);
int setregid(gid_t real, gid_t effective);
int getgroups(int size, gid_t list[]);
int nice(int increment);
/* Login name of the session's audit login uid; NULL (ENXIO) without one. */
char *getlogin(void);
int getlogin_r(char *buffer, size_t size);
/* System information; see ../SYSINFO.md. Only the names below exist. */
int gethostname(char *name, size_t size);
int getpagesize(void);
int getdtablesize(void);
long sysconf(int name);
long pathconf(const char *path, int name);
long fpathconf(int descriptor, int name);
#define _SC_ARG_MAX 0
#define _SC_CHILD_MAX 1
#define _SC_CLK_TCK 2
#define _SC_NGROUPS_MAX 3
#define _SC_OPEN_MAX 4
#define _SC_STREAM_MAX 5
#define _SC_TZNAME_MAX 6
#define _SC_JOB_CONTROL 7
#define _SC_SAVED_IDS 8
#define _SC_VERSION 29
#define _SC_PAGESIZE 30
#define _SC_PAGE_SIZE _SC_PAGESIZE
#define _SC_RTSIG_MAX 31
#define _SC_BC_BASE_MAX 36
#define _SC_BC_DIM_MAX 37
#define _SC_BC_SCALE_MAX 38
#define _SC_BC_STRING_MAX 39
#define _SC_COLL_WEIGHTS_MAX 40
#define _SC_EXPR_NEST_MAX 42
#define _SC_LINE_MAX 43
#define _SC_RE_DUP_MAX 44
#define _SC_2_VERSION 46
#define _SC_IOV_MAX 60
#define _SC_GETGR_R_SIZE_MAX 69
#define _SC_GETPW_R_SIZE_MAX 70
#define _SC_LOGIN_NAME_MAX 71
#define _SC_TTY_NAME_MAX 72
#define _SC_NPROCESSORS_CONF 83
#define _SC_NPROCESSORS_ONLN 84
#define _SC_PHYS_PAGES 85
#define _SC_AVPHYS_PAGES 86
#define _SC_SYMLOOP_MAX 173
#define _SC_HOST_NAME_MAX 180
#define _PC_LINK_MAX 0
#define _PC_MAX_CANON 1
#define _PC_MAX_INPUT 2
#define _PC_NAME_MAX 3
#define _PC_PATH_MAX 4
#define _PC_PIPE_BUF 5
#define _PC_CHOWN_RESTRICTED 6
#define _PC_NO_TRUNC 7
#define _PC_VDISABLE 8
#define _PC_FILESIZEBITS 13
#define _PC_SYMLINK_MAX 19
#define _PC_2_SYMLINKS 20
/* File calls, one Linux syscall each; see ../FILE-CALLS.md. */
int symlink(const char *target, const char *path);
/* No terminating NUL is written; the result is the byte count. */
ssize_t readlink(const char *path, char *buffer, size_t size);
int fchdir(int descriptor);
int fchown(int descriptor, uid_t owner, gid_t group);
int lchown(const char *path, uid_t owner, gid_t group);
int ftruncate(int descriptor, off_t length);
int truncate(const char *path, off_t length);
int fsync(int descriptor);
int fdatasync(int descriptor);
int chroot(const char *path);
void sync(void);
/* O_CLOEXEC is the only flag; see ../FILE-CALLS.md. */
int dup3(int descriptor, int target, int flags);
int pipe2(int descriptors[2], int flags);
/* Terminal names and foreground process groups; see ../TERMIOS.md. */
char *ttyname(int descriptor);
int ttyname_r(int descriptor, char *buffer, size_t size);
pid_t tcgetpgrp(int descriptor);
int tcsetpgrp(int descriptor, pid_t group);
/* Sleeping; see ../SYSINFO.md. */
int usleep(useconds_t microseconds);
/* Argument-list exec forms; see ../PROCESS-POSIX.md. At most 4095
   arguments; execle reads the environment after the terminating NULL. */
int execl(const char *path, const char *argument, ...);
int execlp(const char *file, const char *argument, ...);
int execle(const char *path, const char *argument, ...);
#endif
