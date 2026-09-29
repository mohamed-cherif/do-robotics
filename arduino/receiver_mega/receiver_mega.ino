#include <Servo.h>

/**
 * DO ROBOTICS - Slave Firmware (Arduino Mega Version)
 * ---------------------------------------------------
 * Compatible with Arduino Mega 2560.
 *
 * Key differences from the Uno version:
 *   - 54 digital pins (2-53 usable; 0/1 reserved for Serial)
 *   - PWM available on pins: 2-13, 44, 45, 46
 *   - Up to 48 servos supported by the AVR Servo library on Mega
 *   - Servo array and pin guard updated accordingly
 *
 * Commands
 *   0x00  HEARTBEAT      – no-op, only refreshes the link watchdog
 *                          (the app sends one every 500 ms; no LED pulse)
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
 * Framing (the parser dispatches on the first byte of every frame)
 *   0xAA  control   [0xAA][CMD][PIN][VAL][CK]           phone -> board
 *                   CK = (0xAA + CMD + PIN + VAL) % 256
 *   0xAB  text      [0xAB][LEN][LEN bytes ASCII][CK]    both directions
 *                   CK = (0xAB + LEN + sum of bytes) % 256
 *   any other byte while waiting for a header is ignored (resync).
 *   A bad checksum discards the frame silently.
 *
 * Text commands are NOT supported on this board. Every text frame with
 *   a valid checksum is answered with the text frame  ERR\tunsupported
 *   so the app can tell it is talking to an AVR board. Frames with
 *   LEN > 64 are dropped and answered with  ERR\ttoo long.
 *   The watchdog message is also a text frame:  WATCHDOG\tlink lost
 *
 * Link watchdog / failsafe
 *   Every valid packet (heartbeat included) refreshes lastPacketMillis.
 *   Once any output has been driven ("armed"), if no valid packet arrives
 *   for 2000 ms, failsafeStop() runs once and the text frame
 *   "WATCHDOG\tlink lost" is sent over Serial. Outputs re-arm on the next
 *   command that drives an output.
 *
 *   failsafeStop():
 *     - every pin driven via DIGITAL_WRITE / ANALOG_WRITE since boot -> LOW
 *     - continuous servos (last driven with SERVO_WRITE_US) -> 1500 µs (stop)
 *     - positional servos (last driven with SERVO_WRITE) keep their angle
 */

const byte HEADER_BYTE      = 0xAA; // control frame
const byte TEXT_HEADER_BYTE = 0xAB; // text frame
const byte CMD_HEARTBEAT   = 0x00;
const byte CMD_DIGITAL_WRITE  = 0x01;
const byte CMD_ANALOG_WRITE   = 0x02;
const byte CMD_PIN_MODE       = 0x03;
const byte CMD_SERVO_WRITE    = 0x04;
const byte CMD_SERVO_WRITE_US = 0x05;
const byte CMD_STOP_ALL       = 0x06;

// Mega has 54 digital pins (0-53)
#define MAX_PINS 54

// Link watchdog: app heartbeats every 500 ms, we give up after 2 s of silence
#define WATCHDOG_TIMEOUT_MS 2000

// Longest text frame body we accept (AVR RAM is tight). The body is never
// stored: this board only validates the frame and replies ERR\tunsupported.
#define MAX_TEXT_LEN 64

enum State {
  WAIT_HEADER,
  WAIT_CMD, WAIT_PIN, WAIT_VAL, WAIT_CHECKSUM, // 0xAA control frame
  WAIT_TEXT_LEN, WAIT_TEXT_BODY, WAIT_TEXT_CK  // 0xAB text frame
};
State state = WAIT_HEADER;

uint8_t textLen = 0; // text frame: declared body length
uint8_t textIdx = 0; // text frame: body bytes consumed so far
uint8_t textSum = 0; // text frame: running checksum (wraps at 256)

uint8_t cmd, pin, val;
Servo activeServos[MAX_PINS];
bool isServoAttached[MAX_PINS];

// Failsafe bookkeeping
bool pinTouched[MAX_PINS];          // driven via DIGITAL_WRITE / ANALOG_WRITE since boot
bool servoIsContinuous[MAX_PINS];   // last servo command on this pin was SERVO_WRITE_US
bool outputsArmed = false;          // any output driven since the last failsafe
unsigned long lastPacketMillis = 0; // refreshed on every valid packet

unsigned long lastPulse = 0;

// Stop everything we have ever driven. Safe to call repeatedly.
void failsafeStop() {
  for (uint8_t p = 0; p < MAX_PINS; p++) {
    if (pinTouched[p]) {
      // digitalWrite on AVR also switches off any PWM running on the pin
      digitalWrite(p, LOW);
    }
    if (isServoAttached[p] && servoIsContinuous[p]) {
      activeServos[p].writeMicroseconds(1500); // stop continuous rotation
    }
  }
  outputsArmed = false;
}

