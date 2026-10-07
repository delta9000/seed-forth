\ k1/k1-asm.fth -- K1's assembly (k1/k1.S) as a relocatable object, for the
\ route that builds K1 without TinyCC.  Loaded on 010, 020, 030, 081 and
\ tools/obj-asm.fth, followed by a line that writes the object
\ (k1/boot/asm.fth).
\
\ The bytes are k1.S's instructions, one per line with the instruction as
\ its comment.  They were transcribed from GNU as's listing of k1.S, and
\ python3 k1/tests/asm-check.py proves the object this file writes equal to
\ that assembler's: the same section bytes, global symbols and relocations.
\ Change k1.S and this file together.

cc-obj-init
asm{
.text
.globl _start
_start:
  fa                              \ cli
  48 89 e7                        \ mov %rsp,%rdi
  48 8d 25 %boot_stack+65536      \ lea boot_stack+65536(%rip),%rsp
  e8 ^k1_main                     \ call k1_main
halt_loop:
  f4                              \ hlt
  eb !halt_loop                   \ jmp halt_loop
.globl syscall_entry
syscall_entry:
  48 89 25 %user_rsp_tmp          \ mov %rsp,user_rsp_tmp(%rip)
  48 8b 25 %cur_kstack_top        \ mov cur_kstack_top(%rip),%rsp
  ff 35 %user_rsp_tmp             \ push user_rsp_tmp(%rip)
  41 53                           \ push %r11
  51                              \ push %rcx
  50                              \ push %rax
  57                              \ push %rdi
  56                              \ push %rsi
  52                              \ push %rdx
  41 52                           \ push %r10
  41 50                           \ push %r8
  41 51                           \ push %r9
  53                              \ push %rbx
  55                              \ push %rbp
  41 54                           \ push %r12
  41 55                           \ push %r13
  41 56                           \ push %r14
  41 57                           \ push %r15
  48 89 e7                        \ mov %rsp,%rdi
  e8 ^syscall_c                   \ call syscall_c
.globl ret_user
ret_user:
  41 5f                           \ pop %r15
  41 5e                           \ pop %r14
  41 5d                           \ pop %r13
  41 5c                           \ pop %r12
  5d                              \ pop %rbp
  5b                              \ pop %rbx
  41 59                           \ pop %r9
  41 58                           \ pop %r8
  41 5a                           \ pop %r10
  5a                              \ pop %rdx
  5e                              \ pop %rsi
  5f                              \ pop %rdi
  58                              \ pop %rax
  59                              \ pop %rcx
  41 5b                           \ pop %r11
  5c                              \ pop %rsp
  48 0f 07                        \ sysretq
.globl iret_frame
iret_frame:
  48 89 fc                        \ mov %rdi,%rsp
  e9 %isr_return                  \ jmp isr_return
.globl swtch
swtch:
  55                              \ push %rbp
  53                              \ push %rbx
  41 54                           \ push %r12
  41 55                           \ push %r13
  41 56                           \ push %r14
  41 57                           \ push %r15
  48 89 27                        \ mov %rsp,(%rdi)
  48 89 f4                        \ mov %rsi,%rsp
  41 5f                           \ pop %r15
  41 5e                           \ pop %r14
  41 5d                           \ pop %r13
  41 5c                           \ pop %r12
  5b                              \ pop %rbx
  5d                              \ pop %rbp
  c3                              \ ret
.globl load_cr3
load_cr3:
  0f 22 df                        \ mov %rdi,%cr3
  c3                              \ ret
.globl read_cr2
read_cr2:
  0f 20 d0                        \ mov %cr2,%rax
  c3                              \ ret
.globl fx_save
fx_save:
  48 0f ae 07                     \ fxsave64 (%rdi)
  c3                              \ ret
.globl fx_restore
fx_restore:
  48 0f ae 0f                     \ fxrstor64 (%rdi)
  c3                              \ ret
.globl copy_forward
copy_forward:
  48 89 d1                        \ mov %rdx,%rcx
  f3 a4                           \ rep movsb %ds:(%rsi),%es:(%rdi)
  c3                              \ ret
.globl memset
memset:
  49 89 f8                        \ mov %rdi,%r8
  89 f0                           \ mov %esi,%eax
  48 89 d1                        \ mov %rdx,%rcx
  f3 aa                           \ rep stos %al,%es:(%rdi)
  4c 89 c0                        \ mov %r8,%rax
  c3                              \ ret
.globl console_write
console_write:
  48 89 f1                        \ mov %rsi,%rcx
  48 89 fe                        \ mov %rdi,%rsi
  ba f8 03 00 00                  \ mov $0x3f8,%edx
  f3 6e                           \ rep outsb %ds:(%rsi),(%dx)
  c3                              \ ret
.globl outb
outb:
  89 fa                           \ mov %edi,%edx
  89 f0                           \ mov %esi,%eax
  ee                              \ out %al,(%dx)
  c3                              \ ret
.globl inb
inb:
  89 fa                           \ mov %edi,%edx
  31 c0                           \ xor %eax,%eax
  ec                              \ in (%dx),%al
  c3                              \ ret
.globl outw
outw:
  89 fa                           \ mov %edi,%edx
  89 f0                           \ mov %esi,%eax
  66 ef                           \ out %ax,(%dx)
  c3                              \ ret
.globl inw
inw:
  89 fa                           \ mov %edi,%edx
  31 c0                           \ xor %eax,%eax
  66 ed                           \ in (%dx),%ax
  c3                              \ ret
.globl port_insw
port_insw:
  48 89 d1                        \ mov %rdx,%rcx
  89 fa                           \ mov %edi,%edx
  48 89 f7                        \ mov %rsi,%rdi
  66 f3 6d                        \ rep insw (%dx),%es:(%rdi)
  c3                              \ ret
.globl port_outsw
port_outsw:
  48 89 d1                        \ mov %rdx,%rcx
  89 fa                           \ mov %edi,%edx
  66 f3 6f                        \ rep outsw %ds:(%rsi),(%dx)
  c3                              \ ret
.globl wrmsr
wrmsr:
  89 f9                           \ mov %edi,%ecx
  48 89 f0                        \ mov %rsi,%rax
  48 89 f2                        \ mov %rsi,%rdx
  48 c1 ea 20                     \ shr $0x20,%rdx
  0f 30                           \ wrmsr
  c3                              \ ret
.globl rdmsr
rdmsr:
  89 f9                           \ mov %edi,%ecx
  0f 32                           \ rdmsr
  48 c1 e2 20                     \ shl $0x20,%rdx
  48 09 d0                        \ or %rdx,%rax
  c3                              \ ret
.globl rdtsc
rdtsc:
  0f 31                           \ rdtsc
  48 c1 e2 20                     \ shl $0x20,%rdx
  48 09 d0                        \ or %rdx,%rax
  c3                              \ ret
.globl load_gdt
load_gdt:
  66 89 74 24 f6                  \ mov %si,-0xa(%rsp)
  48 89 7c 24 f8                  \ mov %rdi,-0x8(%rsp)
  0f 01 54 24 f6                  \ lgdt -0xa(%rsp)
  6a 10                           \ push $0x10
  48 8d 05 %reload_segments       \ lea reload_segments(%rip),%rax
  50                              \ push %rax
  48 cb                           \ lretq
reload_segments:
  66 b8 18 00                     \ mov $0x18,%ax
  8e d8                           \ mov %eax,%ds
  8e c0                           \ mov %eax,%es
  8e d0                           \ mov %eax,%ss
  66 b8 00 00                     \ mov $0x0,%ax
  8e e0                           \ mov %eax,%fs
  8e e8                           \ mov %eax,%gs
  c3                              \ ret
.globl load_idt
load_idt:
  66 89 74 24 f6                  \ mov %si,-0xa(%rsp)
  48 89 7c 24 f8                  \ mov %rdi,-0x8(%rsp)
  0f 01 5c 24 f6                  \ lidt -0xa(%rsp)
  c3                              \ ret
.globl load_tr
load_tr:
  0f 00 df                        \ ltr %edi
  c3                              \ ret
.globl invlpg
invlpg:
  0f 01 3f                        \ invlpg (%rdi)
  c3                              \ ret
.globl fpu_init
fpu_init:
  db e3                           \ fninit
  c3                              \ ret
.globl cpu_halt
cpu_halt:
  f4                              \ hlt
  c3                              \ ret
.globl cpu_pause
cpu_pause:
  f3 90                           \ pause
  c3                              \ ret
.globl enter_user
enter_user:
  48 89 fc                        \ mov %rdi,%rsp
  e9 %ret_user                    \ jmp ret_user
.globl linux_jump
linux_jump:
  fa                              \ cli
  0f 22 df                        \ mov %rdi,%cr3
  31 ed                           \ xor %ebp,%ebp
  31 ff                           \ xor %edi,%edi
  ff e2                           \ jmp *%rdx
isr_common:
  50                              \ push %rax
  51                              \ push %rcx
  52                              \ push %rdx
  53                              \ push %rbx
  55                              \ push %rbp
  56                              \ push %rsi
  57                              \ push %rdi
  41 50                           \ push %r8
  41 51                           \ push %r9
  41 52                           \ push %r10
  41 53                           \ push %r11
  41 54                           \ push %r12
  41 55                           \ push %r13
  41 56                           \ push %r14
  41 57                           \ push %r15
  48 89 e7                        \ mov %rsp,%rdi
  e8 ^trap_c                      \ call trap_c
.globl isr_return
isr_return:
  41 5f                           \ pop %r15
  41 5e                           \ pop %r14
  41 5d                           \ pop %r13
  41 5c                           \ pop %r12
  41 5b                           \ pop %r11
  41 5a                           \ pop %r10
  41 59                           \ pop %r9
  41 58                           \ pop %r8
  5f                              \ pop %rdi
  5e                              \ pop %rsi
  5d                              \ pop %rbp
  5b                              \ pop %rbx
  5a                              \ pop %rdx
  59                              \ pop %rcx
  58                              \ pop %rax
  48 83 c4 10                     \ add $0x10,%rsp
  48 cf                           \ iretq
isr0:
  6a 00                           \ push $0x0
  6a 00                           \ push $0x0
  eb !isr_common                  \ jmp isr_common
isr1:
  6a 00                           \ push $0x0
  6a 01                           \ push $0x1
  eb !isr_common                  \ jmp isr_common
isr2:
  6a 00                           \ push $0x0
  6a 02                           \ push $0x2
  eb !isr_common                  \ jmp isr_common
isr3:
  6a 00                           \ push $0x0
  6a 03                           \ push $0x3
  eb !isr_common                  \ jmp isr_common
isr4:
  6a 00                           \ push $0x0
  6a 04                           \ push $0x4
  eb !isr_common                  \ jmp isr_common
isr5:
  6a 00                           \ push $0x0
  6a 05                           \ push $0x5
  eb !isr_common                  \ jmp isr_common
isr6:
  6a 00                           \ push $0x0
  6a 06                           \ push $0x6
  eb !isr_common                  \ jmp isr_common
isr7:
  6a 00                           \ push $0x0
  6a 07                           \ push $0x7
  eb !isr_common                  \ jmp isr_common
isr8:
  6a 08                           \ push $0x8
  eb !isr_common                  \ jmp isr_common
isr9:
  6a 00                           \ push $0x0
  6a 09                           \ push $0x9
  eb !isr_common                  \ jmp isr_common
isr10:
  6a 0a                           \ push $0xa
  eb !isr_common                  \ jmp isr_common
isr11:
  6a 0b                           \ push $0xb
  eb !isr_common                  \ jmp isr_common
isr12:
  6a 0c                           \ push $0xc
  e9 %isr_common                  \ jmp isr_common
isr13:
  6a 0d                           \ push $0xd
  e9 %isr_common                  \ jmp isr_common
isr14:
  6a 0e                           \ push $0xe
  e9 %isr_common                  \ jmp isr_common
isr15:
  6a 00                           \ push $0x0
  6a 0f                           \ push $0xf
  e9 %isr_common                  \ jmp isr_common
isr16:
  6a 00                           \ push $0x0
  6a 10                           \ push $0x10
  e9 %isr_common                  \ jmp isr_common
isr17:
  6a 11                           \ push $0x11
  e9 %isr_common                  \ jmp isr_common
isr18:
  6a 00                           \ push $0x0
  6a 12                           \ push $0x12
  e9 %isr_common                  \ jmp isr_common
isr19:
  6a 00                           \ push $0x0
  6a 13                           \ push $0x13
  e9 %isr_common                  \ jmp isr_common
isr20:
  6a 00                           \ push $0x0
  6a 14                           \ push $0x14
  e9 %isr_common                  \ jmp isr_common
isr21:
  6a 15                           \ push $0x15
  e9 %isr_common                  \ jmp isr_common
isr22:
  6a 00                           \ push $0x0
  6a 16                           \ push $0x16
  e9 %isr_common                  \ jmp isr_common
isr23:
  6a 00                           \ push $0x0
  6a 17                           \ push $0x17
  e9 %isr_common                  \ jmp isr_common
isr24:
  6a 00                           \ push $0x0
  6a 18                           \ push $0x18
  e9 %isr_common                  \ jmp isr_common
isr25:
  6a 00                           \ push $0x0
  6a 19                           \ push $0x19
  e9 %isr_common                  \ jmp isr_common
isr26:
  6a 00                           \ push $0x0
  6a 1a                           \ push $0x1a
  e9 %isr_common                  \ jmp isr_common
isr27:
  6a 00                           \ push $0x0
  6a 1b                           \ push $0x1b
  e9 %isr_common                  \ jmp isr_common
isr28:
  6a 00                           \ push $0x0
  6a 1c                           \ push $0x1c
  e9 %isr_common                  \ jmp isr_common
isr29:
  6a 1d                           \ push $0x1d
  e9 %isr_common                  \ jmp isr_common
isr30:
  6a 1e                           \ push $0x1e
  e9 %isr_common                  \ jmp isr_common
isr31:
  6a 00                           \ push $0x0
  6a 1f                           \ push $0x1f
  e9 %isr_common                  \ jmp isr_common
isr32:
  6a 00                           \ push $0x0
  6a 20                           \ push $0x20
  e9 %isr_common                  \ jmp isr_common
isr33:
  6a 00                           \ push $0x0
  6a 21                           \ push $0x21
  e9 %isr_common                  \ jmp isr_common
isr34:
  6a 00                           \ push $0x0
  6a 22                           \ push $0x22
  e9 %isr_common                  \ jmp isr_common
isr35:
  6a 00                           \ push $0x0
  6a 23                           \ push $0x23
  e9 %isr_common                  \ jmp isr_common
isr36:
  6a 00                           \ push $0x0
  6a 24                           \ push $0x24
  e9 %isr_common                  \ jmp isr_common
isr37:
  6a 00                           \ push $0x0
  6a 25                           \ push $0x25
  e9 %isr_common                  \ jmp isr_common
isr38:
  6a 00                           \ push $0x0
  6a 26                           \ push $0x26
  e9 %isr_common                  \ jmp isr_common
isr39:
  6a 00                           \ push $0x0
  6a 27                           \ push $0x27
  e9 %isr_common                  \ jmp isr_common
isr40:
  6a 00                           \ push $0x0
  6a 28                           \ push $0x28
  e9 %isr_common                  \ jmp isr_common
isr41:
  6a 00                           \ push $0x0
  6a 29                           \ push $0x29
  e9 %isr_common                  \ jmp isr_common
isr42:
  6a 00                           \ push $0x0
  6a 2a                           \ push $0x2a
  e9 %isr_common                  \ jmp isr_common
isr43:
  6a 00                           \ push $0x0
  6a 2b                           \ push $0x2b
  e9 %isr_common                  \ jmp isr_common
isr44:
  6a 00                           \ push $0x0
  6a 2c                           \ push $0x2c
  e9 %isr_common                  \ jmp isr_common
isr45:
  6a 00                           \ push $0x0
  6a 2d                           \ push $0x2d
  e9 %isr_common                  \ jmp isr_common
isr46:
  6a 00                           \ push $0x0
  6a 2e                           \ push $0x2e
  e9 %isr_common                  \ jmp isr_common
isr47:
  6a 00                           \ push $0x0
  6a 2f                           \ push $0x2f
  e9 %isr_common                  \ jmp isr_common

.data
.globl isr_table
isr_table:
  *isr0 *isr1 *isr2 *isr3 *isr4 *isr5 *isr6 *isr7
  *isr8 *isr9 *isr10 *isr11 *isr12 *isr13 *isr14 *isr15
  *isr16 *isr17 *isr18 *isr19 *isr20 *isr21 *isr22 *isr23
  *isr24 *isr25 *isr26 *isr27 *isr28 *isr29 *isr30 *isr31
  *isr32 *isr33 *isr34 *isr35 *isr36 *isr37 *isr38 *isr39
  *isr40 *isr41 *isr42 *isr43 *isr44 *isr45 *isr46 *isr47
}asm
