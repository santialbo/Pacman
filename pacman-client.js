// Generated by CoffeeScript 1.6.2
(function() {
  var Game, Level, Sprite, SpriteAnimation, SpriteAnimationDict, SpriteDict, SpriteTextDrawer, canvas, game,
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

  Sprite = (function() {
    function Sprite(image, info, scale) {
      this.image = image;
      this.info = info;
      this.scale = scale;
    }

    Sprite.prototype.width = function() {
      return this.info.sourceSize.w;
    };

    Sprite.prototype.height = function() {
      return this.info.sourceSize.h;
    };

    Sprite.prototype.draw = function(ctx, x, y) {
      x += this.info.spriteSourceSize.x;
      y += this.info.spriteSourceSize.y;
      return ctx.drawImage(this.image, this.info.frame.x, this.info.frame.y, this.info.frame.w, this.info.frame.h, x * this.scale, y * this.scale, this.info.frame.w * this.scale, this.info.frame.h * this.scale);
    };

    return Sprite;

  })();

  SpriteDict = (function() {
    SpriteDict.prototype.sprite = null;

    SpriteDict.prototype.info = null;

    SpriteDict.prototype.scale = 1;

    SpriteDict.prototype.setScale = function(scale) {
      this.scale = scale;
    };

    function SpriteDict(spriteFile, infoFile, callback) {
      var _this = this;

      this.sprite = new Image();
      this.sprite.src = spriteFile;
      $.getJSON(infoFile, function(json) {
        _this.info = json;
        return callback();
      });
    }

    SpriteDict.prototype.get = function(name) {
      return new Sprite(this.sprite, this.info[name], this.scale);
    };

    return SpriteDict;

  })();

  SpriteTextDrawer = (function() {
    function SpriteTextDrawer(spriteDict) {
      this.spriteDict = spriteDict;
    }

    SpriteTextDrawer.prototype.drawText = function(ctx, text, x, y, align) {
      var sprite, sprites, width, _i, _len, _results,
        _this = this;

      sprites = (text.split("")).map(function(letter) {
        if (letter === '.') {
          return _this.spriteDict.get("dot");
        } else {
          return _this.spriteDict.get(letter);
        }
      });
      if (align !== "left") {
        width = (sprites.map(function(s) {
          return s.width();
        })).reduce(function(x, y) {
          return x + y;
        });
        if (align === "center") {
          x -= width / 2;
        } else {
          x -= width;
        }
      }
      _results = [];
      for (_i = 0, _len = sprites.length; _i < _len; _i++) {
        sprite = sprites[_i];
        sprite.draw(ctx, x, y);
        _results.push(x += sprite.width());
      }
      return _results;
    };

    return SpriteTextDrawer;

  })();

  Level = (function() {
    Level.prototype.entities = null;

    Level.prototype.cells = null;

    function Level(filename, callback) {
      var _this = this;

      $.get(filename, function(data) {
        _this.cells = (data.split("\n")).map(function(row) {
          return row.split("");
        });
        return callback();
      });
    }

    return Level;

  })();

  SpriteAnimation = (function() {
    SpriteAnimation.prototype.dt = 0;

    function SpriteAnimation(sprites, times, fps) {
      this.sprites = sprites;
      this.times = times;
      this.fps = fps;
    }

    SpriteAnimation.prototype.requestSprite = function() {
      var dt;

      dt = 1000 / this.fps;
      if (dt > this.dt) {
        this.sprites.splice(0, 0, this.sprites.pop());
        this.dt = this.times.pop();
        this.times.splice(0, 0, this.dt);
        return this.requestSprite(dt - this.dt);
      } else {
        this.dt -= dt;
        return this.sprites[this.sprites.length - 1];
      }
    };

    return SpriteAnimation;

  })();

  SpriteAnimationDict = (function() {
    SpriteAnimationDict.prototype.info = null;

    function SpriteAnimationDict(spriteDict, fileName, fps, callback) {
      var _this = this;

      this.spriteDict = spriteDict;
      this.fps = fps;
      $.getJSON(fileName, function(json) {
        _this.info = json;
        return callback();
      });
    }

    SpriteAnimationDict.prototype.get = function(name) {
      var sprites,
        _this = this;

      sprites = this.info[name].sprites.map(function(sprite_name) {
        return _this.spriteDict.get(sprite_name);
      });
      return new SpriteAnimation(sprites, this.info[name].times, this.fps);
    };

    return SpriteAnimationDict;

  })();

  Game = (function() {
    Game.prototype.SCALE = 2;

    Game.prototype.WIDTH = 232;

    Game.prototype.HEIGHT = 40 + 248 + 20;

    Game.prototype.FPS = 30;

    Game.prototype.SERVER = "ws://localhost:8888/pacman";

    Game.prototype.initialTime = null;

    Game.prototype.connection = null;

    Game.prototype.interval = null;

    Game.prototype.sprites = null;

    Game.prototype.animations = null;

    Game.prototype.animationsPool = {};

    Game.prototype.level = null;

    Game.prototype.state = {};

    Game.prototype.id = null;

    function Game(canvas) {
      this.canvas = canvas;
      this.runGame = __bind(this.runGame, this);
      this.drawWaitingRoom = __bind(this.drawWaitingRoom, this);
      this.updateWaitingRoom = __bind(this.updateWaitingRoom, this);
      this.runWaitingRoom = __bind(this.runWaitingRoom, this);
      this.createEntities = __bind(this.createEntities, this);
      this.loadAnimations = __bind(this.loadAnimations, this);
      this.loadSprites = __bind(this.loadSprites, this);
      this.initialTime = new Date().getTime();
      this.setup();
    }

    Game.prototype.time = function() {
      return new Date().getTime() - this.initialTime;
    };

    Game.prototype.setup = function() {
      this.canvas.height = this.HEIGHT * this.SCALE;
      this.canvas.width = this.WIDTH * this.SCALE;
      return this.loadLevel();
    };

    Game.prototype.loadLevel = function() {
      return this.level = new Level('res/level', this.loadSprites);
    };

    Game.prototype.loadSprites = function() {
      this.sprites = new SpriteDict('res/sprites.png', 'res/sprites.json', this.loadAnimations);
      return this.sprites.setScale(this.SCALE);
    };

    Game.prototype.loadAnimations = function() {
      return this.animations = new SpriteAnimationDict(this.sprites, 'res/animations.json', this.FPS, this.createEntities);
    };

    Game.prototype.createEntities = function() {
      return this.connect();
    };

    Game.prototype.connect = function() {
      this.connection = new WebSocket(this.SERVER);
      this.connection.onmessage = this.updateWaitingRoom;
      return this.connection.onopen = this.runWaitingRoom;
    };

    Game.prototype.runWaitingRoom = function() {
      var color, i, _i, _j, _len, _ref,
        _this = this;

      this.animationsPool["pacman_right"] = this.animations.get("pacman_right");
      this.animationsPool["pacman_left"] = this.animations.get("pacman_left");
      _ref = ["red", "blue", "pink", "orange"];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        color = _ref[_i];
        this.animationsPool["ghost_" + color + "_right"] = this.animations.get("ghost_" + color + "_right");
      }
      for (i = _j = 0; _j < 4; i = ++_j) {
        this.animationsPool["ghost_dead_blue_" + i] = this.animations.get("ghost_dead_blue");
      }
      return this.interval = setInterval(function() {
        return _this.drawWaitingRoom();
      }, 1000 / this.FPS);
    };

    Game.prototype.updateWaitingRoom = function(e) {
      if (this.id === null) {
        this.id = e.data;
        return this.state.players = 1;
      } else if (e.data === "5") {
        return this.runGame();
      } else {
        return this.state.players = parseInt(e.data);
      }
    };

    Game.prototype.drawWaitingRoom = function() {
      var color, ctx, i, s, t, x, y, _i, _j, _len, _ref;

      ctx = this.canvas.getContext('2d');
      ctx.fillRect(0, 0, this.WIDTH * this.SCALE, this.HEIGHT * this.SCALE);
      s = this.sprites.get("title");
      y = 60;
      s.draw(ctx, this.WIDTH / 2 - s.width() / 2, y);
      y += s.height() + 10;
      t = new SpriteTextDrawer(this.sprites);
      t.drawText(ctx, "waiting for players", this.WIDTH / 2, y, "center");
      if (this.time() % 2000 < 1200) {
        y += 20;
        t.drawText(ctx, this.state.players + " of 5", this.WIDTH / 2, y, "center");
      }
      y = 200;
      x = -10 + (this.time() % 10000) / 3000 * (this.WIDTH + 20);
      this.animationsPool["pacman_right"].requestSprite().draw(ctx, x, y);
      x -= 60;
      _ref = ["red", "blue", "pink", "orange"];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        color = _ref[_i];
        this.animationsPool["ghost_" + color + "_right"].requestSprite().draw(ctx, x, y);
        x -= 18;
      }
      x = (7800 - this.time() % 10000) / 3000 * (this.WIDTH + 20);
      for (i = _j = 0; _j < 4; i = ++_j) {
        this.animationsPool["ghost_dead_blue_" + i].requestSprite().draw(ctx, x, y);
        x += 18;
      }
      x += 60;
      return this.animationsPool["pacman_left"].requestSprite().draw(ctx, x, y);
    };

    Game.prototype.runGame = function() {
      var _this = this;

      clearInterval(this.interval);
      return this.interval = setInterval(function() {
        _this.update();
        return _this.drawGame();
      }, 1000 / this.FPS);
    };

    Game.prototype.update = function() {};

    Game.prototype.drawGame = function() {
      var ctx;

      ctx = this.canvas.getContext('2d');
      this.drawMaze(ctx);
      return this.drawCookies(ctx);
    };

    Game.prototype.drawMaze = function(ctx) {
      var s;

      ctx.fillStyle = '#000';
      ctx.fillRect(0, 0, this.WIDTH * this.SCALE, this.HEIGHT * this.SCALE);
      s = this.sprites.get("maze");
      return s.draw(ctx, 4, 40, this.SCALE);
    };

    Game.prototype.drawCookies = function(ctx) {
      var b, cols, i, j, l, p, r, rows, s, t, _i, _results;

      s = this.sprites.get("cookie");
      p = this.sprites.get("pill");
      l = 4;
      t = 5;
      b = 252;
      r = 221;
      rows = this.level.cells.length;
      cols = this.level.cells[0].length;
      _results = [];
      for (i = _i = 0; _i < rows; i = _i += 1) {
        _results.push((function() {
          var _j, _results1;

          _results1 = [];
          for (j = _j = 0; _j < cols; j = _j += 1) {
            if (this.level.cells[i][j] === "o") {
              _results1.push(s.draw(ctx, 4 + (l + (r - l) * j / (cols - 1)), 40 + (t + (b - t) * i / (rows - 1))));
            } else if (this.level.cells[i][j] === "O") {
              _results1.push(p.draw(ctx, 4 + (l + (r - l) * j / (cols - 1)), 40 + (t + (b - t) * i / (rows - 1))));
            } else {
              _results1.push(void 0);
            }
          }
          return _results1;
        }).call(this));
      }
      return _results;
    };

    return Game;

  })();

  canvas = document.getElementById('canvas');

  game = new Game(canvas);

}).call(this);
