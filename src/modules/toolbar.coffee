Quill = require('../quill')
_     = Quill.require('lodash')
dom   = Quill.require('dom')


class Toolbar
  @DEFAULTS:
    container: null

  @formats:
    LINE    : { 'align', 'bullet', 'list', 'firstheader', 'secondheader', 'thirdheader', 'fourthheader', 'fifthheader', 'blockquote' }
    SELECT  : { 'align', 'background', 'color', 'font', 'size' }
    TOGGLE  : { 'firstheader', 'secondheader', 'thirdheader', 'fourthheader', 'fifthheader', 'bold', 'bullet', 'image', 'italic', 'link', 'list', 'strike', 'underline' }
    TOOLTIP : { 'image', 'link' }

  constructor: (@quill, @options) ->
    @options = { container: @options } if _.isString(@options) or _.isElement(@options)
    @container = if _.isString(@options.container) then document.querySelector(@options.container) else @options.container
    throw new Error("container required for toolbar, #{@options.container} not found") unless @container?
    @formatHandlers = {}
    @preventUpdate = false
    @triggering = false
    @quill.on(Quill.events.SELECTION_CHANGE, (range) =>
      this.updateActive(range) if range?
    )
    @quill.on(Quill.events.TEXT_CHANGE, => this.updateActive())
    @quill.onModuleLoad('keyboard', (keyboard) =>
      keyboard.addHotkey(['Backspace', 'Delete'], =>
        _.defer(_.bind(this.updateActive, this))
      )
    )
    dom(@container).on('click', this._onClick)
    dom(@container).on('change', this._onClick)
    dom(@container).addClass('ql-toolbar')
    dom(@container).addClass('ios') if dom.isIOS()  # Fix for iOS not losing hover state after click

  initFormat: (format, callback) ->
    @formatHandlers[format] = callback

  setActive: (format, value) ->
    value = false if format == 'image'  # TODO generalize to all embeds
    input = @container.querySelector(".ql-#{format}")
    return unless input?
    $input = dom(input)
    if input.tagName == 'SELECT'
      @triggering = true
      selectValue = $input.value(input)
      value = $input.default()?.value unless value?
      value = '' if Array.isArray(value)  # Must be a defined falsy value
      if value != selectValue
        if value?
          $input.option(value)
        else
          $input.reset()
      @triggering = false
    else
      $input.toggleClass('ql-active', value or false)

  updateActive: (range) ->
    range or= @quill.getSelection()
    return unless range? and !@preventUpdate
    activeFormats = this._getActive(range)
    _.each(@quill.editor.doc.formats, (format, name) =>
      this.setActive(name, activeFormats[name])
      return true
    )

  _onClick: (event) =>
    return if @triggering
    _.each(@quill.editor.doc.formats, (format, name) =>
      target = event.target
      until dom(target).hasClass("ql-#{name}") or target == @container
        target = target.parentNode
      return unless target? and target != @container
      return if target.tagName == 'SELECT' and event.type == 'click'

      value =
        if target.tagName == 'SELECT'
          target.value
        else
          !dom(target).hasClass('ql-active')

      @preventUpdate = true
      @quill.focus()
      range = @quill.getSelection()
      if range?
        handler = @formatHandlers[name] ||
          (range, value) => this._applyFormat(name, range, value)
        handler(range, value)
      @preventUpdate = false
      return false
    )
    return false

  _applyFormat: (name, range, value) ->
    if range.isCollapsed()
      @quill.prepareFormat(name, value, 'user')
    else if Toolbar.formats.LINE[name]?
      @quill.formatLine(range, name, value, 'user')
    else
      @quill.formatText(range, name, value, 'user')
    _.defer( =>
      this.updateActive(range)
      this.setActive(name, value)
    )

  _getActive: (range) ->
    leafFormats = this._getLeafActive(range)
    lineFormats = this._getLineActive(range)
    return _.defaults({}, leafFormats, lineFormats)

  _getLeafActive: (range) ->
    if range.isCollapsed()
      [line, offset] = @quill.editor.doc.findLineAt(range.index)
      if offset == 0
        contents = @quill.getContents(range.index, 1)
      else
        contents = @quill.getContents(range.index - 1, 1)
    else
      contents = @quill.getContents(range)
    formatsArr = _.map(contents.ops, 'attributes')
    return this._intersectFormats(formatsArr)

  _getLineActive: (range) ->
    formatsArr = []
    [firstLine, offset] = @quill.editor.doc.findLineAt(range.start)
    [lastLine, offset] = @quill.editor.doc.findLineAt(range.end)
    lastLine = lastLine.next if lastLine? and lastLine == firstLine
    while firstLine? and firstLine != lastLine
      formatsArr.push(_.clone(firstLine.formats))
      firstLine = firstLine.next
    return this._intersectFormats(formatsArr)

  _intersectFormats: (formatsArr) ->
    return _.reduce(formatsArr.slice(1), (activeFormats, formats = {}) ->
      activeKeys = Object.keys(activeFormats)
      formatKeys = if formats? then Object.keys(formats) else {}
      intersection = _.intersection(activeKeys, formatKeys)
      missing = _.difference(activeKeys, formatKeys)
      added = _.difference(formatKeys, activeKeys)
      _.each(intersection, (name) ->
        if Toolbar.formats.SELECT[name]?
          if Array.isArray(activeFormats[name])
            activeFormats[name].push(formats[name]) if activeFormats[name].indexOf(formats[name]) < 0
          else if activeFormats[name] != formats[name]
            activeFormats[name] = [activeFormats[name], formats[name]]
      )
      _.each(missing, (name) ->
        if Toolbar.formats.TOGGLE[name]?
          delete activeFormats[name]
        else if Toolbar.formats.SELECT[name]? and !Array.isArray(activeFormats[name])
          activeFormats[name] = [activeFormats[name]]
      )
      _.each(added, (name) ->
        activeFormats[name] = [formats[name]] if Toolbar.formats.SELECT[name]?
      )
      return activeFormats
    , _.clone(formatsArr[0] || {}))


Quill.registerModule('toolbar', Toolbar)
module.exports = Toolbar
