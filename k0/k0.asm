; K0: a single-task bootstrap kernel for the seed-forth amd64 route.
;
; Multiboot (a.out kludge) -> long mode, the first 4 GiB identity-mapped
; with 1 GiB pages, everything in ring 0, interrupts off.  Programs enter
; through SYSCALL and return through JMP, so there is no TSS, no IDT and
; no user segment.
;
; K0 boots from a memory image that mkfs.py writes and QEMU's loader
; places at FSIMG: kernel state, page tables, init's argv, and the file
; table with every file's contents.  Names are canonical: no leading '/'.
;
; fork runs the child to completion: the parent's registers, process
; state, image and stack are saved, then restored when the child exits.
; Every fork in the chain is fork -> redirect -> execve with the parent
; waiting at once, so nothing else is needed.
;
; Every address K0 handles is below 4 GiB, so it works in 32-bit
; registers wherever a value is its own.

bits 32
org 0x100000

SP0   equ 0x3FFF0000            ; initial rsp; the argv block sits above it
STOP  equ 0x40000000            ; top of the region saved as "stack"
PB    equ 0x30000000            ; canonical path buffer
KB    equ 0x30010000            ; argv block under construction
FSIMG equ 0x50000000            ; the boot image (see mkfs.py)
BASE  equ FSIMG + 0x80          ; rbp: kernel state
PML4  equ FSIMG + 0x1000
INIT  equ FSIMG + 0x3000        ; init's argv; the path follows it
ENTS  equ FSIMG + 0x4000        ; file table, 24-byte entries

; file entry, 6 dwords
E_NAME equ 0
E_NLEN equ 4
E_DATA equ 8
E_SIZE equ 12
E_CAP  equ 16
E_TYPE equ 20                   ; byte: 0 deleted, 1 file, 2 directory
CONSOLE equ 1                   ; fd entry value meaning the serial port

; rbp-relative kernel state.  [U, P_END) is what fork saves.
G_FP    equ -128                ; innermost fork snapshot, 0 at top level
G_PID   equ -120
G_END   equ -112                ; end of the file table
G_HEAP  equ -104
G_BUMP  equ -96
G_PBLEN equ -88
U       equ -80                 ; user registers, in push order
U_RFL   equ -48                 ; (r11)
U_RIP   equ 24                  ; (rcx)
U_RAX   equ 32
U_RSP   equ 40
P_CWDLEN equ 48
P_LO    equ 56                  ; loaded image [lo, hi)
P_HI    equ 64
P_LPID  equ 72                  ; last child: pid and wait status
P_LST   equ 80
P_FDS   equ 88                  ; 64 x {entry, pos}
P_CWD   equ 600
P_END   equ 1112

hdr:    dd 0x1BADB002, 0x00010000, -(0x1BADB002 + 0x00010000)
        dd hdr, hdr, file_end, file_end, start32

start32:
        mov eax, PML4
        mov cr3, eax
        mov eax, 0x620                  ; PAE | OSFXSR | OSXMMEXCPT
        mov cr4, eax
        mov ecx, 0xC0000080             ; EFER: LME | SCE
        rdmsr
        or eax, 0x101
        wrmsr
        mov eax, cr0
        or eax, 0x80000002              ; PG | MP
        mov cr0, eax
        lgdt [gdt]
        jmp 8:start64

gdt:    dw 15                           ; the null descriptor holds the GDTR
        dd gdt
        dw 0
        dq 0x00209A0000000000           ; 64-bit code

bits 64
default rel
start64:
        mov ebp, BASE
        lea esp, [rbp + G_FP]           ; kernel stack: below the image
        mov ecx, 0xC0000081             ; STAR: syscall CS 8, SS 16
        xor eax, eax
        mov edx, 0x00100008
        wrmsr
        inc ecx                         ; LSTAR
        mov eax, syscall_entry
        cdq
        wrmsr
        mov edi, INIT + 16
        mov esi, INIT
        call sys_execve
        jmp ret_user

; ---- entry and exit -------------------------------------------------------

syscall_entry:
        mov [abs BASE + U_RSP], rsp
        mov esp, BASE + U_RSP
        push rax
        push rcx
        push rdx
        push rbx
        push rbp
        push rsi
        push rdi
        push r8
        push r9
        push r10
        push r11
        push r12
        push r13
        push r14
        push r15
        mov ebp, BASE
        lea esp, [rbp + G_FP]
        mov ebx, sctab
