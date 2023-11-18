import std/math
import std/typetraits

import tls
import chunk
import region
import deprecated

const USE_STD_DEQUE = false

when USE_STD_DEQUE:
  import std/deques
else:
  import deque

type
  InternIOBuf* = object
    len: int
    lastChunk: Chunk
    regionQueue: Deque[Region]

  LocatePos = object
    idx: int
    left: int
    right: int

  InternPos = object
    idx: int
    offset: int

template len*(buf: InternIOBuf): int = buf.len
template queueSize*(buf: InternIOBuf): int = buf.regionQueue.len

template clear*(buf: var InternIOBuf) =
  if buf.len > 0:
    buf.len = 0
    buf.regionQueue.clear

iterator items*(buf: InternIOBuf): lent Region =
  for region in buf.regionQueue:
    yield region

proc initIOBuf*(result: var InternIOBuf) {.inline.} =
  result.len = 0
  result.lastChunk = nil

proc `=destroy`(buf: var InternIOBuf) {.`fix=destroy(var T)`.} =
  var lastChunk = buf.lastChunk
  while lastChunk != nil:
    lastChunk = lastChunk.dequeueChunk()

  `=destroy`(buf.lastChunk)
  `=destroy`(buf.regionQueue.getAddr[])

proc allocChunk*(buf: var InternIOBuf): Chunk {.inline.} =
  while true:
    result = move buf.lastChunk
    if result.isNil:
      return allocTlsChunk()

    buf.lastChunk = result.dequeueChunk()
    if not result.isFull:
      break

iterator allocChunk*(buf: var InternIOBuf, size: int): owned Chunk =
  var left = size

  while left > 0:
    let total = size - left
    if total >= DEFAULT_LARGE_CHUNK_SIZE and left >= DEFAULT_LARGE_CHUNK_SIZE:
      let chunk = newChunk(DEFAULT_LARGE_CHUNK_SIZE)
      dec left, DEFAULT_LARGE_CHUNK_SIZE
      yield chunk
    else:
      let chunk = buf.allocChunk()
      dec left, chunk.leftSpace
      yield chunk

proc releaseChunk*(buf: var InternIOBuf, chunk: sink Chunk) {.inline.} =
  if not chunk.isFull:
    if not buf.lastChunk.isNil:
      buf.lastChunk.enqueueChunk(move chunk)
    else:
      buf.lastChunk = move chunk

template enqueueSlowCopy(buf: var InternIOBuf, data: pointer,
    size: int, enqueueProc: untyped) =

  var offset = 0
  var lastChunk = Chunk(nil)

  for chunk in buf.allocChunk(size):
    let leftAddr = chunk.leftAddr
    let oldOffset = chunk.len

    let len = min(size - offset, chunk.leftSpace)
    let dstAddr = cast[pointer](cast[uint](leftAddr) + uint(oldOffset))
    let srcAddr = cast[pointer](cast[uint](data) + uint(offset))

    copyMem(dstAddr, srcAddr, len)

    inc offset, len
    lastChunk = chunk

    chunk.extendLen(len)

    var region = initRegion(chunk, oldOffset, len)
    enqueueProc(region)

  assert lastChunk != nil

  buf.releaseChunk(move lastChunk)

proc enqueueLeftZeroCopy*(buf: var InternIOBuf, other: InternIOBuf) {.inline.} =
  inc buf.len, other.len

  for i in countdown(other.queueSize - 1, 0):
    buf.regionQueue.addFirst(other.regionQueue[i])

proc enqueueLeftZeroCopy*(buf: var InternIOBuf,
    region: sink Region) {.inline.} =
  inc buf.len, region.len

  if buf.queueSize > 0:
    let head = buf.regionQueue[0].getAddr
    if head[].chunk == region.chunk and
      head[].leftAddr == region.rightAddr:
      head[].extendLeft(region.len)
      return

  buf.regionQueue.addFirst(move region)

proc enqueueLeftCopy*(buf: var InternIOBuf, data: pointer,
    size: int) {.inline.} =
  template enqueueLeft(region: sink Region) =
    buf.enqueueLeftZeroCopy(move region)

  buf.enqueueSlowCopy(data, size, enqueueLeft)

proc enqueueRightZeroCopy*(buf: var InternIOBuf,
    other: InternIOBuf) {.inline.} =
  inc buf.len, other.len

  for region in other.regionQueue:
    buf.regionQueue.addLast(region)

proc enqueueRightZeroCopy*(buf: var InternIOBuf,
    region: sink Region) {.inline.} =
  inc buf.len, region.len

  if buf.queueSize > 0:
    let tail = buf.regionQueue[^1].getAddr
    if tail[].chunk == region.chunk and
      tail[].rightAddr == region.leftAddr:
      tail[].extendRight(region.len)
      return

  buf.regionQueue.addLast(move region)

