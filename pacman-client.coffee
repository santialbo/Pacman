class Sprite
  scale: 1

  constructor: (@image, @info, @scale) ->
  
  width: () -> @info.sourceSize.w
  height: () -> @info.sourceSize.h

  drawScaled: (ctx, x, y) ->
    x += @info.spriteSourceSize.x
    y += @info.spriteSourceSize.y
    ctx.drawImage @image, @info.frame.x, @info.frame.y,
      @info.frame.w, @info.frame.h,
      x*@scale, y*@scale, @info.frame.w*@scale, @info.frame.h*@scale

class SpriteDict
  sprite: null
  info: null
  scale: 1
  
  setScale: (@scale) ->

  constructor: (spriteFile, infoFile, callback) ->
    @sprite = new Image()
    @sprite.src = spriteFile
    $.getJSON infoFile, (json) => @info = json; callback()

  get: (name) ->
    new Sprite(@sprite, @info[name], @scale)

class SpriteTextDrawer

  constructor: (@spriteDict) ->

  drawText: (ctx, text, x, y, halign, valign) ->
    sprites = (text.split "").map (letter) =>
      if letter == '.' then @spriteDict.get "dot" else @spriteDict.get letter
    if halign != "left"
      width = (sprites.map (s) -> s.width()).reduce (x, y) -> x + y
      if halign == "center" then x-= width/2
      else x -= width
    if valign == "middle"
      y -= sprites[0].height()/2
    else if valign == "bottom"
      y -= sprites[0].height()/2
    for sprite in sprites
      sprite.drawScaled ctx, x, y
      x += sprite.width()

class Level
  entities: null
  cells: null

  constructor: (filename, callback) ->
    $.get filename, (data) => 
      @cells = (data.split "\n").map (row) -> row.split ""
      callback()

class Game
  SCALE: 1
  WIDTH: 232
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
    @sprites.setScale @SCALE

  createEntities: () =>
    @connect()

  run: () =>
    @runGame()

  runGame: () =>
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
    s.drawScaled ctx, 4, 40, @SCALE
    t = new SpriteTextDrawer(@sprites)
    t.drawText ctx, "hola", 10, 10, "left", "top"

  drawCookies: (ctx) ->
    s = @sprites.get("cookie")
    p = @sprites.get("pill")
    l = 4; t = 5; b = 252; r = 221 # manually calibrated
    rows = @level.cells.length
    cols = @level.cells[0].length
    for i in [0...rows] by 1
      for j in [0...cols] by 1
        if @level.cells[i][j] == "o"
          s.drawScaled ctx, 4+(l+(r-l)*j/(cols-1)), 40+(t+(b-t)*i/(rows-1))
        else if @level.cells[i][j] == "O"
          p.drawScaled ctx, 4+(l+(r-l)*j/(cols-1)), 40+(t+(b-t)*i/(rows-1))

canvas = document.getElementById('canvas')
game = new Game(canvas)
