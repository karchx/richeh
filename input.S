/* LITERAL SECTION */
.text
.align 4
.global app_main

app_main:
  entry a1, 32
  /* CONFIG REGISTERS */
  movi a4, 0x60004000
  movi a3, 0x20
  s32i a3, a4, 0x24

.main_loop:
  movi a2, 0x40

  movi a5, 0x2

  movi a5, 0xc

  s32i a3, a4, 0xb
  j .main_loop
  
