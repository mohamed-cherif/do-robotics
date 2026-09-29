// Uncomment to get human-readable debug output on USB Serial (EXEC lines,
// checksum failures, connection logs). Leave commented for production: the
// phone parses the serial stream as frames and expects it to stay clean.
// #define DEBUG_ECHO

#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <ESP32Servo.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <WiFi.h>
#include <freertos/stream_buffer.h>

/**
 * DO ROBOTICS - Slave Firmware (ESP32 Version)
 * --------------------------------------------
 * Requires: "esp32 by Espressif Systems" board package 3.x, library
 * ESP32Servo >= 3.0, board "ESP32 Dev Module", Partition Scheme
 * "Huge APP (3MB No OTA/1MB SPIFFS)".
 *
 * v2.1 - safe-pin whitelist (bad pins answered with ERR), BLE bytes queued and
 *        handled in loop() (no cross-core races), newest WiFi client wins,
 *        per-board names, WIFI/NAME/FORGET only over BLE/USB, FORGET also
 *        erases the WiFi driver's copy of the password, station retry
 *        back-off, BLE notify sized to the negotiated MTU, HELLO once the
 *        phone is listening, pin re-use between servo/PWM/digital.
 * v2.0 - text frames, station-mode WiFi (NVS credentials), mDNS, BLE TX notify
 *
 * Transports: BLE (Nordic UART), USB Serial, WiFi TCP (port 4210, reachable
 * on the soft-AP 192.168.4.1 and, once joined to a network, on the station
 * IP / robot.local). All three feed the same byte-stream framing.
 *
 * Framing (the parser dispatches on the first byte of every frame)
 *   0xAA  control   [0xAA][CMD][PIN][VAL][CK]           phone -> board
 *                   CK = (0xAA + CMD + PIN + VAL) % 256
 *   0xAB  text      [0xAB][LEN][LEN bytes ASCII][CK]    both directions
 *                   LEN <= 120, CK = (0xAB + LEN + sum of bytes) % 256
 *   any other byte while waiting for a header is ignored (resync).
 *   A bad checksum discards the frame silently.
 *
 * Control commands
 *   0x00  HEARTBEAT      – no-op, only refreshes the link watchdog
 *                          (the app sends one every 500 ms; not logged)
 *   0x01  DIGITAL_WRITE  – val: 0=LOW, 1=HIGH
 *   0x02  ANALOG_WRITE   – val: 0-255 PWM duty cycle
 *   0x03  PIN_MODE       – val: 0=INPUT, 1=OUTPUT, 2=INPUT_PULLUP
 *   0x04  SERVO_WRITE    – positional servo, val = angle 0-180
 *   0x05  SERVO_WRITE_US – continuous servo, val = (µs - 1300) / 2
 *                          val=0   -> 1300 µs (full reverse)
 *                          val=100 -> 1500 µs (stop)
 *                          val=200 -> 1700 µs (full forward)
 *   0x06  STOP_ALL       – pin/val ignored, runs failsafeStop()
 *
 * Pins (ESP32-WROOM DevKit)
 *   Outputs: 2 4 5 12 13 14 15 16 17 18 19 21 22 23 25 26 27 32 33
 *   Inputs only (PIN_MODE 0/2): 34 35 36 39
 *   Rejected: 0 (boot button), 1/3 (USB serial), 6-11 (SPI flash - driving
 *   them crashes the board), anything else. A rejected command is answered
 *   with  ERR\tbad pin <n>  (at most once per second).
 *
 * Text commands (fields separated by TAB, no trailing newline). The reply
 * goes back on the transport the command arrived on.
 *   phone -> board                 board -> phone
 *   WIFI\t<ssid>\t<password>       OK\tWIFI saved, connecting
 *                                  then later (broadcast on every transport):
 *                                  WIFI\tCONNECTED\t<ip>  or  WIFI\tFAILED\t<reason>
 *   NAME\t<hostname>               OK\tNAME saved, reboot to apply to BLE
 *                                  (hostname: 1-31 of a-z 0-9 -, lowercased)
 *   STATUS                         STATUS\tsta=<connected|off>\tip=<ip>\tap=192.168.4.1
 *                                        \tname=<name>\tble=<connected|no>\tuptime=<s>
 *   FORGET                         OK\tFORGET credentials erased
 *   <anything else>                ERR\tunknown command
 *   (bad arguments)                ERR\t<msg>
 *   WIFI, NAME and FORGET are only accepted over BLE or USB: anyone on the
 *   same network can reach the TCP port, so it can't reconfigure the robot.
 *
 * Unsolicited board -> phone text
 *   HELLO\tesp32\t2.1              on a new TCP client, and over BLE as soon
 *                                  as the phone sends its first frame (it is
 *                                  subscribed to notifications by then);
 *                                  followed by WIFI\tCONNECTED\t<ip> or WIFI\tAP\t192.168.4.1
 *   WIFI\tCONNECTED\t<ip>          station joined the saved network (mDNS up)
 *   WIFI\tFAILED\t<reason>         station attempt timed out, or "lost" when dropped
 *   WATCHDOG\tlink lost            link watchdog fired (see below)
 *   ERR\tbad pin <n>               a command used a pin that is not allowed
 *
 * Names
 *   BLE advertises "ESP32 Robot XXXX" and the hotspot is "ESP32_Robot_XXXX",
 *   where XXXX are the last 4 hex digits of the board's MAC address, so
 *   several robots in one room can be told apart. After NAME, BLE advertises
 *   "Robot <name>" (the app finds robots whose name contains "Robot").
 *
 * WiFi
 *   Mode is AP+STA: the soft-AP (ESP32_Robot_XXXX / WIFI_PASS, 192.168.4.1)
 *   is always up. If NVS holds credentials (Preferences namespace "dorobot",
 *   keys ssid/pass/name) the board also joins that network: 10 s connect
 *   timeout, then retries 30 s, 60 s, 120 s ... up to 5 min apart, and not at
 *   all while a phone is connected to the hotspot (a station scan hops
 *   channels and would stall it). On station connect mDNS advertises
 *   <name>.local (default "robot") with _dorobot._tcp:4210.
 *
 * Link watchdog / failsafe
 *   Every valid frame on any transport (heartbeat and text included)
 *   refreshes lastPacketMillis. Once any output has been driven ("armed"),
 *   if no valid frame arrives for 2000 ms, failsafeStop() runs once and
 *   "WATCHDOG\tlink lost" is sent as a text frame. Outputs re-arm on the
 *   next command that drives an output. failsafeStop() also runs on BLE
 *   disconnect, when the WiFi TCP client drops, and when a new WiFi client
 *   replaces the old one.
 *
 *   failsafeStop():
 *     - every pin driven since boot (DIGITAL_WRITE / ANALOG_WRITE / PIN_MODE
 *       OUTPUT) -> LOW (PWM pins get analogWrite(0) first)
 *     - continuous servos (last driven with SERVO_WRITE_US) -> 1500 µs (stop)
 *     - positional servos (last driven with SERVO_WRITE) keep their angle
 */

