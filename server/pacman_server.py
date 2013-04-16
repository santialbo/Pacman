from tornado import httpserver, websocket, ioloop, web
from uuid import uuid1
from random import shuffle
import json
import threading, time
import os

def enum(**enums):
    return type('Enum', (), enums)

Direction = enum(NONE = 0, LEFT = 1, UP = 2, RIGHT = 3, DOWN = 4)

GhostMode = enum(NORMAL = 0, VULNERABLE = 1, DEAD = 2)
GhostColor = enum(RED = 0, BLUE = 1, ORANGE = 2, PINK = 3)

class Entity(object):

    def __init__(self, client):
        self.key_state = {'left': None, 'up': None, 'right': None, 'down': None}
        self.is_pacman = False
        self.client = client
        self.position = (0.0, 0.0)
        self.moving = False
        self.speed = 7
        self.facing = Direction.NONE

    def round_position(self, dx=0, dy=0):
        x = int(round(self.position[0] + dx))
        y = int(round(self.position[1] + dy))
        return (x, y)

    def state(self):
        return {
            'id': self.client.id,
            'moving': self.moving,
            'position': self.position,
            'pacman': self.is_pacman,
            'facing': self.facing
        }


class Pacman(Entity):

    def __init__(self, client):
        super(Pacman, self).__init__(client)
        self.is_pacman = True

    def state(self):
        state = super(Pacman, self).state()
        return state
    

class Ghost(Entity):

    def __init__(self, client, color):
        super(Ghost, self).__init__(client)
        self.is_pacman = False
        self.mode = GhostMode.NORMAL
        self.color = color
        self.active = False
        self.just_eaten = False
        self.facing = Direction.NONE
    
    def state(self):
        state = super(Ghost, self).state()
        state['mode'] = self.mode
        state['color'] = self.color
        state['active'] = self.active
        state['justEaten'] = self.just_eaten
        return state


