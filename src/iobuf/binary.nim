import ./iobuf

import ./intern/iobuf

template readImpl[T](s: var IOBuf, result: var T) =
  assert s.len >= sizeof(T)

  s.readCopyInto(result.addr, sizeof(T))

template peekImpl[T](s: IOBuf, result: var T) =
  assert s.len >= sizeof(T)

  s.peekCopyInto(result.addr, sizeof(T))

template writeImpl[T](s: var IOBuf, data: T) =
  s.writeCopy(data.addr, sizeof(T))

proc readChar*(s: var IOBuf): char {.inline.} =
  s.readImpl(result)

proc peekChar*(s: IOBuf): char {.inline.} =
  s.peekImpl(result)

proc readBool*(s: var IOBuf): bool {.inline.} =
  var t: byte
  s.readImpl(t)

  result = t != 0

proc peekBool*(s: IOBuf): bool {.inline.} =
  var t: byte
  s.peekImpl(t)

  result = t != 0

proc readInt8*(s: var IOBuf): int8 {.inline.} =
  s.readImpl(result)

proc peekInt8*(s: IOBuf): int8 {.inline.} =
  s.peekImpl(result)

proc readInt16*(s: var IOBuf): int16 {.inline.} =
  s.readImpl(result)

proc peekInt16*(s: IOBuf): int16 {.inline.} =
  s.peekImpl(result)

proc readInt32*(s: var IOBuf): int32 {.inline.} =
  s.readImpl(result)

proc peekInt32*(s: IOBuf): int32 {.inline.} =
  s.peekImpl(result)

proc readInt64*(s: var IOBuf): int64 {.inline.} =
  s.readImpl(result)

proc peekInt64*(s: IOBuf): int64 {.inline.} =
  s.peekImpl(result)

proc readUint8*(s: var IOBuf): uint8 {.inline.} =
  s.readImpl(result)

proc peekUint8*(s: IOBuf): uint8 {.inline.} =
  s.peekImpl(result)

proc readUint16*(s: var IOBuf): uint16 {.inline.} =
  s.readImpl(result)

proc peekUint16*(s: IOBuf): uint16 {.inline.} =
  s.peekImpl(result)

proc readUint32*(s: var IOBuf): uint32 {.inline.} =
  s.readImpl(result)

proc peekUint32*(s: IOBuf): uint32 {.inline.} =
  s.peekImpl(result)

proc readUint64*(s: var IOBuf): uint64 {.inline.} =
  s.readImpl(result)

proc peekUint64*(s: IOBuf): uint64 {.inline.} =
  s.peekImpl(result)

proc writeChar*(s: var IOBuf, data: char) {.inline.} =
  s.writeImpl(data)

proc writeBool*(s: var IOBuf, data: bool) {.inline.} =
  let t = byte(ord(data))
  s.writeImpl(t)

proc writeInt8*(s: var IOBuf, data: int8) {.inline.} =
  s.writeImpl(data)

proc writeInt16*(s: var IOBuf, data: int16) {.inline.} =
  s.writeImpl(data)

proc writeInt32*(s: var IOBuf, data: int32) {.inline.} =
  s.writeImpl(data)

proc writeInt64*(s: var IOBuf, data: int64) {.inline.} =
  s.writeImpl(data)

proc writeUint8*(s: var IOBuf, data: uint8) {.inline.} =
  s.writeImpl(data)

proc writeUint16*(s: var IOBuf, data: uint16) {.inline.} =
  s.writeImpl(data)

proc writeUint32*(s: var IOBuf, data: uint32) {.inline.} =
  s.writeImpl(data)

proc writeUint64*(s: var IOBuf, data: uint64) {.inline.} =
  s.writeImpl(data)