#define FW_VERSION "2.1"

const byte HEADER_BYTE        = 0xAA; // control frame
const byte TEXT_HEADER_BYTE   = 0xAB; // text frame
const byte CMD_HEARTBEAT      = 0x00;
const byte CMD_DIGITAL_WRITE  = 0x01;
const byte CMD_ANALOG_WRITE   = 0x02;
const byte CMD_PIN_MODE       = 0x03;
const byte CMD_SERVO_WRITE    = 0x04; // Positional servo: val = angle 0-180
const byte CMD_SERVO_WRITE_US = 0x05; // Continuous servo: val encodes µs as (µs-1300)/2, range 0-200
const byte CMD_STOP_ALL       = 0x06; // Failsafe stop of every driven output (pin/val ignored)

// Names (a MAC suffix is appended at boot, see buildNames())
#define DEVICE_NAME_PREFIX "ESP32 Robot" // BLE advertising name
#define DEFAULT_HOSTNAME "robot"         // mDNS: robot.local

// WiFi AP Settings. Change WIFI_PASS (8-63 characters) before using the
// robot around other people.
#define WIFI_SSID_PREFIX "ESP32_Robot"
#define WIFI_PASS "12345678"
#define TCP_PORT  4210

// Station connect policy
#define STA_CONNECT_TIMEOUT_MS 10000
#define STA_RETRY_MS           30000
#define STA_RETRY_MAX_MS       300000

// UUIDs
#define SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// BLE MTU we ask for. Notifications are chunked to what was negotiated.
#define BLE_MTU        185

// Bytes written by the phone over BLE wait here until loop() parses them
#define BLE_RX_BUFFER  1024

// Text frame limits
#define MAX_TEXT_LEN   120
#define TEXT_BUF_SIZE  (MAX_TEXT_LEN + 1) // + NUL terminator

// GPIO numbers are 0..39 on the ESP32
#define MAX_PINS 40

// Link watchdog: app heartbeats every 500 ms, we give up after 2 s of silence
#define WATCHDOG_TIMEOUT_MS 2000

// At most one "ERR\tbad pin" reply per this many ms (a program loop could
// otherwise flood the link)
#define ERR_REPLY_INTERVAL_MS 1000

#ifdef DEBUG_ECHO
#define DBG_PRINTF(...) Serial.printf(__VA_ARGS__)
#define DBG_PRINTLN(x) Serial.println(x)
#else
#define DBG_PRINTF(...)
#define DBG_PRINTLN(x)
#endif

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------

