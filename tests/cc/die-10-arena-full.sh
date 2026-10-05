# Error 10: the 32 KiB arena is full.  Each one-field struct definition
# takes a 56-byte descriptor header and a 320-byte field table (room for
# 8 legacy records) from it: 87 fit in 32,712 bytes, and the 88th
# struct's header exactly fills the arena, so its field table does not fit.
i=1
while [ $i -le 100 ]; do
  echo "struct s$i { int a; };"
  i=$((i + 1))
done
echo "int main() { return 0; }"
