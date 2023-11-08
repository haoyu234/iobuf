import std/monotimes
import std/strformat

import ../src/cbuf
import ../src/cbuf/intern/chunk

const SIZE = 100000000

const data = static:
  let chunk = 1234
  var data = newSeqOfCap[byte](chunk)
  for i in 0 ..< chunk:
    data.add(byte(i mod int(high(byte))))
  data

# time dd if=/dev/zero of=/dev/null bs=100000000 count=1

template benchLoop(op, maxSize) =
  var num = 0
  while num < maxSize:
    let result = op(num)
    inc num, result

  assert num == maxSize

proc readBenchBuf() =
  var buf = initBuf()

  let file = open("/dev/zero", FileMode.fmRead)
  let fd = file.getFileHandle
  defer: file.close()

  template body(size): int =
    readv(cint(fd), buf, SIZE - size)

  benchLoop(body, SIZE)

proc writeBenchBuf(data: openArray[byte]) =
  var buf = initBuf()

  template append(size): int =
    let offset = size mod data.len
    let left = min(data.len - offset, SIZE - size)
    assert left > 0
    buf.enqueueZeroCopyRight(addr(data[offset]), left)
    left

  benchLoop(append, SIZE)

  let file = open("/dev/null", FileMode.fmWrite)
  let fd = file.getFileHandle
  defer: file.close()

  template body(size): int =
    writev(cint(fd), buf, SIZE - size)

  benchLoop(body, SIZE)

proc writeBenchBuf2(data: openArray[byte]) =
  var buf = initBuf()

  template append(size): int =
    let offset = size mod data.len
    let left = min(data.len - offset, SIZE - size)
    assert left > 0
    buf.enqueueZeroCopyRight(addr(data[offset]), left)
    left

  benchLoop(append, SIZE)

  let file = open("/dev/null", FileMode.fmWrite)
  let fd = file.getFileHandle
  defer: file.close()

  template body(size): int =
    writev(cint(fd), buf, SIZE - size)

  benchLoop(body, SIZE)

proc readBenchSeq() =
  var data = newSeq[byte]()
  var buf: array[DEFAULT_CHUNK_SIZE, byte]

  let file = open("/dev/zero", FileMode.fmRead)
  defer: file.close()

  template body(size): int =
    let r = file.readBuffer(addr(buf[0]), min(SIZE - size, buf.len))
    data.add(buf.toOpenArray(0, r - 1))
    r

  benchLoop(body, SIZE)

proc writeBenchSeq(data: openArray[byte]) =
  let file = open("/dev/null", FileMode.fmWrite)
  defer: file.close()

  template body(size): int =
    let offset = size mod data.len
    let left = min(data.len - offset, SIZE - size)
    file.writeBuffer(addr(data[offset]), left)

  benchLoop(body, SIZE)

proc writeBenchSeq2(data: openArray[byte]) =
  let file = open("/dev/null", FileMode.fmWrite)
  defer: file.close()

  var buf = newSeq[byte]()

  template append(size): int =
    let offset = size mod data.len
    let left = min(data.len - offset, SIZE - size)
    buf.add(data.toOpenArray(offset, left - 1))
    left

  benchLoop(append, SIZE)

  template body(size): int =
    file.writeBuffer(addr(buf[size]), SIZE - size)

  benchLoop(body, SIZE)

type
  BenchTp = enum
    ReadBenchSeq,
    WriteBenchSeq,
    WriteBenchSeq2,
    ReadBenchIOBuf,
    WriteBenchIOBuf,
    WriteBenchIOBuf2,

proc bench(tp: BenchTp, info: string) =
  let startTs = getMonoTime().ticks

  case tp:
  of ReadBenchSeq:
    readBenchSeq()
  of ReadBenchIOBuf:
    readBenchBuf()
  of WriteBenchSeq:
    writeBenchSeq(data)
  of WriteBenchSeq2:
    writeBenchSeq2(data)
  of WriteBenchIOBuf:
    writeBenchBuf(data)
  of WriteBenchIOBuf2:
    writeBenchBuf2(data)

  let passTs = getMonoTime().ticks - startTs

  let mb = float64(SIZE) / 1024 / 1024
  let seconds = float64(passTs) / 1e9

  echo fmt"{tp} in {seconds:.3f} seconds, {mb / seconds:.2f} MB/s info: {info}"

bench(ReadBenchSeq, "read * N")
bench(ReadBenchIOBuf, "readv")
bench(WriteBenchSeq, "write * N")
bench(WriteBenchSeq2, "append, write")
bench(WriteBenchIOBuf, "append, writev")
bench(WriteBenchIOBuf2, "writev")
