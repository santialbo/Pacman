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

    def __init__(self):
        self.pacman = Pacman()
        self.ghosts = [Ghost(), Ghost(), Ghost(), Ghost()]


class SocketHandler(websocket.WebSocketHandler):
    clients = {}
    waiting_clients = []
    running_games = []

    def open(self):
        self.id = str(uuid1())
        self.clients[self.id] = self
        self.waiting_clients.append(self.id)
        self.write_message(self.id)
        self.check_players()
        print "new connection with id %s" % self.id

    def on_message(self, message):
        print 'message received %s' % message

    def on_close(self):
        del self.clients[self.id]
        if self.id in self.waiting_clients:
            self.waiting_clients.remove(self.id)
            self.check_players()
        print 'connection closed %s' % self.id

    def check_players(self):
        num_players = len(self.waiting_clients)
        for id in self.waiting_clients:
            self.send_message(id, str(num_players))
        if num_players == 5:
            start_game()

    def start_game():
        players = self.waiting_clients[:5]
        self.waiting_clients = self.waiting_clients[5:]
        
    def send_message(self, id, msg):
        self.clients[id].write_message(msg)

app = web.Application([
    (r"/pacman/?", SocketHandler),
])

if __name__ == "__main__":
    server = httpserver.HTTPServer(app)
    server.listen(8888)
    ioloop.IOLoop.instance().start()
