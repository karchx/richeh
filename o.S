/* LITERAL SECTION */
.text
.align 4
.global app_main

app_main:
  entry a1, 32
  /* CONFIG REGISTERS */
  movi a2, 0x60004000
  movi a6, 0x20
  s32i a6, a2, 0x24

.main_loop:
  movi a3, 0x5

  movi a4, 0x5

  movi a5, 0x1

  s32i a6, a2, 0x8
  j .main_loop
  
