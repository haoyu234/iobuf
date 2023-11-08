import std/importutils

proc stealSeq*[T](s: sink seq[T]): ptr UncheckedArray[T] =
  privateAccess(NimSeqV2[T])

  var xu = cast[ptr NimSeqV2[T]](addr s)

  privateAccess(typeof(xu.p[]))

  let d = xu.p[].data.addr

  xu.p = nil
  xu.len = 0

  return d

proc restoreSeq*[T](len: int, p: ptr UncheckedArray[T]): owned(seq[T]) =
  privateAccess(NimSeqV2[T])

  var xu = cast[ptr NimSeqV2[T]](addr result)

  privateAccess(typeof(xu.p[]))

  let p = cast[typeof(xu.p)](cast[uint](p) - cast[uint](sizeof(typeof(xu.p[].cap))))

  xu.p = p
  xu.len = len
