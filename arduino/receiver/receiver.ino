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

/**
 * DO ROBOTICS - Slave Firmware (ESP32 Version)
 * --------------------------------------------
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
 * Text commands (fields separated by TAB, no trailing newline). The reply
 * goes back on the transport the command arrived on.
 *   phone -> board                 board -> phone
 *   WIFI\t<ssid>\t<password>       OK\tWIFI saved, connecting
 *                                  then later (broadcast on every transport):
 *                                  WIFI\tCONNECTED\t<ip>  or  WIFI\tFAILED\t<reason>
 *   NAME\t<hostname>               OK\tNAME saved, reboot to apply to BLE
 *   STATUS                         STATUS\tsta=<connected|off>\tip=<ip>\tap=192.168.4.1
 *                                        \tname=<name>\tble=<connected|no>\tuptime=<s>
 *   FORGET                         OK\tFORGET credentials erased
 *   <anything else>                ERR\tunknown command
 *   (bad arguments)                ERR\t<msg>
 *
 * Unsolicited board -> phone text
 *   HELLO\tesp32\t2.0              when a BLE client subscribes / TCP client connects,
 *                                  followed by WIFI\tCONNECTED\t<ip> or WIFI\tAP\t192.168.4.1
 *   WIFI\tCONNECTED\t<ip>          station joined the saved network (mDNS up)
 *   WIFI\tFAILED\t<reason>         station attempt timed out, or "lost" when dropped
 *   WATCHDOG\tlink lost            link watchdog fired (see below)
 *
 * WiFi
 *   Mode is AP+STA: the soft-AP (ESP32_Robot / 12345678, 192.168.4.1) is
 *   always up. If NVS holds credentials (Preferences namespace "dorobot",
 *   keys ssid/pass/name) the board also joins that network: 10 s connect
 *   timeout, retried every 30 s while credentials exist. On station connect
 *   mDNS advertises <name>.local (default "robot") with _dorobot._tcp:4210.
 *
 * Link watchdog / failsafe
 *   Every valid frame on any transport (heartbeat and text included)
 *   refreshes lastPacketMillis. Once any output has been driven ("armed"),
 *   if no valid frame arrives for 2000 ms, failsafeStop() runs once and
 *   "WATCHDOG\tlink lost" is sent as a text frame. Outputs re-arm on the
 *   next command that drives an output. failsafeStop() also runs on BLE
 *   disconnect and when the WiFi TCP client drops.
 *
 *   failsafeStop():
 *     - every pin driven via DIGITAL_WRITE / ANALOG_WRITE since boot -> LOW
 *       (PWM pins get analogWrite(0) first, then digitalWrite LOW)
 *     - continuous servos (last driven with SERVO_WRITE_US) -> 1500 µs (stop)
 *     - positional servos (last driven with SERVO_WRITE) keep their angle
 */

#define FW_VERSION "2.0"

const byte HEADER_BYTE        = 0xAA; // control frame
const byte TEXT_HEADER_BYTE   = 0xAB; // text frame
const byte CMD_HEARTBEAT      = 0x00;
const byte CMD_DIGITAL_WRITE  = 0x01;
const byte CMD_ANALOG_WRITE   = 0x02;
const byte CMD_PIN_MODE       = 0x03;
const byte CMD_SERVO_WRITE    = 0x04; // Positional servo: val = angle 0-180
const byte CMD_SERVO_WRITE_US = 0x05; // Continuous servo: val encodes µs as (µs-1300)/2, range 0-200
const byte CMD_STOP_ALL       = 0x06; // Failsafe stop of every driven output (pin/val ignored)

// Device Name (BLE advertising name until the user stores one with NAME)
#define DEVICE_NAME "ESP32 Robot"
#define DEFAULT_HOSTNAME "robot" // mDNS: robot.local

// WiFi AP Settings
#define WIFI_SSID "ESP32_Robot"
#define WIFI_PASS "12345678"
#define TCP_PORT  4210

