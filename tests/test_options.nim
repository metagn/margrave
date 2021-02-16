{.define: marggersUseOptions.}

import module_bridge, marggers, strutils

test "Raw curly options":
  const
    defaultOpts = MarggersParserOptions()
    testOpts = MarggersParserOptions(curlyNoHtmlEscape: true)

  type
    DefaultOptsParser = MarggersParser[defaultOpts]
    TestOptsParser = MarggersParser[testOpts]

  const
    text: NativeString = "{ < }"
    defaultResult: NativeString = "<p> &lt; </p>"
    testResult: NativeString = "<p> < </p>"

  var
    allDefault = DefaultOptsParser(runtimeOptions: defaultOpts, str: text)
    ctDefault = DefaultOptsParser(runtimeOptions: testOpts, str: text)
    allTest = TestOptsParser(runtimeOptions: testOpts, str: text)
    ctTest = TestOptsParser(runtimeOptions: defaultOpts, str: text)
  
  check:
    becomes allDefault, defaultResult
    becomes ctDefault, testResult
    becomes allTest, testResult
    becomes ctTest, testResult
