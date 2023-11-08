import blockbuf

type
  ThreadTlsObj = object
    lastBuf*: BlockBuf

var g_threadTls* {.threadvar.}: ThreadTlsObj

proc getTlsBlockBuf*(occupyBuf: static[bool] = false): BlockBuf =
  var lastBuf {.cursor.} = g_threadTls.lastBuf

  while true:
    result = lastBuf
    if result.isNil:
      result = newBlockBuf()
      if not occupyBuf:
        g_threadTls.lastBuf = result
      break

    if result.isFull:
      lastBuf = result.popBuf()
      continue

    if occupyBuf:
      lastBuf = result.popBuf()

    g_threadTls.lastBuf = lastBuf
    break

proc releaseTlsBlockBuf*(blockBuf: sink BlockBuf) =
  if blockBuf.isNil or blockBuf.isFull:
    return

  if not g_threadTls.lastBuf.isNil:
    blockBuf.enqueueBuf(g_threadTls.lastBuf)

  g_threadTls.lastBuf = blockBuf