.find:  cmp [rbx], al
        je .hit
        add ebx, 3
        cmp byte [rbx], 0xFF
        jne .find
        push -38                        ; ENOSYS
        pop rax
        jmp ret_user
.hit:   movzx ebx, word [rbx + 1]
        add ebx, handlers
        call rbx
ret_user:
        mov [rbp + U_RAX], rax
        lea esp, [rbp + U]
        pop r15
        pop r14
        pop r13
        pop r12
        pop r11
        pop r10
        pop r9
        pop r8
        pop rdi
        pop rsi
        pop rbp
        pop rbx
        pop rdx
        pop rcx
        pop rax
        push r11
        popfq
        pop rsp
        jmp rcx

%macro SC 2
        db %1
        dw %2 - handlers
%endmacro
sctab:  SC 0, sys_read
        SC 1, sys_write
        SC 2, sys_open
        SC 3, sys_close
        SC 6, sys_lstat
        SC 8, sys_lseek
        SC 9, sys_mmap
        SC 33, sys_dup2
        SC 57, sys_fork
        SC 59, sys_execve
        SC 60, sys_exit
        SC 61, sys_wait4
        SC 79, sys_getcwd
        SC 80, sys_chdir
        SC 82, sys_rename
        SC 83, sys_mkdir
        SC 87, sys_unlink
        SC 90, ok                       ; no permissions
        db 0xFF

; ---- paths and the file table --------------------------------------------

handlers:

; rsi = path -> PB holds its canonical form, [G_PBLEN] its length.
; The chain's paths never contain "..", an inner "//" or "/./", or a
; trailing '/'; "./" and repeated '/' occur only as prefixes.
canon:
        mov edi, PB
        cmp byte [rsi], '/'
        je .abs
        push rsi
        lea esi, [rbp + P_CWD]
        mov ecx, [rbp + P_CWDLEN]
        rep movsb
        pop rsi
        cmp edi, PB
        je .dots
        mov al, '/'
        stosb
        jmp .dots
.abs:   inc esi                         ; ROOT "/" + "/x" gives "//x"
        cmp byte [rsi], '/'
        je .abs
.dots:  cmp word [rsi], './'
        jne .copy
        lodsw
        jmp .dots
.copy:  lodsb
        stosb
        test al, al
        jnz .copy
        sub edi, PB + 1
        mov [rbp + G_PBLEN], edi
        ret

; rdi = path -> rax = entry, or 0 with ZF set
resolve:
        mov esi, edi
        call canon
        mov edx, [rbp + G_END]
.l:     sub edx, 24
        cmp edx, ENTS
        jb .no
        cmp byte [rdx + E_TYPE], 0
        je .l
        mov ecx, [rbp + G_PBLEN]
        cmp ecx, [rdx + E_NLEN]
        jne .l
        mov esi, [rdx + E_NAME]
        mov edi, PB
        repe cmpsb
        jne .l
        xchg eax, edx
        test eax, eax
        ret
.no:    xor eax, eax
        ret

; bl = type -> rax = new entry named PB
newent:
        mov eax, [rbp + G_END]
        add dword [rbp + G_END], 24
        mov [rax + E_TYPE], bl
; rax = entry; its name becomes a copy of PB
setname:
        mov edi, [rbp + G_HEAP]
        mov [rax + E_NAME], edi
        mov ecx, [rbp + G_PBLEN]
        mov [rax + E_NLEN], ecx
        mov esi, PB
        rep movsb
        mov [rbp + G_HEAP], edi
        ret

; rdi = fd -> rbx = slot, rax = entry; CF if closed
fdp:
        lea ebx, [rbp + P_FDS + rdi*8]
        mov eax, [rbx]
        cmp eax, 1
        ret

; ---- files ---------------------------------------------------------------

sys_open:                               ; rdi path, rsi flags
        push rsi
        call resolve
        pop rsi
        jnz .have
        bt esi, 6                       ; O_CREAT
        jnc enoent
        mov bl, 1
        call newent
        jmp .fd
.have:  bt esi, 7                       ; O_EXCL
        jc eexist
        bt esi, 9                       ; O_TRUNC: past size stays zero
        jnc .fd
        and dword [rax + E_SIZE], 0
        and dword [rax + E_CAP], 0
