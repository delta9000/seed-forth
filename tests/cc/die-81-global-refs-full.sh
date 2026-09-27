# Error 81: more than 16,384 references to globals (each is a placeholder
# address patched once the globals are placed).  g's 16,385th use is one
# too many.
echo "int g;"
echo "int main() {"
awk 'BEGIN { for (i = 0; i < 16385; i++) print "  g = " i ";" }'
echo "  return 0;"
echo "}"
