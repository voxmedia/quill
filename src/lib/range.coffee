_ = require('lodash')


class Range
  @compare: (r1, r2) ->
    return true if r1 == r2           # Covers both is null case
    return false unless r1? and r2?   # If either is null they are not equal
    return r1.equals(r2)

  constructor: (@start, @end) ->

  equals: (range) ->
    return false unless range?
    return @start == range.start and @end == range.end

  shift: (index, length) ->
    [@start, @end] = _.map([@start, @end], (pos) ->
      if index > pos
        pos
      else
        Math.max(index, pos + length)
    )

  transform: (delta) ->
    index = 0
    _.each(delta.ops, (op) =>
      if _.isString(op.insert)
        this.shift(index, op.insert.length)
        index += op.insert.length
      else if _.isNumber(op.insert)
        this.shift(index, 1)
        index += 1
      else if _.isNumber(op.delete)
        this.shift(index, -1 * op.delete)
        index -= op.delete
      else if _.isNumber(op.retain)
        index += op.retain
    )

  isCollapsed: ->
    return @start == @end


module.exports = Range
