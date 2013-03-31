from tornado import httpserver, websocket, ioloop, web

class GameServerHandler(websocket.WebSocketHandler):
    clients = {}

    def open(self):
        print 'new connection'
        self.write_message('hello world')

    def on_message(self, message):
        print 'message received %s' % message

    def on_close(self):
        print 'connection closed'

app = web.Application([
    (r"/pacman/?", GameServerHandler),
])

if __name__ == "__main__":
    server = httpserver.HTTPServer(app)
    server.listen(8888)
    ioloop.IOLoop.instance().start()
