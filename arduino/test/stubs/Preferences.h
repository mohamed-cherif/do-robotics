// Host stand-in for ESP32 Preferences (NVS), kept in memory.
#pragma once
#include "Arduino.h"
#include <map>

namespace sim {
inline std::map<std::string, std::string> nvs;
}

class Preferences {
public:
  bool begin(const char *, bool = false) { return true; }
  void end() {}
  String getString(const char *key, const char *def) {
    auto it = sim::nvs.find(key);
    return it == sim::nvs.end() ? String(def) : String(it->second);
  }
  size_t putString(const char *key, const char *v) {
    sim::nvs[key] = v;
    return strlen(v);
  }
  bool remove(const char *key) { return sim::nvs.erase(key) > 0; }
  bool isKey(const char *key) { return sim::nvs.count(key) > 0; }
};
