/* Original seed-forth implementation; see LICENSE and PASSWD.md.
   /etc/group lookups. Results share one static record. */
#include <grp.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <seed-dbfile.h>

#define SEED_GROUP_PATH "/etc/group"
static struct group seed_group;
static char **seed_members;
static char *seed_lookup_text;
static char *seed_scan_text;
static char *seed_scan_cursor;

/* Fill seed_group from LINE; 0 for a malformed entry or no memory. */
static int seed_group_entry(char *line)
{
    char *fields[4], *member, *comma, **vector;
    unsigned int group;
    size_t count = 1, index = 0;
    /* The member list may be absent entirely ("name:x:gid"). */
    if (!__seed_split_fields(line, fields, 4)) {
        if (!__seed_split_fields(line, fields, 3)) return 0;
        fields[3] = line + strlen(line);
    }
    if (!__seed_parse_id(fields[2], &group)) return 0;
    for (member = fields[3]; *member; member++)
        if (*member == ',') count++;
    vector = malloc((count + 1) * sizeof(*vector));
    if (vector == NULL) return 0;
    member = fields[3];
    while (*member) {
        comma = strchr(member, ',');
        if (comma) *comma = '\0';
        if (*member) vector[index++] = member;
        if (comma == NULL) break;
        member = comma + 1;
    }
    vector[index] = NULL;
    free(seed_members);
    seed_members = vector;
    seed_group.gr_name = fields[0];
    seed_group.gr_passwd = fields[1];
    seed_group.gr_gid = group;
    seed_group.gr_mem = vector;
    return 1;
}

static struct group *seed_group_find(const char *name, gid_t group)
{
    char *cursor, *line;
    int saved = errno;
    free(seed_lookup_text);
    seed_lookup_text = __seed_load_file(SEED_GROUP_PATH);
    if (seed_lookup_text == NULL) {
        if (errno == ENOENT) errno = saved;
        return NULL;
    }
    cursor = seed_lookup_text;
    while ((line = __seed_next_entry(&cursor)) != NULL) {
        if (!seed_group_entry(line)) continue;
        if (name ? strcmp(seed_group.gr_name, name) == 0 : seed_group.gr_gid == group)
            return &seed_group;
    }
    return NULL;
}

struct group *getgrnam(const char *name) { return seed_group_find(name, 0); }
struct group *getgrgid(gid_t group) { return seed_group_find(NULL, group); }

/* Parsing splits the text in place, so rewinding rereads the file. */
void endgrent(void)
{
    free(seed_scan_text);
    seed_scan_text = NULL;
    seed_scan_cursor = NULL;
}

void setgrent(void)
{
    endgrent();
}

struct group *getgrent(void)
{
    char *line;
    if (seed_scan_text == NULL) {
        seed_scan_text = __seed_load_file(SEED_GROUP_PATH);
        if (seed_scan_text == NULL) return NULL;
        seed_scan_cursor = seed_scan_text;
    }
    while ((line = __seed_next_entry(&seed_scan_cursor)) != NULL)
        if (seed_group_entry(line)) return &seed_group;
    return NULL;
}
