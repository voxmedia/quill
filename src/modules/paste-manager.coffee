Quill    = require('../quill')
Document = require('../core/document')
_        = Quill.require('lodash')
dom      = Quill.require('dom')
Delta    = Quill.require('delta')

class PasteManager
  @DEFAULTS:
    onConvert: null

  constructor: (@quill, options) ->
    @container = @quill.addContainer('ql-paste-manager')
    @container.setAttribute('contenteditable', true)
    dom(@quill.root).on('paste', _.bind(this._paste, this))
    @options = _.defaults(options, PasteManager.DEFAULTS)
    @options.onConvert ?= this._onConvert;

  _onConvert: (container) =>
    formats = _.reduce(@quill.editor.doc.formats, (memo, format, name) ->
      memo[name] = format.config
      memo
    , {})
    doc = new Document(@container, { formats })
    delta = doc.toDelta()
    lengthAdded = delta.length()
    if lengthAdded == 0
      return delta
    # Need to remove trailing newline so paste is inline, losing format is expected and observed in Word
    return delta.compose(new Delta().retain(lengthAdded - 1).delete(1))

  _paste: ->
    oldDocLength = @quill.getLength()
    range = @quill.getSelection()
    return unless range?
    @container.focus()
    _.defer( =>
      delta = @options.onConvert(@container)
      lengthAdded = delta.length()
      if lengthAdded > 0
        delta.ops.unshift({ retain: range.start }) if range.start > 0
        delta.delete(range.end - range.start)
        @quill.updateContents(delta, 'user')
      @quill.setSelection(range.start + lengthAdded, range.start + lengthAdded)
      # Make sure bottom of pasted content is visible
      [line, offset] = @quill.editor.doc.findLineAt(range.start + lengthAdded)
      lineBottom = line.node.getBoundingClientRect().bottom
      windowBottom = document.documentElement.clientHeight
      line.node.scrollIntoView(false) if lineBottom > windowBottom
      @container.innerHTML = ""
    )


Quill.registerModule('paste-manager', PasteManager)
module.exports = PasteManager
