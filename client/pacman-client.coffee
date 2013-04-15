window.SCALE = 1
window.WIDTH = 4 + 224 + 4
window.HEIGHT = 4 + 26 + 248 + 20 + 4
window.FPS = 30
window.ROWS = 31
window.COLS = 32
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


class SpriteTextWriter
  # SpriteTextWriter writes the given text in the given position.
  constructor: (@spriteDict) ->

  write: (ctx, text, x, y, align) ->
    sprites = (text.split "").map (letter) => @spriteDict.get letter
    if align != "left"
      width = (sprites.map (s) -> s.width()).reduce (x, y) -> x + y
      if align == "center" then x-= width/2
      else x -= width
    for sprite in sprites
      sprite.draw ctx, Math.round(x), Math.round(y)
      x += sprite.width()


class SpriteAnimation
  # SpriteAnimation handles repeating sprite animation. Every time a sprite
  # is requested it updates the current state.
  rem_dt: 0

  constructor: (@sprites, @times, @fps) ->
  
  requestSprite: () ->
    dt = 1000/@fps
    if dt > @rem_dt
      @sprites.splice(0, 0, @sprites.pop())
      time = @times.pop()
      @times.splice(0, 0, time)
      @rem_dt += time
      @requestSprite()
    else
      @rem_dt -= dt
      @sprites[@sprites.length - 1]

  peekSprite: () -> @sprites[@sprites.length - 1]

class AnimationDict
  # AnimationDict handles the creation of animations by reading the
  # information from the animations.json file
  info: null

  constructor: (@spriteDict, fileName, @fps, callback) ->
    $.getJSON fileName, (json) => @info = json; callback()

  get: (name) ->
    sprites = @info[name].sprites.map (sprite_name) => @spriteDict.get sprite_name
    new SpriteAnimation(sprites, @info[name].times, @fps)

