/* Tags, members and ordinary identifiers occupy their C namespaces. */
struct stat { int stat; };
int stat(const char *, struct stat *);
int stat(const char *path, struct stat *value) { value->stat = *path; return 0; }

int reverse(int value);
struct reverse { long reverse; };
int reverse(int value) { return value + 1; }

int shared = 19;
struct shared { int shared; };
int *shared_address = &shared;

typedef unsigned long Alias;
struct Alias { int Alias; };
struct Later { long Later; };
typedef struct Later Later;
Alias alias_value = 23;

enum values { enumerator = 29 };
struct enumerator { int enumerator; };
int enum_value = enumerator;

union choice { long choice; int smaller; };
int choice(union choice *value) { return value->choice; }

typedef int (*Callback)(int);
struct Callback { int Callback; };
Callback callback = reverse;

int namespace_check(void) {
    struct stat value;
    struct reverse reverse_value;
    struct shared shared_value;
    struct Alias alias_record;
    Later later;
    union choice choice_value;
    int result;
    result = stat("A", &value);
    reverse_value.reverse = reverse(6);
    shared_value.shared = *shared_address;
    alias_record.Alias = sizeof(Alias);
    later.Later = alias_value;
    choice_value.choice = enumerator;
    if (result || value.stat != 65 || reverse_value.reverse != 7) return 1;
    if (shared_value.shared != 19 || alias_record.Alias != 8) return 2;
    if (later.Later != 23 || enum_value != 29 || choice(&choice_value) != 29) return 3;
    if (callback(30) != 31 || sizeof(struct Callback) != 4) return 4;
    {
        int stat = 37;
        struct stat inner;
        inner.stat = stat;
        if (inner.stat != 37 || sizeof(struct stat) != 4) return 5;
    }
    {
        struct reverse { int payload; };
        struct reverse inner;
        inner.payload = reverse(40);
        if (inner.payload != 41) return 6;
    }
    return 0;
}
int main(void) { return namespace_check(); }
