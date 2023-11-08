import std/unittest

import cbuf

test "readIntoBuf":
  var buf = initBuf()

  # for _ in 0 ..< 2:
  #   let n = readIntoBuf(1, buf, 24)
  #   echo "return: ", n

  # for sliceBuf in buf:
  #   let slice = sliceBuf.slice()
  #   echo slice
