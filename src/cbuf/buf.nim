import intern/tls
import intern/indices
import intern/blockbuf

import slice2

const INLINE_STORAGE = true
const INITIAL_QUEUE_CAPACITY = 32

type
  Buf* = object
    len: int
    lastBuf: BlockBuf

    queueSize: int32
    when INLINE_STORAGE:
      queueCapacity: int32 = 2
    else:
      queueCapacity: int32
    queueStart: int32
    queueStorage: ptr UncheckedArray[SliceBuf]
    when INLINE_STORAGE:
      inlineStorage: array[2, SliceBuf]

template storage(buf: Buf): ptr UncheckedArray[SliceBuf] =
  when not INLINE_STORAGE:
    buf.queueStorage
  else:
    if buf.queueStorage != nil:
      buf.queueStorage
    else:
      cast[ptr UncheckedArray[SliceBuf]](buf.inlineStorage[0].addr)

template index(buf: Buf, idx: Natural): int =
  (buf.queueStart + int(idx)) and (buf.queueCapacity - 1)

template index(buf: Buf, idx: BackwardsIndex): int =
  (buf.queueStart + buf.queueSize - int(idx)) and (buf.queueCapacity - 1)

proc `=destroy`(buf: Buf) =
  var lastBuf = buf.lastBuf
  while lastBuf != nil:
    lastBuf = lastBuf.popBuf()

  let storage = buf.queueStorage
  if storage != nil:
    for idx in 0..<buf.queueSize:
      reset(storage[idx])

    freeShared(storage)

proc initBuf*(result: var Buf) {.inline.} =
  result.len = 0
  result.lastBuf = nil
  result.queueSize = 0
  result.queueStart = 0
  result.queueCapacity = 2
  result.queueStorage = nil

proc initBuf*(): Buf {.inline.} =
  result.len = 0
  result.lastBuf = nil
  result.queueSize = 0
  result.queueStart = 0
  result.queueCapacity = 2
  result.queueStorage = nil

template len*(buf: Buf): int = buf.len

template allocQueueBuf(capacity: int): ptr UncheckedArray[SliceBuf] =
  cast[ptr UncheckedArray[SliceBuf]](allocShared0(sizeof(SliceBuf) * capacity))

proc extendQueueBuf(buf: var Buf) {.inline.} =
  if buf.queueSize == buf.queueCapacity or
    (not INLINE_STORAGE and buf.queueStorage.isNil):

    let newCapacity = max(buf.queueCapacity * 2, INITIAL_QUEUE_CAPACITY)
    let queueStorage = allocQueueBuf(newCapacity)
  
    for idx in 0..<buf.queueSize:
      queueStorage[idx] = buf.storage[buf.index(idx)]

    if buf.queueStorage != nil:
      freeShared(buf.queueStorage)
    else:
      when INLINE_STORAGE:
        reset(buf.inlineStorage)

    buf.queueStart = 0
    buf.queueStorage = queueStorage
    buf.queueCapacity = newCapacity

proc internalEnqueue(buf: var Buf,
  sliceBuf: sink SliceBuf, extendBuf: static[bool]) {.inline.} =
  var append = true

  if extendBuf and buf.queueSize > 0:
    let idx = buf.index(^1)
    let dataAddr = sliceBuf.leftAddr
    let tailBuf = buf.storage[idx].addr

    if sliceBuf.blockBuf == tailBuf[].blockBuf and dataAddr == tailBuf[].rightAddr:
      tailBuf[].extendLen(sliceBuf.len)
      append = false

  if append:
    buf.extendQueueBuf()
    buf.storage[buf.index(buf.queueSize)] = move sliceBuf

    inc buf.queueSize

proc internalEnqueue(buf: var Buf,
  blockBuf2: sink BlockBuf, offset2, len2: int, extendBuf: static[
      bool]) {.inline.} =
  var append = true

  if extendBuf and offset2 > 0 and buf.queueSize > 0:
    let idx = buf.index(^1)
    let dataAddr = cast[pointer](cast[uint](blockBuf2.leftAddr) + uint(offset2))
    let tailBuf = buf.storage[idx].addr

    if blockBuf2 == tailBuf[].blockBuf and dataAddr == tailBuf[].rightAddr:
      tailBuf[].extendLen(len2)
      append = false

  if append:
    buf.extendQueueBuf()
    buf.storage[buf.index(buf.queueSize)].initSliceBuf(move blockBuf2, offset2, len2)

    inc buf.queueSize

proc allocBlockBuf*(buf: var Buf,
  occupyBuf: static[bool] = false): BlockBuf {.inline.} =
  while true:
    result = buf.lastBuf
    if result.isNil:
      return getTlsBlockBuf(occupyBuf)

    buf.lastBuf = result.popBuf()
    if not result.isFull:
      break

