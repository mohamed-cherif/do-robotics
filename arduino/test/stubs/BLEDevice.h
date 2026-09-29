// Host stand-in for the ESP32 BLE library: the test plays the phone by
// calling the registered callbacks and reading the TX notifications.
#pragma once
#include "Arduino.h"

class BLEServer;
class BLECharacteristic;

class BLEServerCallbacks {
public:
  virtual ~BLEServerCallbacks() {}
  virtual void onConnect(BLEServer *) {}
  virtual void onDisconnect(BLEServer *) {}
};

class BLECharacteristicCallbacks {
public:
  virtual ~BLECharacteristicCallbacks() {}
  virtual void onWrite(BLECharacteristic *) {}
};

class BLEDescriptor {};
class BLE2902 : public BLEDescriptor {};

class BLECharacteristic {
public:
  static constexpr uint32_t PROPERTY_READ = 1, PROPERTY_WRITE = 2, PROPERTY_NOTIFY = 4, PROPERTY_WRITE_NR = 8;
  BLECharacteristicCallbacks *cb = nullptr;
  std::string value;
  std::vector<std::vector<uint8_t>> notifications;

  void setCallbacks(BLECharacteristicCallbacks *c) { cb = c; }
  void addDescriptor(BLEDescriptor *) {}
  void setValue(uint8_t *d, size_t n) { value.assign((const char *)d, n); }
  String getValue() { return String(value); }
  void notify() { notifications.emplace_back(value.begin(), value.end()); }
};

class BLEService {
public:
  std::vector<BLECharacteristic *> chars;
  BLECharacteristic *createCharacteristic(const char *, uint32_t) {
    chars.push_back(new BLECharacteristic());
    return chars.back();
  }
  void start() {}
};

class BLEServer {
public:
  BLEServerCallbacks *cb = nullptr;
  uint16_t mtu = 185;
  void setCallbacks(BLEServerCallbacks *c) { cb = c; }
  BLEService *createService(const char *) { return new BLEService(); }
  uint16_t getConnId() { return 0; }
  uint16_t getPeerMTU(uint16_t) { return mtu; }
};

class BLEDevice {
public:
  static inline std::string name;
  static inline int advertisingStarts = 0;
  static inline BLEServer *server = nullptr;
  static void init(const char *n) { name = n; }
  static void setMTU(uint16_t) {}
  static BLEServer *createServer() {
    server = new BLEServer();
    return server;
  }
  static void startAdvertising() { advertisingStarts++; }
};
