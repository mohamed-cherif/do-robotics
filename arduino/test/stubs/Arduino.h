// Minimal host-side stand-in for the Arduino core, for firmware unit tests.
// Records what the sketch does to pins and the serial port; time is manual.
#pragma once

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <string>
#include <vector>

typedef uint8_t byte;

#define HIGH 1
#define LOW 0
#define INPUT 0
#define OUTPUT 1
#define INPUT_PULLUP 2
#ifndef LED_BUILTIN
#define LED_BUILTIN 13
#endif

namespace sim {
struct Pin {
  int mode = -1;  // -1 = never configured
  int level = 0;  // last digital level (or PWM >= 128)
  int pwm = -1;   // last analogWrite duty, -1 = not PWM
  int writes = 0; // digitalWrite + analogWrite calls
};
inline unsigned long now = 0;
inline Pin pins[80];
inline std::vector<int> ledcDetached;

inline void reset() {
  now = 0;
  for (auto &p : pins) p = Pin();
  ledcDetached.clear();
}
} // namespace sim

inline unsigned long millis() { return sim::now; }
inline void delay(unsigned long ms) { sim::now += ms; }
inline void pinMode(uint8_t p, int m) { sim::pins[p].mode = m; }
inline void digitalWrite(uint8_t p, int v) {
  sim::pins[p].level = v ? 1 : 0;
  sim::pins[p].pwm = -1;
  sim::pins[p].writes++;
}
inline void analogWrite(uint8_t p, int v) {
  sim::pins[p].pwm = v;
  sim::pins[p].level = v >= 128 ? 1 : 0;
  sim::pins[p].writes++;
}
inline bool ledcDetach(uint8_t p) {
  sim::ledcDetached.push_back(p);
  return true;
}

struct SerialPort {
  std::deque<uint8_t> in;
  std::vector<uint8_t> out;
  void begin(long) {}
  int available() { return (int)in.size(); }
  int read() {
    if (in.empty()) return -1;
    int b = in.front();
    in.pop_front();
    return b;
  }
  size_t write(uint8_t b) {
    out.push_back(b);
    return 1;
  }
  size_t write(const uint8_t *b, size_t n) {
    out.insert(out.end(), b, b + n);
    return n;
  }
  template <typename... A> void printf(const char *, A...) {}
  template <typename T> void println(T) {}
};
inline SerialPort Serial;

// Flash strings are plain strings on the host.
class __FlashStringHelper;
#define F(s) (reinterpret_cast<const __FlashStringHelper *>(s))
typedef const char *PGM_P;
#define strlen_P strlen
#define pgm_read_byte(p) (*(const uint8_t *)(p))

// Which pins have a hardware PWM timer (set by the board-specific test).
#define NOT_ON_TIMER 0
uint8_t digitalPinToTimer(uint8_t p);

// ---- ESP32 extras ----------------------------------------------------------

class String {
  std::string s_;

public:
  String() {}
  String(const char *c) : s_(c ? c : "") {}
  String(const std::string &s) : s_(s) {}
  String(unsigned long v) : s_(std::to_string(v)) {}
  String(int v) : s_(std::to_string(v)) {}
  const char *c_str() const { return s_.c_str(); }
  size_t length() const { return s_.size(); }
  char operator[](size_t i) const { return s_[i]; }
  String &operator+=(const String &o) {
    s_ += o.s_;
    return *this;
  }
  String &operator+=(const char *o) {
    s_ += o;
    return *this;
  }
  friend String operator+(const String &a, const String &b) { return String(a.s_ + b.s_); }
  friend String operator+(const String &a, const char *b) { return String(a.s_ + b); }
  friend String operator+(const char *a, const String &b) { return String(std::string(a) + b.s_); }
  bool operator==(const char *o) const { return s_ == o; }
};

struct IPAddress {
  std::string ip;
  explicit IPAddress(const char *s = "0.0.0.0") : ip(s) {}
  String toString() const { return String(ip); }
};

struct EspClass {
  uint64_t mac = 0x0000F6E5D4C3B2A1ULL; // MAC A1:B2:C3:D4:E5:F6
  uint64_t getEfuseMac() { return mac; }
};
inline EspClass ESP;
