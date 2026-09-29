// Host stand-in for the ESP32 WiFi library: a controllable station status and
// an in-memory TCP server whose pending connections the test can queue.
#pragma once
#include "Arduino.h"
#include <memory>

enum wl_status_t { WL_IDLE_STATUS = 0, WL_NO_SSID_AVAIL = 1, WL_CONNECTED = 3, WL_CONNECT_FAILED = 4, WL_DISCONNECTED = 6 };
#define WIFI_AP_STA 3

struct WiFiClass {
  wl_status_t st = WL_DISCONNECTED;
  int apStations = 0;
  bool persistentFlag = true;
  std::string apSsid, apPass, hostname, lastBeginSsid;
  int beginCount = 0;
  int disconnectCalls = 0;
  bool lastEraseAp = false;

  void persistent(bool p) { persistentFlag = p; }
  bool setHostname(const char *h) {
    hostname = h;
    return true;
  }
  bool mode(int) { return true; }
  bool softAP(const char *s, const char *p) {
    apSsid = s;
    apPass = p ? p : "";
    return true;
  }
  void begin(const char *s, const char *) {
    lastBeginSsid = s;
    beginCount++;
  }
  wl_status_t status() { return st; }
  bool disconnect(bool = false, bool eraseap = false) {
    disconnectCalls++;
    lastEraseAp = eraseap;
    return true;
  }
  IPAddress localIP() { return IPAddress("192.168.1.50"); }
  IPAddress softAPIP() { return IPAddress("192.168.4.1"); }
  int softAPgetStationNum() { return apStations; }
};
inline WiFiClass WiFi;

struct FakeConn {
  bool open = true;
  bool stopped = false;
  std::deque<uint8_t> in;
  std::vector<uint8_t> out;
};

class WiFiClient {
  std::shared_ptr<FakeConn> c_;

public:
  WiFiClient() {}
  explicit WiFiClient(std::shared_ptr<FakeConn> c) : c_(std::move(c)) {}
  explicit operator bool() const { return (bool)c_; }
  bool connected() { return c_ && c_->open; }
  int available() { return c_ ? (int)c_->in.size() : 0; }
  int read() {
    if (!c_ || c_->in.empty()) return -1;
    int b = c_->in.front();
    c_->in.pop_front();
    return b;
  }
  size_t write(const uint8_t *b, size_t n) {
    if (c_) c_->out.insert(c_->out.end(), b, b + n);
    return n;
  }
  void stop() {
    if (c_) {
      c_->open = false;
      c_->stopped = true;
    }
  }
  void setNoDelay(bool) {}
};

class WiFiServer {
public:
  std::deque<std::shared_ptr<FakeConn>> pending;
  explicit WiFiServer(int) {}
  void begin() {}
  bool hasClient() { return !pending.empty(); }
  WiFiClient accept() {
    if (pending.empty()) return WiFiClient();
    auto c = pending.front();
    pending.pop_front();
    return WiFiClient(c);
  }
};
