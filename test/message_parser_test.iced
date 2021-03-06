{ deepEqual } = require 'assert'
{ MessageParser } = require "../#{process.env.JSLIB or 'lib'}/session"

o = (manifest, func) ->
  describe "with #{JSON.stringify manifest}", ->
    fmt = new MessageParser(manifest)
    oo = (input, expected) ->
      desc = "should find #{JSON.stringify expected} in #{JSON.stringify input}"
      it desc, ->
        { messages } = fmt.parse(input)
        deepEqual messages, expected
    func(oo)


describe "MessageParser", ->

  o { errors: ["error: ((message))\n"] }, (oo) ->
    oo 'hello there', []
    oo 'error: hello world', [{type: "error", message: "hello world"}]

  o { errors: ["error: ((message))\n"], warnings: ["warning: ((message))\n"] }, (oo) ->
    oo "warning: foo bar\nerror: hello world", [{type: "warning", message: "foo bar"}, {type: "error", message: "hello world"}]
