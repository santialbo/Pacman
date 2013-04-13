window.SCALE = 1
window.WIDTH = 232
window.HEIGHT = 40 + 248 + 20
window.FPS = 30
window.ROWS = 31
window.COLS = 28
window.SERVER = "ws://localhost:8888/pacman" 

class Sprite
  # Sprite contains a reference to the spritesheet and the necessary
  # information to draw the actual sprite
  constructor: (@image, @info) ->
  
  width: () -> @info.sourceSize.w
  height: () -> @info.sourceSize.h

  draw: (ctx, x, y) ->
    x += @info.spriteSourceSize.x
    y += @info.spriteSourceSize.y
    ctx.drawImage @image, @info.frame.x, @info.frame.y,
      @info.frame.w, @info.frame.h,
      x*SCALE, y*SCALE, @info.frame.w*SCALE, @info.frame.h*SCALE

class SpriteDict
  # SpriteDict is a dictionary with all the sprites in the sprites json file.
  # It avoids the creation of multiple image objects by having only one.
  sprite: null
  info: null
  
  constructor: (spriteFile, infoFile, callback) ->
    @sprite = new Image()
    @sprite.src = spriteFile
    $.getJSON infoFile, (json) => @info = json; callback()

  get: (name) -> new Sprite(@sprite, @info[name])

class SpriteTextDrawer
  constructor: (@spriteDict) ->

  drawText: (ctx, text, x, y, align) ->
    sprites = (text.split "").map (letter) => @spriteDict.get letter
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
      @cells.pop()
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

  peekSprite: () -> @sprites[@sprites.length - 1]

class AnimationDict
  # AnimationDict handles the creation of animations by reading the
  # information from the animations.json file
  info: null

  constructor: (@spriteDict, fileName, @fps, callback) ->
    $.getJSON fileName, (json) => @info = json; callback()

  get: (name) ->
    sprites = @info[name].sprites.map (sprite_name) => @spriteDict.get(sprite_name)
    new SpriteAnimation(sprites, @info[name].times, @fps)

