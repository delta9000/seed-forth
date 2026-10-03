struct file_record { int value; };
struct buf { int value; };
struct stat { int value; };
typedef struct file_record FILE;
int stat(const char *, struct stat *);
int pairnames(int, char **, FILE *(*)(struct buf *, struct stat *, int), int, int);
int pairnames(int count, char **names, FILE *(*open_file)(struct buf *b, struct stat *s, int flags), int first, int last);
FILE result;
FILE *open_record(struct buf *b, struct stat *s, int flags) {
    result.value = b->value + s->value + flags;
    return &result;
}
int pairnames(int count, char **names, FILE *(*open_file)(struct buf *, struct stat *, int), int first, int last) {
    struct buf b;
    struct stat s;
    FILE *p;
    b.value = first;
    s.value = last;
    p = open_file(&b, &s, count);
    return sizeof(open_file) == 8 && sizeof(p) == 8 && p == &result && p->value == 42;
}
int main(void) { return pairnames(12, 0, open_record, 13, 17) != 1; }
