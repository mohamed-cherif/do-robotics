// Host stand-in for the AVR Servo library. Like the real one, every
// constructed Servo takes a slot and only the first 12 can ever attach.
#pragma once
#include "Arduino.h"

class Servo {
public:
  static inline int constructed = 0;
  static constexpr int kMaxServos = 12;
  int index;
  int pin = -1;
  bool isAttached = false;
  int angle = -1;
  int us = -1;

  Servo() : index(constructed++) {}
  uint8_t attach(int p, int = 544, int = 2400) {
    if (index >= kMaxServos) return 255; // INVALID_SERVO: nothing happens
    pin = p;
    isAttached = true;
    return (uint8_t)index;
  }
  void detach() { isAttached = false; }
  bool attached() { return isAttached; }
  void write(int a) { angle = a; }
  void writeMicroseconds(int u) { us = u; }
};
