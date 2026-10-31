// hello.c - smallest end-to-end check: print over the UART and blink LEDs.
#include "runtime.h"

int main(void) {
  print("Hello from my RISC-V CPU!\n");
  for (uint32_t i = 0; i < 8; i++) LEDS = 1u << i;
  print("LEDs = "); print_hex(LEDS); print("\n");
  return 0;
}
