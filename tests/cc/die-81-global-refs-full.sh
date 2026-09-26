# Error 81: more than 4096 references to globals (each is a placeholder
# address patched once the globals are placed).  g's 4,097th use is one
# too many.
echo "int g;"
echo "int main() {"
awk 'BEGIN { for (i = 0; i < 4097; i++) print "  g = " i ";" }'
echo "  return 0;"
echo "}"
