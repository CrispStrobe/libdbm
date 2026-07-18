import 'dart:io';
import 'dart:typed_data';

import 'package:libdbm/libdbm.dart';
import 'package:test/test.dart';

/// The bucket-table page pointer (in the hash record-pool header) and the
/// free-list page pointer (in the memory-pool header) are both read straight
/// from disk and neither is covered by the 256-byte header CRC. A corrupt page
/// pointer used to reach [PointerBlock] unchecked:
///
///  * a page length below one full pointer (1..15 bytes) produced a *zero*
///    bucket count, so the first `hash(key) % bucketCount` in a lookup threw a
///    raw `IntegerDivisionByZeroException`;
///  * a page length running past EOF made `readInto` throw a raw
///    `FileSystemException` (EINVAL) and could allocate gigabytes.
///
/// Coverage-guided fuzzing (covfuzz) found both. A malformed page pointer must
/// now be rejected with a [DBMException], never a raw error.
void main() {
  late Directory dir;
  late Uint8List valid;
  late int memPoolOffset;

  // Header field layout (see HashHeader): magic(8) version(4) buckets(4)
  // records(8) bytes(8) modified(8) -> memPoolOffset(uint64) at byte 40.
  const memPoolOffsetField = 40;
  // MemoryPoolHeader / HashRecordPoolHeader layout: magic(8) then page
  // pointer = start(uint64) + length(uint64). Both headers are 128 bytes.
  const headerSize = 128;
  const pageStartField = 8;
  const pageLengthField = 16;
  const pointerWidth = 16; // Pointer.OFFSET_WIDTH + LENGTH_WIDTH

  setUp(() {
    dir = Directory.systemTemp.createTempSync('libdbm_pageguard');
    final path = '${dir.path}/valid.bin';
    final raf = File(path).openSync(mode: FileMode.write);
    final db = HashDBM(raf, buckets: 17);
    for (var i = 0; i < 12; i++) {
      db.put(Uint8List.fromList('key$i'.codeUnits),
          Uint8List.fromList('value-number-$i'.codeUnits));
    }
    db.close();
    valid = File(path).readAsBytesSync();
    memPoolOffset = ByteData.view(valid.buffer).getUint64(memPoolOffsetField);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Opens [bytes] as a DBM, traverses every record, and probes a couple of
  /// keys. Returns the thrown object, or null if nothing was thrown.
  Object? open(Uint8List bytes) {
    final path = '${dir.path}/m.bin';
    File(path).writeAsBytesSync(bytes);
    RandomAccessFile? raf;
    try {
      raf = File(path).openSync(mode: FileMode.append);
      final db = HashDBM(raf);
      final it = db.entries();
      var guard = 0;
      while (it.moveNext()) {
        final _ = it.current;
        if (++guard > 200000) break;
      }
      db.get(Uint8List.fromList('key5'.codeUnits));
      db.get(Uint8List.fromList('nope'.codeUnits));
      return null;
    } catch (e) {
      return e;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  test('bucket-table page shorter than one pointer rejects with DBMException',
      () {
    final bad = Uint8List.fromList(valid);
    // The record-pool header sits immediately after the memory-pool header.
    final recordPoolHeader = memPoolOffset + headerSize;
    // Shrink the bucket-table page to below one pointer -> zero bucket count.
    ByteData.view(bad.buffer)
        .setUint64(recordPoolHeader + pageLengthField, pointerWidth - 1);

    final e = open(bad);
    expect(e, isA<DBMException>(),
        reason: 'a sub-pointer bucket page must reject cleanly, got: $e');
    expect(e, isNot(isA<RangeError>()));
    expect(e, isNot(isA<StateError>()));
    // The original raw crash here was IntegerDivisionByZeroException on
    // `% count`; isA<DBMException> above already excludes it.
  });

  test('memory-pool page running past EOF rejects with DBMException', () {
    final bad = Uint8List.fromList(valid);
    final view = ByteData.view(bad.buffer);
    // Make the free-list page non-empty and name a length far past EOF.
    view.setUint64(memPoolOffset + pageStartField, memPoolOffset);
    view.setUint64(memPoolOffset + pageLengthField, valid.length * 1000);

    final e = open(bad);
    expect(e, isA<DBMException>(),
        reason: 'a past-EOF memory-pool page must reject cleanly, got: $e');
    expect(e, isNot(isA<RangeError>()));
    expect(e, isNot(isA<StateError>()));
    expect(e is FileSystemException, isFalse);
  });
}
