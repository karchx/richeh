/* LITERAL SECTION */
.literal DELAY_TICKS_3, 500

.text
.align 4
.global app_main

app_main:
  entry a1, 32
  /* CONFIG REGISTERS */
  movi a2, 0x20
  s32i a2, a0, 0x24

.main_loop:
  s32i a2, a0, 0x8
  l32r a3, DELAY_TICKS_3

  mov a6, a3

  call4 vTaskDelay

  j .main_loop
  
