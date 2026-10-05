/* Host-only ABI observer: actual %al and entry stack alignment. */
.text
.globl host_al
.type host_al,@function
host_al:
 movzbl %al,%eax
 mov %rsp,%rdx
 and $15,%edx
 cmp $8,%edx
 je 1f
 add $16,%eax
1: ret
.size host_al,.-host_al
.section .note.GNU-stack,"",@progbits
