int main()
{
    int x = 0;
    goto skip;
    x = 100;
skip:
    x = x + 7;
    return x;
}
