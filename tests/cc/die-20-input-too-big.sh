# Error 20: the raw source fills the 1 MiB input buffer (cc-in-buf).
echo "int main() { return 0; }"
i=0
while [ $i -lt 17 ]; do          # 17 x 64 KiB of blank lines
  head -c 65536 /dev/zero | tr '\0' '\n'
  i=$((i + 1))
done
