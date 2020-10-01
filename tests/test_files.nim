import unittest, marggers, strutils, os

proc joinedParse(str: string): string =
  for p in str.parseMarggers:
    result.add($p)
    result.add('\n')
  result.replace("\r\n", "\n")

for (kind, inputFile) in walkDir("tests/files"):
  if kind == pcFile:
    var testName = inputFile
    testName.removeSuffix(".mrg")
    if testName.len != inputFile.len:
      test "Test file " & testName[12..^1]:
        let input = joinedParse(readFile(inputFile))
        let output = readFile(testName & ".html")
        check input == output
        if input != output:
          writeFile(testName & "_real.html", input)
          for i, c in input:
            if input[i] != output[i]:
              echo input[i..i + 10]
              echo output[i..i + 10]
              break
          echo input.len, " - ", output.len