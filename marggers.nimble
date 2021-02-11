version       = "0.2.3"
author        = "hlaaftana"
description   = "markdown dialect"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 1.0.4"

when (compiles do: import nimbleutils):
  import nimbleutils

task tools, "builds tools, only browser converter for now":
  exec "nim js -d:danger browser/converter"

task docs, "build docs for all modules":
  when declared(buildDocs):
    buildDocs(gitUrl = "https://github.com/hlaaftana/marggers")
  else:
    echo "docs task not implemented, need nimbleutils"

task tests, "run tests for multiple backends":
  when declared(runTests):
    runTests(backends = {c, js, nims})
  else:
    echo "tests task not implemented, need nimbleutils"
