/* Host-built ABI instrumentation only; never part of the compiler/runtime. */
.text
.globl review_checked_callback
.type review_checked_callback,@function
review_checked_callback:
    mov %rsp,%rax
    and $15,%eax
    cmp $8,%eax
    jne .Lbad_align
    jmp review_host_callback
.Lbad_align:
    movl $1,review_bad_alignment(%rip)
    jmp review_host_callback
.size review_checked_callback,.-review_checked_callback
.globl review_checked_variadic
.type review_checked_variadic,@function
review_checked_variadic:
    test %al,%al
    je .Lvector_ok
    movl $1,review_bad_vector_count(%rip)
.Lvector_ok:
    mov %rsp,%rax
    and $15,%eax
    cmp $8,%eax
    je .Lvar_align_ok
    movl $1,review_bad_alignment(%rip)
.Lvar_align_ok:
    xor %eax,%eax
    jmp review_host_variadic
.size review_checked_variadic,.-review_checked_variadic
/* long guard(fn(long), arg): sentinel check every callee-saved GPR. */
.globl review_preserve_guard
.type review_preserve_guard,@function
review_preserve_guard:
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
    jne .Lpreserve_bad
    cmp $0x23456789,%rbx
    jne .Lpreserve_bad
    cmp $0x3456789a,%r12
    jne .Lpreserve_bad
    cmp $0x456789ab,%r13
    jne .Lpreserve_bad
    cmp $0x56789abc,%r14
    jne .Lpreserve_bad
    cmp $0x6789abcd,%r15
    jne .Lpreserve_bad
    jmp .Lpreserve_done
.Lpreserve_bad:
    movl $1,review_bad_preservation(%rip)
.Lpreserve_done:
    add $24,%rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    pop %rbp
    ret
.size review_preserve_guard,.-review_preserve_guard
.section .note.GNU-stack,"",@progbits
