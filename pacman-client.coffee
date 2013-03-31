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
  cells: null

  constructor: (filename, callback) ->
    $.get filename, (data) => 
      @cells = (data.split "\n").map (row) -> row.split ""
      callback()
      

class Game
  SCALE: 1.5
  WIDTH: 224
  HEIGHT: 40 + 248 + 20
  FPS: 30
  SERVER: "ws://localhost:8888/pacman"
  connection: null
  interval: null
  sprites: null
  level: null
  
  constructor: (@canvas) ->
    @setup()

  setup: () ->
    @canvas.height = @HEIGHT*@SCALE
    @canvas.width = @WIDTH*@SCALE
    @loadLevel()

  connect: () ->
    @connection = new WebSocket(@SERVER)
    @connection.onopen = @run
    
  loadLevel: () ->
    @level = new Level('res/level', @loadSprites)

  loadSprites: () =>
    @sprites = new SpriteDict 'res/sprites.png', 'res/sprites.json', @createEntities

  createEntities: () =>
    @connect()

  run: () =>
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
    s = @sprites.get("cookie")
    p = @sprites.get("pill")
    l = 4; t = 5; b = 268; r = 221 # manually calibrated
    rows = @level.cells.length
    cols = @level.cells[0].length
    for i in [0...rows] by 1
      for j in [0...cols] by 1
        if @level.cells[i][j] == "o"
          s.drawScaled ctx, (l+(r-l)*j/(cols-1)), 40+(t+(b-t)*i/(rows-1)), @SCALE
        else if @level.cells[i][j] == "O"
          p.drawScaled ctx, (l+(r-l)*j/(cols-1)), 40+(t+(b-t)*i/(rows-1)), @SCALE

canvas = document.getElementById('canvas')
game = new Game(canvas)
