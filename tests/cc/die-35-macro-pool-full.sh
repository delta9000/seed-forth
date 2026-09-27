# Error 35: macro names and bodies overflow the 64 KiB macro pool.  Each
# #define here puts a 100-byte name and a 100-byte body in it; the
# built-in macros already take 109 bytes.
i=1
while [ $i -le 400 ]; do
  printf '#define M%03d' $i
  awk 'BEGIN { for (j = 0; j < 96; j++) printf "x"; printf " "; for (j = 0; j < 100; j++) printf "1" }'
  echo
  i=$((i + 1))
done
echo "int main() { return 0; }"
