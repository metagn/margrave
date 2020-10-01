# marggers

Dialect of markdown (that outputs to HTML) that I once made for a purpose that didn't work out.
Tested for C backend, but JS backend only works in 1.3/1.4.

````markdown
To escape use \\

# Heading1
## Heading2
### Heading3
#### Heading4
##### Heading5
###### Heading6

####{heading-id} Heading (if you add #heading-id to the link it links to this)

* Bullet points
+ Plus
- Minus

1. Numbered list
2. Can be
4. Any number
.  or dot
   , can also indent

> Blockquotes
>
> can be **formatted** _lol_

```
Code blocks
Have no formatting
```

Inline formatting:

Link: [text](url)
      [text **can have formatting**](url "tooltip text")
Image: ![](url)
       ![alt text (image doesnt load)](url "tooltip text")
Superscript: 4^(3) = 64
Subscript: a[n] = 2n + 1
Bold: **text**
Underline: __text__
italic: *text* _text_
Strikethrough: ~~text~~
Inline code (has formatting): `text`
Checkboxes: [ ] [x]
No formatting: {aaaa **aa**}
Double curly acts as 1 curly: {{aaadooooo}}

Inline HTML (no formatting inside): <table>
  <tbody>
    <tr>
      <td>aids 1</td>
      <td>aids 2</td>
    </tr>
    <tr>
      <td>aids 3</td>
      <td>aids 4</td>
    </tr>
  </tbody>
</table>
````

Output:

```HTML
<p>To escape use \</p>
<h1> Heading1</h1>
<h2> Heading2</h2>
<h3> Heading3</h3>
<h4> Heading4</h4>
<h5> Heading5</h5>
<h6> Heading6</h6>
<h4 id="heading-id"> Heading (if you add #heading-id to the link it links to this)</h4>
<ul><li>Bullet points</li><li>Plus</li><li>Minus</li></ul>
<ol><li> Numbered list</li><li> Can be</li><li> Any number</li><li>  or dot
    , can also indent</li></ol>
<blockquote><p> Blockquotes</p>

<p>can be <strong>formatted</strong> <em>lol</em></p></blockquote>
<pre>Code blocks
Have no formatting
</pre>
<p>Inline formatting:</p>
<p>Link: <a href="url">text</a>
      <a href="url" title="tooltip text">text <strong>can have formatting</strong></a>
Image: <img src="url">
       <img src="url" alt="alt text (image doesnt load)" title="tooltip text">
Superscript: 4<sup>3</sup> = 64
Subscript: a<sub>n</sub> = 2n + 1
Bold: <strong>text</strong>
Underline: <u>text</u>
italic: <em>text</em> <em>text</em>
Strikethrough: <s>text</s>
Inline code (has formatting): <code>text</code>
Checkboxes: <input type="checkbox" disabled> <input type="checkbox" disabled checked>
No formatting: aaaa **aa**
Double curly acts as 1 curly: {aaadooooo}</p>
<p>Inline HTML (no formatting inside): <table>
  <tbody>
    <tr>
      <td>aids 1</td>
      <td>aids 2</td>
    </tr>
    <tr>
      <td>aids 3</td>
      <td>aids 4</td>
    </tr>
  </tbody>
</table></p>
```