import module_bridge, marggers, strutils

test "Raw curly options":
  const
    defaultOpts = MarggersOptions()
    testOpts = MarggersOptions(curlyNoHtmlEscape: true)

  const
    text: NativeString = "{ < }"
    defaultResult: NativeString = "<p> &lt; </p>"
    testResult: NativeString = "<p> < </p>"

  var
    allDefault = MarggersParser(options: defaultOpts, str: text)
    ctDefault = MarggersParser(options: testOpts, str: text)
    allTest = MarggersParser(options: testOpts, str: text)
    ctTest = MarggersParser(options: defaultOpts, str: text)
  
  check:
    becomes allDefault, defaultResult, defaultOpts
    becomes ctDefault, testResult, defaultOpts
    becomes allTest, testResult, testOpts
    becomes ctTest, testResult, testOpts