// Station connect policy
#define STA_CONNECT_TIMEOUT_MS 10000
#define STA_RETRY_MS           30000

// UUIDs
#define SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// BLE MTU we ask for, and the largest notify payload we send in one go
#define BLE_MTU        185
#define BLE_CHUNK      180

// Text frame limits
#define MAX_TEXT_LEN   120
#define TEXT_BUF_SIZE  (MAX_TEXT_LEN + 1) // + NUL terminator

// GPIO range we accept (0..39)
#define MAX_PINS 40

// Link watchdog: app heartbeats every 500 ms, we give up after 2 s of silence
#define WATCHDOG_TIMEOUT_MS 2000

// Delay between BLE connect and the HELLO notify, so the client has time to
// subscribe to the TX characteristic
#define BLE_HELLO_DELAY_MS 300

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
bool deviceConnected = false;
bool bleHelloPending = false;          // send HELLO once the notify subscription is up
unsigned long bleConnectMillis = 0;

// WiFi TCP
WiFiServer tcpServer(TCP_PORT);
WiFiClient tcpClient;
bool wifiClientWasConnected = false;

// WiFi station (credentials live in NVS)
enum StaState { STA_IDLE, STA_CONNECTING, STA_CONNECTED };
StaState staState = STA_IDLE;
unsigned long staAttemptMillis = 0;    // start of the current attempt / last failure
String staSsid;                        // empty -> no credentials, station stays off
String staPass;
String hostName;                       // mDNS name (default "robot")
bool mdnsRunning = false;
Preferences prefs;

// State
Servo servos[MAX_PINS]; // Increased range
bool isServoAttached[MAX_PINS] = {false};

// Failsafe bookkeeping
bool pinTouched[MAX_PINS] = {false};        // driven via DIGITAL_WRITE / ANALOG_WRITE since boot
bool pinIsPwm[MAX_PINS] = {false};          // last drive on this pin was ANALOG_WRITE (LEDC PWM)
bool servoIsContinuous[MAX_PINS] = {false}; // last servo command on this pin was SERVO_WRITE_US
bool outputsArmed = false;                  // any output driven since the last failsafe
unsigned long lastPacketMillis = 0;         // refreshed on every valid frame (any transport)

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
void executeCommand(uint8_t cmd, uint8_t pin, uint8_t val);
void sendText(Transport t, const char *text);
void broadcastText(const char *text);
void sendHello(Transport t);
void handleTextCommand(Transport t, char *text);
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
      executeCommand(p.cmd, p.pin, p.val); // also refreshes the watchdog
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
      handleTextCommand(p.transport, (char *)p.buf);
    } else {
      DBG_PRINTF("Text Checksum Fail (t=%d): Rec=%d Calc=%d\n", (int)p.transport, b, p.sum);
    }
    p.state = WAIT_HEADER;
    break;
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

