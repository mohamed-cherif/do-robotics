// Host stand-in for ESPmDNS.
#pragma once
#include "Arduino.h"

struct MDNSResponder {
  bool running = false;
  std::string host;
  bool begin(const char *h) {
    host = h;
    running = true;
    return true;
  }
  void addService(const char *, const char *, int) {}
  void end() { running = false; }
};
inline MDNSResponder MDNS;
