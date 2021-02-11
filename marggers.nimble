version       = "0.2.2"
author        = "hlaaftana"
description   = "markdown dialect"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 1.0.4"

task tools, "builds tools, only browser converter for now":
  exec "nim js -d:danger browser/converter"

import os

task docs, "build docs for all modules":
  const
    gitUrl = "https://github.com/hlaaftana/marggers"
    gitCommit = "master"
    gitDevel = "master"
    docExtraOptions = ""
    docOutDir = "docs"
  echo "Building docs:"
  for f in walkDirRec(srcDir):
    exec "nim doc --git.url:" & gitUrl &
      " --git.commit:" & gitCommit &
      " --git.devel:" & gitDevel &
      " --outdir:" & docOutDir &
      " " & docExtraOptions &
      " " & f
  
import strutils

task tests, "run tests for multiple backends":
  type Backend = enum
    c, cpp, objc, js, nims
  const
    testsBackends = {c, js, nims}
    testsNimsSuffix = "_nims"
    testsUseRunCommand = false # whether to use nim r or nim c -r
    testsExtraOptions = ""
    testsDir = "tests"
    testsHintsOff = true
    testsWarningsOff = false
    testsBackendExtraOptions: array[Backend, string] = [
      c: "",
      cpp: "",
      objc: "",
      js: "",
      nims: ""
    ]
  echo "Running tests:"
  for k, fn in walkDir(testsDir):
    if k == pcFile and (let (dir, name, ext) = splitFile(fn); name[0] == 't' and ext == ".nim"):
      let noExt = fn[0..^(ext.len + 1)]
      echo "Test: ", name
      var failedBackends: set[Backend]
      for backend in testsBackends:
        echo "Backend: ", backend
        let cmd =
          if backend == nims:
            "e"
          elif testsUseRunCommand:
            "r --backend:" & $backend
          else:
            $backend & " --run"
        template runTest(extraOpts: string = "", file: string = fn) =
          var testFailed = false
          try:
            exec "nim " & cmd &
              (if testsHintsOff: " --hints:off" else: "") &
              (if testsWarningsOff: " --warnings:off" else: "") &
              " --path:. " & extraOpts &
              " " & testsExtraOptions &
              " " & testsBackendExtraOptions[backend] &
              " " & file
            when false:
              const nimsTestFailFile = "nims_test_failed"
              if backend == nims and fileExists(nimsTestFailFile):
                testFailed = true
                rmFile(nimsTestFailFile)
          except:
            # exec exit code 1
            testFailed = true
          if true:#backend != nims:
            if testFailed:
              failedBackends.incl(backend)
              echo "Failed backend: ", backend
            else:
              echo "Passed backend: ", backend
        template removeAfter(file: string, body: untyped) =
          let toRemove = file
          let toRemoveExisted = fileExists(toRemove)
          body
          if not toRemoveExisted and fileExists(toRemove):
            rmFile(toRemove)
        case backend
        of c, cpp, objc:
          let exe = if ExeExt == "": noExt else: noExt & "." & ExeExt 
          removeAfter(exe):
            runTest()
        of js:
          let output = noExt & ".js" 
          removeAfter(output):
            runTest(extraOpts = "-d:nodejs")
        of nims:
          let nimsFile = noExt & testsNimsSuffix & ".nims"
          removeAfter(nimsFile):
            # maybe rename and rename back here
            cpFile(fn, nimsFile)
            runTest(file = nimsFile)
      if failedBackends == {}:
        echo "Passed: ", name
      else:
        echo "Failed: ", name, ", backends: ", ($failedBackends)[1..^2]
