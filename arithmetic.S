/* LITERAL SECTION */
.literal DELAY_TICKS_a6, 200

.text
.align 4
.global app_main

app_main:
  entry a1, 32
  /* CONFIG REGISTERS */
  movi a3, 0x60004000
  movi a2, 0x20
  s32i a2, a3, 0x24

.main_loop:
  s32i a2, a3, 0x8
  l32r a6, DELAY_TICKS_a6

  call4 vTaskDelay

  s32i a2, a3, 0xc
  call4 vTaskDelay

  j .main_loop
  
