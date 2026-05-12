int main()
{
    int sum = 0;
    int i = 0;
    do {
        i = i + 1;
        if (i == 5) {
            continue;
        }
        if (i > 10) {
            break;
        }
        sum = sum + i;
    } while (i < 100);
    return sum;
}
