#include <Servo.h>

/**
 * DO ROBOTICS - Slave Firmware (Arduino Uno Version)
 * --------------------------------------------------
 * Requires: "Arduino AVR Boards" and the built-in Servo library.
 *
 * v1.5 - servo pool (the old one-Servo-per-pin array silently used up every
 *        servo slot, so servos on some pins never moved), pin 13 activity
 *        blink only while the program isn't using pin 13, analog pins usable
 *        as digital outputs, clear ERR replies for bad pins / pins without
 *        PWM / PWM pins taken over by the servo timer, PIN_MODE OUTPUT pins
 *        included in the failsafe.
 * v1.4 - 0xAB text-frame parsing (answers ERR\tunsupported), framed WATCHDOG
 * v1.3 - Link watchdog / failsafe + STOP_ALL command
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
 * Pins
 *   Digital 2-13 and A0-A5 (numbers 14-19; digital only). PWM: 3 5 6 9 10 11.
 *   Pins 0 and 1 are the USB serial link and are never driven.
 *   ANALOG_WRITE on a pin without PWM keeps the old behaviour (on at >= 128)
 *   and answers  ERR\tpin <n> has no PWM.  Once a servo has been attached, the
 *   Servo library owns Timer1 (pins 9 and 10) from the first servo until reset, so PWM
 *   on those pins is refused with
 *   ERR\tpin <n>: no PWM once servos are used  (until the board is reset).
 *   Up to 8 servos at once.
 *   Replies are sent at most once per second.
 *
 * Link watchdog / failsafe
 *   Every valid packet (heartbeat included) refreshes lastPacketMillis.
 *   Once any output has been driven ("armed"), if no valid packet arrives
 *   for 2000 ms, failsafeStop() runs once and the text frame
 *   "WATCHDOG\tlink lost" is sent over Serial. Outputs re-arm on the next
 *   command that drives an output.
 *
 *   failsafeStop():
 *     - every pin driven as an output since boot -> LOW
 *     - continuous servos (last driven with SERVO_WRITE_US) -> 1500 µs (stop)
 *     - positional servos (last driven with SERVO_WRITE) keep their angle
 */

const byte HEADER_BYTE = 0xAA;      // control frame
const byte TEXT_HEADER_BYTE = 0xAB; // text frame
const byte CMD_HEARTBEAT = 0x00;
const byte CMD_DIGITAL_WRITE = 0x01;
const byte CMD_ANALOG_WRITE = 0x02;
const byte CMD_PIN_MODE = 0x03;
const byte CMD_SERVO_WRITE = 0x04;    // Positional servo: val = angle 0-180
const byte CMD_SERVO_WRITE_US = 0x05; // Continuous servo: val encodes µs as (µs-1300)/2, range 0-200
const byte CMD_STOP_ALL = 0x06;       // Failsafe stop of every driven output (pin/val ignored)

// Usable pins are FIRST_PIN .. NUM_PINS-1 (digital pins, then the analog
// pins used as digital outputs).
#define FIRST_PIN 2
#define NUM_PINS 20

// Servo objects are handed out on attach. Each Servo object reserves a slot
// in the library when it is constructed, so there must be only a few.
#define SERVO_POOL 8

// PWM pins whose timer the Servo library takes over once a servo is attached
const uint8_t SERVO_TIMER_PINS[] = {9, 10};

// Link watchdog: app heartbeats every 500 ms, we give up after 2 s of silence
#define WATCHDOG_TIMEOUT_MS 2000

// Minimum time between two ERR replies (a program loop could flood the link)
#define ERR_REPLY_INTERVAL_MS 1000

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

Servo servoPool[SERVO_POOL];
int8_t servoSlotOfPin[NUM_PINS]; // -1 = no servo on this pin
uint8_t servosAttached = 0;
// The Servo library takes over a timer on the first attach and never gives
// it back (not even after the last detach), so remember it until reset.
bool servoTimerClaimed = false;

// Failsafe bookkeeping
bool pinTouched[NUM_PINS];          // driven as an output since boot
bool servoIsContinuous[NUM_PINS];   // last servo command on this pin was SERVO_WRITE_US
bool pinUsedByProgram[NUM_PINS];    // any command addressed this pin (activity LED check)
bool outputsArmed = false;          // any output driven since the last failsafe
unsigned long lastPacketMillis = 0; // refreshed on every valid packet
unsigned long lastErrMillis = 0;

unsigned long lastPulse = 0;

// Send a text frame [0xAB][LEN][text][CK] over Serial from a RAM string.
void sendText(const char *text) {
  uint8_t len = (uint8_t)strlen(text);
  uint8_t sum = (uint8_t)(TEXT_HEADER_BYTE + len);
  Serial.write(TEXT_HEADER_BYTE);
  Serial.write(len);
  for (uint8_t i = 0; i < len; i++) {
    Serial.write((uint8_t)text[i]);
    sum += (uint8_t)text[i];
  }
  Serial.write(sum);
}

// Same for a string that lives in flash (F("...")).
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

// "ERR\t<prefix><pin><suffix>", at most once per ERR_REPLY_INTERVAL_MS.
void replyPinError(const char *prefix, uint8_t p, const char *suffix) {
  unsigned long now = millis();
  if (now - lastErrMillis < ERR_REPLY_INTERVAL_MS)
    return;
  lastErrMillis = now;
  char msg[48];
  snprintf(msg, sizeof(msg), "ERR\t%s%u%s", prefix, (unsigned)p, suffix);
  sendText(msg);
}

