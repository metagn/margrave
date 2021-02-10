when defined(js):
  type NativeString = cstring

  import unittest
  export unittest except test, suite
  
  template test*(name, body): untyped =
    unittest.test(name):
      try:
        body
      except:
        let e = getCurrentException()
        if e.isNil:
          {.emit: "console.trace(EXC);".}
          fail()
        else:
          raise e
  
  type FileSystem* = ref object
  var fs* {.importc, nodecl.}: FileSystem
  {.emit: "const fs = require(\"fs\");".}
  using fs: FileSystem
  proc readdirSync*(fs; path: NativeString): seq[NativeString] {.importjs: "#.$1(@)".}
  proc readFileSync*(fs; path: NativeString, encoding = NativeString("utf8")): NativeString {.importjs: "#.$1(@)".}
  proc writeFileSync*(fs; path, data: NativeString, encoding = NativeString("utf8")) {.importjs: "#.$1(@)".}

  template read*(path: NativeString): string = $fs.readFileSync(path)
  template write*(path, data: NativeString) = fs.writeFileSync(path, data)

  iterator files*(path: NativeString): NativeString =
    var prefix = path
    for c in prefix.mitems:
      if c == '\\': c = '/'
    if prefix[prefix.len - 1] notin {'\\', '/'}: prefix.add("/")
    let files = fs.readdirSync(path)
    for file in files:
      var fn = prefix
      fn.add(file)
      yield fn
  
  template suite*(body) =
    proc runTest*() =
      body
else:
  type NativeString = string

  when defined(nimscript):
    type Test* = object
      name*: string
      checkpoints*: seq[string]
      failed*: bool
    
    var programResult*: int
    proc setProgramResult*(c: int) = programResult = c
    var currentTest*: Test # threadvar

    template check*(b: bool) =
      if not b:
        echo "Check failed: " & astToStr(b)
        fail()

    template checkpoint*(s: string) = currentTest.checkpoints.add(s)

    template fail*() =
      when false:
        # this is so stupid
        writeFile("nims_test_failed", "") 
      setProgramResult(1)
      currentTest.failed = true
    
    template test*(testName, testBody) =
      block:
        currentTest = Test(name: testName)
        
        try:
          testBody
        except:
          checkpoint("Unhandled exception")
          fail()

        if currentTest.failed:
          for c in currentTest.checkpoints:
            echo c
          echo "[FAILED] " & testName
        else:
          echo "[OK] " & testName
  
    template suite*(body) =
      proc runTest*() =
        body
        if programResult != 0:
          raise newException(Exception, "test failed")
  else:
    import unittest
    export unittest except suite
  
    template suite*(body) =
      proc runTest*() =
        body

  from os import walkDir, PathComponent

  iterator files*(path: NativeString): NativeString =
    for (kind, file) in walkDir(path):
      if kind == pcFile:
        when defined(nimscript):
          var fn = newStringOfCap(file.len)
          for c in file:
            fn.add(if c == '\\': '/' else: c)
        else:
          var fn = file
          for c in fn.mitems:
            if c == '\\': c = '/'
        yield fn

  template read*(path: NativeString): string = readFile(path)
  template write*(path, data: NativeString) = writeFile(path, data)
