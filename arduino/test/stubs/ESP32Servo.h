// Host stand-in for ESP32Servo.
#pragma once
#include "Arduino.h"

class Servo {
public:
  int pin = -1;
  bool isAttached = false;
  int angle = -1;
  int us = -1;
  int attach(int p, int = 544, int = 2400) {
    pin = p;
    isAttached = true;
    return 1;
  }
  void detach() { isAttached = false; }
  bool attached() { return isAttached; }
  void write(int a) { angle = a; }
  void writeMicroseconds(int u) { us = u; }
};
