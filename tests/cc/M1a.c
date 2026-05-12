/* M.1.b: built-in libc constants (NULL, EOF, EXIT_*, std{in,out,err}). */

int main()
{
    int *p = NULL;
    int sum = 0;
    if (p == NULL) sum = sum + 1;
    if (EOF == 0 - 1) sum = sum + 2;
    if (EXIT_SUCCESS == 0) sum = sum + 4;
    if (EXIT_FAILURE == 1) sum = sum + 8;
    if (stdin == 0) sum = sum + 16;
    if (stdout == 1) sum = sum + 32;
    if (stderr == 2) sum = sum + 64;
    return sum;
}
