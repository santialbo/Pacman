from tornado import httpserver, websocket, ioloop, web
from uuid import uuid1
from random import shuffle
import threading, time
import os

def enum(**enums):
    return type('Enum', (), enums)

Direction = enum(NONE = 0, LEFT = 1, UP = 2, RIGHT = 3, DOWN = 4)

GhostMode = enum(NORMAL = 0, VULNERABLE = 1, DEAD = 2)
GhostColor = enum(RED = 0, BLUE = 1, ORANGE = 2, PINK = 3)

class Entity(object):

    def __init__(self, client):
        self.client = client
        self.position = (0.0, 0.0)
        self.moving = False
        self.speed = 10
        self.facing = Direction.NONE
        self.moving = Direction.NONE


class Pacman(Entity):

    def __init__(self, client):
        super(Pacman, self).__init__(client)

class Ghost(Entity):

    def __init__(self, client, color):
        self.mode = GhostMode.NORMAL
        self.color = color
        self.active = False
        super(Ghost, self).__init__(client)


class Level:
    cells = None

    def __init__(self, fname):
        with open(fname) as f:
            lines = f.readlines()


class Game(threading.Thread):

    def __init__(self, clients):
        self.server = server
        self.level = Level(os.path.join(os.path.dirname(__file__), 'level'))
        self.running = False
        self.assign_players(clients)
        super(Game, self).__init__()

    def assign_players(self, clients):
        shuffle(clients)
        self.entities = [Pacman(clients[0]),
                         Ghost(clients[1], GhostColor.RED),
                         Ghost(clients[2], GhostColor.BLUE),
                         Ghost(clients[3], GhostColor.ORANGE),
                         Ghost(clients[4], GhostColor.PINK)]

    def run(self):
        self.running = True
        while self.running:
            itime = time.time()
            if self.all_offline():
                self.running = False
                break
            print time.time()
            time.sleep(itime + 1 - time.time())

    def all_offline(self):
        actives = [ent.client.active for ent in self.entities]
        return not any(actives)        

class PacmanServer:
    _instance = None
    clients = {}
    waiting_queue = []
    games = {}

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(PacmanServer, cls).__new__(
                    cls, *args, **kwargs)
        return cls._instance

    def add_client(self, client):
        client.id = str(uuid1())
        print "new connection with id %s" % client.id
        self.clients[client.id] = client
        self.waiting_queue.append(client.id)
        client.write_message(client.id)
        self.check_players()

    def del_client(self, client):
        print 'connection closed %s' % client.id
        del self.clients[client.id]
        if client.id in self.waiting_queue:
            self.waiting_queue.remove(client.id)
            self.check_players()

    def message(self, id, message):
        print '%s -> %s' % (id, message)

    def check_players(self):
        num_players = len(self.waiting_queue)
        for id in self.waiting_queue:
            self.clients[id].write_message(str(num_players))
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
        pacman_server.message(self.id, message)

    def on_close(self):
        self.active = False
        pacman_server.del_client(self)


if __name__ == "__main__":
    app = web.Application([(r"/pacman/?", SocketHandler)])
    server = httpserver.HTTPServer(app)
    server.listen(8888)
    ioloop.IOLoop.instance().start()