class Game
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
    @canvas.height = HEIGHT*SCALE
    @canvas.width = WIDTH*SCALE
    @loadLevel()
    
  loadLevel: () ->
    @level = new Level('res/level', @loadSprites)

  loadSprites: () =>
    @sprites = new SpriteDict 'res/sprites.png', 'res/sprites.json', @loadAnimations

  loadAnimations: () =>
    @animations =
      new AnimationDict @sprites, 'res/animations.json', FPS, @createEntities

  createEntities: () =>
    @animationsPool["pill"] = @animations.get "pill"
    #load animations
    for d in ["left", "up", "right", "down"]
      @animationsPool["pacman_" + d] = @animations.get("pacman_" + d)
      for c in ["red", "blue", "pink", "orange"]
        name = "ghost_" + c + "_" + d
        @animationsPool[name] = @animations.get(name)
    @animationsPool["ghost_dead_blue"] = @animations.get("ghost_dead_blue")

    @connect()

  connect: () ->
    # connect to server and proceed to the waiting room
    @connection = new WebSocket(SERVER)
    @connection.onmessage = @waitingRoomMsg
    @connection.onopen = @runWaitingRoom

  send: (description, obj) =>
    @connection.send(JSON.stringify {label: description, data: obj})
    
  # Waiting screen

  runWaitingRoom: () =>
    @interval = setInterval @drawWaitingRoom, (1000/FPS)

  waitingRoomMsg: (e) =>
    msg = JSON.parse(e.data)
    if msg.label == "id"
      @id = msg.data
    else if msg.label == "numPlayers"
      @state.players = msg.data
    else if msg.label == "ready"
      @runGame()

  drawWaitingRoom: () =>
    ctx = @canvas.getContext('2d')
    ctx.fillRect 0, 0, WIDTH*SCALE, HEIGHT*SCALE
    s = @sprites.get("title")
    y = 60
    s.draw ctx, WIDTH/2-s.width()/2, y
    y += s.height()+ 10
    t = new SpriteTextDrawer(@sprites)
    t.drawText ctx, "waiting for players", WIDTH/2, y , "center"
    if @time()%2000 < 1200
      y += 20
      t.drawText ctx, @state.players + " of 5", WIDTH/2, y , "center"
    y = 200
    x = -10 + (@time()%10000)/3000*(WIDTH + 20)
    @animationsPool["pacman_right"].requestSprite().draw ctx, x, y
    x -= 60
    for color in ["red", "blue", "pink", "orange"]
      @animationsPool["ghost_" + color + "_right"].requestSprite().draw ctx, x, y
      x -= 18
    x = (7800 - @time()%10000)/3000*(WIDTH+20)
    s = @animationsPool["ghost_dead_blue"].requestSprite()
    for i in [0...4]
      s.draw ctx, x, y
      x += 18
    x += 60
    @animationsPool["pacman_left"].requestSprite().draw ctx, x, y

  # Actual game

  runGame: () =>
    # setup
    clearInterval @interval
    @connection.onmessage = @gameMsg
    @hookKeys()
    @initialTime = new Date().getTime()
    @state.running = false
    @interval = setInterval =>
        @update()
        @drawGame()
    , (1000/FPS)

  gameMsg: (e) =>
    msg = JSON.parse(e.data)
    if msg.label == "go"
      @state.running = true
    else if msg.label == "gameState"
      @level.cells = msg.data["level"]
      @state.players = msg.data["players"]
    

  hookKeys: () =>
    @state.keys = {left: null, up: null, right: null, down: null}
    window.onkeyup = (e) =>
      switch e.keyCode
        when 37, 65
          @state.keys.left = false
          @send "keyEvent", @state.keys
        when 38, 87
          @state.keys.up = false
          @send "keyEvent", @state.keys
        when 39, 68
          @state.keys.right = false
          @send "keyEvent", @state.keys
        when 40, 83
          @state.keys.down = false
          @send "keyEvent", @state.keys
    window.onkeydown = (e) =>
      switch e.keyCode
        when 37, 65
          if not @state.keys.left
            @state.keys.left = true
            @send "keyEvent", @state.keys
        when 38, 87
          if not @state.keys.up
            @state.keys.up = true
            @send "keyEvent", @state.keys
        when 39, 68
          if not @state.keys.right
            @state.keys.right = true
            @send "keyEvent", @state.keys
        when 40, 83
          if not @state.keys.down
            @state.keys.down = true
            @send "keyEvent", @state.keys

  update: () ->

  drawGame: () =>
    ctx = @canvas.getContext('2d')
    @drawMaze(ctx)
    @drawCookies(ctx)
    if not @state.running
      t = new SpriteTextDrawer(@sprites)
      t.drawText ctx, "ready!", WIDTH/2, 177 , "center"
    @drawPlayers ctx

  drawPlayers: (ctx) ->
    d = ["left", "up", "right", "down"]
    c = ["red", "blue", "orange", "pink"]
    for p in @state.players
      if p.pacman
        if p.facing == 0
          s = @sprites.get("pacman")
        else if p.moving
          s = @animationsPool["pacman_" + d[p.facing - 1]].requestSprite()
        else
          s = @animationsPool["pacman_" + d[p.facing - 1]].peekSprite()
      else
        name = "ghost_" + c[p.color] + "_" + d[p.facing - 1]
        s = @animationsPool[name].requestSprite()
      @drawSpriteInPosition ctx, s, p.position[0], p.position[1]

      
  drawSpriteInPosition: (ctx, s, x, y) ->
    l = 4; t = 5; b = 244; r = 221 # manually calibrated
    x = Math.round(4+(l+(r-l)*x/(COLS-1)) - s.width()/2)
    y = Math.round(40+(t+(b-t)*y/(ROWS-1)) - s.height()/2)
    s.draw ctx, x, y
      
  drawMaze: (ctx) ->
    ctx.fillStyle = '#000'
    ctx.fillRect 0, 0, WIDTH*SCALE, HEIGHT*SCALE
    @sprites.get("maze").draw ctx, 4, 40, SCALE

  drawCookies: (ctx) ->
    s = @sprites.get("cookie")
    if @state.running
      p = @animationsPool["pill"].requestSprite()
    else
      p = @sprites.get("pill")

    for y in [0...ROWS] by 1
      for x in [0...COLS] by 1
        if @level.cells[y][x] == "o"
          @drawSpriteInPosition ctx, s, x, y
        else if @level.cells[y][x] == "O"
          @drawSpriteInPosition ctx, p, x, y

canvas = document.getElementById('canvas')
game = new Game(canvas)
