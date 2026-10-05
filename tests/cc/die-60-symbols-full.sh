# Error 60: more than 8192 live symbols. Every enumerator occupies one row;
# the 8193rd enumerator must fail even if no builtins were installed.
echo "enum big {"
awk 'BEGIN { for (i = 0; i < 8193; i++) print "  E" i "," }'
echo "  LAST"
echo "};"
echo "int main() { return 0; }"
