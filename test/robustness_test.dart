import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:libdbm/libdbm.dart';
import 'package:test/test.dart';

/// Opening and reading a *corrupt* DBM file must fail with a [DBMException] —
/// never leak a raw RangeError/IndexError, never attempt a monster write, and
/// never hang. A mangled bucket/next chain used to hand `_fetch` a record
/// pointer whose length overran the block header or whose key/value length ran
/// past the block, and a corrupt (CRC-less legacy) header could name a
/// memory-pool offset that extended the file to exabytes.
void main() {
  late Directory dir;
  late Uint8List valid;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('libdbm_robust');
    final path = '${dir.path}/valid.bin';
    final raf = File(path).openSync(mode: FileMode.write);
    final db = HashDBM(raf);
    for (var i = 0; i < 30; i++) {
      db.put(Uint8List.fromList('key$i'.codeUnits),
          Uint8List.fromList('value-number-$i'.codeUnits));
    }
    raf.closeSync();
    valid = File(path).readAsBytesSync();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Opens [bytes] as a DBM and traverses it. Returns the offending error if a
  /// non-DBMException leaks, else null.
  Object? openError(List<int> bytes) {
    final path = '${dir.path}/m.bin';
    File(path).writeAsBytesSync(Uint8List.fromList(bytes));
    RandomAccessFile? raf;
    try {
      raf = File(path).openSync(mode: FileMode.append);
      final db = HashDBM(raf);
      final it = db.entries();
      var guard = 0;
      while (it.moveNext()) {
        if (++guard > 200000) return StateError('runaway iteration');
      }
      db.get(Uint8List.fromList('key5'.codeUnits));
      return null;
    } on DBMException {
      return null; // clean rejection — the contract
    } catch (e) {
      return e; // a raw error leaked — a bug
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  test('mutated files reject with DBMException, never a raw error or hang', () {
    final rng = Random(1);
    for (var i = 0; i < 4000; i++) {
      final l = valid.toList();
      switch (rng.nextInt(4)) {
        case 0:
          l[rng.nextInt(l.length)] = rng.nextInt(256);
        case 1:
          for (var k = 0; k < 1 + rng.nextInt(6); k++) {
            l[rng.nextInt(l.length)] = rng.nextInt(256);
          }
        case 2:
          l.removeRange(rng.nextInt(l.length), l.length); // truncate
        default:
          final at = rng.nextInt(l.length);
          l.removeRange(at, min(l.length, at + 1 + rng.nextInt(20)));
      }
      final err = openError(l);
      expect(err, isNull,
          reason: 'mutation $i leaked ${err?.runtimeType}: $err');
    }
  });
}