bool isServoTimerPin(uint8_t p) {
  for (uint8_t i = 0; i < sizeof(SERVO_TIMER_PINS); i++) {
    if (SERVO_TIMER_PINS[i] == p)
      return true;
  }
  return false;
}

void detachServo(uint8_t p) {
  int8_t slot = servoSlotOfPin[p];
  if (slot < 0)
    return;
  servoPool[slot].detach();
  servoSlotOfPin[p] = -1;
  servosAttached--;
}

// Returns the servo on pin p, attaching a free pool slot if needed; NULL if
// every slot is in use.
Servo *servoFor(uint8_t p, int minUs, int maxUs) {
  if (servoSlotOfPin[p] >= 0)
    return &servoPool[servoSlotOfPin[p]];
  for (int8_t slot = 0; slot < SERVO_POOL; slot++) {
    if (!servoPool[slot].attached()) {
      servoPool[slot].attach(p, minUs, maxUs);
      servoSlotOfPin[p] = slot;
      servosAttached++;
      servoTimerClaimed = true;
      pinTouched[p] = false; // owned by the servo now, not a plain output
      return &servoPool[slot];
    }
  }
  return NULL;
}

// Stop everything we have ever driven. Safe to call repeatedly.
void failsafeStop() {
  for (uint8_t p = FIRST_PIN; p < NUM_PINS; p++) {
    if (pinTouched[p]) {
      // digitalWrite on AVR also switches off any PWM running on the pin
      digitalWrite(p, LOW);
    }
    if (servoSlotOfPin[p] >= 0 && servoIsContinuous[p]) {
      servoPool[servoSlotOfPin[p]].writeMicroseconds(1500); // stop continuous rotation
    }
  }
  outputsArmed = false;
}

void executeCommand(uint8_t c, uint8_t p, uint8_t v) {
  // Every valid packet (heartbeat included) refreshes the link watchdog
  lastPacketMillis = millis();

  // Heartbeat: no-op, and no LED pulse (it arrives twice a second)
  if (c == CMD_HEARTBEAT)
    return;

  if (c == CMD_STOP_ALL) {
    failsafeStop();
    return;
  }

  // Pins 0/1 are the USB serial link; others must exist on this board
  if (p < FIRST_PIN || p >= NUM_PINS) {
    replyPinError("bad pin ", p, "");
    return;
  }
  pinUsedByProgram[p] = true;

  // Activity blink on the built-in LED, unless the program uses that pin
  if (!pinUsedByProgram[LED_BUILTIN]) {
    digitalWrite(LED_BUILTIN, HIGH);
    lastPulse = millis();
  }

  if (c == CMD_PIN_MODE) {
    detachServo(p);
    if (v == 1) {
      pinMode(p, OUTPUT);
      pinTouched[p] = true; // an output we may have to force LOW
    } else if (v == 0) {
      pinMode(p, INPUT);
    } else if (v == 2) {
      pinMode(p, INPUT_PULLUP);
    }
    // A pin reconfigured as an input is no longer something we drive
    if (v == 0 || v == 2)
      pinTouched[p] = false;
  } else if (c == CMD_DIGITAL_WRITE) {
    detachServo(p);
    pinMode(p, OUTPUT);
    digitalWrite(p, v ? HIGH : LOW);
    pinTouched[p] = true;
    outputsArmed = true;
  } else if (c == CMD_ANALOG_WRITE) {
    detachServo(p);
    if (servoTimerClaimed && isServoTimerPin(p)) {
      // The Servo library runs this pin's timer; analogWrite would disturb
      // every servo and still not give PWM here.
      replyPinError("pin ", p, ": no PWM once servos are used");
      return;
    }
    if (digitalPinToTimer(p) == NOT_ON_TIMER) {
      replyPinError("pin ", p, " has no PWM");
    }
    pinMode(p, OUTPUT);
    analogWrite(p, v); // on a non-PWM pin: HIGH at >= 128, else LOW
    pinTouched[p] = true;
    outputsArmed = true;
  } else if (c == CMD_SERVO_WRITE || c == CMD_SERVO_WRITE_US) {
    bool continuous = (c == CMD_SERVO_WRITE_US);
    Servo *s = continuous ? servoFor(p, 1000, 2000) : servoFor(p, 544, 2400);
    if (s == NULL) {
      replyPinError("too many servos, pin ", p, " ignored");
      return;
    }
    if (continuous) {
      // val encodes the pulse width as (µs - 1300) / 2:
      // 0 -> 1300 µs (full reverse), 100 -> 1500 µs (stop), 200 -> 1700 µs (full forward)
      s->writeMicroseconds(1300 + ((unsigned int)v * 2));
    } else {
      s->write(v);
    }
    servoIsContinuous[p] = continuous; // continuous ones are stopped on failsafe
    outputsArmed = true;
  }
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
  for (uint8_t i = 0; i < NUM_PINS; i++) {
    servoSlotOfPin[i] = -1;
    pinTouched[i] = false;
    servoIsContinuous[i] = false;
    pinUsedByProgram[i] = false;
  }
  pinMode(LED_BUILTIN, OUTPUT);

  // Power-on sequence
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

  // Activity blink lasts 40 ms
  if (lastPulse != 0 && (millis() - lastPulse > 40)) {
    if (!pinUsedByProgram[LED_BUILTIN])
      digitalWrite(LED_BUILTIN, LOW);
    lastPulse = 0;
  }
}
