class Sprite
  constructor: (@image, @left, @top, @width, @height) -> 

class SpriteDict
  sprite: null
  info: null
  
  constructor: (spriteFile, infoFile, callback) ->
    $.getJSON spriteFile, (json) =>
      @sheet = json
      @loaded(callback)
    $.get infoFile, (image) =>
      @sprite = image
      @loaded(callback)

  loaded: (callback) ->
    if not ((@sprite is undefined) or (@info is undefined))
      callback()

  get: (name) ->
    spriteInfo = @info[name]
    new Sprite(@sheet, spriteInfo.left, spriteInfo.top, spriteInfo.width, spriteInfo.height)

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
    sprites = new SpriteDict 'resources/spritesheet.png',
                             'resources/spritesheet.json',
                             @createEntities

  createEntities: () =>
    @run()

  run: () ->
    @interval = setInterval =>
        @update()
        @draw()
    , (1000/@FPS)

  update: () ->

  draw: () ->
    ctx = @canvas.getContext('2d')
    ctx.fillStyle = '#000'
    ctx.fillRect 0, 0, @WIDTH, @HEIGHT


canvas = document.getElementById('canvas')
game = new Game(canvas)
