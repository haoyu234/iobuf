import std/monotimes
import std/strformat

import ../src/iobuf/iobuf
import ../src/iobuf/io
import ../src/iobuf/intern/chunk

const SIZE = 100000000

const data = static:
  let chunk = 1234
  var data = newSeqOfCap[byte](chunk)
  for i in 0 ..< chunk:
    data.add(byte(i mod int(high(byte))))
  data

var preConcatData: seq[byte]

# time dd if=/dev/zero of=/dev/null bs=100000000 count=1

template benchLoop(op, maxSize) =
  var num = 0
  while num < maxSize:
    let result = op(num)
    inc num, result

  assert num == maxSize

proc readIntoIOBuf() =
  var buf: IOBuf

  let file = open("/dev/zero", FileMode.fmRead)
  let fd = file.getFileHandle
  defer:
    file.close()

  template body(size): int =
    readIntoIOBuf(cint(fd), buf, SIZE - size)

  benchLoop(body, SIZE)

proc writeIOBuf() =
  var buf: IOBuf

  template appendZeroCopy(size): int =
    let offset = size mod data.len
    let left = min(data.len - offset, SIZE - size)
    assert left > 0
    buf.writeZeroCopy(data[offset].addr, left)
    left

  benchLoop(appendZeroCopy, SIZE)

  let file = open("/dev/null", FileMode.fmWrite)
  let fd = file.getFileHandle
  defer:
    file.close()

  template body(size): int =
    writeIOBuf(cint(fd), buf, SIZE - size)

  benchLoop(body, SIZE)

proc readIntoStackBuf() =
  var data = newSeq[byte]()
  var buf: array[DEFAULT_CHUNK_SIZE, byte]

  let file = open("/dev/zero", FileMode.fmRead)
  defer:
    file.close()

  template body(size): int =
    let r = file.readBuffer(buf[0].addr, min(SIZE - size, buf.len))
    data.add(buf.toOpenArray(0, r - 1))
    r

  benchLoop(body, SIZE)

proc writeLoop() =
  let file = open("/dev/null", FileMode.fmWrite)
  defer:
    file.close()

  template body(size): int =
    let offset = size mod data.len
    let left = min(data.len - offset, SIZE - size)
    file.writeBuffer(data[offset].addr, left)

  benchLoop(body, SIZE)

proc writeConcatSeq() =
  let file = open("/dev/null", FileMode.fmWrite)
  defer:
    file.close()

  var buf = newSeq[byte]()

  template appendZeroCopy(size): int =
    let offset = size mod data.len
    let left = min(data.len - offset, SIZE - size)
    buf.add(data.toOpenArray(offset, left - 1))
    left

  benchLoop(appendZeroCopy, SIZE)

  doAssert buf.len == SIZE

  template body(size): int =
    file.writeBuffer(buf[size].addr, SIZE - size)

  benchLoop(body, SIZE)

  preConcatData = move buf

proc writePreConcatSeq() =
  let file = open("/dev/null", FileMode.fmWrite)
  defer:
    file.close()

  doAssert preConcatData.len == SIZE

  template body(size): int =
    file.writeBuffer(preConcatData[size].addr, SIZE - size)

  benchLoop(body, SIZE)

type BenchTp = enum
  Memcpy
  ReadIntoStackBuf
  ReadIntoIOBuf
  WriteN
  WriteConcatSeq
  WritePreConcatSeq
  WriteIOBuf

proc memcpyBench() =
  var buf: array[2000, byte]

  template doCopy(size): int =
    let offset = size mod data.len
    let left = min(data.len - offset, SIZE - size)
    copyMem(buf[0].addr, data[offset].addr, left)
    left

  benchLoop(doCopy, SIZE)

proc bench(tp: BenchTp, info: string) =
  GC_fullCollect()

  let startTs = getMonoTime().ticks

  case tp
  of Memcpy:
    memcpyBench()
  of ReadIntoStackBuf:
    readIntoStackBuf()
  of ReadIntoIOBuf:
    readIntoIOBuf()
  of WriteN:
    writeLoop()
  of WriteConcatSeq:
    writeConcatSeq()
  of WritePreConcatSeq:
    writePreConcatSeq()
  of WriteIOBuf:
    writeIOBuf()

  let passTs = getMonoTime().ticks - startTs

  let mb = float64(SIZE) / 1024 / 1024
  let seconds = float64(passTs) / 1e9
  var speed = mb / seconds

  var unitStr = "MB"
  if speed > 1024:
    unitStr = "GB"
    speed = speed / 1024

  echo fmt"{tp} in {seconds:.3f} seconds, {speed:.2f} {unitStr}/s info: {info}"

bench(Memcpy, "memcpy in N call")
bench(ReadIntoStackBuf, "read in N call")
bench(ReadIntoIOBuf, "readv")
bench(WriteN, "write in N call")
bench(WriteConcatSeq, "concat into seq, write in 1 call")
bench(WritePreConcatSeq, "use pre concat seq, write in 1 call")
bench(WriteIOBuf, "appendZeroCopy, writev")
