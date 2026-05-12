int main()
{
    int sum = 0;
    int i;
    for (i = 0; i < 6; i = i + 1) {
        switch (i) {
        case 0:
            sum = sum + 100;
            break;
        case 1:
            sum = sum + 10;
        case 2:
            sum = sum + 1;
            break;
        case 5:
            sum = sum + 50;
            break;
        default:
            sum = sum + 1000;
            break;
        }
    }
    return sum;
}
