import unittest, marggers, strutils, os

proc joinedParse(str: string): string =
  for p in str.parseMarggers:
    result.add($p)
    result.add("\r\n")

for (kind, inputFile) in walkDir("tests/files"):
  if kind == pcFile:
    var testName = inputFile
    testName.removeSuffix(".mrg")
    if testName.len != inputFile.len:
      test "Test file " & testName["tests/files/".len .. ^1]:
        let input = joinedParse(readFile(inputFile)).splitLines
        let output = readFile(testName & ".html").splitLines
        check input == output
        if input != output:
          writeFile(testName & "_real.html", input.join("\r\n"))
