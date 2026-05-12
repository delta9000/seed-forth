#include <stdio.h>
int main() {
    int sum = 0;
    int i = 1;
    while (i <= 10) {
        sum = sum + i;
        i = i + 1;
    }
    /* sum = 55 */
    int j;
    for (j = 0; j < 5; j = j + 1) {
        sum += 1;
    }
    /* sum = 60 */
    return sum;
}
