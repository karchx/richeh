/* LITERAL SECTION */
.text
.align 4
.global app_main

app_main:
  entry a1, 32
  /* CONFIG REGISTERS */
  movi a3, 0x60004000
  movi a5, 0x20
  s32i a5, a3, 0x24

.main_loop:
  l32i a2, a3, 0x3c
  extui a4, a2, 6, 1
  mull a2, a4, a5
  sub a4, a5, a2
  s32i a2, a3, 0x8
  s32i a4, a3, 0xc
  j .main_loop
  
