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
        self.facing = Direction.NONE
    
    def state(self):
        state = super(Ghost, self).state()
        state['mode'] = self.mode
        state['color'] = self.color
        state['active'] = self.active
        return state


class Game(threading.Thread):

    def __init__(self, clients):
        self.server = server
        self.load_level(os.path.join(os.path.dirname(__file__), 'level'))
        self.running = False
        self.dt = 1.0/30
        self.pill_time = 0
        self.assign_players(clients)
        super(Game, self).__init__()

    def load_level(self, file_name):
        with open(file_name) as f:
            lines = f.readlines()
        self.cells = [list(line[:-1]) for line in lines]

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
        self.entities[2].position = (12, 14)
        self.entities[3].position = (13.5, 14)
        self.entities[4].position = (15, 14)

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
        if self.pill_time > 0:
            self.pill_time -= self.dt
            if self.pill_time <= 0:
                for ent in self.entities:
                    if not ent.is_pacman and ent.mode == GhostMode.VULNERABLE:
                        ent.mode = GhostMode.NORMAL
            
        for ent in self.entities:
            self.update_ent(ent)
        self.publish("gameState", self.game_state())

    def update_ent(self, ent):
        dirs = ["", "left", "up", "right", "down"]
        for i in range(1, 5):
            if ent.key_state[dirs[i]]:
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
                ent.position = (round(ent.position[0]), round(ent.position[1]))

    def can_go(self, ent, direction):
        dx = [[-1, 0], [0, -1], [1, 0], [0, 1]][direction - 1]
        x = int(round(ent.position[0] + dx[0]))
        y = int(round(ent.position[1] + dx[1]))
        return self.cells[y][x] != '#'
        
    def move(self, ent, direction):
        dx = [[-1, 0], [0, -1], [1, 0], [0, 1]][direction - 1]
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
        if self.cells[y][x] == 'o':
            self.cells[y][x] = ' '
            self.score += 10
        elif self.cells[y][x] == 'O':
            for ent in self.entities:
                if not ent.is_pacman and ent.mode == GhostMode.NORMAL:
                    ent.mode = GhostMode.VULNERABLE
            self.pill_time = 8.0
            self.cells[y][x] = ' '
            self.score += 50

    def game_state(self):
        return {
            'level': self.cells,
            'score': self.score,
            'players': [ent.state() for ent in self.entities],
            'pillTime': self.pill_time*1000,
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
