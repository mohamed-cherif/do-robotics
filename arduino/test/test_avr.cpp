// Host tests for the Uno and Mega sketches. Build with -DBOARD_UNO or
// -DBOARD_MEGA (see run_tests.sh). The sketch is compiled unchanged.
#include "Arduino.h"
#include "testlib.h"

#if defined(BOARD_UNO)
#include "../receiver_uno/receiver_uno.ino"
static const char *kSuite = "uno";
uint8_t digitalPinToTimer(uint8_t p) {
  return (p == 3 || p == 5 || p == 6 || p == 9 || p == 10 || p == 11) ? 1 : NOT_ON_TIMER;
}
static const uint8_t kServoTimerPin = 9;
static const uint8_t kNonPwmPin = 7;
static const uint8_t kLastPin = 19;       // A5
static const uint8_t kFirstMissingPin = 20;
#elif defined(BOARD_MEGA)
#include "../receiver_mega/receiver_mega.ino"
static const char *kSuite = "mega";
uint8_t digitalPinToTimer(uint8_t p) {
  return ((p >= 2 && p <= 13) || (p >= 44 && p <= 46)) ? 1 : NOT_ON_TIMER;
}
static const uint8_t kServoTimerPin = 45;
static const uint8_t kNonPwmPin = 22;
static const uint8_t kLastPin = 69;       // A15
static const uint8_t kFirstMissingPin = 70;
#else
#error "define BOARD_UNO or BOARD_MEGA"
#endif

static void send(const std::vector<uint8_t> &frame) {
  for (uint8_t b : frame) processByte(b);
}
static std::vector<std::string> replies() { return textFramesIn(Serial.out); }
static void advance(unsigned long ms) {
  sim::now += ms;
  loop();
}

static void resetAll() {
  sim::reset();
  Serial = SerialPort();
  for (auto &s : servoPool) s.detach();
  state = WAIT_HEADER;
  servosAttached = 0;
  servoTimerClaimed = false;
  outputsArmed = false;
  lastPacketMillis = 0;
  lastErrMillis = 0;
  lastPulse = 0;
  sim::now = 10000; // well past boot
  setup();
  Serial.out.clear();
}

TEST(digital_write_drives_the_pin) {
  send(controlFrame(0x01, 12, 1));
  CHECK(sim::pins[12].mode == OUTPUT);
  CHECK(sim::pins[12].level == 1);
}

TEST(pin_13_led_is_not_hijacked_by_the_activity_blink) {
  // Before v1.5 every command flashed pin 13 and forced it LOW 40 ms later.
  send(controlFrame(0x01, 13, 1));
  advance(100);
  send(controlFrame(0x00, 0, 0)); // heartbeat
  advance(100);
  CHECK(sim::pins[13].level == 1);
  send(controlFrame(0x01, 13, 0));
  send(controlFrame(0x01, 12, 1)); // commands to other pins must not light it
  CHECK(sim::pins[13].level == 0);
  send(controlFrame(0x01, 13, 1));
  send(controlFrame(0x01, 12, 0)); // ... nor switch it off
  advance(100);
  CHECK(sim::pins[13].level == 1);
}

TEST(activity_blink_still_works_while_pin_13_is_unused) {
  send(controlFrame(0x01, 12, 1));
  CHECK(sim::pins[13].level == 1);
  advance(50);
  CHECK(sim::pins[13].level == 0);
}

TEST(serial_pins_and_missing_pins_are_rejected_with_err) {
  send(controlFrame(0x01, 1, 1));
  CHECK(sim::pins[1].writes == 0);
  CHECK(contains(replies(), "ERR\tbad pin 1"));
  sim::now += 1100;
  send(controlFrame(0x01, kFirstMissingPin, 1));
  CHECK(contains(replies(), "ERR\tbad pin " + std::to_string(kFirstMissingPin)));
}

TEST(err_replies_are_rate_limited) {
  send(controlFrame(0x01, 1, 1));
  send(controlFrame(0x01, 1, 1));
  send(controlFrame(0x01, 1, 1));
  CHECK(replies().size() == 1);
}

TEST(analog_pins_work_as_digital_outputs) {
  send(controlFrame(0x01, kLastPin, 1));
  CHECK(sim::pins[kLastPin].level == 1);
  CHECK(replies().empty());
}

