# Error 37: a macro argument's expansion overflows its 64 KiB temporary
# buffer.  The argument is 70,000 bytes of 1+1+...
echo "#define ID(x) x"
printf 'int main() { return ID('
awk 'BEGIN { for (i = 0; i < 35000; i++) printf "1+" }'
echo '0); }'
