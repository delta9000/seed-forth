/* Host-only instrumentation: never a production runtime input. */
.text
.globl seed_nonlocal_abi_guard
.type seed_nonlocal_abi_guard,@function
seed_nonlocal_abi_guard:
    push %rbp
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    sub $88,%rsp
    mov %edi,64(%rsp)
    mov %rsp,72(%rsp)
    movabs $0x1234567812345678,%rbp
    movabs $0x2345678923456789,%rbx
    movabs $0x3456789a3456789a,%r12
    movabs $0x456789ab456789ab,%r13
    movabs $0x56789abc56789abc,%r14
    movabs $0x6789abcd6789abcd,%r15
    mov %rsp,%rdi
    call setjmp
    test %eax,%eax
    jne .Lrestored
    /* All saved registers change in the abandoned nested frame. */
    not %rbp
    not %rbx
    not %r12
    not %r13
    not %r14
    not %r15
    sub $32,%rsp
    lea 32(%rsp),%rdi
    /* Poison upper argument bits: only ESI is specified for an int. */
    movabs $0xdeadbeef00000000,%rsi
    mov 96(%rsp),%edx
    or %rdx,%rsi
    call longjmp
    ud2
.Lrestored:
    cmp %rsp,72(%rsp)
    jne .Lbad
    mov %rsp,%rdx
    and $15,%edx
    jne .Lbad
    mov 64(%rsp),%edx
    test %edx,%edx
    jne .Lvalue
    mov $1,%edx
.Lvalue:
    cmp %edx,%eax
    jne .Lbad
    movabs $0x1234567812345678,%rdx
    cmp %rdx,%rbp
    jne .Lbad
    movabs $0x2345678923456789,%rdx
    cmp %rdx,%rbx
    jne .Lbad
    movabs $0x3456789a3456789a,%rdx
    cmp %rdx,%r12
    jne .Lbad
    movabs $0x456789ab456789ab,%rdx
    cmp %rdx,%r13
    jne .Lbad
    movabs $0x56789abc56789abc,%rdx
    cmp %rdx,%r14
    jne .Lbad
    movabs $0x6789abcd6789abcd,%rdx
    cmp %rdx,%r15
    jne .Lbad
    xor %eax,%eax
    jmp .Ldone
.Lbad:
    mov $1,%eax
.Ldone:
    add $88,%rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    pop %rbp
    ret
.size seed_nonlocal_abi_guard,.-seed_nonlocal_abi_guard

.globl seed_nonlocal_alignment
.type seed_nonlocal_alignment,@function
seed_nonlocal_alignment:
    mov %rsp,%rax
    and $15,%eax
    cmp $8,%eax
    setne %al
    movzbl %al,%eax
    ret
.size seed_nonlocal_alignment,.-seed_nonlocal_alignment
.section .note.GNU-stack,"",@progbits
