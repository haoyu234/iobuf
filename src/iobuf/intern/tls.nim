import std/exitprocs

import chunk
import instru/queue

type ThreadTlsObj = object
  registeredExit: bool
  queuedChunk: InstruQueue

var g_threadTls* {.threadvar.}: ThreadTlsObj

proc removeAllChunk() {.noconv.} =
  let head = g_threadTls.queuedChunk.addr

  while not head[].isEmpty:
    discard head[].dequeueChunk()

proc registerExitProc() =
  if g_threadTls.registeredExit:
    return

  {.gcsafe.}:
    g_threadTls.registeredExit = true
    addExitProc(removeAllChunk)

proc allocTlsChunk*(): Chunk {.inline.} =
  let head = g_threadTls.queuedChunk.addr

  registerExitProc()

  while not head[].isEmpty:
    let chunk = head[].dequeueChunk()
    if chunk.isFull:
      continue

    result = chunk
    return

  result = newChunk(DEFAULT_CHUNK_SIZE)

proc releaseTlsChunk*(chunk: sink Chunk) =
  if chunk.isFull:
    return

  registerExitProc()

  g_threadTls.queuedChunk.enqueueChunkUnsafe(chunk)
