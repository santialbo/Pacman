window.SCALE = 1
window.WIDTH = 4 + 224 + 4
window.HEIGHT = 4 + 22 + 248 + 20 + 4
window.FPS = 30
window.ROWS = 31
window.COLS = 32
window.SERVER = "ws://localhost:8888/pacman" 

class Sprite
  # Sprite contains a reference to the spritesheet and the necessary
  # information to draw the actual sprite
  constructor: (@name, @image, @info) ->
  
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

  get: (name) -> new Sprite(@name, @sprite, @info[name])


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

  constructor: (@name, @sprites, @times, @fps) ->
    rem_dt: @times[@times.length - 1]
  
  requestSprite: () ->
    dt = 1000/@fps
    if dt > @rem_dt
      @sprites.splice(0, 0, @sprites.pop())
      @times.splice(0, 0, @times.pop())
      @rem_dt += @times[@times.length - 1]
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
    new SpriteAnimation(name, sprites, @info[name].times.slice(), @fps)

class Game
  refTime: null
  connection: null
  interval: null
  sprites: null
  textWriter: null
  animations: null
  animationsPool: {}
  cells: null
  state: {}
  id: null
  identity: null
  
  constructor: (@canvas) ->
    @refTime = new Date().getTime()
    @setup()
  
  time: () -> new Date().getTime() - @refTime

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
    load "death"
    for d in ["left", "up", "right", "down"]
      load "pacman_" + d
      for c in ["red", "blue", "pink", "orange"]
        load "ghost_" + c + "_" + d
    load "ghost_dead_blue"
    load "ghost_dead_blue_white"
    for ent in ["pacman", "ghost_red", "ghost_blue", "ghost_orange", "ghost_pink"]
      @animationsPool[ent + "_left_aux"] = @animations.get ent + "_left"
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
    else if msg.label == "identity"
      @identity = msg.data
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
    @refTime = new Date().getTime()
    @state.running = false
    @interval = setInterval =>
        @update()
        @drawGame()
    , (1000/FPS)

  update: () =>
    if not @state.pause
      for player in @state.players
        if @canMove player
          @move player
      @state.timestamp = new Date().getTime()

  canMove: (player) =>
    dx = [[0, 0], [-1, 0], [0, -1], [1, 0], [0, 1]][player.facing]
    x = Math.round(player.position[0] + dx[0])
    y = Math.round(player.position[1] + dx[1])
    c = @cells[y][x]
    free_move = [' ', 'o', 'O', 's', '@']
    return c in free_move or (c >= '0' and c <= '9') or
           (c == '|' and not player.pacman and
            ((player.mode == 2 and player.facing == 4) or
             (player.mode == 0 and player.facing == 2)))

  move: (player) =>
    dt = new Date().getTime() - @state.timestamp
    speed = player.speed
    if not player.pacman
      if player.mode == 0
        [x, y] = [Math.round(player.position[0]), Math.round(player.position[1])]
        if @cells[y][x] == 's'
          speed *= 0.6
      else if player.mode == 1
        speed *= 0.8
      else if player.mode == 2
        speed *= 2
    dx = [[0, 0], [-1, 0], [0, -1], [1, 0], [0, 1]][player.facing]
    x = player.position[0] + dx[0]*speed*dt/1000
    y = player.position[1] + dx[1]*speed*dt/1000
    player.position = [x, y]

  gameMsg: (e) =>
    # Handler function for onmessage event
    msg = JSON.parse e.data
    if msg.label == "ready"
      @runGame()
    else if msg.label == "go"
      @state.running = true
      @refTime = new Date().getTime()
    else if msg.label == "gameState"
      @cells = msg.data["level"]
      things = ["players", "score", "lives", "pillTime", "pause", "bonus", "death"]
      if not @state.death and msg.data.death
        @refTime = new Date().getTime()
        @animationsPool["death"] = @animations.get "death"
      for thing in things
        @state[thing] = msg.data[thing]
      @state.timestamp = new Date().getTime()
    
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
    @drawPacman ctx
    @drawGhosts ctx
    @drawHUD ctx
    if not @state.running
      @textWriter.write ctx, "ready!", WIDTH/2, 166, "center"

  pacman: () ->
    (@state.players.filter (player) -> player.pacman)[0]

  ghosts: () ->
    @state.players.filter (player) -> not player.pacman

  me: () =>
    if @identity == 0 then @pacman()
    else (@ghosts().filter (ghost) => ghost.color == @identity - 1)[0]

  drawPacman: (ctx) ->
    d = ["left", "left", "up", "right", "down"]
    c = ["red", "blue", "orange", "pink"]
    pacman = @pacman()
    if @state.death 
      if @time() < 1000
        s = @sprites.get("pacman_" + d[pacman.facing] + "_1")
      else
        s = @animationsPool["death"].requestSprite()
    else if @state.pause
      s = @sprites.get("score_" + @state.bonus)
    else if pacman.facing == 0
      s = @sprites.get("pacman")
    else if pacman.moving
      s = @animationsPool["pacman_" + d[pacman.facing]].requestSprite()
    else
      s = @sprites.get("pacman_" + d[pacman.facing] + "_1")
    @drawSpriteInPosition ctx, s, pacman.position[0], pacman.position[1]

  drawGhosts: (ctx) ->
    if @state.death and @time() > 1000
      return
    d = ["left", "left", "up", "right", "down"]
    c = ["red", "blue", "orange", "pink"]
    first = true
    for ghost in @ghosts()
      if @state.pause and ghost.justEaten then continue
      if ghost.active
        if ghost.mode == 0 # NORMAL  
          name = "ghost_" + c[ghost.color] + "_" + d[ghost.facing]
          s = @animationsPool[name].requestSprite()
        else if ghost.mode == 1 # VULNERABLE
          a = "ghost_dead_blue"
          if @state.pillTime < 2800 then a = "ghost_dead_blue_white"
          if first
            s = @animationsPool[a].requestSprite()
            first = false
          else
            s = @animationsPool[a].peekSprite()
        else if ghost.mode == 2 # DEAD
          s = @sprites.get("eyes_" + d[ghost.facing])
        @drawSpriteInPosition ctx, s, ghost.position[0], ghost.position[1]
      else
        [a, b] = [500, 0.5]
        # YEAH MR. WHITE, SCIENCE!
        x = 13.6 + (ghost.color - 1)*(17.4 - 13.6)/2
        t = if @state.running then @time() else 0
        t += (ghost.color - 1)/2*a + a*1.25
        y = 14 + b*(2*Math.abs(2*(t/a - Math.floor(t/a + 0.5))) - 1)
        sign = (x) -> if x >= 0 then 1 else -1
        updown = ["up", "down"][Math.round((sign((t - a/2) % a - a/2))/2 + 0.5)]
        s = @animationsPool["ghost_" + c[ghost.color] + "_" + updown].requestSprite()
        @drawSpriteInPosition ctx, s, x, y



  drawSpriteInPosition: (ctx, s, x, y) ->
    [l, t, r, b] = [12, 12, 221, 244] # manually calibrated
    x = Math.round(4 + ( l+ (r - l)*(x - 3)/(COLS - 6)) - s.width()/2)
    y = Math.round(26 + (t + (b - t)*(y - 1)/(ROWS - 2)) - s.height()/2)
    s.draw ctx, x, y
      
  drawMaze: (ctx) ->
    ctx.fillStyle = '#000'
    ctx.fillRect 0, 0, WIDTH*SCALE, HEIGHT*SCALE
    @sprites.get("maze").draw ctx, 4, 26, SCALE

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
    # identity
    [x, y] = [WIDTH - 44, 4]
    @textWriter.write ctx, "you", x, y, 'center'
    y += 10
    @textWriter.write ctx, "are", x, y, 'center'
    [x, y] = [WIDTH - 24, 6]
    e = ["pacman", "ghost_red", "ghost_blue", "ghost_orange", "ghost_pink"][@identity]
    @animationsPool[e + "_left_aux"].requestSprite().draw ctx, x, y
    # lives
    s = @sprites.get("pacman_left_1")
    [x, y] = [24, HEIGHT - 4 - s.height()]
    for i in [0...@state.lives]
      s.draw ctx, x, y
      x += 20

canvas = document.getElementById 'canvas'
game = new Game(canvas)
