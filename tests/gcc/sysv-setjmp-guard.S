/* Host-only instrumentation; no bytes enter the bootstrap. */
.text
.globl sysv_jump_guard
.type sysv_jump_guard,@function
sysv_jump_guard:
    push %rbp
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    sub $24,%rsp
    mov %rdi,(%rsp)
    mov %rsi,%rdi
    mov $0x12345678,%ebp
    mov $0x23456789,%ebx
    mov $0x3456789a,%r12d
    mov $0x456789ab,%r13d
    mov $0x56789abc,%r14d
    mov $0x6789abcd,%r15d
    call *(%rsp)
    cmp $0x12345678,%rbp
    jne .Lbad
    cmp $0x23456789,%rbx
    jne .Lbad
    cmp $0x3456789a,%r12
    jne .Lbad
    cmp $0x456789ab,%r13
    jne .Lbad
    cmp $0x56789abc,%r14
    jne .Lbad
    cmp $0x6789abcd,%r15
    jne .Lbad
    jmp .Ldone
.Lbad:
    movl $1,sysv_jump_bad_registers(%rip)
.Ldone:
    add $24,%rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    pop %rbp
    ret
.size sysv_jump_guard,.-sysv_jump_guard
.section .note.GNU-stack,"",@progbits