proc enqueueRightCopy*(buf: var InternIOBuf, data: pointer,
    size: int) {.inline.} =
  template enqueueRight(region: sink Region) =
    buf.enqueueRightZeroCopy(move region)

  buf.enqueueSlowCopy(data, size, enqueueRight)

proc dequeueLeftAdjust*(buf: var InternIOBuf,
  idx, offset, size: int) {.inline.} =

  assert size <= buf.len

  if offset > 0:
    buf.regionQueue[idx].discardLeft(offset)

  for idx2 in 0..<idx:
    discard buf.regionQueue.popFirst()

  dec buf.len, size

proc dequeueRightAdjust*(buf: var InternIOBuf,
  idx, offset, size: int) {.inline.} =

  assert size <= buf.len

  if offset > 0:
    buf.regionQueue[idx].discardRight(offset)

  for idx2 in (idx + 1) ..< buf.queueSize:
    discard buf.regionQueue.popLast()

  dec buf.len, size

proc locate(buf: InternIOBuf,
  offset: int, reverseSearch: static[bool] = false): LocatePos {.inline.} =

  assert offset < buf.len

  var searchPos = offset
  let upperBound = buf.queueSize - 1

  for idx in 0 .. upperBound:
    when reverseSearch:
      let newIdx = upperBound - idx
    else:
      let newIdx = idx

    let dataLen = buf.regionQueue[newIdx].len

    if searchPos < dataLen:
      when reverseSearch:
        result.idx = newIdx
        result.left = dataLen - searchPos
        result.right = searchPos
      else:
        result.idx = newIdx
        result.left = searchPos
        result.right = dataLen - searchPos
      return

    dec searchPos, dataLen

  assert false

proc dequeueLeft*(buf: var InternIOBuf, size: int) {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  if size < buf.len:
    let locatePos = buf.locate(size)
    buf.dequeueLeftAdjust(locatePos.idx, locatePos.left, size)
    return

  buf.clear()

proc dequeueRight*(buf: var InternIOBuf, size: int) {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  if size < buf.len:
    let locatePos = buf.locate(size, reverseSearch = true)
    buf.dequeueRightAdjust(locatePos.idx, locatePos.right, size)
    return

  buf.clear()

template consumeRange*(buf: InternIOBuf, start, stop: InternPos,
    consumeBuf: untyped) =
  block consumeRangeScope:
    var idx {.inject.} = start.idx

    if idx == stop.idx:
      var it {.inject.} =
        buf.regionQueue[idx][start.offset ..< stop.offset]
      consumeBuf

      break consumeRangeScope

    if start.offset > 0:
      var it {.inject.} =
        buf.regionQueue[idx][start.offset .. ^1]
      consumeBuf

      inc idx

    while idx < stop.idx:
      template it: untyped {.inject.} =
        buf.regionQueue[idx]
      consumeBuf

      inc idx

    if stop.offset > 0:
      var it {.inject.} =
        buf.regionQueue[idx][0 ..< stop.offset]
      consumeBuf

template consumeLeft*(buf, size, dequeueLeft, consumeBuf) =
  block consumeLeftScope:
    if size >= buf.len:
      for idx in 0 ..< buf.queueSize:
        template it: untyped {.inject.} =
          buf.regionQueue[idx]

        consumeBuf

      when dequeueLeft:
        buf.clear()

      break consumeLeftScope

    let locatePos = buf.locate(size)
    let leftPos = InternPos(idx: 0, offset: 0)
    let rightPos = InternPos(idx: locatePos.idx, offset: locatePos.left)

    consumeRange(buf, leftPos, rightPos):
      consumeBuf

    when dequeueLeft:
      buf.dequeueLeftAdjust(locatePos.idx, locatePos.left, size)

template consumeRight*(buf, size, dequeueRight, consumeBuf) =
  block consumeRightScope:
    if size >= buf.len:
      for idx in 0 ..< buf.queueSize:
        template it: untyped {.inject.} =
          buf.regionQueue[idx]

        consumeBuf

      when dequeueRight:
        buf.clear()

      break consumeRightScope

    let locatePos = buf.locate(size, reverseSearch = true)
    let leftPos = InternPos(idx: locatePos.idx, offset: locatePos.left)
    let rightPos = InternPos(idx: buf.queueSize - 1, offset: buf.regionQueue[^1].len)

    consumeRange(buf, leftPos, rightPos):
      consumeBuf

    when dequeueRight:
      buf.dequeueRightAdjust(locatePos.idx, locatePos.right, size)
