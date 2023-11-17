import intern/iobuf
import intern/deprecated

import iobuf

template readImpl[T](s: var IOBuf, result: var T) =
  assert s.len >= sizeof(T)

  when sizeof(T) == 1:
    let b = InternIOBuf(s).leftByte(dequeue = true)

    when T is bool:
      result = b != byte(0)
    else:
      result = cast[T](b)
  else:
    if s.readLeftCopy(result.getAddr, sizeof(T)) != sizeof(T):
      assert false

template peekImpl[T](s: IOBuf, result: var T) =
  assert s.len >= sizeof(T)

  when sizeof(T) == 1:
    let b = InternIOBuf(s).leftByte(dequeue = false)

    when T is bool:
      result = b != byte(0)
    else:
      result = cast[T](b)
  else:
    if s.peekLeftCopy(result.getAddr, sizeof(T)) != sizeof(T):
      assert false

proc readChar*(s: var IOBuf): char {.inline.} =
  s.readImpl(result)

proc peekChar*(s: IOBuf): char {.inline.} =
  s.peekImpl(result)

proc readBool*(s: var IOBuf): bool {.inline.} =
  s.readImpl(result)

proc peekBool*(s: IOBuf): bool {.inline.} =
  s.peekImpl(result)

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