class Game(threading.Thread):

    def __init__(self, clients):
        self.server = server
        self.running = False
        self.dt = 1.0/30
        self.pill_time = 0
        self.lives = 3
        self.level = 1
        self.score = 0
        self.portals = {}
        self.pause_time = 0
        self.bonus = 100
        self.load_level(os.path.join(os.path.dirname(__file__), 'level'))
        self.assign_players(clients)
        super(Game, self).__init__()

    def load_level(self, file_name):
        with open(file_name) as f:
            lines = f.readlines()
        self.cells = [list(line[:-1]) for line in lines]
        # Find portals
        portals = [[] for i in range(10)]
        for i, line in enumerate(self.cells):
            for j, cell in enumerate(line):
                if cell.isdigit():
                    portals[int(cell)].append((j, i))
        for portal in portals:
            if portal:
                self.portals[portal[0]] = portal[1]
                self.portals[portal[1]] = portal[0]

    def player_by_id(self, id):
        for ent in self.entities:
            if ent.client.id == id:
                return ent
        return None

    def assign_players(self, clients):
        #shuffle(clients)
        self.entities = [Pacman(clients[0]),
                         Ghost(clients[1], GhostColor.RED),
                         Ghost(clients[2], GhostColor.BLUE),
                         Ghost(clients[3], GhostColor.ORANGE),
                         Ghost(clients[4], GhostColor.PINK)]

    def initialize_level(self):
        self.death = False
        self.running = True
        self.pacman().active = True
        self.pacman().facing = Direction.NONE
        self.entities[0].position = (15.5, 23)
        self.entities[1].position = (15.5, 11)
        self.entities[2].position = (14, 14)
        self.entities[3].position = (15.5, 14)
        self.entities[4].position = (17, 14)

    def publish(self, label, data = {}):
        for ent in self.entities:
            if ent.client.active:
                msg = {'label': label, 'data': data}
                ent.client.write_message(json.dumps(msg))

    def run(self):
        self.initialize_level()
        time.sleep(1.0) # give time before starting
        self.publish("ready")
        self.publish("gameState", self.game_state())
        time.sleep(2.0) # give time before starting
        self.publish("go")
        while self.running:
            if self.pause_time > 0:
                time.sleep(self.pause_time)
                self.pause_time = 0
                if self.death:
                    self.lives -= 1
                    break
            itime = time.time()
            if self.all_offline():
                self.running = False
                break
            self.update()
            time.sleep(itime + self.dt - time.time())
        if self.running:
            self.run()

    def update(self):
        self.check_pacman()
        if self.pill_time > 0:
            self.pill_time -= self.dt
            if self.pill_time <= 0:
                for ent in self.entities:
                    if not ent.is_pacman and ent.mode == GhostMode.VULNERABLE:
                        ent.mode = GhostMode.NORMAL
            
        for ent in self.entities:
            self.update_ent(ent)
        self.publish("gameState", self.game_state())

    def pacman(self):
        for ent in self.entities:
            if ent.is_pacman:
                return ent

    def ghosts(self):
        ghosts = []
        for ent in self.entities:
            if not ent.is_pacman:
                ghosts.append(ent)
        return ghosts

    def update_ent(self, ent):
        dirs = ["", "left", "up", "right", "down"]
        self.check_portal(ent)
        for i in range(1, 5):
            if ent.key_state[dirs[i]]:
                x, y = ent.round_position()
                if self.cells[y][x] == 's' or self.cells[y][x].isdigit():
                    # can't go back when accessing portal
                    continue
                if not ent.is_pacman and (i - ent.facing + 4) % 4 == 2:
                    # ghosts can't go back unless it's the only way
                    j = i - 2 if i > 2 else i + 2
                    left = j - 1 if j > 1 else 4
                    right = j + 1 if j < 4 else 1
                    if (self.can_go(ent, j) or
                        self.can_go(ent, left) or
                        self.can_go(ent, right)):
                        continue
                if self.can_go(ent, i):
                    ent.facing = i
                    break
        if ent.facing > 0:
            if self.can_go(ent, ent.facing):
                self.move(ent, ent.facing)
            else:
                ent.moving = False
                ent.position = ent.round_position()

    def check_portal(self, ent):
        ds = [[-1, 0], [0, -1], [1, 0], [0, 1]][ent.facing - 1]
        x, y = ent.round_position()
        if (x, y) in self.portals:
            dx = x - ent.position[0]
            dy = y - ent.position[1]
            if dx*ds[0] > 0 or dy*ds[1] > 0:
                ent.position = self.portals[(x, y)]

    def can_go(self, ent, direction):
        dx = [[-1, 0], [0, -1], [1, 0], [0, 1]][direction - 1]
        x, y = ent.round_position(dx[0], dx[1])
        return self.cells[y][x] != '#'
        
    def move(self, ent, direction):
        speed = ent.speed
        if not ent.is_pacman:
            if ent.mode == GhostMode.NORMAL:
                x, y = ent.round_position()
                if self.cells[y][x] == 's':
                    speed *= 0.6
            elif ent.mode == GhostMode.VULNERABLE:
                speed *= 0.8
            else:
                speed *= 2
        dx = [[-1, 0], [0, -1], [1, 0], [0, 1]][direction - 1]
        if dx[0] == 0:
            x = round(ent.position[0])
            y = ent.position[1] + dx[1]*speed*self.dt
        else:
            x = ent.position[0] + dx[0]*speed*self.dt
            y = round(ent.position[1])
        ent.position = (x, y)
        ent.moving = True

    def check_pacman(self):
        x, y = self.pacman().round_position()
        if self.cells[y][x] == 'o':
            self.cells[y][x] = ' '
            self.score += 10
        elif self.cells[y][x] == 'O':
            self.cells[y][x] = ' '
            self.score += 50
            self.set_ghost_vulnerable()

        for ghost in self.ghosts():
            ghost.just_eaten = False
            pp = self.pacman().position
            gp = ghost.position
            if abs(gp[0] - pp[0]) + abs(gp[1] - pp[1]) < 1.0:
                if ghost.mode == GhostMode.VULNERABLE:
                    ghost.mode = GhostMode.DEAD
                    ghost.just_eaten = True
                    self.pause_time = 1
                    self.bonus *= 2
                    self.score += self.bonus
                elif ghost.mode == GhostMode.NORMAL:
                    self.death = True
                    self.pause_time = 2

    def set_ghost_vulnerable(self):
        for ghost in self.ghosts():
            if ghost.mode == GhostMode.NORMAL:
                ghost.mode = GhostMode.VULNERABLE
        self.pill_time = 8.0
        self.bonus = 100

    def game_state(self):
        return {
            'level': self.cells,
            'score': self.score,
            'lives': self.lives,
            'players': [ent.state() for ent in self.entities],
            'pillTime': self.pill_time*1000,
            'pause': self.pause_time > 0,
            'bonus': self.bonus,
            'death': self.death,
         }

    def handle_message(self, id, message_string):
        message = json.loads(message_string)
        if message['label'] == 'keyEvent':
            self.player_by_id(id).key_state = message['data']

    def all_offline(self):
        actives = [ent.client.active for ent in self.entities]
        return not any(actives)        

class PacmanServer:
    clients = {}
    waiting_queue = []
    games = {}

    def add_client(self, client):
        client.id = str(uuid1())
        print "new connection with id %s" % client.id
        self.clients[client.id] = client
        self.waiting_queue.append(client.id)
        msg = json.dumps({'label': "id", 'data': client.id})
        client.write_message(msg)
        self.check_players()

    def del_client(self, client):
        print 'connection closed %s' % client.id
        del self.clients[client.id]
        if client.id in self.waiting_queue:
            self.waiting_queue.remove(client.id)
            self.check_players()

    def handle_message(self, id, message):
        self.games[id].handle_message(id, message)

    def check_players(self):
        num_players = len(self.waiting_queue)
        msg = json.dumps({'label': "numPlayers", 'data': num_players})
        for id in self.waiting_queue:
            self.clients[id].write_message(msg)
        if num_players == 5: # Start game
            players = self.waiting_queue[:5]
            self.waiting_queue = self.waiting_queue [5:]
            game = Game([self.clients[id] for id in players])
            for player in players:
                self.games[player] = game
            game.start()

pacman_server = PacmanServer()

class SocketHandler(websocket.WebSocketHandler):

    def open(self):
        self.active = True
        pacman_server.add_client(self)

    def on_message(self, message):
        pacman_server.handle_message(self.id, message)

    def on_close(self):
        self.active = False
        pacman_server.del_client(self)


if __name__ == "__main__":
    app = web.Application([(r"/pacman/?", SocketHandler)])
    server = httpserver.HTTPServer(app)
    server.listen(8888)
    ioloop.IOLoop.instance().start()
