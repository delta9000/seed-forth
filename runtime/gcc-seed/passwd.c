/* Original seed-forth implementation; see LICENSE and PASSWD.md.
   /etc/passwd lookups. Results share one static record. */
#include <pwd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <seed-dbfile.h>

#define SEED_PASSWD_PATH "/etc/passwd"
static struct passwd seed_passwd;
/* Separate storage for lookups and for the getpwent enumeration, so a
   lookup does not disturb an enumeration in progress. */
static char *seed_lookup_text;
static char *seed_scan_text;
static char *seed_scan_cursor;

/* Fill seed_passwd from LINE; 0 for a malformed entry. */
static int seed_passwd_entry(char *line)
{
    char *fields[7];
    unsigned int user, group;
    if (!__seed_split_fields(line, fields, 7)) return 0;
    if (!__seed_parse_id(fields[2], &user) || !__seed_parse_id(fields[3], &group)) return 0;
    seed_passwd.pw_name = fields[0];
    seed_passwd.pw_passwd = fields[1];
    seed_passwd.pw_uid = user;
    seed_passwd.pw_gid = group;
    seed_passwd.pw_gecos = fields[4];
    seed_passwd.pw_dir = fields[5];
    seed_passwd.pw_shell = fields[6];
    return 1;
}

/* First entry matching NAME (when nonnull) or USER. A missing entry
   returns NULL with errno unchanged; a read failure sets errno. */
static struct passwd *seed_passwd_find(const char *name, uid_t user)
{
    char *cursor, *line;
    int saved = errno;
    free(seed_lookup_text);
    seed_lookup_text = __seed_load_file(SEED_PASSWD_PATH);
    if (seed_lookup_text == NULL) {
        if (errno == ENOENT) errno = saved;
        return NULL;
    }
    cursor = seed_lookup_text;
    while ((line = __seed_next_entry(&cursor)) != NULL) {
        if (!seed_passwd_entry(line)) continue;
        if (name ? strcmp(seed_passwd.pw_name, name) == 0 : seed_passwd.pw_uid == user)
            return &seed_passwd;
    }
    return NULL;
}

struct passwd *getpwnam(const char *name) { return seed_passwd_find(name, 0); }
struct passwd *getpwuid(uid_t user) { return seed_passwd_find(NULL, user); }

/* Parsing splits the text in place, so rewinding rereads the file. */
void endpwent(void)
{
    free(seed_scan_text);
    seed_scan_text = NULL;
    seed_scan_cursor = NULL;
}

void setpwent(void)
{
    endpwent();
}

struct passwd *getpwent(void)
{
    char *line;
    if (seed_scan_text == NULL) {
        seed_scan_text = __seed_load_file(SEED_PASSWD_PATH);
        if (seed_scan_text == NULL) return NULL;
        seed_scan_cursor = seed_scan_text;
    }
    while ((line = __seed_next_entry(&seed_scan_cursor)) != NULL)
        if (seed_passwd_entry(line)) return &seed_passwd;
    return NULL;
}
