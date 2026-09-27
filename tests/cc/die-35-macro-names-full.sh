# Error 35: macro names overflow the 16 KiB name pool.  Each name here is
# 100 bytes; the built-ins' names already take 48.
i=1
while [ $i -le 200 ]; do
  printf '#define M%03d' $i
  awk 'BEGIN { for (j = 0; j < 96; j++) printf "x" }'
  echo " $i"
  i=$((i + 1))
done
echo "int main() { return 0; }"
