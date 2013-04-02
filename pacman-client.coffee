class Sprite
  # Sprite contains a reference to the spritesheet and the necessary
  # information to draw the actual sprite
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
  # SpriteDict is a dictionary with all the sprites in the sprites json file.
  # It avoids the creation of multiple image objects by having only one.
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

class SpriteAnimation
  # SpriteAnimation handles repeating sprite animation. Every time a sprite
  # is requested it updates the current state.
  dt: 0

  constructor: (@sprites, @times, @fps) ->
  
  requestSprite: () ->
    dt = 1000/@fps
    if dt > @dt
      @sprites.splice(0, 0, @sprites.pop())
      @dt = @times.pop()
      @times.splice(0, 0, @dt)
      @requestSprite (dt - @dt)
    else
      @dt -= dt
      return @sprites[@sprites.length - 1]

class SpriteAnimationDict
  # SpriteAnimationDict handles the creation of animations by reading the
  # information from the animations.json file
  info: null

  constructor: (@spriteDict, fileName, @fps, callback) ->
    $.getJSON fileName, (json) => @info = json; callback()

  get: (name) ->
    sprites = @info[name].sprites.map (sprite_name) => @spriteDict.get(sprite_name)
    new SpriteAnimation(sprites, @info[name].times, @fps)

class Game
  SCALE: 2
  WIDTH: 232
  HEIGHT: 40 + 248 + 20
  FPS: 30
  SERVER: "ws://localhost:8888/pacman"
  initialTime: null
  connection: null
  interval: null
  sprites: null
  animations: null
  animationsPool: {}
  level: null
  state: {}
  id: null
  
  constructor: (@canvas) ->
    @initialTime = new Date().getTime()
    @setup()
  
  time: () -> new Date().getTime() - @initialTime

  setup: () ->
    @canvas.height = @HEIGHT*@SCALE
    @canvas.width = @WIDTH*@SCALE
    @loadLevel()
    
  loadLevel: () ->
    @level = new Level('res/level', @loadSprites)

  loadSprites: () =>
    @sprites =
      new SpriteDict 'res/sprites.png', 'res/sprites.json', @loadAnimations
    @sprites.setScale @SCALE

  loadAnimations: () =>
    @animations =
      new SpriteAnimationDict @sprites, 'res/animations.json', @FPS, @createEntities

  createEntities: () =>
    @connect()

  connect: () ->
    # connect to server and proceed to the waiting room
    @connection = new WebSocket(@SERVER)
    @connection.onmessage = @updateWaitingRoom
    @connection.onopen = @runWaitingRoom

  # Waiting screen

  runWaitingRoom: () =>
    # load animations
    @animationsPool["pacman_right"] = @animations.get("pacman_right")
    @animationsPool["pacman_left"] = @animations.get("pacman_left")
    for color in ["red", "blue", "pink", "orange"]
      @animationsPool["ghost_" + color + "_right"] =
        @animations.get("ghost_" + color + "_right")
    for i in [0...4]
      @animationsPool["ghost_dead_blue_" + i] = @animations.get("ghost_dead_blue")

    @interval = setInterval =>
        @drawWaitingRoom()
    , (1000/@FPS)

  updateWaitingRoom: (e) =>
    if @id == null
      @id = e.data
      @state.players = 1
    else if e.data == "5"
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
    t = new SpriteTextDrawer(@sprites)
    t.drawText ctx, "waiting for players", @WIDTH/2, y , "center"
    if @time()%2000 < 1200
      y += 20
      t.drawText ctx, @state.players + " of 5", @WIDTH/2, y , "center"
    y = 200
    x = -10 + (@time()%10000)/3000*(@WIDTH + 20)
    @animationsPool["pacman_right"].requestSprite().draw ctx, x, y
    x -= 60
    for color in ["red", "blue", "pink", "orange"]
      @animationsPool["ghost_" + color + "_right"].requestSprite().draw ctx, x, y
      x -= 18
    x = (7800 - @time()%10000)/3000*(@WIDTH+20)
    for i in [0...4]
      @animationsPool["ghost_dead_blue_" + i].requestSprite().draw ctx, x, y
      x += 18
    x += 60
    @animationsPool["pacman_left"].requestSprite().draw ctx, x, y

  # Actual game

  runGame: () =>
    clearInterval @interval
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
