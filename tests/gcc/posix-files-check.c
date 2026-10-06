/* POSIX file-call fixture: Forth runtime versus host glibc. Runs in a fresh
   empty directory; absolute names are printed relative to it. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <utime.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <sys/sysmacros.h>

#define CALL(label, expression) do { long value_; errno = 0; value_ = (long)(expression); int error_ = errno; \
    printf("%s %ld errno %d\n", label, value_, error_); errno = 0; } while (0)

static char home[PATH_MAX];

static void show_path(const char *label, const char *path)
{
    size_t length = strlen(home);
    if (path == NULL) {
        printf("%s NULL errno %d\n", label, errno);
    } else if (strncmp(path, home, length) == 0) {
        printf("%s <cwd>%s\n", label, path + length);
    } else {
        printf("%s %s\n", label, path);
    }
    errno = 0;
}

static void write_file(const char *path, const char *text)
{
    int descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (write(descriptor, text, strlen(text)) < 0) puts("write failed");
    close(descriptor);
}

static void links(void)
{
    char buffer[64];
    ssize_t count;
    write_file("target", "hello\n");
    CALL("symlink", symlink("target", "link"));
    CALL("symlink exists", symlink("target", "link"));
    count = readlink("link", buffer, sizeof(buffer));
    printf("readlink %ld %.*s\n", (long)count, (int)(count > 0 ? count : 0), buffer);
    memset(buffer, 'x', sizeof(buffer));
    count = readlink("link", buffer, 3);
    printf("readlink short %ld %.4s\n", (long)count, buffer);
    CALL("readlink regular", readlink("target", buffer, sizeof(buffer)));
    CALL("readlink missing", readlink("missing", buffer, sizeof(buffer)));
    CALL("link", link("target", "hard"));
    CALL("lchown none", lchown("link", (uid_t)-1, (gid_t)-1));
    CALL("chown none", chown("link", (uid_t)-1, (gid_t)-1));
    CALL("symlink dangling", symlink("nowhere", "dangling"));
    CALL("symlink loop a", symlink("loop-b", "loop-a"));
    CALL("symlink loop b", symlink("loop-a", "loop-b"));
}

static void metadata(void)
{
    struct stat status;
    struct timeval times[2];
    struct utimbuf old;
    int descriptor;
    mode_t previous = umask(022);
    descriptor = creat("created", 0777);
    printf("creat %d\n", descriptor >= 0);
    fstat(descriptor, &status);
    printf("creat mode %o size %ld\n", (unsigned)(status.st_mode & 07777), (long)status.st_size);
    CALL("fchmod", fchmod(descriptor, 0640));
    fstat(descriptor, &status);
    printf("fchmod mode %o\n", (unsigned)(status.st_mode & 07777));
    CALL("fchown none", fchown(descriptor, (uid_t)-1, (gid_t)-1));
    CALL("write", write(descriptor, "0123456789", 10));
    CALL("ftruncate", ftruncate(descriptor, 4));
    fstat(descriptor, &status);
    printf("size after ftruncate %ld\n", (long)status.st_size);
    CALL("fsync", fsync(descriptor));
    CALL("fdatasync", fdatasync(descriptor));
    close(descriptor);
    CALL("truncate", truncate("created", 100));
    stat("created", &status);
    printf("size after truncate %ld blocks-type %d\n", (long)status.st_size, (int)sizeof(status.st_blocks));
    CALL("truncate missing", truncate("missing", 1));
    descriptor = open("created", O_RDONLY);
    CALL("ftruncate read-only", ftruncate(descriptor, 0));
    close(descriptor);
    CALL("creat directory", creat(".", 0644));
    times[0].tv_sec = 1000000000;
    times[0].tv_usec = 500000;
    times[1].tv_sec = 1234567890;
    times[1].tv_usec = 250;
    CALL("utimes", utimes("created", times));
    stat("created", &status);
    printf("atime %ld %ld mtime %ld %ld\n", (long)status.st_atim.tv_sec, status.st_atim.tv_nsec,
           (long)status.st_mtim.tv_sec, status.st_mtim.tv_nsec);
    printf("aliases %d %d %d\n", status.st_atime == status.st_atim.tv_sec,
           status.st_mtime == status.st_mtim.tv_sec, status.st_ctime == status.st_ctim.tv_sec);
    old.actime = 86400;
    old.modtime = 172800;
    CALL("utime", utime("created", &old));
    stat("created", &status);
    printf("utime %ld %ld nsec %ld\n", (long)status.st_atime, (long)status.st_mtime, status.st_mtim.tv_nsec);
    CALL("utimes now", utimes("created", NULL));
    CALL("mkfifo", mkfifo("fifo", 0666));
    lstat("fifo", &status);
    printf("fifo %d mode %o\n", S_ISFIFO(status.st_mode), (unsigned)(status.st_mode & 07777));
    CALL("mkfifo exists", mkfifo("fifo", 0666));
    CALL("mknod regular", mknod("node", S_IFREG | 0600, 0));
    lstat("node", &status);
    printf("node %d mode %o\n", S_ISREG(status.st_mode), (unsigned)(status.st_mode & 07777));
    if (geteuid() != 0) {
        CALL("mknod device", mknod("device", S_IFCHR | 0600, makedev(1, 3)));
        CALL("chroot", chroot("."));
    }
    umask(previous);
    sync();
    printf("S_IREAD %o S_IWRITE %o S_IEXEC %o ALLPERMS %o\n", S_IREAD, S_IWRITE, S_IEXEC, ALLPERMS);
}

static void devices(void)
{
    struct stat status;
    dev_t device;
    device = makedev(8, 1);
    printf("makedev 8 1 %lu major %u minor %u\n", (unsigned long)device, major(device), minor(device));
    device = makedev(0x12345, 0xabcdef);
    printf("makedev big %lx major %x minor %x\n", (unsigned long)device, major(device), minor(device));
    device = makedev(4095, 255);
    printf("makedev edge %lx\n", (unsigned long)device);
    stat("/dev/null", &status);
    printf("/dev/null %u %u chr %d\n", major(status.st_rdev), minor(status.st_rdev), S_ISCHR(status.st_mode));
}

static int compare_names(const void *left, const void *right)
{
    return strcmp(*(char *const *)left, *(char *const *)right);
}

static void directories(void)
{
    DIR *directory;
    struct dirent *entry;
    struct stat status;
    char *names[64];
    int count = 0, again = 0, index;
    directory = opendir(".");
    printf("dirfd %d\n", dirfd(directory) >= 0);
    fstat(dirfd(directory), &status);
    printf("dirfd is directory %d\n", S_ISDIR(status.st_mode));
    while ((entry = readdir(directory)) != NULL && count < 64) {
        names[count] = malloc(strlen(entry->d_name) + 8);
        sprintf(names[count], "%s %d", entry->d_name, entry->d_type);
        count++;
    }
    rewinddir(directory);
    while (readdir(directory) != NULL) again++;
    closedir(directory);
    qsort(names, (size_t)count, sizeof(names[0]), compare_names);
    for (index = 0; index < count; index++) printf("entry %s\n", names[index]);
    printf("rewound count %d %d\n", again, count);
    printf("DT %d %d %d %d %d %d %d %d\n", DT_UNKNOWN, DT_FIFO, DT_CHR, DT_DIR, DT_BLK, DT_REG, DT_LNK, DT_SOCK);
    printf("IFTODT %d %d DTTOIF %o\n", IFTODT(S_IFDIR), IFTODT(S_IFLNK), (unsigned)DTTOIF(DT_REG));
    CALL("mkdir", mkdir("sub", 0755));
    CALL("mkdir inner", mkdir("sub/inner", 0755));
    index = open("sub", O_RDONLY | O_DIRECTORY);
    CALL("fchdir", fchdir(index));
    close(index);
    write_file("inner/file", "x");
    CALL("chdir back", chdir(".."));
    CALL("fchdir bad", fchdir(-1));
}

static void resolution(void)
{
    char buffer[PATH_MAX], *allocated;
    show_path("realpath .", realpath(".", buffer));
    show_path("realpath target", realpath("target", buffer));
    show_path("realpath link", realpath("link", buffer));
    show_path("realpath dots", realpath("./sub/../sub/./inner/../inner/file", buffer));
    show_path("realpath slashes", realpath("sub//inner///", buffer));
    show_path("realpath root", realpath("/", buffer));
    show_path("realpath root dots", realpath("/../..//./", buffer));
    show_path("realpath abs", realpath("/dev/null", buffer));
    CALL("symlink to dir", symlink("sub/inner", "inner-link"));
    CALL("symlink abs", symlink("/dev", "dev-link"));
    show_path("realpath through", realpath("inner-link/file", buffer));
    show_path("realpath through dotdot", realpath("inner-link/../inner/file", buffer));
    show_path("realpath abs link", realpath("dev-link/null", buffer));
    show_path("realpath dangling", realpath("dangling", buffer));
    show_path("realpath loop", realpath("loop-a", buffer));
    show_path("realpath missing", realpath("missing/x", buffer));
    show_path("realpath notdir", realpath("target/", buffer));
    show_path("realpath notdir dot", realpath("target/.", buffer));
    show_path("realpath notdir more", realpath("target/x", buffer));
    show_path("realpath empty", realpath("", buffer));
    allocated = realpath("sub/inner", NULL);
    show_path("realpath allocated", allocated);
    free(allocated);
}

static void descriptors(void)
{
    int ends[2], descriptor, copy, count;
    struct winsize size;
    descriptor = open("created", O_RDONLY);
    CALL("dup3 same", dup3(descriptor, descriptor, 0));
    copy = dup3(descriptor, 20, O_CLOEXEC);
    printf("dup3 %d cloexec %d\n", copy, fcntl(copy, F_GETFD) & FD_CLOEXEC);
    close(copy);
    CALL("dup3 bad flags", dup3(descriptor, 21, 1));
    close(descriptor);
    CALL("pipe2", pipe2(ends, O_CLOEXEC | O_NONBLOCK));
    printf("pipe2 flags %d %d\n", fcntl(ends[0], F_GETFD) & FD_CLOEXEC, (fcntl(ends[1], F_GETFL) & O_NONBLOCK) != 0);
    CALL("write pipe", write(ends[1], "abcde", 5));
    count = -1;
    CALL("FIONREAD", ioctl(ends[0], FIONREAD, &count));
    printf("pending %d\n", count);
    CALL("fsync pipe", fsync(ends[0]));
    CALL("TIOCGWINSZ pipe", ioctl(ends[0], TIOCGWINSZ, &size));
    close(ends[0]);
    close(ends[1]);
    descriptor = open("synced", O_WRONLY | O_CREAT | O_SYNC | O_NOATIME, 0600);
    printf("O_SYNC open %d flags %d\n", descriptor >= 0, (fcntl(descriptor, F_GETFL) & O_SYNC) == O_SYNC);
    close(descriptor);
    printf("O constants %d %d %d %d %d\n", O_SYNC, O_DSYNC, O_NDELAY, O_ASYNC, O_NOATIME);
}

static void locks(void)
{
    int descriptor, status;
    pid_t child;
    descriptor = open("created", O_RDWR);
    CALL("flock ex", flock(descriptor, LOCK_EX));
    child = fork();
    if (child == 0) {
        int other = open("created", O_RDWR);
        errno = 0;
        if (flock(other, LOCK_EX | LOCK_NB) != -1 || errno != EWOULDBLOCK) _exit(1);
        if (flock(other, LOCK_SH | LOCK_NB) != -1) _exit(2);
        _exit(0);
    }
    waitpid(child, &status, 0);
    printf("contended child %d\n", WEXITSTATUS(status));
    CALL("flock un", flock(descriptor, LOCK_UN));
    child = fork();
    if (child == 0) {
        int other = open("created", O_RDWR);
        _exit(flock(other, LOCK_EX | LOCK_NB) == 0 ? 0 : 1);
    }
    waitpid(child, &status, 0);
    printf("free child %d\n", WEXITSTATUS(status));
    CALL("flock sh", flock(descriptor, LOCK_SH));
    CALL("flock bad", flock(descriptor, 99));
    CALL("flock badf", flock(-1, LOCK_EX));
    close(descriptor);
    printf("LOCK %d %d %d %d\n", LOCK_SH, LOCK_EX, LOCK_NB, LOCK_UN);
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    if (getcwd(home, sizeof(home)) == NULL) return 1;
    links();
    metadata();
    devices();
    directories();
    resolution();
    descriptors();
    locks();
    puts("done");
    return 0;
}
