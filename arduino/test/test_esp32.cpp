// Host tests for the ESP32 sketch, compiled unchanged against the stubs.
// The test plays the phone on USB serial, BLE and WiFi TCP.
#include "Arduino.h"
#include "testlib.h"

#include "../receiver/receiver.ino"

// ---- simulated phone -------------------------------------------------------

static void tick() { loop(); } // loop() itself advances the clock by 5 ms

// Run loop() for about `ms` of simulated time.
static void runFor(unsigned long ms) {
  unsigned long end = sim::now + ms;
  while (sim::now < end) {
    sim::now += 95;
    loop();
  }
}

// Run loop() until `done()` holds; returns the simulated ms that took
// (capped at 10 min, which fails any check expecting less).
template <typename F> static unsigned long msUntil(F done) {
  unsigned long start = sim::now;
  while (!done() && sim::now - start < 600000) {
    sim::now += 95;
    loop();
  }
  return sim::now - start;
}

static void serialSend(const std::vector<uint8_t> &frame) {
  Serial.in.insert(Serial.in.end(), frame.begin(), frame.end());
  tick();
}
static std::vector<std::string> serialReplies() { return textFramesIn(Serial.out); }

static void bleConnect(uint16_t mtu = 185) {
  BLEDevice::server->mtu = mtu;
  BLEDevice::server->cb->onConnect(BLEDevice::server);
  tick();
}
static void bleDisconnect() {
  BLEDevice::server->cb->onDisconnect(BLEDevice::server);
  tick();
}
static void bleSend(const std::vector<uint8_t> &frame) {
  pRxCharacteristic->value.assign(frame.begin(), frame.end());
  pRxCharacteristic->cb->onWrite(pRxCharacteristic);
  tick();
}
static std::vector<uint8_t> bleBytes() {
  std::vector<uint8_t> all;
  for (auto &n : pTxCharacteristic->notifications) all.insert(all.end(), n.begin(), n.end());
  return all;
}
static std::vector<std::string> bleReplies() { return textFramesIn(bleBytes()); }

static std::shared_ptr<FakeConn> tcpConnect() {
  auto c = std::make_shared<FakeConn>();
  tcpServer.pending.push_back(c);
  tick();
  return c;
}
static void tcpSend(const std::shared_ptr<FakeConn> &c, const std::vector<uint8_t> &frame) {
  c->in.insert(c->in.end(), frame.begin(), frame.end());
  tick();
}

static int countOf(const std::vector<std::string> &v, const std::string &s) {
  int n = 0;
  for (auto &x : v)
    if (x == s) n++;
  return n;
}

// Reset every global the sketch owns, keep NVS, run setup(): a reboot.
static void powerOn() {
  unsigned long keepTime = 10000;
  sim::reset();
  sim::now = keepTime;
  Serial = SerialPort();
  WiFi = WiFiClass();
  MDNS = MDNSResponder();
  BLEDevice::advertisingStarts = 0;
  tcpServer.pending.clear();
  tcpClient = WiFiClient();
  wifiClientWasConnected = false;
  bleConnected = false;
  bleConnectCount = 0;
  bleDisconnectCount = 0;
  bleConnectsSeen = 0;
  bleDisconnectsSeen = 0;
  bleHelloPending = false;
  staState = STA_IDLE;
  staAttemptMillis = 0;
  staRetryWaitMs = STA_RETRY_MS;
  staNextBackoffMs = STA_RETRY_MS;
  staSsid = "";
  staPass = "";
  hostName = "";
  mdnsRunning = false;
  for (int p = 0; p < MAX_PINS; p++) {
    servos[p] = Servo();
    isServoAttached[p] = false;
    pinTouched[p] = false;
    pinIsPwm[p] = false;
    servoIsContinuous[p] = false;
  }
  outputsArmed = false;
  lastPacketMillis = 0;
  lastErrReplyMillis = 0;
  setup();
}

static void resetAll() {
  sim::nvs.clear();
  powerOn();
}

// ---- names and boot --------------------------------------------------------

