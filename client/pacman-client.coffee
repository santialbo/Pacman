class Sprite
  # Sprite contains a reference to the spritesheet and the necessary
  # information to draw the actual sprite
  constructor: (@name, @image, @info, @scale) ->
  
  width: () -> @info.sourceSize.w
  height: () -> @info.sourceSize.h

  draw: (ctx, x, y) ->
    x += @info.spriteSourceSize.x
    y += @info.spriteSourceSize.y
    ctx.drawImage @image, @info.frame.x, @info.frame.y, @info.frame.w, @info.frame.h,
      x*@scale, y*@scale, @info.frame.w*@scale, @info.frame.h*@scale


class SpriteDict
  # SpriteDict is a dictionary with all the sprites in the sprites json file.
  # It avoids the creation of multiple image objects by having only one.
  sprite: null
  info: null
  
  constructor: (spriteFile, infoFile, @scale, callback) ->
    @sprite = new Image()
    @sprite.src = spriteFile
    $.getJSON infoFile, (json) => @info = json; callback()

  get: (name) -> new Sprite(@name, @sprite, @info[name], @scale)


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
  playerNumber: null
  
  constructor: (@canvas, @gw, @server) ->
    @refTime = new Date().getTime()
    @setup()
  
  time: () -> new Date().getTime() - @refTime

  setup: () ->
    @canvas.height = @gw.height*@gw.scale
    @canvas.width = @gw.width*@gw.scale
    @loadLevel()
    
  loadLevel: () ->
    $.get 'res/level', (data) =>
      @cells = (data.split "\n").map (row) -> row.split ""
      @cells.pop()
      @loadSprites()

  loadSprites: () =>
    @sprites =
      new SpriteDict 'res/sprites.png', 'res/sprites.json', @gw.scale, @loadAnimations

  loadAnimations: () =>
    @animations =
      new AnimationDict @sprites, 'res/animations.json', @gw.fps, @createObjects

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
    @connection = new WebSocket(@server)
    @connection.onmessage = @waitingRoomMsg
    @connection.onopen = @runWaitingRoom

  send: (description, obj) =>
    # Sends object message to the server
    @connection.send(JSON.stringify {label: description, data: obj})
    
  ############### Waiting screen ###############

  runWaitingRoom: () =>
    @interval = setInterval @drawWaitingRoom, (1000/@gw.fps)

  waitingRoomMsg: (e) =>
    msg = JSON.parse(e.data)
    if msg.label == "id"
      @id = msg.data
    else if msg.label == "identity"
      @identity = msg.data
    else if msg.label == "playerNumber"
      @playerNumber = msg.data
    else if msg.label == "numPlayers"
      @state.players = msg.data
    else if msg.label == "ready"
      @runGame()

  clearCanvas: (ctx) =>
    ctx.fillStyle = 'rgb(0,0,0)'
    ctx.fillRect 0, 0, @gw.width*@gw.scale, @gw.height*@gw.scale

  drawWaitingRoom: () =>
    ctx = @canvas.getContext '2d'
    @clearCanvas ctx
    s = @sprites.get("title")
    y = 60
    s.draw ctx, @gw.width/2-s.width()/2, y
    y += s.height()+ 10
    @textWriter.write ctx, "waiting for players", @gw.width/2, y , "center"
    y += 20
    if @time()%2000 < 1200
      @textWriter.write ctx, @state.players + " of 5", @gw.width/2, y, "center"

    # Going right
    y = 200
    x = -10 + (@time()%10000)/3000*(@gw.width + 20)
    @animationsPool["pacman_right"].requestSprite().draw ctx, x, y
    x -= 60
    for color in ["red", "blue", "pink", "orange"]
      @animationsPool["ghost_" + color + "_right"].requestSprite().draw ctx, x, y
      x -= 18

    # Going left
    x = (7800 - @time()%10000)/3000*(@gw.width+20)
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
    , (1000/@gw.fps)

  update: () =>
    if not @state.pause
      for player in @state.players
        if @canMove player
          @move player
        if @state.running and not player.pacman and not player.active
          player.inactiveTime -= 1000/@gw.fps
          if player.inactiveTime < 0
            player.active
            player.position = [15.5, 11]
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
    else
      [x, y] = [Math.round(player.position[0]), Math.round(player.position[1])]
      if @cells[y][x] == 'o' or @time() - @last_pill_time < 200
        @last_pill_time = @time()
        speed *= 0.8
    dx = [[0, 0], [-1, 0], [0, -1], [1, 0], [0, 1]][player.facing]
    x = player.position[0] + dx[0]*speed*dt/1000
    y = player.position[1] + dx[1]*speed*dt/1000
    player.position = [x, y]

  gameMsg: (e) =>
    # Handler function for onmessage event
    msg = JSON.parse e.data
    if msg.label == "ready"
      @runGame()
    else if msg.label == "identity"
      @identity = msg.data
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
    @drawMask ctx
    @drawHUD ctx

  pacman: () ->
    (@state.players.filter (player) -> player.pacman)[0]

  ghosts: () ->
    @state.players.filter (player) -> not player.pacman

  me: () =>
    @state.players[@identity]

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
        sign = (x) -> if x >= 0 then 1 else -1
        [x0, dx] = [15.5, 1.9]
        t = if @state.running then @time() else 0
        t += (ghost.color - 1)/2*a + a*1.25
        if ghost.inactiveTime > 1000
          x = x0 + (ghost.color - 2)*dx
          y = 14 + b*(2*Math.abs(2*(t/a - Math.floor(t/a + 0.5))) - 1)
          dir = ["up", "down"][Math.round((sign((t - a/2) % a - a/2))/2 + 0.5)]
        else if ghost.inactiveTime > 500
          x = x0 + (ghost.color - 2)*dx*(Math.max(ghost.inactiveTime - 500, 0)/500)
          y = 14
          dir = ["right", "left"][Math.round(sign(ghost.color - 2)/2 + 0.5)]
        else
          x = x0
          y = 11 + (ghost.inactiveTime/500)*3*(ghost.inactiveTime > 0)
          dir = "up"
        s = @animationsPool["ghost_" + c[ghost.color] + "_" + dir].requestSprite()
        @drawSpriteInPosition ctx, s, x, y

  coordinateFromPosition: (x, y) ->
    [l, t, r, b] = [12, 12, 221, 244] # manually calibrated
    x = Math.round(4 + ( l+ (r - l)*(x - 3)/(@gw.cols - 6)))
    y = Math.round(26 + (t + (b - t)*(y - 1)/(@gw.rows - 2)))
    return [x, y]

  drawSpriteInPosition: (ctx, s, x, y) ->
    [x, y] = @coordinateFromPosition x, y
    s.draw ctx, x - Math.round(s.width()/2), y - Math.round(s.height()/2)
      
  drawMaze: (ctx) ->
    ctx.fillStyle = '#000'
    ctx.fillRect 0, 0, @gw.width*@gw.scale, @gw.height*@gw.scale
    @sprites.get("maze").draw ctx, 4, 26, @gw.scale

  drawCookies: (ctx) ->
    s = @sprites.get("cookie")
    if @state.running
      p = @animationsPool["pill"].requestSprite()
    else
      p = @sprites.get("pill")

    for y in [1...@gw.rows - 1] by 1
      for x in [3...@gw.cols - 3] by 1
        if @cells[y][x] == "o"
          @drawSpriteInPosition ctx, s, x, y
        else if @cells[y][x] == "O"
          @drawSpriteInPosition ctx, p, x, y

  drawMask: (ctx) ->
    visionRadius = 50*@gw.scale
    if @identity > 0
      [x, y] = @me().position
      [x, y] = @coordinateFromPosition x, y
      mask = document.createElement 'canvas'
      mask.width = @canvas.width
      mask.height = @canvas.height
      ctx2 = mask.getContext '2d'
      if not @state.running
        alpha = Math.min(@time()/1000, 1)
      else if @state.death
        alpha = (1 - @time()/1000)*(@time() < 1000)
      else
        alpha = 1
      @clearCanvas ctx2
      ctx2.globalCompositeOperation = 'xor'
      ctx2.arc x*@gw.scale, y*@gw.scale, visionRadius, 0, Math.PI*2
      ctx2.arc x*@gw.scale - @gw.width*@gw.scale - 12, y, visionRadius, 0, Math.PI*2
      ctx2.arc x*@gw.scale + @gw.width*@gw.scale + 12, y, visionRadius, 0, Math.PI*2
      ctx2.fill()
      imageData = ctx2.getImageData(0, 0, mask.width, mask.height)
      for i in [0...imageData.data.length]
        if i % 4 == 3
          imageData.data[i] = if imageData.data[i] > 0 then Math.round(alpha*255) else 0
      ctx2.putImageData imageData, 0, 0
      ctx.drawImage mask, 0, 0
  
  drawHUD: (ctx) ->
    # scores
    dx = 45
    x = @gw.width/2 - dx*2
    for i in [0...5]
      y = 4
      if @time()%500 < 250
        @textWriter.write ctx, (i + 1) + "up", x, y, 'center'
      y += 10
      @textWriter.write ctx, (@state.score[i] + ""), x, y, 'center'
      x += dx
    if not @state.running
      @textWriter.write ctx, "ready!", @gw.width/2, 162, "center"

    # identity
    [x, y] = [@gw.width - 70, @gw.height - @gw.margin - @gw.bottomMargin + 3]
    @textWriter.write ctx, "you are", x, y, 'center'
    y += 10
    @textWriter.write ctx, "player " + (@playerNumber + 1), x, y, 'center'
    e = ["pacman", "ghost_red", "ghost_blue", "ghost_orange", "ghost_pink"][@identity]
    s = @animationsPool[e + "_left_aux"].requestSprite()
    [x, y] = [@gw.width - 24, @gw.height - @gw.margin - s.height()]
    s.draw ctx, x, y

    # lives
    s = @sprites.get("pacman_left_1")
    [x, y] = [24, @gw.height - @gw.margin - s.height()]
    for i in [0...@state.lives]
      s.draw ctx, x, y
      x += 20


canvas = document.getElementById 'canvas'
gameWindowInfo = {
  'scale': 1,
  'mazeWidth': 224,
  'mazeHeight': 248,
  'margin': 4,
  'topMargin': 22,
  'bottomMargin': 20,
  'height': 4 + 22 + 248 + 20 + 4,
  'width': 4 + 224 + 4,
  'fps': 30,
  'rows': 31,
  'cols': 32,
  }
ip = null
while ip == null
  ip = window.prompt("Please, specify server ip.", "localhost:8888");
server = "ws://" + ip + "/pacman"
game = new Game(canvas, gameWindowInfo, server)
