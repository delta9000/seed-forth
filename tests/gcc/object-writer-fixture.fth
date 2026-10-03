\ Forth-written object inputs. The host assembler never makes these bytes.
create ow-start s, _start
create ow-helper s, triple
create ow-value s, shared_value
create ow-anchor s, local_answer
create ow-pointer s, value_pointer
variable ow-helper-id
variable ow-value-id
variable ow-anchor-id

: object-writer-caller ( -- )
  cc-obj-init
  \ mov edi,7; call triple; add eax,[rip+shared_value]; exit(eax).
  [lit] 191 cc-obj-byte [lit] 7 cc-obj-4le
  [lit] 232 cc-obj-byte [lit] 0 cc-obj-4le
  [lit] 3 cc-obj-byte [lit] 5 cc-obj-byte [lit] 0 cc-obj-4le
  [lit] 137 cc-obj-byte [lit] 199 cc-obj-byte
  [lit] 184 cc-obj-byte [lit] 60 cc-obj-4le
  [lit] 15 cc-obj-byte [lit] 5 cc-obj-byte
  ow-start [lit] 6 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-text [lit] 0 cc-obj-here cc-obj-symbol drop
  ow-helper [lit] 6 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol ow-helper-id !
  ow-value [lit] 12 cc-obj-global cc-obj-object cc-obj-default
  cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol ow-value-id !
  \ Insert a local AFTER global symbols to exercise the ELF-index remap.
  ow-anchor [lit] 12 cc-obj-local cc-obj-notype cc-obj-hidden
  cc-obj-abs [lit] 42 [lit] 0 cc-obj-symbol ow-anchor-id !
  cc-obj-text [lit] 6 cc-obj-plt32 ow-helper-id @ [lit] 0 [lit] 4 - cc-obj-reloc
  cc-obj-text [lit] 12 cc-obj-pc32 ow-value-id @ [lit] 0 [lit] 4 - cc-obj-reloc
  cc-obj-data cc-obj-use [lit] 8 cc-obj-align [lit] 16 cc-obj-reserve drop
  ow-pointer [lit] 13 cc-obj-global cc-obj-object cc-obj-default
  cc-obj-data [lit] 0 [lit] 8 cc-obj-symbol drop
  cc-obj-data [lit] 0 cc-obj-r64 ow-value-id @ [lit] 0 cc-obj-reloc
  cc-obj-data [lit] 8 cc-obj-r32 ow-anchor-id @ [lit] 0 cc-obj-reloc
  cc-obj-data [lit] 12 cc-obj-r32s ow-anchor-id @ [lit] 0 [lit] 43 - cc-obj-reloc ;

: object-writer-provider ( -- )
  cc-obj-init
  \ lea eax,[rdi+rdi*2]; ret. System V integer argument arrives in edi.
  [lit] 141 cc-obj-byte [lit] 4 cc-obj-byte [lit] 127 cc-obj-byte [lit] 195 cc-obj-byte
  ow-helper [lit] 6 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-text [lit] 0 [lit] 4 cc-obj-symbol drop
  cc-obj-data cc-obj-use [lit] 4 cc-obj-align [lit] 21 cc-obj-4le
  ow-value [lit] 12 cc-obj-global cc-obj-object cc-obj-default
  cc-obj-data [lit] 0 [lit] 4 cc-obj-symbol drop ;