proc releaseBlockBuf*(buf: var Buf, blockBuf: sink BlockBuf) {.inline.} =
  if not blockBuf.isFull:
    if not buf.lastBuf.isNil:
      buf.lastBuf.enqueueBuf(move blockBuf)
    else:
      buf.lastBuf = blockBuf

proc append*(buf: var Buf,
  data: openArray[byte], extendBuf: static[bool] = false) {.inline.} =
  inc buf.len, data.len

  if extendBuf and buf.queueSize > 0:
    let idx = buf.index(^1)
    let dataAddr = data[0].addr
    let tailBuf = buf.storage[idx].addr

    if dataAddr == tailBuf[].rightAddr and dataAddr < tailBuf[].blockBuf.rightAddr:
      tailBuf[].extendLen(data.len)
      return

  var written = 0
  let size = data.len

  var lastBuf: BlockBuf = nil

  while written < size:
    lastBuf = buf.allocBlockBuf()
    let dataLen = min(lastBuf.leftSpace(), size - written)
    let oldLen = lastBuf.len

    copyMem(lastBuf.writeAddr, data[written].addr, dataLen)
    lastBuf.extendLen(dataLen)

    buf.internalEnqueue(move lastBuf, oldLen, dataLen, true)

    inc written, dataLen

  if lastBuf.isNil:
    return

  buf.releaseBlockBuf(lastBuf)

proc append*(buf: var Buf, sliceBuf: sink SliceBuf, extendBuf: static[
    bool] = false) {.inline.} =
  inc buf.len, sliceBuf.len
  buf.internalEnqueue(move sliceBuf, extendBuf)

proc append*(buf: var Buf, data: sink seq[byte]) {.inline.} =
  let dataLen = data.len
  inc buf.len, dataLen

  var blockBuf = newBlockBuf(move data)
  buf.internalEnqueue(move blockBuf, 0, dataLen, false)

proc append*(buf: var Buf, data: Buf) {.inline.} =
  for idx in 0..<data.queueSize:
    buf.internalEnqueue(data.storage[data.index(idx)], false)

proc append*(buf: var Buf, data: Slice2[byte], extendBuf: static[
    bool] = false) {.inline.} =
  buf.append(data.toOpenArray(), extendBuf)

proc `=copy`*(buf: var Buf, b: Buf) =
  if buf.addr == b.addr: return

  `=destroy`(buf)
  wasMoved(buf)

  buf.append(b)

proc `=sink`*(buf: var Buf, b: Buf) =
  `=destroy`(buf)
  wasMoved(buf)

  if b.queueStorage != nil:
    buf.len = b.len
    buf.lastBuf = b.lastBuf
    buf.queueSize = b.queueSize
    buf.queueStart = b.queueStart
    buf.queueCapacity = b.queueCapacity
    buf.queueStorage = b.queueStorage
    return

  buf.append(b)

proc whereSliceBuf(buf: Buf, where: int): (int, int) {.inline.} =
  assert where <= buf.len

  var searchPos = where
  for idx in 0..<int(buf.queueSize):
    let dataLen = buf.storage[buf.index(idx)].len

    if searchPos < dataLen:
      result = (idx, searchPos)
      break

    dec searchPos, dataLen

proc `[]`*[U, V: Ordinal](buf: Buf, x: HSlice[U, V]): Buf {.inline.} =
  let a = buf ^^ x.a
  let L = (buf ^^ x.b) - a + 1

  checkSliceOp(buf.len, a, a + L)

  result = initBuf()

  if buf.queueSize > 0:
    var (idx, len) = buf.whereSliceBuf(a)
    var sliceBuf = buf.storage[buf.index(idx)][len..^1]
    result.append(sliceBuf)

    var left = L - sliceBuf.len

    while left > 0:
      inc idx

      sliceBuf = buf.storage[buf.index(idx)]
      if left < sliceBuf.len:
        result.append(sliceBuf[0..<left])
        break

      dec left, sliceBuf.len

      result.append(sliceBuf)

iterator items*(buf: Buf): SliceBuf =
  for idx in 0..<buf.queueSize:
    yield buf.storage[buf.index(idx)]

iterator items*(buf: var Buf): var SliceBuf =
  for idx in 0..<buf.queueSize:
    yield buf.storage[buf.index(idx)]

proc toSeq*(buf: Buf): seq[byte] {.inline.} =
  result = newSeqOfCap[byte](buf.len)

  for idx in 0..<buf.queueSize:
    result.add(buf.storage[buf.index(idx)].toOpenArray())