BLEServer *pServer = NULL;
BLECharacteristic *pRxCharacteristic = NULL;
BLECharacteristic *pTxCharacteristic = NULL;
// Written by the BLE task, read by loop(). Counters (not just a flag) so a
// connect+disconnect between two loop() passes is never missed.
volatile bool bleConnected = false;
volatile uint32_t bleConnectCount = 0;
volatile uint32_t bleDisconnectCount = 0;
uint32_t bleConnectsSeen = 0;
uint32_t bleDisconnectsSeen = 0;
bool bleHelloPending = false;          // send HELLO after the first frame from the phone
StreamBufferHandle_t bleRxBuffer = NULL;

// WiFi TCP
WiFiServer tcpServer(TCP_PORT);
WiFiClient tcpClient;
bool wifiClientWasConnected = false;

// WiFi station (credentials live in NVS)
enum StaState { STA_IDLE, STA_CONNECTING, STA_CONNECTED };
StaState staState = STA_IDLE;
unsigned long staAttemptMillis = 0;    // start of the current attempt / last failure
unsigned long staRetryWaitMs = STA_RETRY_MS;   // wait before the next attempt
unsigned long staNextBackoffMs = STA_RETRY_MS; // wait after the next failure
String staSsid;                        // empty -> no credentials, station stays off
String staPass;
String hostName;                       // mDNS name (default "robot")
bool mdnsRunning = false;
Preferences prefs;

char bleName[32];                      // "ESP32 Robot 1A2B" or "Robot <name>"
char apSsid[32];                       // "ESP32_Robot_1A2B"

// State
Servo servos[MAX_PINS];
bool isServoAttached[MAX_PINS] = {false};

// Failsafe bookkeeping
bool pinTouched[MAX_PINS] = {false};        // driven as an output since boot
bool pinIsPwm[MAX_PINS] = {false};          // last drive on this pin was ANALOG_WRITE (LEDC PWM)
bool servoIsContinuous[MAX_PINS] = {false}; // last servo command on this pin was SERVO_WRITE_US
bool outputsArmed = false;                  // any output driven since the last failsafe
unsigned long lastPacketMillis = 0;         // refreshed on every valid frame (any transport)
unsigned long lastErrReplyMillis = 0;

// ---------------------------------------------------------------------------
// Frame parser (one instance per transport so the byte streams never mix)
// ---------------------------------------------------------------------------

enum Transport { T_SERIAL, T_BLE, T_WIFI };

enum ParseState {
  WAIT_HEADER,
  WAIT_CMD, WAIT_PIN, WAIT_VAL, WAIT_CHECKSUM,   // 0xAA control frame
  WAIT_TEXT_LEN, WAIT_TEXT_BODY, WAIT_TEXT_CK     // 0xAB text frame
};

struct FrameParser {
  ParseState state;
  uint8_t cmd, pin, val;       // control frame fields
  uint8_t len;                 // text frame length
  uint8_t buf[TEXT_BUF_SIZE];  // text frame body (+ NUL)
  uint8_t idx;                 // bytes of body received so far
  uint8_t sum;                 // running text checksum (wraps at 256)
  Transport transport;         // where replies go
};

FrameParser serialParser;
FrameParser bleParser;
FrameParser wifiParser;

// Prototypes (functions used before their definition)
void failsafeStop();
void executeCommand(Transport t, uint8_t cmd, uint8_t pin, uint8_t val);
void sendText(Transport t, const char *text);
void broadcastText(const char *text);
void sendHello(Transport t);
void handleTextCommand(Transport t, char *text);
void onValidFrame(Transport t);
void startStation();
void stopStation();
void serviceStation();
void startMdns();
void stopMdns();

void resetParser(FrameParser &p, Transport t) {
  p.state = WAIT_HEADER;
  p.cmd = p.pin = p.val = 0;
  p.len = 0;
  p.idx = 0;
  p.sum = 0;
  p.transport = t;
}

