template `^^`*(s, i: untyped): untyped =
  (when i is BackwardsIndex: s.len - int(i) else: int(i))

template checkSliceOp*(len, l, r: untyped) =
  let
    l2 = l
    r2 = r
    len2 = len

  if l2 > len2:
    raise newException(IndexDefect, formatErrorIndexBound(l2, len2))

  if r2 > len2:
    raise newException(IndexDefect, formatErrorIndexBound(r2, len2))
