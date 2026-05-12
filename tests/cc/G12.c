int square(int n) { return n * n; }
int cube(int n)   { return n * n * n; }

int main()
{
    int (*op)(int);
    op = square;
    int a = op(5);     /* 25 */
    op = cube;
    int b = op(3);     /* 27 */
    op = square;
    int c = op(7);     /* 49 */
    return a - b + c;  /* 47 */
}
