import std/deques
import std/strformat

import ./chunk
import ../slice2

type DequeBuf* = object
  len: int
  lastChunk: Chunk
  queuedRegion: Deque[Region]

template len*(buf: DequeBuf): int =
  buf.len

template queueSize*(buf: DequeBuf): int =
  buf.queuedRegion.len

template clear*(buf: var DequeBuf) =
  if buf.len > 0:
    buf.len = 0
    buf.queuedRegion.clear

iterator items*(buf: DequeBuf): lent Region =
  for region in buf.queuedRegion:
    yield region

proc `=destroy`(buf: DequeBuf) =
  var last = buf.lastChunk
  while not last.isNil:
    discard last.dequeue

  `=destroy`(buf.lastChunk)
  `=destroy`(buf.queuedRegion.addr[])

proc `=sink`(buf: var DequeBuf, b: DequeBuf) =
  `=destroy`(buf)

  buf.len = b.len
  buf.lastChunk = b.lastChunk

  `=sink`(buf.queuedRegion, b.queuedRegion)

proc `=copy`(buf: var DequeBuf, b: DequeBuf) =
  if b.len <= 0:
    return

  buf.len = b.len
  `=copy`(buf.queuedRegion, b.queuedRegion)

proc allocChunk*(buf: var DequeBuf): Chunk {.inline.} =
  result = buf.lastChunk.dequeue

  if result.isNil:
    result = newChunk(DEFAULT_CHUNK_SIZE)

iterator allocChunkMany*(buf: var DequeBuf, size: int): owned Chunk =
  var left = size

  while left > 0:
    let total = size - left
    if total >= DEFAULT_LARGE_CHUNK_SIZE and left >= DEFAULT_LARGE_CHUNK_SIZE:
      let chunk = newChunk(DEFAULT_LARGE_CHUNK_SIZE)
      dec left, DEFAULT_LARGE_CHUNK_SIZE
      yield chunk
    else:
      let chunk = buf.allocChunk()
      dec left, chunk.freeSpace
      yield chunk

proc releaseChunk*(buf: var DequeBuf, chunk: sink Chunk) {.inline.} =
  if not chunk.isFull:
    buf.lastChunk.enqueue(chunk)

iterator preprocessingEnqueueSlowCopy(
    buf: var DequeBuf, data: pointer, size: int
): Region =
  assert size > 0

  var offset = 0
  var lastChunk = Chunk(nil)

  for chunk in buf.allocChunkMany(size):
    let leftAddr = chunk.leftAddr

    let len = min(size - offset, chunk.freeSpace)
    let dstAddr = cast[pointer](cast[uint](leftAddr) + uint(chunk.len))
    let srcAddr = cast[pointer](cast[uint](data) + uint(offset))

    copyMem(dstAddr, srcAddr, len)

    inc offset, len
    lastChunk = chunk

    yield chunk.advanceWposRegion(len)

  assert lastChunk != nil

  buf.releaseChunk(move lastChunk)

proc preprocessingEnqueueOneByte(buf: var DequeBuf, data: byte): Region {.inline.} =
  var lastChunk = buf.allocChunk()

  defer:
    buf.releaseChunk(lastChunk)

  let len = lastChunk.len
  let dstAddr = cast[pointer](cast[uint](lastChunk.leftAddr) + uint(len))
  cast[ptr byte](dstAddr)[] = data

  lastChunk.advanceWposRegion(1)

proc enqueueLeftZeroCopy*(buf: var DequeBuf, data: DequeBuf) {.inline.} =
  inc buf.len, data.len

  for i in countdown(data.queueSize - 1, 0):
    buf.queuedRegion.addFirst(data.queuedRegion[i])

proc enqueueLeftZeroCopy*(buf: var DequeBuf, region: sink Region) {.inline.} =
  inc buf.len, region.len

  if buf.queueSize > 0:
    let head = buf.queuedRegion[0].addr
    if head[].chunk == region.chunk and head[].leftAddr == region.rightAddr:
      head[].extendLeft(region.len)
      return

  buf.queuedRegion.addFirst(move region)

proc enqueueLeftCopy*(buf: var DequeBuf, data: pointer, size: int) {.inline.} =
  for region in buf.preprocessingEnqueueSlowCopy(data, size):
    buf.enqueueLeftZeroCopy(region)

proc enqueueByteLeft*(buf: var DequeBuf, data: byte) {.inline.} =
  var region = buf.preprocessingEnqueueOneByte(data)
  buf.enqueueLeftZeroCopy(move region)

