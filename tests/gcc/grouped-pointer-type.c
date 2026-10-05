/* Grouped abstract pointers retain base type, depth and descriptors. */
typedef int *IntPointer;
typedef int (*Callback)(int);
struct Item { int value; };
int increment(int n) { return n + 1; }
int main(void)
{
    int n = 41;
    int *p = &n;
    int **pp = &p;
    struct Item item = { 19 };
    struct Item *ip = &item;
    Callback cb = increment;
    int row[2] = { 7, 8 };
    typedef int Row[2];
    Row *rp = &row;
    char *(*pfn) = (char *(*)) increment;
    if (((int (*)(int))pfn)(41) != 42) return 1;
    if (**(int (**))pp != 41) return 2;
    if (**(IntPointer (*))pp != 41) return 3;
    if (((struct Item (*))ip)->value != 19) return 4;
    if ((*(Callback (*))&cb)(41) != 42) return 5;
    if ((*(Row (*))rp)[1] != 8) return 6;
    if (**(const int (*const *))pp != 41) return 7;
    if (sizeof(char *(*)) != sizeof(char **)) return 8;
    if (sizeof(*(int (*))p) != sizeof(int)) return 9;
    if (sizeof(*(struct Item (*))ip) != sizeof(struct Item)) return 10;
    return 0;
}
