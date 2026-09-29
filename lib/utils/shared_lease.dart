import 'dart:async';

/// Reference-counted access to a resource that is expensive to open and must
/// be opened at most once (the camera). Open and close run one at a time, in
/// call order, so a release that arrives while an open is still in progress is
/// applied after that open finishes instead of racing it.
///
/// Contract: every [acquire] — including one whose future completes with an
/// error — must be balanced by exactly one [release]. [open] and [close] must
/// be idempotent: [open] may be called while already open, and [close] while
/// already closed or after a failed [open].
class SharedLease {
  SharedLease({required this.open, required this.close});

  final Future<void> Function() open;
  final Future<void> Function() close;

  int _users = 0;
  Future<void> _tail = Future<void>.value();

  /// Current number of holders.
  int get users => _users;

  /// Registers a holder and opens the resource if needed. Completes when the
  /// resource is open (or with the error from [open]).
  Future<void> acquire() {
    _users++;
    return _serialize(() async {
      // Every holder released before we got our turn: nothing to open.
      if (_users == 0) return;
      await open();
    });
  }

  /// Drops one holder (all of them with [force]) and closes the resource once
  /// nobody holds it.
  Future<void> release({bool force = false}) {
    _users = force ? 0 : (_users > 0 ? _users - 1 : 0);
    return _serialize(() async {
      if (_users > 0) return;
      await close();
    });
  }

  Future<void> _serialize(Future<void> Function() op) {
    final result = _tail.then((_) => op());
    // Keep the chain alive after a failure; the caller still sees the error.
    _tail = result.catchError((Object _) {});
    return result;
  }
}
