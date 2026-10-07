/* k1.S -- K1's assembly: entry from K0, syscall and trap entry, context switch,
 * and the privileged instructions C cannot express.
 * Assembled by tcc-0.9.27; instructions its assembler lacks are .byte.
 * k1/k1-asm.fth is the same code for the Forth route, byte for byte
 * (k1/tests/asm-check.py compares the two). */

    .text
    .globl _start
_start:                         /* from K0: ring 0, K0's page tables, rsp = argv block */
    cli
    mov %rsp, %rdi
    lea boot_stack+65536(%rip), %rsp
    call k1_main
1:  hlt
    jmp 1b

/* SYSCALL: rcx = user rip, r11 = user rflags; IF is masked by FMASK.
 * Build a struct tframe on this process's kernel stack. */
    .globl syscall_entry
syscall_entry:
    mov %rsp, user_rsp_tmp(%rip)
    mov cur_kstack_top(%rip), %rsp
    pushq user_rsp_tmp(%rip)
    push %r11
    push %rcx
    push %rax
    push %rdi
    push %rsi
    push %rdx
    push %r10
    push %r8
    push %r9
    push %rbx
    push %rbp
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rsp, %rdi
    call syscall_c
    .globl ret_user
ret_user:                       /* rsp -> struct tframe */
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    pop %r9
    pop %r8
    pop %r10
    pop %rdx
    pop %rsi
    pop %rdi
    pop %rax
    pop %rcx
    pop %r11
    pop %rsp
    sysretq

/* iret_frame(struct trapframe *f): return to user mode restoring every
 * register in f, rcx and r11 included (sysretq would overwrite them). */
    .globl iret_frame
iret_frame:
    mov %rdi, %rsp
    jmp isr_return

/* swtch(u64 *old_ksp, u64 new_ksp) */
    .globl swtch
swtch:
    push %rbp
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rsp, (%rdi)
    mov %rsi, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    pop %rbp
    ret

    .globl load_cr3
load_cr3:
    mov %rdi, %cr3
    ret
    .globl read_cr2
read_cr2:
    mov %cr2, %rax
    ret
    .globl fx_save
fx_save:
    .byte 0x48, 0x0f, 0xae, 0x07    /* fxsave64 (%rdi) */
    ret
    .globl fx_restore
fx_restore:
    .byte 0x48, 0x0f, 0xae, 0x0f    /* fxrstor64 (%rdi) */
    ret

/* The rest of what C cannot say, one small function each (SysV arguments:
 * rdi, rsi, rdx), so the C files need no inline assembly. */
    .globl copy_forward
copy_forward:                   /* (d, s, n): rep movsb */
    mov %rdx, %rcx
    rep movsb
    ret
    .globl memset
memset:                         /* (d, c, n): rep stosb, returns d */
    mov %rdi, %r8
    mov %esi, %eax
    mov %rdx, %rcx
    rep stosb
    mov %r8, %rax
    ret
    .globl console_write
console_write:                  /* (s, n): rep outsb to COM1 */
    mov %rsi, %rcx
    mov %rdi, %rsi
    mov $0x3f8, %edx
    rep outsb
    ret
    .globl outb
outb:                           /* (port, v) */
    mov %edi, %edx
    mov %esi, %eax
    outb %al, %dx
    ret
    .globl inb
inb:                            /* (port) */
    mov %edi, %edx
    xor %eax, %eax
    inb %dx, %al
    ret
    .globl outw
outw:                           /* (port, v) */
    mov %edi, %edx
    mov %esi, %eax
    outw %ax, %dx
    ret
    .globl inw
inw:                            /* (port) */
    mov %edi, %edx
    xor %eax, %eax
    inw %dx, %ax
    ret
    .globl port_insw
port_insw:                      /* (port, buf, count): rep insw */
    mov %rdx, %rcx
    mov %edi, %edx
    mov %rsi, %rdi
    rep insw
    ret
    .globl port_outsw
port_outsw:                     /* (port, buf, count): rep outsw */
    mov %rdx, %rcx
    mov %edi, %edx
    rep outsw
    ret
    .globl wrmsr
wrmsr:                          /* (msr, v) */
    mov %edi, %ecx
    mov %rsi, %rax
    mov %rsi, %rdx
    shr $32, %rdx
    wrmsr
    ret
    .globl rdmsr
rdmsr:                          /* (msr) */
    mov %edi, %ecx
    rdmsr
    shl $32, %rdx
    or %rdx, %rax
    ret
    .globl rdtsc
rdtsc:
    rdtsc
    shl $32, %rdx
    or %rdx, %rax
    ret
/* load_gdt(base, limit) and load_idt(base, limit) build the 10-byte
 * descriptor below rsp. load_gdt then reloads CS with a far return, then
 * the data segments. */
    .globl load_gdt
load_gdt:
    mov %si, -10(%rsp)
    mov %rdi, -8(%rsp)
    lgdt -10(%rsp)
    pushq $0x10
    lea 1f(%rip), %rax
    push %rax
    .byte 0x48, 0xcb                /* lretq */
1:  mov $0x18, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    mov $0, %ax
    mov %ax, %fs
    mov %ax, %gs
    ret
    .globl load_idt
load_idt:
    mov %si, -10(%rsp)
    mov %rdi, -8(%rsp)
    lidt -10(%rsp)
    ret
    .globl load_tr
load_tr:                        /* (selector) */
    ltr %di
    ret
    .globl invlpg
invlpg:                         /* (va) */
    invlpg (%rdi)
    ret
    .globl fpu_init
fpu_init:
    fninit
    ret
    .globl cpu_halt