void feedParser(FrameParser &p, uint8_t b) {
  switch (p.state) {
  case WAIT_HEADER:
    if (b == HEADER_BYTE) {
      p.state = WAIT_CMD;
    } else if (b == TEXT_HEADER_BYTE) {
      p.sum = TEXT_HEADER_BYTE;
      p.state = WAIT_TEXT_LEN;
    }
    // any other byte: ignored (resync)
    break;

  // ---- control frame ----
  case WAIT_CMD:
    p.cmd = b;
    p.state = WAIT_PIN;
    break;
  case WAIT_PIN:
    p.pin = b;
    p.state = WAIT_VAL;
    break;
  case WAIT_VAL:
    p.val = b;
    p.state = WAIT_CHECKSUM;
    break;
  case WAIT_CHECKSUM: {
    uint8_t calcChecksum = (uint8_t)((HEADER_BYTE + p.cmd + p.pin + p.val) % 256);
    if (b == calcChecksum) {
      onValidFrame(p.transport);
      executeCommand(p.transport, p.cmd, p.pin, p.val);
    } else {
      DBG_PRINTF("Checksum Fail (t=%d): Rec=%d Calc=%d\n", (int)p.transport, b, calcChecksum);
    }
    p.state = WAIT_HEADER;
    break;
  }

  // ---- text frame ----
  case WAIT_TEXT_LEN:
    if (b > MAX_TEXT_LEN) {
      DBG_PRINTF("Text frame too long (t=%d): %d\n", (int)p.transport, b);
      p.state = WAIT_HEADER; // invalid length: drop the frame, resync
      break;
    }
    p.len = b;
    p.idx = 0;
    p.sum += b;
    p.state = (b == 0) ? WAIT_TEXT_CK : WAIT_TEXT_BODY;
    break;
  case WAIT_TEXT_BODY:
    p.buf[p.idx++] = b;
    p.sum += b;
    if (p.idx >= p.len)
      p.state = WAIT_TEXT_CK;
    break;
  case WAIT_TEXT_CK:
    if (b == p.sum) {
      p.buf[p.len] = 0; // NUL-terminate (buf has MAX_TEXT_LEN + 1 slots)
      onValidFrame(p.transport);
      handleTextCommand(p.transport, (char *)p.buf);
    } else {
      DBG_PRINTF("Text Checksum Fail (t=%d): Rec=%d Calc=%d\n", (int)p.transport, b, p.sum);
    }
    p.state = WAIT_HEADER;
    break;
  }
}

// Every valid frame (heartbeat and text included) is link activity.
void onValidFrame(Transport t) {
  lastPacketMillis = millis();
  // The phone subscribes to notifications before it starts sending, so its
  // first frame is the moment a BLE HELLO will actually arrive.
  if (t == T_BLE && bleHelloPending) {
    bleHelloPending = false;
    sendHello(T_BLE);
  }
}

// ---------------------------------------------------------------------------
// Pins
// ---------------------------------------------------------------------------

// GPIOs that can drive an output on an ESP32-WROOM DevKit.
bool isOutputPin(uint8_t p) {
  switch (p) {
  case 2: case 4: case 5: case 12: case 13: case 14: case 15: case 16:
  case 17: case 18: case 19: case 21: case 22: case 23: case 25: case 26:
  case 27: case 32: case 33:
    return true;
  default:
    return false;
  }
}

// GPIOs that can be read (outputs plus the input-only 34-39).
bool isInputPin(uint8_t p) {
  return isOutputPin(p) || p == 34 || p == 35 || p == 36 || p == 39;
}

void replyBadPin(Transport t, uint8_t pin) {
  unsigned long now = millis();
  if (now - lastErrReplyMillis < ERR_REPLY_INTERVAL_MS)
    return;
  lastErrReplyMillis = now;
  char msg[24];
  snprintf(msg, sizeof(msg), "ERR\tbad pin %u", (unsigned)pin);
  sendText(t, msg);
}

// Free a pin from whatever peripheral drove it before (servo or LEDC PWM),
// so it can be re-used for another kind of output.
void releaseServo(uint8_t pin) {
  if (isServoAttached[pin]) {
    servos[pin].detach();
    isServoAttached[pin] = false;
  }
}

