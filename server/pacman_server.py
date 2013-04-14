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
        self.speed = 10
        self.facing = Direction.NONE

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
        self.facing = Direction.UP
    
    def state(self):
        state = super(Ghost, self).state()
        state['mode'] = self.mode
        state['color'] = self.color
        state['active'] = self.active
        return state


class Level:

    def __init__(self, fname):
        with open(fname) as f:
            lines = f.readlines()
        self.cells = [list(line[:-1]) for line in lines]


class Game(threading.Thread):

    def __init__(self, clients):
        self.server = server
        self.level = Level(os.path.join(os.path.dirname(__file__), 'level'))
        self.running = False
        self.dt = 1.0/30
        self.assign_players(clients)
        super(Game, self).__init__()

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

    def first_level(self):
        self.score = 0

    def initialize_level(self):
        self.entities[0].position = (13.5, 23)
        self.entities[1].active = True
        self.entities[1].position = (13.5, 11)

    def publish(self, label, data = {}):
        for ent in self.entities:
            if ent.client.active:
                msg = {'label': label, 'data': data}
                ent.client.write_message(json.dumps(msg))

    def run(self):
        time.sleep(1.0) # give time before starting
        self.running = True
        self.first_level()
        self.initialize_level()
        self.publish("ready")
        self.publish("gameState", self.game_state())
        time.sleep(2.0) # give time before starting
        self.publish("go")
        while self.running:
            itime = time.time()
            if self.all_offline():
                self.running = False
                break
            self.update()
            time.sleep(itime + self.dt - time.time())

    def update(self):
        self.check_pacman()
        for ent in self.entities:
            self.update_ent(ent)
        self.publish("gameState", self.game_state())

    def update_ent(self, ent):
        dirs = ["left", "up", "right", "down"]
        dx = [[-1, 0], [0, -1], [1, 0], [0, 1]]
        for i in range(4):
            if ent.key_state[dirs[i]]:
                if not ent.is_pacman and (i + 1 - ent.facing + 4) % 4 == 2:
                    # ghosts can't go back
                    continue
                x = int(round(ent.position[0] + dx[i][0]))
                y = int(round(ent.position[1] + dx[i][1]))
                if self.level.cells[y][x] != '#':
                    ent.facing = i + 1
                    break
        if ent.facing > 0:
            x = int(round(ent.position[0] + dx[ent.facing - 1][0]))
            y = int(round(ent.position[1] + dx[ent.facing - 1][1]))
            if self.level.cells[y][x] != '#':
                self.move(ent, dx[ent.facing - 1])
            else:
                ent.moving = False
                ent.position = (round(ent.position[0]), round(ent.position[1]))
        
    def move(self, ent, dx):
        if dx[0] == 0:
            x = round(ent.position[0])
            y = ent.position[1] + dx[1]*ent.speed*self.dt
        else:
            x = ent.position[0] + dx[0]*ent.speed*self.dt
            y = round(ent.position[1])
        ent.position = (x, y)
        ent.moving = True

    def check_pacman(self):
        pacman = self.entities[0]
        x = int(round(pacman.position[0]))
        y = int(round(pacman.position[1]))
        if self.level.cells[y][x] == 'o':
            self.level.cells[y][x] = ' '
            self.score += 10
        elif self.level.cells[y][x] == 'O':
            self.level.cells[y][x] = ' '
            self.score += 50

    def game_state(self):
        return {
            'level': self.level.cells,
            'score': self.score,
            'players': [ent.state() for ent in self.entities]
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
