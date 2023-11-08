import unsafe
import indices

import instru/queue

const DEFAULT_BLOCK_BUF_SIZE = 8192

type
  BlockBufFlags* = enum
    CompactBuf
    StealFromSeq

  BlockBufObj = object
    capacity: int
    flags: set[BlockBufFlags]
    len: int
    queueBlockBuf: InstruQueue
    data: ptr UncheckedArray[byte]

  BlockBuf* = ref BlockBufObj

  SliceBuf* = object
    offset: int32
    len: int32
    blockBuf: BlockBuf

proc `=destroy`*(blockBuf: BlockBufObj) =
  if blockBuf.flags.contains(CompactBuf):
    return

  let data = blockBuf.data
  if blockBuf.flags.contains(StealFromSeq):
    discard restoreSeq(0, data)
    return

  freeShared(data)

proc newBlockBuf*(capacity: int = DEFAULT_BLOCK_BUF_SIZE): BlockBuf {.inline.} =
  when defined(UseCompactBuf):
    unsafeNew(result, capacity + sizeof(BlockBufObj))

    result.flags.incl(CompactBuf)

    let data = cast[ptr UncheckedArray[BlockBufObj]](result)[1].addr
    result.data = cast[ptr UncheckedArray[byte]](data)
  else:
    new(result)

    result.data = cast[ptr UncheckedArray[byte]](allocShared(capacity))

  result.len = 0
  result.capacity = capacity
  result.queueBlockBuf.initEmpty()

proc newBlockBuf*(data: sink seq[byte]): BlockBuf {.inline.} =
  result.flags.incl(StealFromSeq)
  result.len = data.len
  result.capacity = data.capacity
  result.data = stealSeq(move data)
  result.queueBlockBuf.initEmpty()

proc newBlockBuf*(data: ptr UncheckedArray[byte], flags: set[BlockBufFlags],
    len, capacity: int): BlockBuf {.inline.} =
  result.flags = flags
  result.len = len
  result.capacity = capacity
  result.data = data
  result.queueBlockBuf.initEmpty()

template initSliceBuf*(result: var SliceBuf,
  blockBuf2: BlockBuf, offset2: int, len2: int) =
  result.len = int32(len2)
  result.offset = int32(offset2)
  result.blockBuf = blockBuf2

proc popBuf*(blockBuf: BlockBuf): BlockBuf {.inline.} =
  if not blockBuf.queueBlockBuf.isEmpty:
    let node = blockBuf.queueBlockBuf.popFront
    result = cast[BlockBuf](data(node[], BlockBufObj, queueBlockBuf))
    GC_unref(result)

proc enqueueBuf*(blockBuf, nodeBuf: BlockBuf) {.inline.} =
  GC_ref(nodeBuf)
  blockBuf.queueBlockBuf.insertBack(nodeBuf.queueBlockBuf.InstruQueueNode)

template leftSpace*(blockBuf: BlockBuf): int =
  int(blockBuf.capacity - blockBuf.len)

template isFull*(blockBuf: BlockBuf): bool =
  blockBuf.len >= blockBuf.capacity

template writeAddr*(blockBuf: BlockBuf): pointer =
  blockBuf.data[blockBuf.len].addr

template leftAddr*(blockBuf: BlockBuf): pointer =
  blockBuf.data

template rightAddr*(blockBuf: BlockBuf): pointer =
  blockBuf.data[blockBuf.capacity].addr

template extendLen*(blockBuf: BlockBuf, dataLen: int) =
  inc blockBuf.len, dataLen

template capacity*(blockBuf: BlockBuf): int =
  blockBuf.capacity

template len*(blockBuf: BlockBuf): int =
  blockBuf.len

proc extendIntoSliceBuf*(blockBuf: BlockBuf, len: int): SliceBuf {.inline.} =
  result = SliceBuf(
    offset: int32(blockBuf.len),
    len: int32(len),
    blockBuf: blockBuf,
  )

  blockBuf.extendLen(len)

proc `[]`*[U, V: Ordinal](sliceBuf: SliceBuf, x: HSlice[U, V]): SliceBuf =
  let a = sliceBuf ^^ x.a
  let L = (sliceBuf ^^ x.b) - a + 1

  checkSliceOp(sliceBuf.len, a, a + L)

  result.initSliceBuf(
    sliceBuf.blockBuf,
    int32(sliceBuf.offset + a),
    int32(L),
  )

template blockBuf*(sliceBuf: SliceBuf): BlockBuf =
  sliceBuf.blockBuf

template leftAddr*(sliceBuf: SliceBuf): pointer =
  sliceBuf.blockBuf.data[sliceBuf.offset].addr

template rightAddr*(sliceBuf: SliceBuf): pointer =
  sliceBuf.blockBuf.data[sliceBuf.offset + sliceBuf.len].addr

template extendLen*(sliceBuf: var SliceBuf, dataLen: int) =
  inc sliceBuf.len, dataLen

template len*(sliceBuf: SliceBuf): int =
  int(sliceBuf.len)

template toOpenArray*(sliceBuf: SliceBuf): openArray[byte] =
  sliceBuf.blockBuf.data.toOpenArray(sliceBuf.offset, sliceBuf.offset +
      sliceBuf.len - 1)