void releasePwm(uint8_t pin) {
  if (pinIsPwm[pin]) {
    analogWrite(pin, 0);
    ledcDetach(pin);
    pinIsPwm[pin] = false;
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

// Stop everything we have ever driven. Safe to call repeatedly.
void failsafeStop() {
  for (int p = 0; p < MAX_PINS; p++) {
    if (pinTouched[p]) {
      if (pinIsPwm[p])
        analogWrite(p, 0); // zero the LEDC duty before forcing the pin LOW
      digitalWrite(p, LOW);
    }
    if (isServoAttached[p] && servoIsContinuous[p]) {
      servos[p].writeMicroseconds(1500); // stop continuous rotation
    }
  }
  outputsArmed = false;
}

void executeCommand(Transport t, uint8_t cmd, uint8_t pin, uint8_t val) {
  // Heartbeat: no-op, and not logged (it arrives twice a second)
  if (cmd == CMD_HEARTBEAT)
    return;

  DBG_PRINTF("EXEC: CMD=%02X PIN=%d VAL=%d\n", cmd, pin, val);

  if (cmd == CMD_STOP_ALL) {
    failsafeStop();
    return;
  }

  bool inputMode = (cmd == CMD_PIN_MODE && (val == 0 || val == 2));
  if (pin >= MAX_PINS || !(inputMode ? isInputPin(pin) : isOutputPin(pin))) {
    replyBadPin(t, pin);
    return;
  }

  if (cmd == CMD_PIN_MODE) {
    releaseServo(pin);
    releasePwm(pin);
    if (val == 1) {
      pinMode(pin, OUTPUT);
      pinTouched[pin] = true; // an output we may have to force LOW
    } else if (val == 0) {
      pinMode(pin, INPUT);
    } else if (val == 2) {
      pinMode(pin, INPUT_PULLUP);
    }
    // A pin reconfigured as an input is no longer something we drive
    if (val == 0 || val == 2)
      pinTouched[pin] = false;
  } else if (cmd == CMD_DIGITAL_WRITE) {
    releaseServo(pin);
    releasePwm(pin);
    pinMode(pin, OUTPUT);
    digitalWrite(pin, val ? HIGH : LOW);
    pinTouched[pin] = true;
    outputsArmed = true;
  } else if (cmd == CMD_ANALOG_WRITE) {
    releaseServo(pin);
    analogWrite(pin, val);
    pinTouched[pin] = true;
    pinIsPwm[pin] = true;
    outputsArmed = true;
  } else if (cmd == CMD_SERVO_WRITE || cmd == CMD_SERVO_WRITE_US) {
    bool continuous = (cmd == CMD_SERVO_WRITE_US);
    if (!isServoAttached[pin]) {
      releasePwm(pin);
      pinTouched[pin] = false; // now owned by the servo, not a plain output
      if (continuous)
        servos[pin].attach(pin, 1000, 2000);
      else
        servos[pin].attach(pin);
      isServoAttached[pin] = true;
    }
    if (continuous) {
      // val encodes the pulse width as (µs - 1300) / 2:
      // 0 -> 1300 µs (full reverse), 100 -> 1500 µs (stop), 200 -> 1700 µs (full forward)
      servos[pin].writeMicroseconds(1300 + ((unsigned int)val * 2));
    } else {
      servos[pin].write(val);
    }
    servoIsContinuous[pin] = continuous; // continuous ones are stopped on failsafe
    outputsArmed = true;
  }
}

// ---------------------------------------------------------------------------
// Text frame output
// ---------------------------------------------------------------------------

// Largest notification payload the connected phone accepts (ATT MTU - 3).
size_t bleChunkSize() {
  uint16_t mtu = pServer ? pServer->getPeerMTU(pServer->getConnId()) : 23;
  if (mtu < 23)
    mtu = 23;
  return (size_t)(mtu - 3);
}

// Build [0xAB][LEN][text][CK] and write it to the given transport.
// Text longer than MAX_TEXT_LEN is truncated.
void sendText(Transport t, const char *text) {
  size_t n = strlen(text);
  if (n > MAX_TEXT_LEN)
    n = MAX_TEXT_LEN;

  uint8_t frame[MAX_TEXT_LEN + 3];
  frame[0] = TEXT_HEADER_BYTE;
  frame[1] = (uint8_t)n;
  uint8_t sum = (uint8_t)(TEXT_HEADER_BYTE + (uint8_t)n);
  for (size_t i = 0; i < n; i++) {
    frame[2 + i] = (uint8_t)text[i];
    sum += (uint8_t)text[i];
  }
  frame[2 + n] = sum;
  size_t total = n + 3;

  switch (t) {
  case T_SERIAL:
    Serial.write(frame, total);
    break;

  case T_BLE: {
    if (!bleConnected || pTxCharacteristic == NULL)
      return;
    // Notifications longer than the negotiated MTU would be truncated and
    // the phone would drop the frame, so split to the real size.
    size_t chunkSize = bleChunkSize();
    for (size_t off = 0; off < total; off += chunkSize) {
      size_t chunk = total - off;
      if (chunk > chunkSize)
        chunk = chunkSize;
      pTxCharacteristic->setValue(frame + off, chunk);
      pTxCharacteristic->notify();
    }
    break;
  }

  case T_WIFI:
    if (tcpClient && tcpClient.connected())
      tcpClient.write(frame, total);
    break;
  }
}

// Unsolicited events go to every transport that currently has a listener.
void broadcastText(const char *text) {
  sendText(T_SERIAL, text);
  if (bleConnected)
    sendText(T_BLE, text);
  if (tcpClient && tcpClient.connected())
    sendText(T_WIFI, text);
}

// Tell a freshly connected client who we are and where we are reachable.
void sendHello(Transport t) {
  sendText(t, "HELLO\tesp32\t" FW_VERSION);
  if (staState == STA_CONNECTED) {
    String msg = "WIFI\tCONNECTED\t" + WiFi.localIP().toString();
    sendText(t, msg.c_str());
  } else {
    String msg = "WIFI\tAP\t" + WiFi.softAPIP().toString();
    sendText(t, msg.c_str());
  }
}

// ---------------------------------------------------------------------------
// NVS settings
// ---------------------------------------------------------------------------

void loadSettings() {
  prefs.begin("dorobot", true); // read-only
  staSsid = prefs.getString("ssid", "");
  staPass = prefs.getString("pass", "");
  hostName = prefs.getString("name", DEFAULT_HOSTNAME);
  prefs.end();
  if (hostName.length() == 0)
    hostName = DEFAULT_HOSTNAME;
}

void saveCredentials(const char *ssid, const char *pass) {
  prefs.begin("dorobot", false);
  prefs.putString("ssid", ssid);
  prefs.putString("pass", pass);
  prefs.end();
  staSsid = ssid;
  staPass = pass;
}

void eraseCredentials() {
  prefs.begin("dorobot", false);
  prefs.remove("ssid");
  prefs.remove("pass");
  prefs.end();
  staSsid = "";
  staPass = "";
}

void saveHostName(const char *name) {
  prefs.begin("dorobot", false);
  prefs.putString("name", name);
  prefs.end();
  hostName = name;
}

// "robot-2" style hostname: 1-31 characters of a-z 0-9 '-', not starting or
// ending with '-'. Lowercases in place. Returns false if invalid.
bool normalizeHostName(char *name) {
  size_t n = strlen(name);
  if (n == 0 || n > 31)
    return false;
  for (size_t i = 0; i < n; i++) {
    char c = name[i];
    if (c >= 'A' && c <= 'Z')
      c = c - 'A' + 'a';
    bool ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-';
    if (!ok)
      return false;
    name[i] = c;
  }
  return name[0] != '-' && name[n - 1] != '-';
}

// Unique per-board names from the last two bytes of the MAC address.
void buildNames(bool hasCustomName) {
  uint64_t mac = ESP.getEfuseMac(); // byte 0 of the MAC is the lowest byte
  unsigned b4 = (unsigned)((mac >> 32) & 0xFF);
  unsigned b5 = (unsigned)((mac >> 40) & 0xFF);
  snprintf(apSsid, sizeof(apSsid), "%s_%02X%02X", WIFI_SSID_PREFIX, b4, b5);
  if (hasCustomName)
    snprintf(bleName, sizeof(bleName), "Robot %s", hostName.c_str());
  else
    snprintf(bleName, sizeof(bleName), "%s %02X%02X", DEVICE_NAME_PREFIX, b4, b5);
}

// ---------------------------------------------------------------------------
// Text commands
// ---------------------------------------------------------------------------

// `text` is a NUL-terminated, TAB-separated command; it is modified in place.
void handleTextCommand(Transport t, char *text) {
  // Split "CMD\targ1\targ2" (arg2 keeps any further tabs, so a WiFi password
  // may contain a tab; SSIDs cannot).
  char *cmd = text;
  char *arg1 = NULL;
  char *arg2 = NULL;
  char *tab = strchr(cmd, '\t');
  if (tab) {
    *tab = 0;
    arg1 = tab + 1;
    tab = strchr(arg1, '\t');
    if (tab) {
      *tab = 0;
      arg2 = tab + 1;
    }
  }

  DBG_PRINTF("TEXT (t=%d): %s\n", (int)t, cmd);

  bool configCommand = strcmp(cmd, "WIFI") == 0 || strcmp(cmd, "NAME") == 0 ||
                       strcmp(cmd, "FORGET") == 0;
  if (configCommand && t == T_WIFI) {
    // Anyone on the network can reach the TCP port; only a phone that is
    // paired over BLE or plugged in over USB may change the robot's setup.
    sendText(t, "ERR\tuse Bluetooth or USB to change robot settings");
    return;
  }

  if (strcmp(cmd, "WIFI") == 0) {
    if (arg1 == NULL || arg1[0] == 0) {
      sendText(t, "ERR\tWIFI needs ssid");
      return;
    }
    if (strlen(arg1) > 32) {
      sendText(t, "ERR\tssid too long");
      return;
    }
    saveCredentials(arg1, arg2 ? arg2 : "");
    sendText(t, "OK\tWIFI saved, connecting");
    staNextBackoffMs = STA_RETRY_MS;
    startStation();

  } else if (strcmp(cmd, "NAME") == 0) {
    if (arg1 == NULL || arg1[0] == 0) {
      sendText(t, "ERR\tNAME needs hostname");
      return;
    }
    if (!normalizeHostName(arg1)) {
      sendText(t, "ERR\tname: use 1-31 letters, digits or -");
      return;
    }
    saveHostName(arg1);
    if (staState == STA_CONNECTED) {
      // Re-announce under the new name right away; BLE picks it up after reboot
      stopMdns();
      startMdns();
    }
    sendText(t, "OK\tNAME saved, reboot to apply to BLE");

  } else if (strcmp(cmd, "STATUS") == 0) {
    String msg = "STATUS\tsta=";
    msg += (staState == STA_CONNECTED) ? "connected" : "off";
    msg += "\tip=";
    msg += (staState == STA_CONNECTED) ? WiFi.localIP().toString() : String("0.0.0.0");
    msg += "\tap=";
    msg += WiFi.softAPIP().toString();
    msg += "\tname=";
    msg += hostName;
    msg += "\tble=";
    msg += bleConnected ? "connected" : "no";
    msg += "\tuptime=";
    msg += String(millis() / 1000UL);
    sendText(t, msg.c_str());

  } else if (strcmp(cmd, "FORGET") == 0) {
    eraseCredentials();
    stopStation();
    sendText(t, "OK\tFORGET credentials erased");

  } else {
    sendText(t, "ERR\tunknown command");
  }
}

// ---------------------------------------------------------------------------
// WiFi station + mDNS (non-blocking, polled from loop())
// ---------------------------------------------------------------------------

void startMdns() {
  if (mdnsRunning)
    return;
  if (MDNS.begin(hostName.c_str())) {
    MDNS.addService("dorobot", "tcp", TCP_PORT);
    mdnsRunning = true;
    DBG_PRINTF("mDNS: %s.local\n", hostName.c_str());
  } else {
    DBG_PRINTLN("mDNS start failed");
  }
}

void stopMdns() {
  if (!mdnsRunning)
    return;
  MDNS.end();
  mdnsRunning = false;
}

// Begin (or restart) a station connection attempt with the stored credentials.
void startStation() {
  if (staSsid.length() == 0)
    return;
  stopMdns();
  WiFi.begin(staSsid.c_str(), staPass.c_str());
  staState = STA_CONNECTING;
  staAttemptMillis = millis();
  DBG_PRINTF("STA: connecting to %s\n", staSsid.c_str());
}

// Drop the station link (credentials erased). The soft-AP stays up.
void stopStation() {
  stopMdns();
  // wifioff=false keeps the soft-AP running; eraseap=true also clears the
  // copy of the credentials the WiFi driver may have stored in flash.
  WiFi.disconnect(false, true);
  staState = STA_IDLE;
  staAttemptMillis = millis();
}

void onStationConnected() {
  staState = STA_CONNECTED;
  staNextBackoffMs = STA_RETRY_MS;
  startMdns();
  String msg = "WIFI\tCONNECTED\t" + WiFi.localIP().toString();
  DBG_PRINTF("STA: %s\n", msg.c_str());
  broadcastText(msg.c_str());
}

void onStationLost() {
  stopMdns();
  staState = STA_IDLE;
  staAttemptMillis = millis();
  staRetryWaitMs = STA_RETRY_MS; // a network that just dropped: retry soon
  DBG_PRINTLN("STA: lost");
  broadcastText("WIFI\tFAILED\tlost");
}

void serviceStation() {
  if (staSsid.length() == 0)
    return; // no credentials: station stays off

  wl_status_t st = WiFi.status();
  unsigned long now = millis();

  switch (staState) {
  case STA_CONNECTING:
    if (st == WL_CONNECTED) {
      onStationConnected();
    } else if (now - staAttemptMillis > STA_CONNECT_TIMEOUT_MS) {
      const char *reason = "timeout";
      if (st == WL_NO_SSID_AVAIL)
        reason = "no such network";
      else if (st == WL_CONNECT_FAILED)
        reason = "connect failed";
      String msg = String("WIFI\tFAILED\t") + reason;
      DBG_PRINTF("STA: %s\n", msg.c_str());
      broadcastText(msg.c_str());
      staState = STA_IDLE;
      staAttemptMillis = now;
      // Back off: wait 30 s, then 60 s, 120 s ... up to 5 min between attempts
      staRetryWaitMs = staNextBackoffMs;
      staNextBackoffMs = (staNextBackoffMs * 2 > STA_RETRY_MAX_MS) ? STA_RETRY_MAX_MS : staNextBackoffMs * 2;
    }
    break;

  case STA_CONNECTED:
    if (st != WL_CONNECTED)
      onStationLost();
    break;

  case STA_IDLE:
    if (st == WL_CONNECTED) {
      onStationConnected(); // the stack auto-reconnected in the background
    } else if (now - staAttemptMillis > staRetryWaitMs) {
      // A connection attempt scans other channels and would stall a phone
      // that is using the hotspot, so wait until nobody is on it.
      if (WiFi.softAPgetStationNum() == 0)
        startStation();
      else
        staAttemptMillis = now;
    }
    break;
  }
}

// ---------------------------------------------------------------------------
// BLE callbacks — these run on the Bluetooth task (another core), so they
// only record events and queue bytes; loop() does all the work.
// ---------------------------------------------------------------------------

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    bleConnected = true;
    bleConnectCount = bleConnectCount + 1;
  }
  void onDisconnect(BLEServer *pServer) {
    bleConnected = false;
    bleDisconnectCount = bleDisconnectCount + 1;
  }
};

