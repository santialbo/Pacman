class Sprite
  scale: 1

  constructor: (@image, @info, @scale) ->
  
  width: () -> @info.sourceSize.w
  height: () -> @info.sourceSize.h

  draw: (ctx, x, y) ->
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

  drawText: (ctx, text, x, y, align) ->
    sprites = (text.split "").map (letter) =>
      if letter == '.' then @spriteDict.get "dot" else @spriteDict.get letter
    if align != "left"
      width = (sprites.map (s) -> s.width()).reduce (x, y) -> x + y
      if align == "center" then x-= width/2
      else x -= width
    for sprite in sprites
      sprite.draw ctx, x, y
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
  state: {}
  id: null
  
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
    @sprites.setScale @SCALE

  createEntities: () =>
    @connect()

  connect: () ->
    @connection = new WebSocket(@SERVER)
    @connection.onmessage = @updateWaitingRoom
    @connection.onopen = @runWaitingRoom

  runWaitingRoom: () =>
    @interval = setInterval =>
        @drawWaitingRoom()
    , (1000/@FPS)

  updateWaitingRoom: (e) =>
    if @id == null
      @id = e.data
      @state.players = 1
    else if e.data == "5"
      clearInterval @interval
      @runGame()
    else
      @state.players = parseInt(e.data)

  drawWaitingRoom: () =>
    ctx = @canvas.getContext('2d')
    ctx.fillRect 0, 0, @WIDTH*@SCALE, @HEIGHT*@SCALE
    s = @sprites.get("title")
    y = 60
    s.draw ctx, @WIDTH/2-s.width()/2, y
    y += s.height()+ 10
    m = (new Date()).getTime()
    if m%2000 > 1200
      t = new SpriteTextDrawer(@sprites)
      t.drawText ctx, "waiting for players", @WIDTH/2, y , "center"
      y += 20
      t.drawText ctx, @state.players + " of 5", @WIDTH/2, y , "center"



  runGame: () =>
    @interval = setInterval =>
        @update()
        @drawGame()
    , (1000/@FPS)

  update: () ->

  drawGame: () ->
    ctx = @canvas.getContext('2d')
    @drawMaze(ctx)
    @drawCookies(ctx)

  drawMaze: (ctx) ->
    ctx.fillStyle = '#000'
    ctx.fillRect 0, 0, @WIDTH*@SCALE, @HEIGHT*@SCALE
    s = @sprites.get("maze")
    s.draw ctx, 4, 40, @SCALE

  drawCookies: (ctx) ->
    s = @sprites.get("cookie")
    p = @sprites.get("pill")
    l = 4; t = 5; b = 252; r = 221 # manually calibrated
    rows = @level.cells.length
    cols = @level.cells[0].length
    for i in [0...rows] by 1
      for j in [0...cols] by 1
        if @level.cells[i][j] == "o"
          s.draw ctx, 4+(l+(r-l)*j/(cols-1)), 40+(t+(b-t)*i/(rows-1))
        else if @level.cells[i][j] == "O"
          p.draw ctx, 4+(l+(r-l)*j/(cols-1)), 40+(t+(b-t)*i/(rows-1))

canvas = document.getElementById('canvas')
game = new Game(canvas)
