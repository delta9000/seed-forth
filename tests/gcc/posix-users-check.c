/* POSIX user/group database fixture: Forth runtime versus host glibc
   (NSS "files" only). The gate supplies /etc/passwd and /etc/group. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>

static void show_user(const char *label, struct passwd *entry)
{
    if (entry == NULL) {
        printf("%s none errno %d\n", label, errno);
        return;
    }
    printf("%s [%s] [%s] %u %u [%s] [%s] [%s]\n", label, entry->pw_name, entry->pw_passwd,
           (unsigned)entry->pw_uid, (unsigned)entry->pw_gid, entry->pw_gecos, entry->pw_dir,
           entry->pw_shell);
}

static void show_group(const char *label, struct group *entry)
{
    char **member;
    if (entry == NULL) {
        printf("%s none errno %d\n", label, errno);
        return;
    }
    printf("%s [%s] [%s] %u", label, entry->gr_name, entry->gr_passwd, (unsigned)entry->gr_gid);
    for (member = entry->gr_mem; *member; member++) printf(" <%s>", *member);
    printf("\n");
}

int main(void)
{
    struct passwd *user;
    struct group *group;
    char name[64];
    int count = 0, error;
    setvbuf(stdout, NULL, _IONBF, 0);
    errno = 0;
    while ((user = getpwent()) != NULL) show_user("getpwent", user);
    endpwent();
    setpwent();
    show_user("again", getpwent());
    show_user("next", getpwent());
    errno = 0;
    show_user("lookup during scan", getpwnam("daemon"));
    show_user("scan continues", getpwent());
    endpwent();
    errno = 0;
    show_user("getpwnam root", getpwnam("root"));
    show_user("getpwnam alice", getpwnam("alice"));
    show_user("getpwnam colon", getpwnam("colon"));
    show_user("getpwnam empty-gecos", getpwnam("empty"));
    show_user("getpwnam missing", getpwnam("missing"));
    show_user("getpwnam short", getpwnam("short"));
    show_user("getpwnam comment", getpwnam("# comment line"));
    show_user("getpwuid 0", getpwuid(0));
    show_user("getpwuid 1000", getpwuid(1000));
    show_user("getpwuid 2000", getpwuid(2000));
    show_user("getpwuid 4242", getpwuid(4242));
    show_user("getpwuid big", getpwuid(4000000000U));
    errno = 0;
    while ((group = getgrent()) != NULL) {
        show_group("getgrent", group);
        count++;
    }
    endgrent();
    printf("groups %d\n", count);
    setgrent();
    show_group("again", getgrent());
    endgrent();
    errno = 0;
    show_group("getgrnam wheel", getgrnam("wheel"));
    show_group("getgrnam empty", getgrnam("empty"));
    show_group("getgrnam trailing", getgrnam("trailing"));
    show_group("getgrnam missing", getgrnam("missing"));
    show_group("getgrgid 0", getgrgid(0));
    show_group("getgrgid 100", getgrgid(100));
    show_group("getgrgid 9999", getgrgid(9999));
    errno = 0;
    if (getlogin() == NULL) printf("getlogin none errno %d\n", errno);
    else printf("getlogin %s\n", getlogin());
    error = getlogin_r(name, 2);
    printf("getlogin_r small %d\n", error);
    error = getlogin_r(name, sizeof(name));
    printf("getlogin_r %d %s\n", error, error ? "-" : name);
    puts("done");
    return 0;
}
