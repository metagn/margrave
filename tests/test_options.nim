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

test "Line breaks":
  const control: NativeString = """a
b

c
d
e

f

g"""
  check:
    becomes control, "<p>a\nb</p><p>c\nd\ne</p><p>f</p><p>g</p>"
    becomes control, "<p>a<br/>b</p><p>c<br/>d<br/>e</p><p>f</p><p>g</p>", MarggersOptions(insertLineBreaks: true)
