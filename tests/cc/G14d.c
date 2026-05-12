int g_counter = 100;
int g_array[5];

int bump()
{
    g_counter = g_counter + 1;
    return g_counter;
}

int main()
{
    g_array[0] = 7;
    g_array[1] = 11;
    int sum = bump() + bump() + g_array[0] + g_array[1];
    /* bump() returns 101, then 102. Sum = 101 + 102 + 7 + 11 = 221. */
    return sum;
}
