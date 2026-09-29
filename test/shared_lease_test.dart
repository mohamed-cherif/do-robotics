import 'dart:async';

import 'package:do_robotics/utils/shared_lease.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake camera: counts opens/closes and lets a test hold an open "in flight".
class _FakeResource {
  int opens = 0;
  int closes = 0;
  bool isOpen = false;
  Completer<void>? gate;
  Object? failWith;

  Future<void> open() async {
    if (isOpen) return;
    opens++;
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
    isOpen = true;
  }

  Future<void> close() async {
    if (!isOpen) return;
    closes++;
    isOpen = false;
  }
}

void main() {
  late _FakeResource res;
  late SharedLease lease;

  setUp(() {
    res = _FakeResource();
    lease = SharedLease(open: res.open, close: res.close);
  });

  test('second holder shares the open resource; last release closes it', () async {
    await lease.acquire();
    await lease.acquire();
    expect(res.opens, 1);
    await lease.release();
    expect(res.isOpen, isTrue);
    await lease.release();
    expect(res.isOpen, isFalse);
    expect(res.closes, 1);
  });

  test('release while the open is still in flight closes after the open', () async {
    // The bug this guards: STOP pressed while the camera is still starting
    // used to leave the camera running for the rest of the session.
    res.gate = Completer<void>();
    final opening = lease.acquire();
    final releasing = lease.release();
    res.gate!.complete();
    await opening;
    await releasing;
    expect(res.isOpen, isFalse);
  });

  test('concurrent acquires open once', () async {
    res.gate = Completer<void>();
    final a = lease.acquire();
    final b = lease.acquire();
    res.gate!.complete();
    await Future.wait([a, b]);
    expect(res.opens, 1);
    expect(lease.users, 2);
  });

  test('a failed open keeps the count balanced for the caller to release', () async {
    res.failWith = StateError('no camera');
    await expectLater(lease.acquire(), throwsStateError);
    expect(lease.users, 1);
    res.failWith = null;
    // Another holder can still open it afterwards.
    await lease.acquire();
    expect(res.isOpen, isTrue);
    await lease.release();
    expect(res.isOpen, isTrue, reason: 'second holder still holds it');
    await lease.release();
    expect(res.isOpen, isFalse);
  });

  test('extra releases never go negative', () async {
    await lease.release();
    await lease.release();
    expect(lease.users, 0);
    await lease.acquire();
    expect(lease.users, 1);
    expect(res.isOpen, isTrue);
  });

  test('force release closes regardless of holders', () async {
    await lease.acquire();
    await lease.acquire();
    await lease.release(force: true);
    expect(lease.users, 0);
    expect(res.isOpen, isFalse);
  });
}
