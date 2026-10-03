/* Host-only oracle: AL is permitted to overestimate used XMM registers. */
.text
.globl host_al_upper_bound
.type host_al_upper_bound, @function
host_al_upper_bound:
    push %rbp
    mov %rsp, %rbp
    mov $1, %edi
    mov $73, %esi
    mov $8, %eax
    call seed_sum
    pop %rbp
    ret
.size host_al_upper_bound, .-host_al_upper_bound
.section .note.GNU-stack,"",@progbits
