import module_bridge, margrave, strutils

test "Raw curly options":
  const
    defaultOpts = MargraveOptions()
    testOpts = MargraveOptions(curlyNoHtmlEscape: true)

  const
    text: NativeString = "{ < }"
    defaultResult: NativeString = "<p> &lt; </p>"
    testResult: NativeString = "<p> < </p>"

  var
    allDefault = MargraveParser(options: defaultOpts, str: text)
    ctDefault = MargraveParser(options: testOpts, str: text)
    allTest = MargraveParser(options: testOpts, str: text)
    ctTest = MargraveParser(options: defaultOpts, str: text)
  
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
    becomes control, "<p>a<br/>b</p><p>c<br/>d<br/>e</p><p>f</p><p>g</p>", MargraveOptions(insertLineBreaks: true)
