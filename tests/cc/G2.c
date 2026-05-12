int main()
{
    int a = 5;
    int b = 10;
    int result = 0;

    if (a < b) {
        result = 1;
    } else {
        result = 2;
    }

    if (a == 5) {
        if (b > 0) {
            result = result + 40;
        }
    }

    if (a >= 100) {
        result = 999;
    }

    return result;
}