TEST(names_carry_the_mac_suffix) {
  CHECK(BLEDevice::name == "ESP32 Robot E5F6");
  CHECK(WiFi.apSsid == "ESP32_Robot_E5F6");
  CHECK(WiFi.apPass == "12345678");
}

TEST(a_custom_name_is_used_for_ble_after_reboot) {
  sim::nvs["name"] = "bench-bot";
  powerOn();
  CHECK(BLEDevice::name == "Robot bench-bot");
  CHECK(WiFi.apSsid == "ESP32_Robot_E5F6");
}

TEST(the_wifi_driver_does_not_keep_its_own_copy_of_credentials) {
  CHECK(WiFi.persistentFlag == false);
}

// ---- BLE -------------------------------------------------------------------

TEST(ble_hello_is_sent_after_the_first_frame_from_the_phone) {
  bleConnect();
  CHECK(pTxCharacteristic->notifications.empty()); // phone may not be subscribed yet
  bleSend(controlFrame(0x00, 0, 0));
  auto r = bleReplies();
  CHECK(countOf(r, "HELLO\tesp32\t2.1") == 1);
  CHECK(contains(r, "WIFI\tAP\t192.168.4.1"));
  bleSend(controlFrame(0x00, 0, 0));
  CHECK(countOf(bleReplies(), "HELLO\tesp32\t2.1") == 1);
}

TEST(ble_notifications_are_split_to_the_negotiated_mtu) {
  bleConnect(23); // phone that never raised the MTU: 20-byte payloads
  bleSend(textFrame("STATUS"));
  for (auto &n : pTxCharacteristic->notifications) CHECK(n.size() <= 20);
  bool gotStatus = false;
  for (auto &s : bleReplies())
    if (s.rfind("STATUS\tsta=off\tip=0.0.0.0\tap=192.168.4.1\tname=robot\tble=connected", 0) == 0)
      gotStatus = true;
  CHECK(gotStatus);
}

TEST(ble_settings_commands_are_accepted) {
  bleConnect();
  bleSend(textFrame("WIFI\tHome\tsecret"));
  CHECK(contains(bleReplies(), "OK\tWIFI saved, connecting"));
  CHECK(sim::nvs["ssid"] == "Home");
  CHECK(sim::nvs["pass"] == "secret");
  CHECK(WiFi.lastBeginSsid == "Home");
}

TEST(ble_disconnect_stops_outputs_and_advertises_again) {
  bleConnect();
  bleSend(controlFrame(0x01, 4, 1));
  CHECK(sim::pins[4].level == 1);
  int adsBefore = BLEDevice::advertisingStarts;
  bleDisconnect();
  CHECK(sim::pins[4].level == 0);
  CHECK(BLEDevice::advertisingStarts == adsBefore + 1);
}

TEST(a_quick_ble_reconnect_is_not_missed) {
  // connect + disconnect + connect between two loop() passes
  bleConnect();
  bleSend(controlFrame(0x01, 4, 1));
  BLEDevice::server->cb->onDisconnect(BLEDevice::server);
  BLEDevice::server->cb->onConnect(BLEDevice::server);
  tick();
  CHECK(sim::pins[4].level == 0); // the disconnect still ran the failsafe
  pTxCharacteristic->notifications.clear();
  bleSend(controlFrame(0x00, 0, 0));
  CHECK(contains(bleReplies(), "HELLO\tesp32\t2.1")); // and the new link says hello
}

// ---- pins ------------------------------------------------------------------

TEST(flash_and_serial_pins_are_refused) {
  serialSend(controlFrame(0x01, 6, 1)); // SPI flash: would crash the board
  CHECK(sim::pins[6].writes == 0);
  CHECK(sim::pins[6].mode == -1);
  CHECK(contains(serialReplies(), "ERR\tbad pin 6"));
  sim::now += 1100;
  serialSend(controlFrame(0x01, 1, 1)); // USB serial TX
  CHECK(sim::pins[1].writes == 0);
  CHECK(contains(serialReplies(), "ERR\tbad pin 1"));
}

TEST(bad_pin_replies_are_rate_limited) {
  serialSend(controlFrame(0x01, 7, 1));
  serialSend(controlFrame(0x01, 8, 1));
  serialSend(controlFrame(0x01, 9, 1));
  CHECK(serialReplies().size() == 1);
}

