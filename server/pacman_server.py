from tornado import httpserver, websocket, ioloop, web
from uuid import uuid1
from random import shuffle
from collections import defaultdict
import json
import threading, time
import os

def enum(**enums):
    return type('Enum', (), enums)

Direction = enum(NONE = 0, LEFT = 1, UP = 2, RIGHT = 3, DOWN = 4)

GhostMode = enum(NORMAL = 0, VULNERABLE = 1, DEAD = 2)
GhostColor = enum(RED = 0, BLUE = 1, ORANGE = 2, PINK = 3)

LEVEL_PATH = os.path.join(os.path.dirname(__file__), 'level')

class Entity(object):

    def __init__(self):
        self.key_state = {'left': None, 'up': None, 'right': None, 'down': None}
        self.is_pacman = False
        self.client = None
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
            'moving': self.moving,
            'position': self.position,
            'pacman': self.is_pacman,
            'facing': self.facing,
            'speed': self.speed
        }


class Pacman(Entity):

    def __init__(self):
        super(Pacman, self).__init__()
        self.is_pacman = True


class Ghost(Entity):

    def __init__(self, color):
        super(Ghost, self).__init__()
        self.is_pacman = False
        self.mode = GhostMode.NORMAL
        self.color = color
        self.active = False
        self.inactive_time = 0
        self.just_eaten = False

    def state(self):
        state = super(Ghost, self).state()
        state['mode'] = self.mode
        state['color'] = self.color
        state['active'] = self.active
        state['inactiveTime'] = self.inactive_time*1000
        state['justEaten'] = self.just_eaten
        return state


def load_level(level_path):
    with open(level_path) as f:
        lines = f.readlines()
    cells = [list(line.strip()) for line in lines]
    # Find portals
    portalmap = {}
    portals = defaultdict(list)
    for i, line in enumerate(cells):
        for j, cell in enumerate(line):
            if cell.isdigit():
                portals[int(cell)].append((j, i))
    for (p1, p2) in portals.values():
        portalmap[p1] = p2
        portalmap[p2] = p1
    return {"cells": cells, "portals": portalmap}


LEVELS = {1: {"map": load_level(LEVEL_PATH),
              "pacman_position": (15.5, 23),
              "ghost_position" : (15.5, 11)}}


