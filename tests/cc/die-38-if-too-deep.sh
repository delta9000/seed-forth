# Error 38: #if nested more than 64 deep.
i=0
while [ $i -lt 65 ]; do echo "#if 1"; i=$((i + 1)); done
echo "int main() { return 0; }"