TEST(input_only_pins_can_be_read_but_not_driven) {
  serialSend(controlFrame(0x03, 34, 0));
  CHECK(sim::pins[34].mode == INPUT);
  serialSend(controlFrame(0x01, 34, 1));
  CHECK(sim::pins[34].writes == 0);
  CHECK(contains(serialReplies(), "ERR\tbad pin 34"));
}

TEST(a_pin_can_switch_from_servo_to_digital) {
  serialSend(controlFrame(0x04, 13, 90));
  CHECK(servos[13].isAttached);
  CHECK(servos[13].angle == 90);
  serialSend(controlFrame(0x01, 13, 1));
  CHECK(!servos[13].isAttached);
  CHECK(sim::pins[13].level == 1);
}

TEST(a_pin_can_switch_from_pwm_to_servo) {
  serialSend(controlFrame(0x02, 14, 128));
  CHECK(sim::pins[14].pwm == 128);
  serialSend(controlFrame(0x04, 14, 45));
  CHECK(sim::ledcDetached.size() == 1 && sim::ledcDetached[0] == 14);
  CHECK(sim::pins[14].pwm == 0);
  CHECK(servos[14].isAttached && servos[14].angle == 45);
}

TEST(watchdog_stops_outputs_after_two_seconds_of_silence) {
  serialSend(controlFrame(0x02, 25, 200));
  serialSend(controlFrame(0x05, 26, 200)); // continuous servo full speed
  CHECK(servos[26].us == 1700);
  runFor(1500);
  CHECK(sim::pins[25].pwm == 200);
  runFor(700);
  CHECK(sim::pins[25].level == 0);
  CHECK(servos[26].us == 1500);
  CHECK(countOf(serialReplies(), "WATCHDOG\tlink lost") == 1);
}

TEST(stop_all_stops_everything) {
  serialSend(controlFrame(0x01, 4, 1));
  serialSend(controlFrame(0x05, 26, 0));
  serialSend(controlFrame(0x06, 0, 0));
  CHECK(sim::pins[4].level == 0);
  CHECK(servos[26].us == 1500);
}

// ---- WiFi TCP --------------------------------------------------------------

TEST(tcp_client_gets_hello) {
  auto a = tcpConnect();
  auto r = textFramesIn(a->out);
  CHECK(contains(r, "HELLO\tesp32\t2.1"));
  CHECK(contains(r, "WIFI\tAP\t192.168.4.1"));
}

TEST(settings_commands_are_refused_over_tcp) {
  auto a = tcpConnect();
  tcpSend(a, textFrame("WIFI\tEvil\tpw"));
  tcpSend(a, textFrame("NAME\tevil"));
  tcpSend(a, textFrame("FORGET"));
  auto r = textFramesIn(a->out);
  CHECK(countOf(r, "ERR\tuse Bluetooth or USB to change robot settings") == 3);
  CHECK(sim::nvs.empty());
  CHECK(WiFi.beginCount == 0);
  tcpSend(a, textFrame("STATUS")); // read-only commands still work
  bool gotStatus = false;
  for (auto &s : textFramesIn(a->out))
    if (s.rfind("STATUS\t", 0) == 0) gotStatus = true;
  CHECK(gotStatus);
}

TEST(the_newest_tcp_client_wins) {
  auto a = tcpConnect();
  tcpSend(a, controlFrame(0x01, 4, 1));
  CHECK(sim::pins[4].level == 1);
  auto b = tcpConnect(); // phone came back on a new socket, old one half-open
  CHECK(a->stopped);
  CHECK(sim::pins[4].level == 0); // failsafe on hand-over
  CHECK(contains(textFramesIn(b->out), "HELLO\tesp32\t2.1"));
  tcpSend(b, controlFrame(0x01, 5, 1));
  CHECK(sim::pins[5].level == 1);
}

TEST(a_dropped_tcp_client_stops_outputs) {
  auto a = tcpConnect();
  tcpSend(a, controlFrame(0x01, 4, 1));
  a->open = false;
  tick();
  CHECK(sim::pins[4].level == 0);
}

