import module_bridge, marggers

# this behaves weird in nimscript, wrong strings are randomly matched together:
const inlineTestTable*: seq[tuple[marggers, html: string]] = @{
  "To escape use \\\\":
    "<p>To escape use \\</p>",
  "# Heading":
    "<h1> Heading</h1>",
  "####{heading-id} Heading with id":
    "<h4 id=\"heading-id\"> Heading with id</h4>",
  "*a* _b_ **c** __d__ ~~e~~ `f` g^(h) i[j] [k](l)":
    "<p><em>a</em> <em>b</em> <strong>c</strong> <u>d</u> " &
    "<s>e</s> <code>f</code> g<sup>h</sup> i<sub>j</sub> <a href=\"l\">k</a></p>",

  # issue #4:
  "a**a__a": "<p>a**a__a</p>",
  "a*a_a": "<p>a*a_a</p>",

  # should not be greedy:
  "*a **b***": "<p><em>a <strong>b</strong></em></p>",

  # issue #14
  "a_b_c": "<p>a_b_c</p>",
  "a_b _c": "<p>a_b _c</p>",
  "a_ b _c": "<p>a_ b _c</p>",
  "a _b _c": "<p>a _b _c</p>",
  "a _b_ c": "<p>a <em>b</em> c</p>",
  "a * b * c": "<p>a * b * c</p>",

  # aligned headings, #8
  "#<{header-id} Header": "<h1 style=\"text-align:left\" id=\"header-id\"> Header</h1>",
  "###|(header-id) Header": "<h3 style=\"text-align:center\" id=\"header-id\"> Header</h3>",
  # :header-id segfaults nimscript for some reason

  # video/audio links, #16
  "video: ![](video.mp4)": "<p>video: <video controls src=\"video.mp4\"></video></p>",
  "audio: ![](audio.mp3)": "<p>audio: <audio controls src=\"audio.mp3\"></audio></p>",
  "ignores space: ![]( video.mp4 )": "<p>ignores space: <video controls src=\"video.mp4\"></video></p>",
  "dir link: ![](video.mp4/)": "<p>dir link: <img src=\"video.mp4/\"></p>",

  # single superscript, #18
  "a^b c^d e ^ f g^ h i ^j k^l": "<p>a<sup>b</sup> c<sup>d</sup> e ^ f g^ h i ^j k<sup>l</sup></p>",

  # restricted sub:
  "[a] b [c] d[e] f[g] ": "<p>[a] b [c] d<sub>e</sub> f<sub>g</sub> </p>",

  "1 > 3": "<p>1 &gt; 3</p>",
}

iterator inlineTests*: tuple[marggers, html: NativeString] =
  when defined(nimscript): # other branch gives sigsegv
    for x in inlineTestTable.items:
      yield x
  else:
    for m, h in inlineTestTable.items:
      yield (NativeString(m), NativeString(h))

runTests:
  test "do inline tests":
    for marggers, html in inlineTests():
      checkpoint("marggers input: " & $marggers)
      checkpoint("html output: " & $html)
      check becomes(marggers, html)
