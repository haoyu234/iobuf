import std/exitprocs

import chunk

type
  ThreadTlsObj = object
    lastChunk*: Chunk

var g_threadTls* {.threadvar.}: ThreadTlsObj

proc removeAllChunk() {.noconv.} =
  var lastChunk = move g_threadTls.lastChunk

  while not lastChunk.isNil:
    lastChunk = lastChunk.dequeueChunk()

proc registerExitProc() =
  {.gcsafe.}:
    once:
      addExitProc(removeAllChunk)

proc allocTlsChunk*(): Chunk {.inline.} =
  var lastChunk = move g_threadTls.lastChunk

  registerExitProc()

  while true:
    if lastChunk.isNil:
      result = newChunk(DEFAULT_CHUNK_SIZE)
      return

    if lastChunk.isFull:
      lastChunk = result.dequeueChunk()
      continue

    g_threadTls.lastChunk = lastChunk.dequeueChunk()
    result = move lastChunk
    return

proc sharedTlsChunk*(): Chunk {.inline.} =
  var lastChunk = g_threadTls.lastChunk

  registerExitProc()

  while true:
    if lastChunk.isNil:
      result = newChunk(DEFAULT_CHUNK_SIZE)
      g_threadTls.lastChunk = result
      return

    if lastChunk.isFull:
      lastChunk = lastChunk.dequeueChunk()
      continue

    result = move lastChunk
    return

proc releaseTlsChunk*(chunk: sink Chunk) =
  if chunk.isFull:
    return

  registerExitProc()

  if not g_threadTls.lastChunk.isNil:
    chunk.enqueueChunk(g_threadTls.lastChunk)

  g_threadTls.lastChunk = move chunk