class Game
  initialTime: null
  connection: null
  interval: null
  sprites: null
  textWriter: null
  animations: null
  animationsPool: {}
  cells: null
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
    $.get 'res/level', (data) => 
      @cells = (data.split "\n").map (row) -> row.split ""
      @cells.pop()
      @loadSprites()

  loadSprites: () =>
    @sprites = new SpriteDict 'res/sprites.png', 'res/sprites.json', @loadAnimations

  loadAnimations: () =>
    @animations = new AnimationDict @sprites, 'res/animations.json', FPS, @createObjects

  createObjects: () =>
    @textWriter = new SpriteTextWriter(@sprites)
    load = (name) => @animationsPool[name] = @animations.get name
    load "pill"
    for d in ["left", "up", "right", "down"]
      load "pacman_" + d
      for c in ["red", "blue", "pink", "orange"]
        load "ghost_" + c + "_" + d
    load "ghost_dead_blue"
    load "ghost_dead_blue_white"
    @connect()

  connect: () ->
    # Connect to server and proceed to the waiting room
    @connection = new WebSocket(SERVER)
    @connection.onmessage = @waitingRoomMsg
    @connection.onopen = @runWaitingRoom

  send: (description, obj) =>
    # Sends object message to the server
    @connection.send(JSON.stringify {label: description, data: obj})
    
  ############### Waiting screen ###############

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
    ctx = @canvas.getContext '2d'
    ctx.fillRect 0, 0, WIDTH*SCALE, HEIGHT*SCALE
    s = @sprites.get("title")
    y = 60
    s.draw ctx, WIDTH/2-s.width()/2, y
    y += s.height()+ 10
    @textWriter.write ctx, "waiting for players", WIDTH/2, y , "center"
    y += 20
    if @time()%2000 < 1200
      @textWriter.write ctx, @state.players + " of 5", WIDTH/2, y, "center"

    # Going right
    y = 200
    x = -10 + (@time()%10000)/3000*(WIDTH + 20)
    @animationsPool["pacman_right"].requestSprite().draw ctx, x, y
    x -= 60
    for color in ["red", "blue", "pink", "orange"]
      @animationsPool["ghost_" + color + "_right"].requestSprite().draw ctx, x, y
      x -= 18

    # Going left
    x = (7800 - @time()%10000)/3000*(WIDTH+20)
    s = @animationsPool["ghost_dead_blue"].requestSprite()
    for i in [0...4]
      s.draw ctx, x, y
      x += 18
    x += 60
    @animationsPool["pacman_left"].requestSprite().draw ctx, x, y

  ############### Actual game ###############

  runGame: () =>
    clearInterval @interval
    @connection.onmessage = @gameMsg
    @hookKeys()
    @initialTime = new Date().getTime()
    @state.running = false
    @interval = setInterval =>
        @drawGame()
    , (1000/FPS)

  gameMsg: (e) =>
    # Handler function for onmessage event
    msg = JSON.parse e.data
    if msg.label == "go"
      @state.running = true
    else if msg.label == "gameState"
      @cells = msg.data["level"]
      for thing in ["players", "score", "lives", "pillTime"]
        @state[thing] = msg.data[thing]
    
  hookKeys: () =>
    # Hooks event handlers to key press events
    @state.keys = {left: null, up: null, right: null, down: null}
    dirFromCode = (keyCode) ->
      switch keyCode
        when 37, 65 then dir = "left"
        when 38, 87 then dir = "up"
        when 39, 68 then dir = "right"
        when 40, 83 then dir = "down"
        else ""
    toggleKey = (state) => (e) =>
      dir = dirFromCode e.keyCode
      if dir != ""
        @state.keys[dir] = state
        @send "keyEvent", @state.keys
    window.onkeyup = toggleKey false
    window.onkeydown = toggleKey true

  drawGame: () =>
    ctx = @canvas.getContext '2d'
    @drawMaze ctx
    @drawCookies ctx
    @drawPlayers ctx
    @drawHUD ctx
    if not @state.running
      @textWriter.write ctx, "ready!", WIDTH/2, 177 , "center"

  drawPlayers: (ctx) ->
    d = ["left", "left", "up", "right", "down"]
    c = ["red", "blue", "orange", "pink"]
    first = true
    for p in @state.players
      if p.pacman
        if p.facing == 0
          s = @sprites.get("pacman")
        else if p.moving
          s = @animationsPool["pacman_" + d[p.facing]].requestSprite()
        else
          s = @sprites.get("pacman_" + d[p.facing] + "_1")
      else
        if p.mode == 1
          a = "ghost_dead_blue"
          if @state.pillTime < 2800 then a = "ghost_dead_blue_white"
          if first
            s = @animationsPool[a].requestSprite()
            first = false
          else
            s = @animationsPool[a].peekSprite()
        else
          name = "ghost_" + c[p.color] + "_" + d[p.facing]
          s = @animationsPool[name].requestSprite()
      @drawSpriteInPosition ctx, s, p.position[0], p.position[1]

  drawSpriteInPosition: (ctx, s, x, y) ->
    [l, t, r, b] = [12, 12, 221, 244] # manually calibrated
    x = Math.round(4 + ( l+ (r - l)*(x - 3)/(COLS - 6)) - s.width()/2)
    y = Math.round(30 + (t + (b - t)*(y - 1)/(ROWS - 2)) - s.height()/2)
    s.draw ctx, x, y
      
  drawMaze: (ctx) ->
    ctx.fillStyle = '#000'
    ctx.fillRect 0, 0, WIDTH*SCALE, HEIGHT*SCALE
    @sprites.get("maze").draw ctx, 4, 30, SCALE

  drawCookies: (ctx) ->
    s = @sprites.get("cookie")
    if @state.running
      p = @animationsPool["pill"].requestSprite()
    else
      p = @sprites.get("pill")

    for y in [1...ROWS - 1] by 1
      for x in [3...COLS - 3] by 1
        if @cells[y][x] == "o"
          @drawSpriteInPosition ctx, s, x, y
        else if @cells[y][x] == "O"
          @drawSpriteInPosition ctx, p, x, y
  
  drawHUD: (ctx) ->
    # score
    [x, y] = [40, 4]
    if @time()%500 < 250
      @textWriter.write ctx, "1up", x, y, 'center'
    y += 10
    @textWriter.write ctx, (@state.score + ""), x, y, 'center'
    # lives
    s = @sprites.get("pacman_left_1")
    [x, y] = [24, HEIGHT - 4 - s.height()]
    for i in [0...@state.lives]
      s.draw ctx, x, y
      x += 20

canvas = document.getElementById 'canvas'
game = new Game(canvas)
