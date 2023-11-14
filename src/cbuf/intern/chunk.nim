import alloc
import deprecated

import instru/queue

const DEFAULT_CHUNK_SIZE* = 8192
const DEFAULT_LARGE_CHUNK_SIZE* = DEFAULT_CHUNK_SIZE * 4

type
  ChunkObj* = object of RootObj
    len: int
    capacity: int
    storage: pointer
    chunkQueue: InstruQueue

  Chunk* = ref ChunkObj
  ChunkObj2 = object of ChunkObj
  Chunk2 = ref ChunkObj2

  ChunkObj3 = object of ChunkObj
    data: seq[byte]
  Chunk3 = ref ChunkObj3

proc `=destroy`(chunk: var ChunkObj2) {.`fix=destroy(var T)`.} =
  let storage = chunk.storage
  if not storage.isNil:
    c_free(storage)

template initChunk*(result: Chunk,
  storage2: pointer, len2, capacity2: int) =

  result.len = len2
  result.capacity = capacity2
  result.storage = storage2
  result.chunkQueue.initEmpty()

proc newChunk*(storage2: pointer, len2, capacity2: int): Chunk {.inline.} =

  new (result)
  result.initChunk(storage2, len2, capacity2)

proc newChunk*(capacity: int): Chunk {.inline.} =
  var chunk = new(Chunk2)

  let p = c_malloc(csize_t(capacity))
  initChunk(Chunk(chunk), p, 0, capacity)

  chunk

proc newChunk*(data: sink seq[byte]): Chunk {.inline.} =
  var chunk = new(Chunk3)

  let len = data.len
  let p = data[0].getAddr

  chunk.data = move data
  initChunk(Chunk(chunk), p, len, len)

  chunk

template len*(chunk: Chunk): int =
  chunk.len

template isFull*(chunk: Chunk): bool =
  chunk.len >= chunk.capacity

template leftSpace*(chunk: Chunk): int =
  int(chunk.capacity - chunk.len)

template writeAddr*(chunk: Chunk): pointer =
  cast[pointer](cast[uint](chunk.storage) + uint(chunk.len))

template leftAddr*(chunk: Chunk): pointer =
  chunk.storage

template rightAddr*(chunk: Chunk): pointer =
  cast[pointer](cast[uint](chunk.storage) + uint(chunk.capacity))

template extendLen*(chunk: Chunk, dataLen: int) =
  assert dataLen <= chunk.leftSpace()

  inc chunk.len, dataLen

template capacity*(chunk: Chunk): int =
  chunk.capacity

proc dequeueChunk*(chunk: Chunk): Chunk {.inline.} =
  if not chunk.chunkQueue.isEmpty:
    let node = chunk.chunkQueue.popFront
    result = cast[Chunk](data(node[], ChunkObj, chunkQueue))
    GC_unref(result)

proc enqueueChunk*(chunk, nodeBuf: sink Chunk) {.inline.} =
  if nodeBuf.chunkQueue.isEmpty:
    GC_ref(nodeBuf)
    chunk.chunkQueue.insertBack(nodeBuf.chunkQueue.InstruQueueNode)

template toOpenArray*(chunk: Chunk): openArray[byte] =
  cast[ptr UncheckedArray[byte]](chunk.storage).toOpenArray(0, chunk.len - 1)