class Game(threading.Thread):

    def __init__(self, clients):
        self.clients = clients
        self.running = False
        self.dt = 1.0/30
        self.pill_time = 0
        self.lives = 3
        self.level = 1
        self.score = [0, 0, 0, 0, 0]
        self.player_map = [0, 1, 2, 3, 4]
        shuffle(self.player_map)
        self.send_update = False
        self.pause_time = 0
        self.bonus = 100
        self.last_pill_eaten = None
        self.entities = [Pacman(), Ghost(GhostColor.RED), Ghost(GhostColor.BLUE),
                         Ghost(GhostColor.ORANGE), Ghost(GhostColor.PINK)]
        self.initialize_level(LEVELS[self.level])
        self.assign_player_numbers()
        super(Game, self).__init__()


    def player_by_id(self, id):
        for ent in self.entities:
            if ent.client.id == id:
                return ent
        return None

    def assign_player_numbers(self):
        for i, client in enumerate(self.clients):
            if client.active:
                msg = {'label': "playerNumber", 'data': i}
                client.write_message(json.dumps(msg))

    def assign_clients(self):
        for i, ent in enumerate(self.entities):
            ent.client = self.clients[self.player_map[i]]

    def send_identity(self):
        inverse = [0] * len(self.player_map)
        for i, p in enumerate(self.player_map):
            inverse[p] = i
        for i, client in enumerate(self.clients):
            if client.active:
                msg = {'label': "identity", 'data': inverse[i]}
                client.write_message(json.dumps(msg))

    def initialize_level(self, level):
        self.cells = level["map"]["cells"]
        self.portals = level["map"]["portals"]
        self.death = False
        pacman, ghosts = self.entities[0], self.entities[1:]
        pacman.facing = Direction.NONE
        pacman.position = level["pacman_position"]
        for ghost in ghosts:
            ghost.active = False
            ghost.facing = Direction.NONE
            ghost.position = level["ghost_position"]
        ghosts[0].active = True
        ghosts[1].inactive_time = 2.5
        ghosts[2].inactive_time = 1.5
        ghosts[3].inactive_time = 3.5

    def publish(self, label, data = {}):
        for ent in self.entities:
            if ent.client.active:
                msg = {'label': label, 'data': data}
                ent.client.write_message(json.dumps(msg))

    def send_game_state(self):
        self.publish("gameState", self.game_state())

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

    def run(self):
        self.initialize_level(LEVELS[self.level])
        self.assign_clients()
        self.send_identity()
        time.sleep(1) # give time before starting
        self.publish("ready")
        self.running = True
        self.send_game_state()
        time.sleep(2) # give time before starting
        self.publish("go")
        ticks_since_last_update = 0
        while self.running:
            if self.pause_time > 0:
                time.sleep(self.pause_time)
                self.pause_time = 0
                if self.death:
                    self.lives -= 1
                    break # to start again
            itime = time.time()
            # finish if all players are disconected
            if self.all_offline():
                self.running = False
                break
            # update and send updated game state if necessary
            self.update()
            ticks_since_last_update += 1
            if self.send_update or ticks_since_last_update > 10:
                self.send_update = False
                ticks_since_last_update = 0
                self.send_game_state()
            # sleep remaining time
            time.sleep(itime + self.dt - time.time())

        if self.lives == 0:
            self.lives == 3

        if self.running:
            self.run()

    def update(self):
        for ent in self.entities:
            if ent.is_pacman or ent.active:
                self.update_ent(ent)
        self.check_pacman()
        self.check_ghosts()
        self.check_ghost_pacman_collisions()
        if self.pill_time > 0:
            self.pill_time -= self.dt
            if self.pill_time <= 0:
                self.send_update = True
                for ent in self.entities:
                    if not ent.is_pacman and ent.mode == GhostMode.VULNERABLE:
                        ent.mode = GhostMode.NORMAL

    def update_ent(self, ent):
        dirs = ["", "left", "up", "right", "down"]
        self.check_portal(ent)
        valid_directions = set([i for i in range(1,5) if self.can_go(ent, i)])
        for i in valid_directions:
            if ent.key_state[dirs[i]]:
                x, y = ent.round_position()
                # The ghost is trying to go backwards. Allow only
                # if there are no other valid directions.
                if not ent.is_pacman and ent.mode == GhostMode.NORMAL \
                    and (i - ent.facing + 4) % 4 == 2 \
                    and len(valid_directions - {i}):
                    continue
                # Can't go back when accessing portal
                if self.cells[y][x] == 's' or self.cells[y][x].isdigit():
                    continue
                if ent.facing != i:
                    self.send_update = True
                    ent.facing = i
                break
        if ent.facing > 0:
            if ent.facing in valid_directions:
                self.move(ent, ent.facing)
            else:
                if ent.moving:
                    self.send_update = True
                    ent.moving = False
                ent.position = ent.round_position()

    def check_portal(self, ent):
        ds = [(-1, 0), (0, -1), (1, 0), (0, 1)][ent.facing - 1]
        x, y = ent.round_position()
        if (x, y) in self.portals:
            dx = x - ent.position[0]
            dy = y - ent.position[1]
            if dx*ds[0] > 0 or dy*ds[1] > 0:
                ent.position = self.portals[(x, y)]
                self.send_update = True

    def can_go(self, ent, direction):
        ds = [(-1, 0), (0, -1), (1, 0), (0, 1)][direction - 1]
        x, y = ent.round_position(*ds)
        try:
            c = self.cells[y][x]
        except IndexError, e:
            # The entity is trying to move off of the map.
            return False
        free_move = {' ', 'o', 'O', 's', '@'}
        return (c in free_move or c.isdigit() or
                (c == '|' and not ent.is_pacman and
                 ((ent.mode == GhostMode.DEAD and direction == Direction.DOWN) or
                  (ent.mode == GhostMode.NORMAL and direction == Direction.UP))))

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
        else:
            if self.last_pill_eaten:
                if time.time() - self.last_pill_eaten < 0.2:
                    speed *= 0.8
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
        x, y = self.entities[0].round_position()
        if self.cells[y][x] == 'o':
            self.last_pill_eaten = time.time()
            self.cells[y][x] = ' '
            self.score[self.player_map[0]] += 10
            self.send_update = True
        elif self.cells[y][x] == 'O':
            self.cells[y][x] = ' '
            self.score[self.player_map[0]] += 50
            self.send_update = True
            self.set_ghost_vulnerable()

    def check_ghosts(self):
        for ghost in self.entities[1:]:
            if ghost.mode == GhostMode.DEAD and self.in_spawn(ghost):
                ghost.mode = GhostMode.NORMAL
                ghost.position = (15.5, 11)
                ghost.active = False
                ghost.inactive_time = 0.5
            if not ghost.active:
                ghost.inactive_time -= self.dt
                if ghost.inactive_time < 0:
                    self.send_update = True
                    ghost.active = True

    def in_spawn(self, ent):
        x, y = ent.round_position()
        return self.cells[y][x] == '@'

    def check_ghost_pacman_collisions(self):
        for i, ghost in enumerate(self.entities[1:]):
            if not ghost.active:
                continue
            ghost.just_eaten = False
            pp, gp = self.entities[0].position, ghost.position
            if abs(gp[0] - pp[0]) + abs(gp[1] - pp[1]) < 1.0:
                if ghost.mode == GhostMode.VULNERABLE:
                    ghost.mode = GhostMode.DEAD
                    ghost.just_eaten = True
                    self.pause_time = 1
                    self.bonus *= 2
                    self.score[self.player_map[0]] += self.bonus
                    self.send_update = True
                elif ghost.mode == GhostMode.NORMAL:
                    self.death = True
                    self.pause_time = 2
                    self.send_update = True
                    self.score[self.player_map[i + 1]] += 500
                    aux = self.player_map[0]
                    self.player_map[0] = self.player_map[i + 1]
                    self.player_map[i + 1] = aux

    def set_ghost_vulnerable(self):
        for ghost in self.entities[1:]:
            if ghost.mode == GhostMode.NORMAL:
                ghost.mode = GhostMode.VULNERABLE
        self.pill_time = 8.0
        self.bonus = 100

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
