class Sprite
  constructor: (@image, @left, @top, @width, @height) -> 

class Level
  entities: null
  background: null

  constructor: (filename) ->
    $.get filename, (data) -> 

class Game 
  WIDTH: 350
  HEIGHT: 500
  FPS: 30
  interval: null
  
  constructor: (@canvas) ->
    @setup()

  setup: () ->
    @canvas.height = @HEIGHT
    @canvas.width = @WIDTH

  start: () ->
    @interval = setInterval =>
        @update()
        @draw()
    , (1000/@FPS)

  update: () ->

  draw: () ->
    ctx = canvas.getContext('2d')
    ctx.fillStyle = '#000'
    ctx.fillRect 0, 0, @WIDTH, @HEIGHT


canvas = document.getElementById('canvas')
game = new Game(canvas)
game.start()

