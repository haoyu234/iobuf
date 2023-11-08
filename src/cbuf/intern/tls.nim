import chunk

type
  ThreadTlsObj = object
    lastChunk*: Chunk

var g_threadTls* {.threadvar.}: ThreadTlsObj

proc allocTlsChunk*(): Chunk {.inline.} =
  var lastChunk {.cursor.} = g_threadTls.lastChunk

  while true:
    if lastChunk.isNil:
      result = newChunk(DEFAULT_CHUNK_SIZE)
      return

    if lastChunk.isFull:
      lastChunk = result.dequeueChunk()
      continue

    result = lastChunk
    g_threadTls.lastChunk = lastChunk.dequeueChunk()
    return

proc sharedTlsChunk*(): Chunk {.inline.} =
  var lastChunk {.cursor.} = g_threadTls.lastChunk

  while true:
    if lastChunk.isNil:
      result = newChunk(DEFAULT_CHUNK_SIZE)
      g_threadTls.lastChunk = result
      return

    if lastChunk.isFull:
      lastChunk = lastChunk.dequeueChunk()
      continue

    result = lastChunk
    return

proc releaseTlsChunk*(chunk: sink Chunk) =
  if chunk.isFull:
    return

  if not g_threadTls.lastChunk.isNil:
    chunk.enqueueChunk(g_threadTls.lastChunk)

  g_threadTls.lastChunk = chunk
