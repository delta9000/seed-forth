# Error 171: more than 64 labels in one function (cc-label-cap).  Labels
# L0..L63 fill the table; L64 is one too many.
echo "int main() {"
echo "  int x;"
awk 'BEGIN { for (i = 0; i < 65; i++) print "L" i ": x = " i ";" }'
echo "  return x;"
echo "}"