TEST(servos_work_on_every_pin_including_12_and_13) {
  // The old Servo-per-pin array used up the library's 12 slots, so pins
  // 12 and 13 (Uno) never got a servo.
  send(controlFrame(0x04, 12, 45));
  send(controlFrame(0x04, 13, 135));
  bool found12 = false, found13 = false;
  for (auto &s : servoPool) {
    if (s.isAttached && s.pin == 12 && s.angle == 45) found12 = true;
    if (s.isAttached && s.pin == 13 && s.angle == 135) found13 = true;
  }
  CHECK(found12);
  CHECK(found13);
}

TEST(more_servos_than_the_pool_are_refused) {
  for (uint8_t p = 2; p < 2 + SERVO_POOL; p++) send(controlFrame(0x04, p, 90));
  CHECK(servosAttached == SERVO_POOL);
  sim::now += 1100;
  send(controlFrame(0x04, 2 + SERVO_POOL, 90));
  CHECK(servosAttached == SERVO_POOL);
  CHECK(replies().size() == 1);
}

TEST(detaching_frees_a_servo_slot) {
  send(controlFrame(0x04, 12, 90));
  CHECK(servosAttached == 1);
  send(controlFrame(0x01, 12, 0)); // same pin used as a digital output
  CHECK(servosAttached == 0);
  CHECK(sim::pins[12].level == 0);
}

TEST(pwm_on_servo_timer_pins_is_refused_once_a_servo_was_used) {
  send(controlFrame(0x02, kServoTimerPin, 200));
  CHECK(sim::pins[kServoTimerPin].pwm == 200); // fine before any servo
  send(controlFrame(0x04, 12, 90));
  send(controlFrame(0x01, 12, 0)); // detached again: the timer stays taken
  sim::now += 1100;
  send(controlFrame(0x02, kServoTimerPin, 100));
  CHECK(sim::pins[kServoTimerPin].pwm == 200); // not changed
  CHECK(!replies().empty());
}

TEST(pwm_on_a_pin_without_pwm_warns_but_keeps_old_behaviour) {
  send(controlFrame(0x02, kNonPwmPin, 200));
  CHECK(sim::pins[kNonPwmPin].level == 1);
  CHECK(contains(replies(), "ERR\tpin " + std::to_string(kNonPwmPin) + " has no PWM"));
}

TEST(watchdog_stops_outputs_after_two_seconds_of_silence) {
  send(controlFrame(0x01, 12, 1));
  send(controlFrame(0x03, 11, 1)); // PIN_MODE OUTPUT is included now
  sim::pins[11].level = 1;         // e.g. driven HIGH by a pull-up before
  advance(1500);
  CHECK(sim::pins[12].level == 1);
  advance(600);
  CHECK(sim::pins[12].level == 0);
  CHECK(sim::pins[11].level == 0);
  CHECK(contains(replies(), "WATCHDOG\tlink lost"));
}

TEST(heartbeats_keep_the_watchdog_quiet) {
  send(controlFrame(0x01, 12, 1));
  for (int i = 0; i < 10; i++) {
    advance(500);
    send(controlFrame(0x00, 0, 0));
  }
  CHECK(sim::pins[12].level == 1);
  CHECK(!contains(replies(), "WATCHDOG\tlink lost"));
}

TEST(stop_all_stops_continuous_servos_and_outputs) {
  send(controlFrame(0x05, 6, 200)); // continuous servo full forward
  send(controlFrame(0x01, 12, 1));
  send(controlFrame(0x06, 0, 0));
  CHECK(sim::pins[12].level == 0);
  int us = -1;
  for (auto &s : servoPool)
    if (s.isAttached && s.pin == 6) us = s.us;
  CHECK(us == 1500);
}

TEST(bad_checksums_are_ignored_and_text_is_unsupported) {
  send({0xAA, 0x01, 12, 1, 0x00}); // wrong checksum
  CHECK(sim::pins[12].writes == 0);
  send(textFrame("STATUS"));
  CHECK(contains(replies(), "ERR\tunsupported"));
}

int main() { return runAllTests(kSuite, resetAll); }
