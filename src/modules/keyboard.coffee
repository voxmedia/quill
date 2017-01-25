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

  removeHotkeys: (hotkey, callback) ->
    hotkey = if _.isString(hotkey) then hotkey.toUpperCase() else hotkey
    hotkey = if Keyboard.hotkeys[hotkey] then Keyboard.hotkeys[hotkey] else hotkey
    hotkey = if _.isObject(hotkey) then hotkey else { key: hotkey }
    which = if _.isNumber(hotkey.key) then hotkey.key else hotkey.key.charCodeAt(0)
    @hotkeys[which] ?= []
    [removed, kept] = _.partition(@hotkeys[which], (handler) ->
      _.isEqual(hotkey, _.omit(handler, 'callback')) and
        (!callback or callback == handler.callback)
    )
    @hotkeys[which] = kept
    return _.map(removed, 'callback')

  toggleFormat: (range, format) ->
    if range.isCollapsed()
      delta = @quill.getContents(Math.max(0, range.start-1), range.end)
    else
      delta = @quill.getContents(range)
    value = delta.ops.length == 0 or !_.every(delta.ops, (op) ->
      # it's ok to have newline-only inserts without the format
      return op.attributes?[format] or /^\n+$/.test(op.insert)
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
    this.addHotkey(keys, (range, hotkey, event) =>
      return true unless range?
      [line, offset] = @quill.editor.doc.findLineAt(range.start)
      [leaf, offset] = line.findLeafAt(offset)
      delta = new Delta().retain(range.start)

      removeInheritedFormats = {}
      removeNonInheritedFormats = {}
      removeFromRightLine = {}
      removeFromLeftLine = {}
      for name, value of line.formats
        format = @quill.editor.doc.formats[name]
        if format and format.isType('line')
          if format.config.inherit
            removeInheritedFormats[name] = false
          if !format.config.inherit
            removeNonInheritedFormats[name] = false
          if format.config.splitAffinity == 'left'
            removeFromRightLine[name] = null
          if format.config.splitAffinity == 'right'
            removeFromLeftLine[name] = null

      # if on an empty line, remove the inheritable formats
      if range.isCollapsed() and line.length == 1 and Object.keys(removeInheritedFormats).length > 0
        delta.retain(1, removeInheritedFormats)
      else
        delta.insert('\n', Object.assign({}, line.formats, removeFromLeftLine)).delete(range.end - range.start)

      # if creating a new empty line (was at the end of the old line),
      # remove line formats from the new line that should not be inherited
      if !leaf.next and offset == leaf.length and !event.shiftKey
        delta.retain(1, removeNonInheritedFormats)
      else
        delta.retain(leaf.length - offset)
        delta.retain(1, Object.assign({}, line.formats, removeFromRightLine))

      @quill.updateContents(delta, Quill.sources.USER)
      _.each(leaf.formats, (value, format) =>
        @quill.prepareFormat(format, value)
        @toolbar.setActive(format, value) if @toolbar?
        return
      )
      @quill.editor.selection.scrollIntoView()
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
              @quill.formatLine(start, start, format, false, Quill.sources.USER)
            else if start > 0
              @quill.deleteText(start - 1, start, Quill.sources.USER)
          else if start < @quill.getLength() - 1
            @quill.deleteText(start, start + 1, Quill.sources.USER)
      @quill.editor.selection.scrollIntoView()
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
