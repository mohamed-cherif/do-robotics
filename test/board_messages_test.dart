import 'package:do_robotics/services/connectivity/connectivity_manager.dart';
import 'package:do_robotics/services/connectivity/frame_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// Firmware text frames that end up in the execution log.
void main() {
  String? line(String text) => ConnectivityManager.logLineFor(TextFrame(text));

  test('bad pin replies name the pin', () {
    expect(line('ERR\tbad pin 6'), "Robot: pin 6 can't be used on this board");
  });

  test('other firmware errors are shown as sent', () {
    expect(line('ERR\tpin 7 has no PWM'), 'Robot: pin 7 has no PWM');
    expect(line('ERR\ttoo many servos, pin 10 ignored'), 'Robot: too many servos, pin 10 ignored');
  });

  test('the watchdog stop is explained', () {
    expect(line('WATCHDOG\tlink lost'), 'Robot stopped its outputs: no signal from the phone for 2 s');
  });

  test('routine frames stay out of the log', () {
    expect(line('ERR\tunsupported'), isNull); // Uno/Mega answer to any text command
    expect(line('HELLO\tesp32\t2.1'), isNull);
    expect(line('OK\tWIFI saved, connecting'), isNull);
    expect(line('WIFI\tCONNECTED\t192.168.1.50'), isNull);
  });
}
