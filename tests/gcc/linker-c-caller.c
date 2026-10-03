long total(long, long, long, long, long, long, long, long);

static long adjust(long value)
{
    return value + 5;
}

int main(void)
{
    return adjust(total(1, 2, 3, 4, 5, 6, 7, 8));
}
