version       = "0.2.0"
author        = "hlaaftana"
description   = "markdown dialect"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 1.0.4"

import os

task docs, "build docs":
  const
    gitUrl = "https://github.com/hlaaftana/marggers"
    gitCommit = "master"
    gitDevel = "master" 
  for f in walkDirRec("src"):
    exec "nim doc --git.url:" & gitUrl &
      " --git.commit:" & gitCommit &
      " --git.devel:" & gitDevel &
      " --outdir:docs " & f