class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String rxValue = pCharacteristic->getValue();
    if (rxValue.length() > 0 && bleRxBuffer != NULL) {
      // Non-blocking: if loop() has fallen far behind, excess bytes are
      // dropped and the parser resynchronizes on the next header.
      xStreamBufferSend(bleRxBuffer, rxValue.c_str(), rxValue.length(), 0);
    }
  }
};

// Handle BLE connect/disconnect transitions and parse queued bytes.
void serviceBle() {
  uint32_t disconnects = bleDisconnectCount;
  uint32_t connects = bleConnectCount;
  if (disconnects != bleDisconnectsSeen) {
    bleDisconnectsSeen = disconnects;
    bleHelloPending = false;
    DBG_PRINTLN("BLE Disconnected");
    failsafeStop(); // link gone: stop everything we were driving
    BLEDevice::startAdvertising();
  }
  if (connects != bleConnectsSeen) {
    bleConnectsSeen = connects;
    if (bleConnected) {
      resetParser(bleParser, T_BLE);
      bleHelloPending = true; // sent on the first frame from the phone
      DBG_PRINTLN("BLE Connected");
    }
  }

  uint8_t chunk[64];
  size_t n;
  while ((n = xStreamBufferReceive(bleRxBuffer, chunk, sizeof(chunk), 0)) > 0) {
    for (size_t i = 0; i < n; i++)
      feedParser(bleParser, chunk[i]);
  }
}