TEST(a_half_received_frame_does_not_leak_into_the_next_client) {
  auto a = tcpConnect();
  tcpSend(a, {0xAA, 0x01, 4}); // cut off mid-frame
  auto b = tcpConnect();
  tcpSend(b, controlFrame(0x01, 5, 1));
  CHECK(sim::pins[5].level == 1);
  CHECK(sim::pins[4].writes == 0);
}

// ---- serial settings commands ---------------------------------------------

TEST(name_is_validated_and_lowercased) {
  serialSend(textFrame("NAME\tBad Name!"));
  serialSend(textFrame("NAME\t-edge"));
  serialSend(textFrame("NAME\tBench-Bot2"));
  auto r = serialReplies();
  CHECK(countOf(r, "ERR\tname: use 1-31 letters, digits or -") == 2);
  CHECK(contains(r, "OK\tNAME saved, reboot to apply to BLE"));
  CHECK(sim::nvs["name"] == "bench-bot2");
}

TEST(forget_erases_saved_and_driver_credentials) {
  serialSend(textFrame("WIFI\tHome\tsecret"));
  CHECK(WiFi.beginCount == 1);
  serialSend(textFrame("FORGET"));
  CHECK(contains(serialReplies(), "OK\tFORGET credentials erased"));
  CHECK(sim::nvs.count("ssid") == 0 && sim::nvs.count("pass") == 0);
  CHECK(WiFi.disconnectCalls >= 1);
  CHECK(WiFi.lastEraseAp);
  runFor(400000); // no credentials: never retries
  CHECK(WiFi.beginCount == 1);
}

// ---- WiFi station ----------------------------------------------------------

TEST(station_retries_back_off_30_60_120_seconds) {
  sim::nvs["ssid"] = "Home";
  sim::nvs["pass"] = "secret";
  powerOn();
  CHECK(WiFi.beginCount == 1); // joins at boot
  // Each attempt times out after 10 s, then the wait before the next one
  // doubles from 30 s up to the 5 min cap. Loop steps are 100 ms.
  const unsigned long waits[] = {30000, 60000, 120000, 240000, 300000, 300000};
  for (int i = 0; i < 6; i++) {
    unsigned long failAfter = msUntil([&] { return countOf(serialReplies(), "WIFI\tFAILED\ttimeout") == i + 1; });
    CHECK(failAfter > 10000 && failAfter <= 10200);
    int begins = WiFi.beginCount;
    unsigned long retryAfter = msUntil([&] { return WiFi.beginCount > begins; });
    CHECK(retryAfter > waits[i] && retryAfter <= waits[i] + 200);
  }
}

TEST(station_does_not_scan_while_a_phone_uses_the_hotspot) {
  sim::nvs["ssid"] = "Home";
  powerOn();
  runFor(11000); // first attempt times out
  WiFi.apStations = 1;
  runFor(120000);
  CHECK(WiFi.beginCount == 1);
  WiFi.apStations = 0;
  runFor(31000);
  CHECK(WiFi.beginCount == 2);
}

TEST(station_connect_starts_mdns_and_a_drop_retries_soon) {
  sim::nvs["ssid"] = "Home";
  powerOn();
  WiFi.st = WL_CONNECTED;
  tick();
  CHECK(contains(serialReplies(), "WIFI\tCONNECTED\t192.168.1.50"));
  CHECK(MDNS.running && MDNS.host == "robot");
  WiFi.st = WL_DISCONNECTED;
  tick();
  CHECK(contains(serialReplies(), "WIFI\tFAILED\tlost"));
  CHECK(!MDNS.running);
  runFor(31000);
  CHECK(WiFi.beginCount == 2);
}

TEST(tcp_hello_reports_the_station_address_once_joined) {
  sim::nvs["ssid"] = "Home";
  powerOn();
  WiFi.st = WL_CONNECTED;
  tick();
  auto a = tcpConnect();
  CHECK(contains(textFramesIn(a->out), "WIFI\tCONNECTED\t192.168.1.50"));
}

int main() { return runAllTests("esp32", resetAll); }
