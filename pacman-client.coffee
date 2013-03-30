class Sprite
  constructor: (@image, @info) ->
  
  width: () -> @info.sourceSize.w
  height: () -> @info.sourceSize.h

  drawScaled: (ctx, x, y, scale) ->
    x += @info.spriteSourceSize.x
    y += @info.spriteSourceSize.y
    ctx.drawImage @image, @info.frame.x, @info.frame.y, @info.frame.w,
      @info.frame.h, x*scale, y*scale, @info.frame.w*scale, @info.frame.h*scale

class SpriteDict
  sprite: null
  info: null
  
  constructor: (spriteFile, infoFile, callback) ->
    @sprite = new Image()
    @sprite.src = spriteFile
    $.getJSON infoFile, (json) => @info = json; callback()

  get: (name) ->
    new Sprite(@sprite, @info[name])

class Level
  entities: null
  cookies: null

  constructor: (filename, callback) ->
    $.get filename, (data) => 
      callback()
      

class Game
  SCALE: 2
  WIDTH: 224
  HEIGHT: 40 + 248 + 20
  FPS: 30
  interval: null
  sprites: null
  level: null
  
  constructor: (@canvas) ->
    @setup()

  setup: () ->
    @canvas.height = @HEIGHT*@SCALE
    @canvas.width = @WIDTH*@SCALE
    @loadLevel()
    
  loadLevel: () ->
    @level = new Level('res/level', @loadSprites)

  loadSprites: () =>
    @sprites = new SpriteDict 'res/sprites.png', 'res/sprites.json', @createEntities

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
    @drawMaze(ctx)
    @drawCookies(ctx)

  drawMaze: (ctx) ->
    ctx.fillStyle = '#000'
    ctx.fillRect 0, 0, @WIDTH*@SCALE, @HEIGHT*@SCALE
    s = @sprites.get("maze")
    s.drawScaled ctx, 0, 40, @SCALE

  drawCookies: (ctx) ->

    

canvas = document.getElementById('canvas')
game = new Game(canvas)