cpu_halt:
    hlt
    ret
    .globl cpu_pause
cpu_pause:
    pause
    ret
    .globl enter_user
enter_user:                     /* (sp): sp -> struct tframe */
    mov %rdi, %rsp
    jmp ret_user
/* linux_jump(pml4, boot_params, entry): the 64-bit boot protocol's entry,
 * rsi = boot_params, on page tables that identity-map this code */
    .globl linux_jump
linux_jump:
    cli
    mov %rdi, %cr3
    xor %ebp, %ebp
    xor %edi, %edi
    jmp *%rdx

/* Exceptions: stubs push an error code (0 if the CPU does not) and the
 * vector, then isr_common saves the rest and calls trap_c(frame). */
isr_common:
    push %rax
    push %rcx
    push %rdx
    push %rbx
    push %rbp
    push %rsi
    push %rdi
    push %r8
    push %r9
    push %r10
    push %r11
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rsp, %rdi
    call trap_c
    .globl isr_return
isr_return:                     /* rsp -> struct trapframe: restore all, iretq */
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %r11
    pop %r10
    pop %r9
    pop %r8
    pop %rdi
    pop %rsi
    pop %rbp
    pop %rbx
    pop %rdx
    pop %rcx
    pop %rax
    add $16, %rsp
    .byte 0x48, 0xcf                /* iretq */

isr0:
    pushq $0
    pushq $0
    jmp isr_common
isr1:
    pushq $0
    pushq $1
    jmp isr_common
isr2:
    pushq $0
    pushq $2
    jmp isr_common
isr3:
    pushq $0
    pushq $3
    jmp isr_common
isr4:
    pushq $0
    pushq $4
    jmp isr_common
isr5:
    pushq $0
    pushq $5
    jmp isr_common
isr6:
    pushq $0
    pushq $6
    jmp isr_common
isr7:
    pushq $0
    pushq $7
    jmp isr_common
isr8:
    pushq $8
    jmp isr_common
isr9:
    pushq $0
    pushq $9
    jmp isr_common
isr10:
    pushq $10
    jmp isr_common
isr11:
    pushq $11
    jmp isr_common
isr12:
    pushq $12
    jmp isr_common
isr13:
    pushq $13
    jmp isr_common
isr14:
    pushq $14
    jmp isr_common
isr15:
    pushq $0
    pushq $15
    jmp isr_common
isr16:
    pushq $0
    pushq $16
    jmp isr_common
isr17:
    pushq $17
    jmp isr_common
isr18:
    pushq $0
    pushq $18
    jmp isr_common
isr19:
    pushq $0
    pushq $19
    jmp isr_common
isr20:
    pushq $0
    pushq $20
    jmp isr_common
isr21:
    pushq $21
    jmp isr_common
isr22:
    pushq $0
    pushq $22
    jmp isr_common
isr23:
    pushq $0
    pushq $23
    jmp isr_common
isr24:
    pushq $0
    pushq $24
    jmp isr_common
isr25:
    pushq $0
    pushq $25
    jmp isr_common
isr26:
    pushq $0
    pushq $26
    jmp isr_common
isr27:
    pushq $0
    pushq $27
    jmp isr_common
isr28:
    pushq $0
    pushq $28
    jmp isr_common
isr29:
    pushq $29
    jmp isr_common
isr30:
    pushq $30
    jmp isr_common
isr31:
    pushq $0
    pushq $31
    jmp isr_common

/* IRQs 0-15, remapped to vectors 32-47 (only the PIT's IRQ 0 is unmasked) */
isr32:
    pushq $0
    pushq $32
    jmp isr_common
isr33:
    pushq $0
    pushq $33
    jmp isr_common
isr34:
    pushq $0
    pushq $34
    jmp isr_common
isr35:
    pushq $0
    pushq $35
    jmp isr_common
isr36:
    pushq $0
    pushq $36
    jmp isr_common
isr37:
    pushq $0
    pushq $37
    jmp isr_common
isr38:
    pushq $0
    pushq $38
    jmp isr_common
isr39:
    pushq $0
    pushq $39
    jmp isr_common
isr40:
    pushq $0
    pushq $40
    jmp isr_common
isr41:
    pushq $0
    pushq $41
    jmp isr_common
isr42:
    pushq $0
    pushq $42
    jmp isr_common
isr43:
    pushq $0
    pushq $43
    jmp isr_common
isr44:
    pushq $0
    pushq $44
    jmp isr_common
isr45:
    pushq $0
    pushq $45
    jmp isr_common
isr46:
    pushq $0
    pushq $46
    jmp isr_common
isr47:
    pushq $0
    pushq $47
    jmp isr_common

    .data
    .globl isr_table
isr_table:
    .quad isr0
    .quad isr1
    .quad isr2
    .quad isr3
    .quad isr4
    .quad isr5
    .quad isr6
    .quad isr7
    .quad isr8
    .quad isr9
    .quad isr10
    .quad isr11
    .quad isr12
    .quad isr13
    .quad isr14
    .quad isr15
    .quad isr16
    .quad isr17
    .quad isr18
    .quad isr19
    .quad isr20
    .quad isr21
    .quad isr22
    .quad isr23
    .quad isr24
    .quad isr25
    .quad isr26
    .quad isr27
    .quad isr28
    .quad isr29
    .quad isr30
    .quad isr31
    .quad isr32
    .quad isr33
    .quad isr34
    .quad isr35
    .quad isr36
    .quad isr37
    .quad isr38
    .quad isr39
    .quad isr40
    .quad isr41
    .quad isr42
    .quad isr43
    .quad isr44
    .quad isr45
    .quad isr46
    .quad isr47
