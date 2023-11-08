# Package

version       = "0.1.0"
author        = "haoyu234"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"
bin           = @["bench", "prof"]


# Dependencies

requires "nim >= 2.1.1"
requires "instru >= 0.0.1"
requires "benchy >= 0.0.1"
