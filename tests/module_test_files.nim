import marggers, strutils, module_bridge

proc joinedParse*(str: string): string =
  for p in str.parseMarggers:
    result.add($p)
    result.add("\r\n")

suite:
  for inputFile in files("tests/files"):
    var testPath = $inputFile
    testPath.removeSuffix(".mrg")
    if testPath.len != inputFile.len:
      var testName = testPath
      testName.removePrefix("tests/files/")
      let fileContent = read(inputFile)
      test "Test file " & testName:
        let input = joinedParse(fileContent).splitLines
        let output = read(testPath & ".html").splitLines
        check input == output
        if input != output:
          write(testPath & "_real.html", input.join("\r\n"))
      test "Test file " & testName & " with LF":
        let input = joinedParse(fileContent.replace("\r\n", "\n")).splitLines
        let output = read(testPath & ".html").splitLines
        check input == output
        if input != output:
          write(testPath & "_real_lf.html", input.join("\r\n"))