void executeCommand(uint8_t c, uint8_t p, uint8_t v) {
  // Every valid packet (heartbeat included) refreshes the link watchdog
  lastPacketMillis = millis();

  // Heartbeat: no-op, and no LED pulse (it arrives twice a second)
  if (c == CMD_HEARTBEAT) return;

  digitalWrite(LED_BUILTIN, HIGH);
  lastPulse = millis();

  if (c == CMD_STOP_ALL) {
    failsafeStop();
    return;
  }

  // Reserve pins 0 and 1 (Serial), block out-of-range pins
  if (p < 2 || p >= MAX_PINS) return;

  if (c == CMD_PIN_MODE) {
    if (v == 1)      pinMode(p, OUTPUT);
    else if (v == 0) pinMode(p, INPUT);
    else if (v == 2) pinMode(p, INPUT_PULLUP);
    if (isServoAttached[p]) {
      activeServos[p].detach();
      isServoAttached[p] = false;
    }
    // A pin reconfigured as an input is no longer something we drive
    if (v == 0 || v == 2) pinTouched[p] = false;

  } else if (c == CMD_DIGITAL_WRITE) {
    if (isServoAttached[p]) {
      activeServos[p].detach();
      isServoAttached[p] = false;
    }
    pinMode(p, OUTPUT);
    digitalWrite(p, v ? HIGH : LOW);
    pinTouched[p] = true;
    outputsArmed = true;

  } else if (c == CMD_ANALOG_WRITE) {
    if (isServoAttached[p]) {
      activeServos[p].detach();
      isServoAttached[p] = false;
    }
    pinMode(p, OUTPUT);
    analogWrite(p, v);
    pinTouched[p] = true;
    outputsArmed = true;

  } else if (c == CMD_SERVO_WRITE) {
    // Positional servo: val = angle in degrees (0-180)
    if (!isServoAttached[p]) {
      activeServos[p].attach(p, 544, 2400);
      isServoAttached[p] = true;
    }
    activeServos[p].write(v);
    servoIsContinuous[p] = false; // positional: left holding its angle on failsafe
    outputsArmed = true;

  } else if (c == CMD_SERVO_WRITE_US) {
    // Continuous rotation servo: val encodes pulse width as (µs - 1300) / 2
    // val=0 -> 1300µs (full rev), val=100 -> 1500µs (stop), val=200 -> 1700µs (full fwd)
    if (!isServoAttached[p]) {
      activeServos[p].attach(p, 1000, 2000);
      isServoAttached[p] = true;
    }
    unsigned int us = 1300 + ((unsigned int)v * 2);
    activeServos[p].writeMicroseconds(us);
    servoIsContinuous[p] = true; // continuous: driven to 1500µs on failsafe
    outputsArmed = true;
  }
}

// Send a text frame [0xAB][LEN][text][CK] over Serial. `text` lives in flash.
void sendText(const __FlashStringHelper *text) {
  PGM_P p = reinterpret_cast<PGM_P>(text);
  uint8_t len = (uint8_t)strlen_P(p);
  uint8_t sum = (uint8_t)(TEXT_HEADER_BYTE + len);
  Serial.write(TEXT_HEADER_BYTE);
  Serial.write(len);
  for (uint8_t i = 0; i < len; i++) {
    uint8_t c = (uint8_t)pgm_read_byte(p + i);
    Serial.write(c);
    sum += c;
  }
  Serial.write(sum);
}

void processByte(uint8_t b) {
  switch (state) {
  case WAIT_HEADER:
    if (b == HEADER_BYTE) {
      state = WAIT_CMD;
    } else if (b == TEXT_HEADER_BYTE) {
      textSum = TEXT_HEADER_BYTE;
      state = WAIT_TEXT_LEN;
    }
    // any other byte: ignored (resync)
    break;
  case WAIT_CMD:
    cmd = b;
    state = WAIT_PIN;
    break;
  case WAIT_PIN:
    pin = b;
    state = WAIT_VAL;
    break;
  case WAIT_VAL:
    val = b;
    state = WAIT_CHECKSUM;
    break;
  case WAIT_CHECKSUM:
    if (b == (uint8_t)((HEADER_BYTE + cmd + pin + val) % 256)) {
      executeCommand(cmd, pin, val);
    }
    state = WAIT_HEADER;
    break;

  // ---- 0xAB text frame: validated, never stored, always unsupported here ----
  case WAIT_TEXT_LEN:
    if (b > MAX_TEXT_LEN) {
      sendText(F("ERR\ttoo long"));
      state = WAIT_HEADER; // drop the frame, resync on the next header
      break;
    }
    textLen = b;
    textIdx = 0;
    textSum += b;
    state = (b == 0) ? WAIT_TEXT_CK : WAIT_TEXT_BODY;
    break;
  case WAIT_TEXT_BODY:
    textSum += b;
    if (++textIdx >= textLen)
      state = WAIT_TEXT_CK;
    break;
  case WAIT_TEXT_CK:
    if (b == textSum) {
      lastPacketMillis = millis(); // a valid frame counts as link activity
      sendText(F("ERR\tunsupported"));
    }
    state = WAIT_HEADER; // bad checksum: dropped silently
    break;
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);

  for (int i = 0; i < MAX_PINS; i++) {
    isServoAttached[i] = false;
    pinTouched[i] = false;
    servoIsContinuous[i] = false;
  }

  // Power-on blink sequence
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_BUILTIN, HIGH);
    delay(100);
    digitalWrite(LED_BUILTIN, LOW);
    delay(100);
  }
}

void loop() {
  while (Serial.available()) {
    processByte(Serial.read());
  }

  // Link watchdog: outputs armed and 2 s without any valid packet -> stop once
  if (outputsArmed && (millis() - lastPacketMillis > WATCHDOG_TIMEOUT_MS)) {
    failsafeStop(); // clears outputsArmed, so this fires only once per link loss
    sendText(F("WATCHDOG\tlink lost"));
  }

  if (lastPulse != 0 && (millis() - lastPulse > 40)) {
    digitalWrite(LED_BUILTIN, LOW);
    lastPulse = 0;
  }
}