// ---------------------------------------------------------------------------
// WiFi TCP: one client at a time, and the newest connection wins. A phone
// that dropped off WiFi leaves a half-open socket behind; when it
// reconnects, its new connection must take over at once instead of queueing
// commands (and replaying them in a burst minutes later).
// ---------------------------------------------------------------------------

void serviceTcp() {
  bool wifiConnectedNow = tcpClient && tcpClient.connected();

  // The client we were talking to has gone away -> failsafe (only on the transition)
  if (wifiClientWasConnected && !wifiConnectedNow) {
    DBG_PRINTLN("WiFi client disconnected");
    failsafeStop();
    tcpClient.stop();
  }

  if (tcpServer.hasClient()) {
    WiFiClient incoming = tcpServer.accept();
    if (incoming) {
      if (wifiConnectedNow) {
        DBG_PRINTLN("WiFi client replaced by a new connection");
        failsafeStop();
        tcpClient.stop();
      }
      tcpClient = incoming;
      tcpClient.setNoDelay(true);
      resetParser(wifiParser, T_WIFI); // fresh state machine for the new client
      wifiConnectedNow = true;
      DBG_PRINTLN("WiFi client connected");
      sendHello(T_WIFI);
    }
  }
  wifiClientWasConnected = wifiConnectedNow;

  if (wifiConnectedNow) {
    while (tcpClient.available()) {
      feedParser(wifiParser, (uint8_t)tcpClient.read());
    }
  }
}

