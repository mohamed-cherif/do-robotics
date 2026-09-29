// Tiny test helpers for the firmware host tests (no external framework).
#pragma once
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

struct TestCase {
  const char *name;
  std::function<void()> fn;
};
inline std::vector<TestCase> &allTests() {
  static std::vector<TestCase> t;
  return t;
}
inline int g_failures = 0;
inline int g_checks = 0;

#define TEST(name)                                                            \
  static void name();                                                         \
  static struct name##_reg {                                                  \
    name##_reg() { allTests().push_back({#name, name}); }                     \
  } name##_instance;                                                          \
  static void name()

#define CHECK(cond)                                                           \
  do {                                                                        \
    g_checks++;                                                               \
    if (!(cond)) {                                                            \
      g_failures++;                                                           \
      std::printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);          \
    }                                                                         \
  } while (0)

inline int runAllTests(const char *suite, const std::function<void()> &reset) {
  for (auto &t : allTests()) {
    int before = g_failures;
    reset();
    t.fn();
    std::printf("%s %s: %s\n", g_failures == before ? "ok  " : "FAIL", suite, t.name);
  }
  std::printf("%s: %d checks, %d failures\n", suite, g_checks, g_failures);
  return g_failures == 0 ? 0 : 1;
}

// [0xAA][cmd][pin][val][ck]
inline std::vector<uint8_t> controlFrame(uint8_t cmd, uint8_t pin, uint8_t val) {
  return {0xAA, cmd, pin, val, (uint8_t)(0xAA + cmd + pin + val)};
}

// [0xAB][len][text][ck]
inline std::vector<uint8_t> textFrame(const std::string &text) {
  std::vector<uint8_t> f{0xAB, (uint8_t)text.size()};
  uint8_t sum = (uint8_t)(0xAB + text.size());
  for (char c : text) {
    f.push_back((uint8_t)c);
    sum += (uint8_t)c;
  }
  f.push_back(sum);
  return f;
}

// Every well-formed text frame in a byte stream (checksums verified).
inline std::vector<std::string> textFramesIn(const std::vector<uint8_t> &bytes) {
  std::vector<std::string> out;
  for (size_t i = 0; i + 2 < bytes.size(); i++) {
    if (bytes[i] != 0xAB) continue;
    size_t len = bytes[i + 1];
    if (i + 2 + len >= bytes.size()) continue;
    uint8_t sum = (uint8_t)(0xAB + len);
    std::string s;
    for (size_t k = 0; k < len; k++) {
      s += (char)bytes[i + 2 + k];
      sum += bytes[i + 2 + k];
    }
    if (bytes[i + 2 + len] == sum) {
      out.push_back(s);
      i += 2 + len;
    }
  }
  return out;
}

inline bool contains(const std::vector<std::string> &v, const std::string &s) {
  for (auto &x : v)
    if (x == s) return true;
  return false;
}
