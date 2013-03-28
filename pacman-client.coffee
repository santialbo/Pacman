class Sprite
  constructor: (@image, @x, @y, @width, @height) ->
  
  draw: (ctx, x, y, width, height) ->
    ctx.drawImage @image, @x, @y, @width, @height, x, y, width, height

  drawScaled: (ctx, x, y, scale) ->
    ctx.drawImage @image, @x, @y, @width, @height, x*scale, y*scale, @width*scale, @height*scale



class SpriteDict
  sprite: null
  info: null
  
  constructor: (spriteFile, infoFile, callback) ->
    @sprite = new Image()
    @sprite.src = spriteFile
    $.getJSON infoFile, (json) =>
      @info = json
      @loaded(callback)

  loaded: (callback) ->
    if not ((@sprite == null) or (@info == null))
      callback()

  get: (name) ->
    spriteInfo = @info[name]
    new Sprite(@sprite, spriteInfo.x, spriteInfo.y, spriteInfo.width, spriteInfo.height)

class Level
  entities: null
  background: null

  constructor: (filename) ->
    $.get filename, (data) -> 

class Game
  SCALE: 1
  WIDTH: 170
  HEIGHT: 40 + 215 + 20
  FPS: 30
  interval: null
  sprites: null
  
  constructor: (@canvas) ->
    @setup()

  setup: () ->
    @canvas.height = @HEIGHT*@SCALE
    @canvas.width = @WIDTH*@SCALE
    @sprites = new SpriteDict 'resources/spritesheet.png',
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
    ctx.fillRect 0, 0, @WIDTH*@SCALE, @HEIGHT*@SCALE
    level_sprite = @sprites.get("level_blue")
    level_sprite.drawScaled ctx, 0, 40, @SCALE

canvas = document.getElementById('canvas')
game = new Game(canvas)
