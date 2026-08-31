/* LITERAL SECTION */
.literal DELAY_TICKS_4, 500

.literal DELAY_TICKS_5, 500

.text
.align 4
.global app_main

app_main:
  entry a1, 32
  /* CONFIG REGISTERS */
  movi a2, 0x20
  movi a3, 0x60004000
  s32i a2, a3, 0x24

.main_loop:
  s32i a2, a3, 0x8
  l32r a4, DELAY_TICKS_4

  mov a6, a4

  call4 vTaskDelay

  s32i a2, a3, 0xc
  l32r a5, DELAY_TICKS_5

  mov a6, a5

  call4 vTaskDelay

  j .main_loop
  
