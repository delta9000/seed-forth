struct entry;
typedef struct entry Entry;
struct entry { Entry *next; long value; };
int errno;
int errno = 0;
int main(void) { Entry a; Entry b; a.next=&b; b.value=73; errno=4; return a.next->value + errno - 77; }
