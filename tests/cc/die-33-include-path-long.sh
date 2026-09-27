# Error 33: an #include path that does not fit the 1024-byte path buffer.
printf '#include "'
awk 'BEGIN { for (i = 0; i < 1100; i++) printf "a" }'
echo '.h"'
echo "int main() { return 0; }"
