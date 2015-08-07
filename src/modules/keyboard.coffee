Quill  = require('../quill')
_      = Quill.require('lodash')
dom    = Quill.require('dom')
Delta  = Quill.require('delta')


class Keyboard
  @hotkeys:
    BOLD:       { key: 'B',          metaKey: true }
    INDENT:     { key: dom.KEYS.TAB }
    ITALIC:     { key: 'I',          metaKey: true }
    OUTDENT:    { key: dom.KEYS.TAB, shiftKey: true }
    UNDERLINE:  { key: 'U',          metaKey: true }

  constructor: (@quill, options) ->
    @hotkeys = {}
    this._initListeners()
    this._initHotkeys()
    @quill.onModuleLoad('toolbar', (toolbar) =>
      @toolbar = toolbar
    )

  addHotkey: (hotkeys, callback) ->
    hotkeys = [hotkeys] unless Array.isArray(hotkeys)
    _.each(hotkeys, (hotkey) =>
      hotkey = if _.isObject(hotkey) then _.clone(hotkey) else { key: hotkey }
      hotkey.callback = callback
      which = if _.isNumber(hotkey.key) then hotkey.key else hotkey.key.toUpperCase().charCodeAt(0)
      @hotkeys[which] ?= []
      @hotkeys[which].push(hotkey)
    )

  toggleFormat: (range, format) ->
    if range.isCollapsed()
      delta = @quill.getContents(Math.max(0, range.start-1), range.end)
    else
      delta = @quill.getContents(range)
    value = delta.ops.length == 0 or !_.all(delta.ops, (op) ->
      return op.attributes?[format]
    )
    if range.isCollapsed()
      @quill.prepareFormat(format, value, Quill.sources.USER)
    else
      @quill.formatText(range, format, value, Quill.sources.USER)
    @toolbar.setActive(format, value) if @toolbar?

  _initEnter: ->
    keys = [
      { key: dom.KEYS.ENTER }
      { key: dom.KEYS.ENTER, shiftKey: true }
    ]
    this.addHotkey(keys, (range, hotkey) =>
      return true unless range?
      [line, offset] = @quill.editor.doc.findLineAt(range.start)
      [leaf, offset] = line.findLeafAt(offset)
      delta = new Delta().retain(range.start)
      removeInheritedFormats = _.reduce(line.formats, (formats, value, name) =>
        format = @quill.editor.doc.formats[name]
        if format and format.isType('line') and format.config.inherit
          formats[name] = false
        return formats
      , {})
      removeNonInheritedFormats = _.reduce(line.formats, (formats, value, name) =>
        format = @quill.editor.doc.formats[name]
        if format and format.isType('line') and !format.config.inherit
          formats[name] = false
        return formats
      , {})

      # if on an empty line, remove the inheritable formats
      if range.isCollapsed() and line.length == 1 and Object.keys(removeInheritedFormats).length > 0
        delta.retain(1, removeInheritedFormats)
      else
        delta.insert('\n', line.formats).delete(range.end - range.start)

      # if creating a new empty line (was at the end of the old line),
      # remove line formats from the new line that should not be inherited
      if !leaf.next and offset == leaf.length
        delta.retain(1, removeNonInheritedFormats)

      @quill.updateContents(delta, Quill.sources.USER)
      _.each(leaf.formats, (value, format) =>
        @quill.prepareFormat(format, value)
        @toolbar.setActive(format, value) if @toolbar?
        return
      )
      return false
    )

  _initDeletes: ->
    this.addHotkey([dom.KEYS.DELETE, dom.KEYS.BACKSPACE], (range, hotkey) =>
      if range? and @quill.getLength() > 0
        { start, end } = range
        if start != end
          # if the surrounding characters are both spaces,
          # kill the preceding space to prevent leaving double-spaces
          before = @quill.getText(Math.max(start - 1, 0), start)
          after = @quill.getText(end, Math.min(end + 1, @quill.getLength()))
          if ' ' == before == after
            start = start - 1
          @quill.deleteText(start, end, Quill.sources.USER)
        else
          if hotkey.key == dom.KEYS.BACKSPACE
            [line, offset] = @quill.editor.doc.findLineAt(start)
            if offset == 0 and (line.formats.bullet or line.formats.list)
              format = if line.formats.bullet then 'bullet' else 'list'
              @quill.formatLine(start, start, format, false)
            else if start > 0
              @quill.deleteText(start - 1, start, Quill.sources.USER)
          else if start < @quill.getLength() - 1
            @quill.deleteText(start, start + 1, Quill.sources.USER)
      return false
    )

  _initHotkeys: ->
    this.addHotkey(Keyboard.hotkeys.INDENT, (range) =>
      this._onTab(range, false)
      return false
    )
    this.addHotkey(Keyboard.hotkeys.OUTDENT, (range) =>
      # TODO implement when we implement multiline tabs
      return false
    )
    _.each(['bold', 'italic', 'underline'], (format) =>
      this.addHotkey(Keyboard.hotkeys[format.toUpperCase()], (range) =>
        if (@quill.editor.doc.formats[format])
          this.toggleFormat(range, format)
        return false
      )
    )
    this._initDeletes()
    this._initEnter()

  _initListeners: ->
    dom(@quill.root).on('keydown', (event) =>
      prevent = false
      _.each(@hotkeys[event.which], (hotkey) =>
        metaKey = if dom.isMac() then event.metaKey else event.metaKey or event.ctrlKey
        return if !!hotkey.metaKey != !!metaKey
        return if !!hotkey.shiftKey != !!event.shiftKey
        return if !!hotkey.altKey != !!event.altKey
        prevent = hotkey.callback(@quill.getSelection(), hotkey, event) == false or prevent
        return true
      )
      return !prevent
    )

  _onTab: (range, shift = false) ->
    # TODO implement multiline tab behavior
    # Behavior according to Google Docs + Word
    # When tab on one line, regardless if shift is down, delete selection and insert a tab
    # When tab on multiple lines, indent each line if possible, outdent if shift is down
    delta = new Delta().retain(range.start)
                       .insert("\t")
                       .delete(range.end - range.start)
                       .retain(@quill.getLength() - range.end)
    @quill.updateContents(delta, Quill.sources.USER)
    @quill.setSelection(range.start + 1, range.start + 1)


Quill.registerModule('keyboard', Keyboard)
module.exports = Keyboard
