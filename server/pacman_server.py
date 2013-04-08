from tornado import httpserver, websocket, ioloop, web
from uuid import uuid1

class Entity:
    def __init__(self):
        self.position = (0, 0)
        self.facing = 0
        self.moving = False


class Pacman(Entity):
    def __init__(self):
        return


class Ghost(Entity):

    def __init__(self):
        self.vulnerable = False
        self.alive = False


class Level:
    cells = None

    def __init__(self, fname):
        with open(fname) as f:
            lines = f.readlines()
        self.cells = [list(line[:-1]) for line in lines]


class Game:

    def __init__(self, players, server):
        self.pacman = Pacman()
        self.ghosts = [Ghost(), Ghost(), Ghost(), Ghost()]


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

    def check_players(self):
        num_players = len(self.waiting_queue)
        for id in self.waiting_queue:
            self.clients[id].write_message(str(num_players))
        if num_players == 5: # Start game
            players = self.waiting_queue[:5]
            self.waiting_queue = self.waiting_queue [5:]
            game = Game(players, self)
            for player in players:
                self.games[player] = game

pacman_server = PacmanServer()

class SocketHandler(websocket.WebSocketHandler):

    def open(self):
        pacman_server.add_client(self)

    def on_message(self, message):
        print '%s -> %s' % (self.id, message)

    def on_close(self):
        pacman_server.del_client(self)


if __name__ == "__main__":
    app = web.Application([(r"/pacman/?", SocketHandler)])
    server = httpserver.HTTPServer(app)
    server.listen(8888)
    ioloop.IOLoop.instance().start()