.fd:    lea ebx, [rbp + P_FDS - 8]
.f:     add ebx, 8
        cmp dword [rbx], 0
        jne .f
        mov [rbx], eax
        and dword [rbx + 4], 0
        lea eax, [rbx - P_FDS]
        sub eax, ebp
        shr eax, 3
        ret

sys_close:
        call fdp
        jc ebadf
        and dword [rbx], 0
        jmp ok

sys_read:                               ; rdi fd, rsi buf, rdx count
        call fdp
        jc ebadf
        mov ecx, [rax + E_SIZE]
        sub ecx, [rbx + 4]
        jbe ok
        cmp rcx, rdx
        jbe .n
        mov ecx, edx
.n:     mov edi, esi
        mov esi, [rax + E_DATA]
        add esi, [rbx + 4]
        add [rbx + 4], ecx
        xchg eax, ecx
        mov ecx, eax
        rep movsb
        ret

sys_write:                              ; rdi fd, rsi buf, rdx count
        call fdp
        jc ebadf
        mov ecx, edx
        push rcx
        dec eax
        jnz .file
        mov dx, 0x3F8
        rep outsb
        pop rax
        ret
.file:  inc eax
        mov edx, [rbx + 4]              ; pos
        add edx, ecx                    ; end
        cmp edx, [rax + E_CAP]
        jbe .fits
        push rsi                        ; grow to twice the new end;
        lea ecx, [rdx + rdx]            ; fresh heap is zero, so bytes
        mov [rax + E_CAP], ecx          ; past size always read as zero
        mov edi, [rbp + G_HEAP]
        add [rbp + G_HEAP], ecx
        mov esi, [rax + E_DATA]
        mov [rax + E_DATA], edi
        mov ecx, [rax + E_SIZE]
        rep movsb
        pop rsi
.fits:  mov edi, [rax + E_DATA]
        add edi, [rbx + 4]
        mov [rbx + 4], edx
        cmp edx, [rax + E_SIZE]
        jbe .cp
        mov [rax + E_SIZE], edx
.cp:    pop rcx
        mov eax, ecx
        rep movsb
        ret

sys_lseek:                              ; rdi fd, rsi offset, rdx whence
        call fdp
        jc ebadf
        xor ecx, ecx
        dec edx
        js .set
        mov ecx, [rbx + 4]
        jz .set
        mov ecx, [rax + E_SIZE]
.set:   add ecx, esi
        mov [rbx + 4], ecx
        xchg eax, ecx
        ret

sys_dup2:                               ; rdi old, rsi new
        call fdp
        jc ebadf
        mov rax, [rbx]
        mov [rbp + P_FDS + rsi*8], rax
        xchg eax, esi
        ret

sys_lstat:                              ; rdi path, rsi buf: only st_mode
        push rsi
        call resolve
        pop rdi
        jz enoent
        mov dh, 0x81                    ; S_IFREG
        cmp byte [rax + E_TYPE], 2
        jne .m
        mov dh, 0x41                    ; S_IFDIR
.m:     mov [rdi + 25], dh
        mov byte [rdi + 24], 0xED
        jmp ok

sys_getcwd:                             ; rdi buf
        mov al, '/'
        stosb
        lea esi, [rbp + P_CWD]
        mov ecx, [rbp + P_CWDLEN]
        lea eax, [rcx + 2]
        rep movsb
        mov [rdi], cl
        ret

sys_chdir:
        call resolve
        jz enoent
        mov esi, PB
        lea edi, [rbp + P_CWD]
        mov ecx, [rbp + G_PBLEN]
        mov [rbp + P_CWDLEN], ecx
        rep movsb
        jmp ok

sys_rename:                             ; rdi old, rsi new
        push rsi
        call resolve
        pop rdi
        jz enoent
        push rax
        call resolve
        pop rdx
        jz .set
        cmp eax, edx
        je .set
        mov byte [rax + E_TYPE], 0
.set:   xchg eax, edx
        call setname
        jmp ok

sys_mkdir:
        call resolve
        jnz eexist
        mov bl, 2
        call newent
        jmp ok

sys_unlink:
        call resolve
        jz enoent
        mov byte [rax + E_TYPE], 0
        jmp ok
ok:     xor eax, eax
        ret
enoent: push -2
        pop rax
        ret
ebadf:  push -9
        pop rax
        ret
eexist: push -17
        pop rax
        ret

; ---- memory and processes ------------------------------------------------