void executeCommand(uint8_t cmd, uint8_t pin, uint8_t val) {
  // Every valid packet (heartbeat included) refreshes the link watchdog
  lastPacketMillis = millis();

  // Heartbeat: no-op, and not logged (it arrives twice a second)
  if (cmd == CMD_HEARTBEAT)
    return;

  DBG_PRINTF("EXEC: CMD=%02X PIN=%d VAL=%d\n", cmd, pin, val);

  if (cmd == CMD_STOP_ALL) {
    failsafeStop();
    return;
  }

  if (pin >= MAX_PINS)
    return;

  if (cmd == CMD_PIN_MODE) {
    if (val == 1)
      pinMode(pin, OUTPUT);
    else if (val == 0)
      pinMode(pin, INPUT);
    else if (val == 2)
      pinMode(pin, INPUT_PULLUP);

    if (isServoAttached[pin]) {
      servos[pin].detach();
      isServoAttached[pin] = false;
    }
    // A pin reconfigured as an input is no longer something we drive
    if (val == 0 || val == 2) {
      pinTouched[pin] = false;
      pinIsPwm[pin] = false;
    }
  } else if (cmd == CMD_DIGITAL_WRITE) {
    pinMode(pin, OUTPUT);
    digitalWrite(pin, val ? HIGH : LOW);
    pinTouched[pin] = true;
    pinIsPwm[pin] = false;
    outputsArmed = true;
  } else if (cmd == CMD_ANALOG_WRITE) {
    analogWrite(pin, val);
    pinTouched[pin] = true;
    pinIsPwm[pin] = true;
    outputsArmed = true;
  } else if (cmd == CMD_SERVO_WRITE) {
    if (!isServoAttached[pin]) {
      servos[pin].attach(pin);
      isServoAttached[pin] = true;
    }
    servos[pin].write(val);
    servoIsContinuous[pin] = false; // positional: left holding its angle on failsafe
    outputsArmed = true;
  } else if (cmd == CMD_SERVO_WRITE_US) {
    // Continuous rotation servo — val encodes pulse width as (µs - 1300) / 2
    // e.g. val=0 -> 1300µs (full rev), val=100 -> 1500µs (stop), val=200 -> 1700µs (full fwd)
    if (!isServoAttached[pin]) {
      servos[pin].attach(pin, 1000, 2000);
      isServoAttached[pin] = true;
    }
    unsigned int us = 1300 + ((unsigned int)val * 2);
    servos[pin].writeMicroseconds(us);
    servoIsContinuous[pin] = true; // continuous: driven to 1500µs on failsafe
    outputsArmed = true;
  }
}

// ---------------------------------------------------------------------------
// Text frame output
// ---------------------------------------------------------------------------

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

  case T_BLE:
    if (!deviceConnected || pTxCharacteristic == NULL)
      return;
    // A whole frame is at most 123 bytes so this normally goes out in one
    // notify; chunk anyway in case the limits above are ever raised.
    for (size_t off = 0; off < total; off += BLE_CHUNK) {
      size_t chunk = total - off;
      if (chunk > BLE_CHUNK)
        chunk = BLE_CHUNK;
      pTxCharacteristic->setValue(frame + off, chunk);
      pTxCharacteristic->notify();
    }
    break;

  case T_WIFI:
    if (tcpClient && tcpClient.connected())
      tcpClient.write(frame, total);
    break;
  }
}

// Unsolicited events go to every transport that currently has a listener.
void broadcastText(const char *text) {
  sendText(T_SERIAL, text);
  if (deviceConnected)
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
// NVS credentials
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

// ---------------------------------------------------------------------------
// Text commands
// ---------------------------------------------------------------------------

// `text` is a NUL-terminated, TAB-separated command; it is modified in place.
void handleTextCommand(Transport t, char *text) {
  // Text frames count as link activity, like control packets
  lastPacketMillis = millis();

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
    startStation();

  } else if (strcmp(cmd, "NAME") == 0) {
    if (arg1 == NULL || arg1[0] == 0) {
      sendText(t, "ERR\tNAME needs hostname");
      return;
    }
    if (strlen(arg1) > 31) {
      sendText(t, "ERR\tname too long");
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
    msg += deviceConnected ? "connected" : "no";
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
  WiFi.disconnect(false, false); // station only; AP untouched
  staState = STA_IDLE;
  staAttemptMillis = millis();
}

void onStationConnected() {
  staState = STA_CONNECTED;
  startMdns();
  String msg = "WIFI\tCONNECTED\t" + WiFi.localIP().toString();
  DBG_PRINTF("STA: %s\n", msg.c_str());
  broadcastText(msg.c_str());
}

void onStationLost() {
  stopMdns();
  staState = STA_IDLE;
  staAttemptMillis = millis(); // next retry in STA_RETRY_MS
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
      staAttemptMillis = now; // retry in STA_RETRY_MS
    }
    break;

  case STA_CONNECTED:
    if (st != WL_CONNECTED)
      onStationLost();
    break;

  case STA_IDLE:
    if (st == WL_CONNECTED) {
      onStationConnected(); // the stack auto-reconnected in the background
    } else if (now - staAttemptMillis > STA_RETRY_MS) {
      startStation();
    }
    break;
  }
}

