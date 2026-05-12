int main()
{
    int x = 5;
    int y = 0;

    int a = x++;
    int b = ++x;

    int s = 1 << 4;
    int r = 256 >> 2;

    int and_v = 255 & 15;
    int or_v  = 16 | 32;

    int t = (x > 0) && (y == 0);
    int f = (x < 0) || (y > 100);

    int q = (x > y) ? 100 : 200;

    int c = 10;
    c += 5;
    c *= 2;
    c -= 4;
    c /= 2;
    c <<= 1;

    /* a=5, b=7, s=16, r=64, and_v=15, or_v=48, t=1, f=0, q=100, c=26
       a+b+s+r+and_v+or_v+t+q+c = 282; halved = 141 (fits in exit byte). */
    return (a + b + s + r + and_v + or_v + t + q + c) / 2;
}
