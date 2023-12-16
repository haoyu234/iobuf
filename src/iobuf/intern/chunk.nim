import instru/queue

const DEFAULT_CHUNK_SIZE* = 8192
const DEFAULT_LARGE_CHUNK_SIZE* = DEFAULT_CHUNK_SIZE * 4

type
  ChunkObj* {.acyclic.} = object of RootObj
    len: int
    capacity: int
    storage: pointer
    queueNode: InstruQueueNode

  Chunk* = ref ChunkObj
  ChunkObj2 = object of ChunkObj
  Chunk2 = ref ChunkObj2

  Chunk3 = ref ChunkObj3
  ChunkObj3 = object of ChunkObj
    data: seq[byte]

proc `=destroy`(chunk: ChunkObj2) =
  let storage = chunk.storage
  if not storage.isNil:
    deallocShared(storage)

template initChunk*(result: Chunk, storage2: pointer, len2, capacity2: int) =
  result.len = len2
  result.capacity = capacity2
  result.storage = storage2
  result.queueNode.initEmpty()

proc newChunk*(storage2: pointer, len2, capacity2: int): Chunk {.inline.} =
  new (result)
  result.initChunk(storage2, len2, capacity2)

proc newChunk*(capacity: int): Chunk {.inline.} =
  var chunk = new(Chunk2)

  let p = allocShared(capacity)
  Chunk(chunk).initChunk(p, 0, capacity)

  chunk

proc newChunk*(data: sink seq[byte]): Chunk {.inline.} =
  var chunk = new(Chunk3)

  let len = data.len

  chunk.data = move data

  let p = chunk.data[0].addr
  Chunk(chunk).initChunk(p, len, len)

  chunk

template len*(chunk: Chunk): int =
  chunk.len

template isFull*(chunk: Chunk): bool =
  chunk.len >= chunk.capacity

template storage*(chunk: Chunk): pointer =
  chunk.storage

template leftSpace*(chunk: Chunk): int =
  int(chunk.capacity - chunk.len)

template writeAddr*(chunk: Chunk): pointer =
  cast[pointer](cast[uint](chunk.storage) + uint(chunk.len))

template leftAddr*(chunk: Chunk): pointer =
  chunk.storage

template rightAddr*(chunk: Chunk): pointer =
  cast[pointer](cast[uint](chunk.storage) + uint(chunk.capacity))

template advanceWpos*(chunk: Chunk, dataLen: int) =
  assert dataLen <= chunk.leftSpace()

  inc chunk.len, dataLen

template capacity*(chunk: Chunk): int =
  chunk.capacity

proc dequeueChunk*(queuedChunk: var InstruQueue): Chunk {.inline.} =
  if not queuedChunk.isEmpty:
    let node = queuedChunk.popFront
    result = cast[Chunk](data(node[], ChunkObj, queueNode))
    GC_unref(result)

proc dequeueChunkUnsafe*(queuedChunk: var InstruQueue): Chunk {.inline.} =
  let node = queuedChunk.popFront
  result = cast[Chunk](data(node[], ChunkObj, queueNode))
  GC_unref(result)

proc enqueueChunk*(queuedChunk: var InstruQueue, chunk: sink Chunk) {.inline.} =
  if not chunk.queueNode.isQueued:
    GC_ref(chunk)
    queuedChunk.insertFront(chunk.queueNode)

proc enqueueChunkUnsafe*(queuedChunk: var InstruQueue, chunk: sink Chunk) {.inline.} =
  GC_ref(chunk)
  queuedChunk.insertFront(chunk.queueNode)

template toOpenArray*(chunk: Chunk): openArray[byte] =
  cast[ptr UncheckedArray[byte]](chunk.storage).toOpenArray(0, chunk.len - 1)
