Quill    = require('../quill')
Document = require('../core/document')
_        = Quill.require('lodash')
dom      = Quill.require('dom')
Delta    = Quill.require('delta')
cachedCanUpdateClipboard = null

canUpdateClipboard = (dataTransfer) ->
  if (cachedCanUpdateClipboard != null)
    return cachedCanUpdateClipboard
  dataTransfer.setData("text/html", "<hr>")
  cachedCanUpdateClipboard = (dataTransfer.getData("text/html") == "<hr>")
  return cachedCanUpdateClipboard

class PasteManager
  @DEFAULTS:
    onConvert: null

  constructor: (@quill, options) ->
    @container = @quill.addContainer('ql-paste-manager')
    @container.setAttribute('contenteditable', true)
    @container.setAttribute('tabindex', '-1')
    dom(@quill.root).on('cut', _.bind(this._cut, this))
    dom(@quill.root).on('copy', _.bind(this._copy, this))
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

  _cut: (event) ->
    this._copy(event)
    range = @quill.getSelection()
    return unless range?
    { start, end } = range
    # if the surrounding characters are both spaces,
    # kill the preceding space to prevent leaving double-spaces
    before = @quill.getText(Math.max(start - 1, 0), start)
    after = @quill.getText(end, Math.min(end + 1, @quill.getLength()))
    if ' ' == before == after
      start = start - 1
    @quill.deleteText(start, end, 'user')

  _copy: (event) ->
    range = @quill.getSelection()
    if range
      delta = @quill.getContents(range)
      event.clipboardData.setData('application/rich-text+json', JSON.stringify(delta))

      text = @quill.getText(range)
      event.clipboardData.setData('text/plain', text)

    nativeRange = @quill.editor.selection._getNativeRange()
    if nativeRange
      div = document.createElement('div')
      div.appendChild(nativeRange.cloneContents())
      event.clipboardData.setData('text/html', div.innerHTML)

    event.preventDefault()

  _paste: (event) ->
    range = @quill.getSelection()
    return unless range?

    if event.clipboardData?.types.indexOf('application/rich-text+json') > -1
      delta = JSON.parse event.clipboardData.getData('application/rich-text+json')
      delta = new Delta().retain(range.start).delete(range.end - range.start).concat(delta)
      @quill.updateContents(delta, 'user')
      event.preventDefault()
      return

    oldDocLength = @quill.getLength()
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
      @quill.editor.selection.scrollIntoView()
      @container.innerHTML = ""
    )


Quill.registerModule('paste-manager', PasteManager)
module.exports = PasteManager
