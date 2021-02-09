import unittest, marggers, strutils, os

proc joinedParse(str: string): string =
  for p in str.parseMarggers:
    result.add($p)
    result.add("\r\n")

when not defined(js):
  for (kind, inputFile) in walkDir("tests/files"):
    if kind == pcFile:
      var testPath = inputFile
      testPath.removeSuffix(".mrg")
      if testPath.len != inputFile.len:
        var testName = testPath
        testName.removePrefix("tests\\files\\")
        let fileContent = readFile(inputFile)
        test "Test file " & testName:
          let input = joinedParse(fileContent).splitLines
          let output = readFile(testPath & ".html").splitLines
          check input == output
          if input != output:
            writeFile(testPath & "_real.html", input.join("\r\n"))
        test "Test file " & testName & " with LF":
          let input = joinedParse(fileContent.replace("\r\n", "\n")).splitLines
          let output = readFile(testPath & ".html").splitLines
          check input == output
          if input != output:
            writeFile(testPath & "_real_lf.html", input.join("\r\n"))
else:
  type FileSystem = ref object
  var fs {.importc, nodecl.}: FileSystem
  {.emit: "const fs = require(\"fs\");".}
  using fs: FileSystem
  proc readdirSync(fs; path: cstring): seq[cstring] {.importjs: "#.$1(@)".}
  proc readFileSync(fs; path: cstring, encoding = cstring("utf8")): cstring {.importjs: "#.$1(@)".}
  proc writeFileSync(fs; path, data: cstring, encoding = cstring("utf8")) {.importjs: "#.$1(@)".}
  for path in fs.readdirSync("tests/files"):
    var testPath = $path
    testPath.removeSuffix(".mrg")
    if testPath.len != path.len:
      var testName = testPath
      testName.removePrefix("tests/files/")
      # paths are just to be safe
      let fileContent = $fs.readFileSync("tests/files/" & testName & ".mrg")
      test "Test file " & testName:
        try:
          # paths are just to be safe
          let input = joinedParse(fileContent).splitLines
          let output = ($fs.readFileSync("tests/files/" & testName & ".html")).splitLines
          check input == output
          if input != output:
            fs.writeFileSync(cstring("tests/files/" & testName & "_real.html"), cstring(input.join("\r\n")))
        except:
          {.emit: "console.trace(EXC);".}
      test "Test file " & testName & " with LF":
        try:
          let input = joinedParse(fileContent.replace("\r\n", "\n")).splitLines
          let output = ($fs.readFileSync("tests/files/" & testName & ".html")).splitLines
          check input == output
          if input != output:
            fs.writeFileSync(cstring("tests/files/" & testName & "_real_lf.html"), cstring(input.join("\r\n")))
        except:
          {.emit: "console.trace(EXC);".}
