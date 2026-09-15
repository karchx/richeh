/* LITERAL SECTION */
.literal DELAY_TICKS_4, 200

.text
.align 4
.global app_main

app_main:
  entry a1, 32
  /* CONFIG REGISTERS */
  movi a2, 0x60004000
  movi a3, 0x20
  s32i a3, a2, 0x24
  s32i a3, a2, 0x24

.main_loop:
  s32i a3, a2, 0x8
  l32r a4, DELAY_TICKS_4

  mov a6, a4

  call4 vTaskDelay

  s32i a3, a2, 0xc
  mov a6, a4

  call4 vTaskDelay

  j .main_loop
  
