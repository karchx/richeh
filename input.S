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
  movi a2, 0x2

  slli a4, a4, a2

  movi a2, 0xc

  sub a2, a2, a4

  add a12, a3, a2
  s32i a5, a12, 0
  j .main_loop
  