sys_mmap:                               ; rsi length; anonymous only
        mov edi, [rbp + G_BUMP]
        push rdi
        lea ecx, [rsi + 4095]
        and ecx, -4096
        add [rbp + G_BUMP], ecx
        xor eax, eax
        rep stosb
        pop rax
        ret

sys_fork:
        mov ebx, [rbp + G_BUMP]
        mov eax, [rbp + G_FP]
        mov [rbx], eax
        mov [rbp + G_FP], ebx
        inc dword [rbp + G_PID]
        mov eax, [rbp + G_PID]
        mov [rbx + 4], eax
        add ebx, 8
        xor edx, edx
        call xfer
        add ebx, 4095
        and ebx, -4096
        mov [rbp + G_BUMP], ebx
        jmp ok

sys_exit:
        mov ebx, [rbp + G_FP]
        test ebx, ebx
        jz .halt
        mov [rbp + G_BUMP], ebx
        mov eax, [rbx]
        mov [rbp + G_FP], eax
        mov r12d, [rbx + 4]
        movzx r13d, dil
        shl r13d, 8
        add ebx, 8
        mov dl, 1
        call xfer
        mov [rbp + P_LPID], r12d
        mov [rbp + P_LST], r13d
        xchg eax, r12d
        ret
.halt:  xchg eax, edi
        out 0xF4, al                    ; isa-debug-exit
        hlt

; Copy process state to (dl=0) or from (dl=1) the snapshot at rbx:
; registers and process state, the image, then the stack.  On restore
; each range is computed from what the previous copy put back.
xfer:
        lea eax, [rbp + U]
        mov ecx, P_END - U
        call .r
        mov eax, [rbp + P_LO]
        mov ecx, [rbp + P_HI]
        sub ecx, eax
        call .r
        mov eax, [rbp + U_RSP]
        sub eax, 128                    ; red zone
        mov ecx, STOP
        sub ecx, eax
.r:     mov esi, eax
        mov edi, ebx
        add ebx, ecx
        test dl, dl
        jz .c
        xchg esi, edi
.c:     rep movsb
        ret

sys_wait4:                              ; rsi status*
        mov eax, [rbp + P_LPID]
        mov ecx, [rbp + P_LST]
        mov [rsi], ecx
        ret

sys_execve:                             ; rdi path, rsi argv
        push rsi
        call resolve
        pop rsi
        jz enoent
        mov r12d, [rax + E_DATA]
        ; argv block in KB, laid out for SP0:
        ; argc, argv[], NULL, NULL envp, AT_NULL, strings
        xor ecx, ecx
.cnt:   cmp qword [rsi + rcx*8], 0
        je .cntd
        inc ecx
        jmp .cnt
.cntd:  mov r9, rsi
        mov edi, KB
        mov [rdi], rcx
        lea r8d, [rdi + 8]
        lea edi, [rdi + rcx*8 + 40]
.arg:   mov rsi, [r9]
        add r9, 8
        test rsi, rsi
        jz .argd
        lea eax, [rdi + SP0 - KB]
        mov [r8], rax
        add r8d, 8
.str:   lodsb
        stosb
        test al, al
        jnz .str
        jmp .arg
.argd:  push rdi
        mov edi, r8d
        xor eax, eax
        push 4
        pop rcx
        rep stosq
        ; every phdr is a PT_LOAD, in address order, from offset 64
        lea ebx, [r12 + 64]
        mov eax, [rbx + 16]
        mov [rbp + P_LO], eax
        movzx r13d, word [r12 + 56]     ; e_phnum
.ph:    mov esi, [rbx + 8]
        add esi, r12d
        mov edi, [rbx + 16]
        mov ecx, [rbx + 32]
        rep movsb
        mov ecx, [rbx + 40]
        sub ecx, [rbx + 32]
        xor eax, eax
        rep stosb
        mov [rbp + P_HI], edi
        add ebx, 56
        dec r13d
        jnz .ph
        pop rcx                         ; argv block -> SP0
        sub ecx, KB
        mov esi, KB
        mov edi, SP0
        rep movsb
        mov r12d, [r12 + 24]            ; e_entry
        lea edi, [rbp + U]              ; all registers zero
        xor eax, eax
        push 16
        pop rcx
        rep stosq
        mov [rbp + U_RIP], r12d
        mov dword [rbp + U_RSP], SP0
        ret

file_end:

