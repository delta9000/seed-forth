/* Pre-existing syntax: compare before/after bytes in default and native modes. */
int sum(int n) {
    int i;
    int j;
    int s;
    i = 0;
    s = 0;
    for (i = 0; i < n; /* real step */ ++i) {
        if (i == 2) continue;
        for (j = 3; j > 0; --j) { if (j == 2) break; s = s + i + j; }
    }
    return s;
}
int main(void) { return sum(5) != 20; }