// ---------------------------------------------------------------------------
// Setup / loop
// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);

  resetParser(serialParser, T_SERIAL);
  resetParser(bleParser, T_BLE);
  resetParser(wifiParser, T_WIFI);

  loadSettings();
  prefs.begin("dorobot", true);
  bool hasCustomName = prefs.isKey("name");
  prefs.end();
  buildNames(hasCustomName);

  // BLE Init
  bleRxBuffer = xStreamBufferCreate(BLE_RX_BUFFER, 1);
  BLEDevice::init(bleName);
  BLEDevice::setMTU(BLE_MTU);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pRxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_RX,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  pRxCharacteristic->setCallbacks(new MyCallbacks());
  pTxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  BLEDevice::startAdvertising();

  // WiFi: soft-AP always up, station joins the saved network if we have one.
  // Credentials live only in our own NVS namespace, not the driver's.
  WiFi.persistent(false);
  WiFi.setHostname(hostName.c_str()); // must precede mode() on the ESP32 core
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(apSsid, WIFI_PASS);
  tcpServer.begin();
  DBG_PRINTF("BLE name: %s\n", bleName);
  DBG_PRINTF("WiFi AP started: %s (%s)\n", apSsid, WiFi.softAPIP().toString().c_str());
  DBG_PRINTF("TCP server on port %d\n", TCP_PORT);

  if (staSsid.length() > 0)
    startStation();

  DBG_PRINTLN("Ready (BLE + Serial + WiFi AP/STA).");

  // Built-in LED (GPIO 2) as an output for a quick first test
  pinMode(2, OUTPUT);
}

void loop() {
  // Poll Serial
  while (Serial.available()) {
    feedParser(serialParser, (uint8_t)Serial.read());
  }

  serviceTcp();
  serviceBle();

  // Station connect / retry / loss detection
  serviceStation();

  // Link watchdog: outputs armed and 2 s without any valid frame -> stop once
  if (outputsArmed && (millis() - lastPacketMillis > WATCHDOG_TIMEOUT_MS)) {
    failsafeStop(); // clears outputsArmed, so this fires only once per link loss
    broadcastText("WATCHDOG\tlink lost");
  }

  delay(5);
}