// ---------------------------------------------------------------------------
// BLE callbacks
// ---------------------------------------------------------------------------

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    deviceConnected = true;
    resetParser(bleParser, T_BLE);
    bleHelloPending = true; // HELLO goes out from loop() after BLE_HELLO_DELAY_MS
    bleConnectMillis = millis();
    DBG_PRINTLN("BLE Connected");
  }
  void onDisconnect(BLEServer *pServer) {
    deviceConnected = false;
    bleHelloPending = false;
    DBG_PRINTLN("BLE Disconnected");
    failsafeStop(); // link gone: stop everything we were driving
    BLEDevice::startAdvertising();
  }
};

class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String rxValue = pCharacteristic->getValue();
    if (rxValue.length() > 0) {
      for (int i = 0; i < rxValue.length(); i++) {
        feedParser(bleParser, (uint8_t)rxValue[i]);
      }
    }
  }
};

// ---------------------------------------------------------------------------
// Setup / loop
// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);

  resetParser(serialParser, T_SERIAL);
  resetParser(bleParser, T_BLE);
  resetParser(wifiParser, T_WIFI);

  loadSettings();

  // BLE Init — advertise under the stored name once the user has set one
  prefs.begin("dorobot", true);
  bool hasCustomName = prefs.isKey("name");
  prefs.end();
  BLEDevice::init(hasCustomName ? hostName.c_str() : DEVICE_NAME);
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

  // WiFi: soft-AP always up, station joins the saved network if we have one
  WiFi.setHostname(hostName.c_str()); // must precede mode() on the ESP32 core
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(WIFI_SSID, WIFI_PASS);
  tcpServer.begin();
  DBG_PRINTF("WiFi AP started: %s\n", WiFi.softAPIP().toString().c_str());
  DBG_PRINTF("TCP server on port %d\n", TCP_PORT);

  if (staSsid.length() > 0)
    startStation();

  DBG_PRINTLN("Ready (BLE + Serial + WiFi AP/STA).");

  // Special: Initialize builtin LED as Output for immediate gratification
  pinMode(2, OUTPUT);
}

void loop() {
  // Poll Serial
  while (Serial.available()) {
    feedParser(serialParser, (uint8_t)Serial.read());
  }

  // Poll WiFi TCP
  bool wifiConnectedNow = tcpClient && tcpClient.connected();

  // The client we were talking to has gone away -> failsafe (only on the transition)
  if (wifiClientWasConnected && !wifiConnectedNow) {
    DBG_PRINTLN("WiFi client disconnected");
    failsafeStop();
    tcpClient.stop();
  }

  if (!wifiConnectedNow) {
    WiFiClient newClient = tcpServer.available();
    if (newClient) {
      tcpClient = newClient;
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

  // BLE RX is callback driven (onWrite). HELLO is deferred so the client has
  // time to enable notifications on the TX characteristic.
  if (bleHelloPending && deviceConnected &&
      (millis() - bleConnectMillis >= BLE_HELLO_DELAY_MS)) {
    bleHelloPending = false;
    sendHello(T_BLE);
  }

  // Station connect / retry / loss detection
  serviceStation();

  // Link watchdog: outputs armed and 2 s without any valid frame -> stop once
  if (outputsArmed && (millis() - lastPacketMillis > WATCHDOG_TIMEOUT_MS)) {
    failsafeStop(); // clears outputsArmed, so this fires only once per link loss
    broadcastText("WATCHDOG\tlink lost");
  }

  delay(5);
}