proc enqueueRightZeroCopy*(buf: var DequeBuf, data: DequeBuf) {.inline.} =
  inc buf.len, data.len

  for region in data.queuedRegion:
    buf.queuedRegion.addLast(region)

proc enqueueRightZeroCopy*(buf: var DequeBuf, region: sink Region) {.inline.} =
  inc buf.len, region.len

  if buf.queueSize > 0:
    let tail = buf.queuedRegion[^1].addr
    if tail[].chunk == region.chunk and tail[].rightAddr == region.leftAddr:
      tail[].extendRight(region.len)
      return

  buf.queuedRegion.addLast(move region)

proc enqueueRightCopy*(buf: var DequeBuf, data: pointer, size: int) {.inline.} =
  for region in buf.preprocessingEnqueueSlowCopy(data, size):
    buf.enqueueRightZeroCopy(region)

proc enqueueByteRight*(buf: var DequeBuf, data: byte) {.inline.} =
  var region = buf.preprocessingEnqueueOneByte(data)
  buf.enqueueRightZeroCopy(move region)

proc dequeueLeft*(buf: var DequeBuf, size: int) =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    buf.clear()
    return

  var searchPos = size

  for idx in 0 ..< buf.queueSize:
    let region = buf.queuedRegion[0].addr

    if searchPos < region[].len:
      if searchPos > 0:
        region[].discardLeft(searchPos)
      break

    dec searchPos, region[].len
    discard buf.queuedRegion.popFirst()

  dec buf.len, size

proc dequeueRight*(buf: var DequeBuf, size: int) =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    buf.clear()
    return

  var searchPos = size

  for idx in 0 ..< buf.queueSize:
    let region = buf.queuedRegion[^1].addr

    if searchPos < region[].len:
      if searchPos > 0:
        region[].discardRight(searchPos)
      break

    dec searchPos, region[].len
    discard buf.queuedRegion.popLast()

  dec buf.len, size

iterator visitLeft*(buf: DequeBuf, size: int): Slice2[byte] =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    for idx in 0 ..< buf.queueSize:
      yield buf.queuedRegion[idx].toOpenArray.slice
  else:
    var searchPos = size

    for idx in 0 ..< buf.queueSize:
      let region = buf.queuedRegion[idx].addr

      if searchPos < region[].len:
        if searchPos > 0:
          yield region[].toOpenArray.slice(0, searchPos)
        break

      dec searchPos, region[].len

      yield region[].toOpenArray.slice

iterator visitLeftAndDequeue*(buf: var DequeBuf, size: int): Slice2[byte] =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    while buf.queueSize > 0:
      let region = buf.queuedRegion.popFirst()
      dec buf.len, region.len
      yield region.toOpenArray.slice
  else:
    var searchPos = size

    for idx in 0 ..< buf.queueSize:
      let len = buf.queuedRegion[0].len

      if searchPos < len:
        if searchPos > 0:
          dec buf.len, searchPos
          var r = buf.queuedRegion[0].toOpenArray.slice(0, searchPos)
          buf.queuedRegion[0].discardLeft(searchPos)
          yield r
        break

      dec buf.len, len
      dec searchPos, len

      let region = buf.queuedRegion.popFirst()
      yield region.toOpenArray.slice

iterator visitLeftRegion*(buf: DequeBuf, size: int): Region =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    for idx in 0 ..< buf.queueSize:
      yield buf.queuedRegion[idx]
  else:
    var searchPos = size

    for idx in 0 ..< buf.queueSize:
      let region = buf.queuedRegion[idx].addr

      if searchPos < region[].len:
        if searchPos > 0:
          yield region[][0 ..< searchPos]
        break

      dec searchPos, region[].len

      yield region[]

iterator visitLeftRegionAndDequeue*(buf: var DequeBuf, size: int): Region =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    while buf.queueSize > 0:
      dec buf.len, buf.queuedRegion[0].len
      yield buf.queuedRegion.popFirst()
  else:
    var searchPos = size

    for idx in 0 ..< buf.queueSize:
      let len = buf.queuedRegion[0].len

      if searchPos < len:
        if searchPos > 0:
          dec buf.len, searchPos
          var region = buf.queuedRegion[0][0 ..< searchPos]
          buf.queuedRegion[0].discardLeft(searchPos)
          yield move region
        break

      dec buf.len, len
      dec searchPos, len

      yield buf.queuedRegion.popFirst()

proc `$`*(buf: DequeBuf): string {.inline.} =
  result = fmt"(len: {buf.len}, queueSize: {buf.queueSize}, queuedRegion: ["
  for i, region in buf.queuedRegion.pairs:
    if i != 0:
      result.add(", ")
    result.addQuoted(region)
  result.add("])")
