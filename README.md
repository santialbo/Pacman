Pacman
======

A multiplayer version of the classic arcade

![Screenshot](https://raw.github.com/santialbo/Pacman/master/screenshots/screenshot000.png)
![Screenshot](https://raw.github.com/santialbo/Pacman/master/screenshots/screenshot002.png)
![Screenshot](https://raw.github.com/santialbo/Pacman/master/screenshots/screenshot001.png)

Installation
------------
In order to run the server there is some dependencies in `requirements.txt that need to be installed. You can do that by running the following command.
```bash
pip install -r requirements.txt
```

Playing on a local network
--------------------------
If you want to test the game on a local network, one computer needs to run the server. Check that computer's local ip by running:
```bash
# on a mac:
ifconfig | grep "inet " | grep -v 127.0.0.1 | cut -d\  -f2
# on a linux machine:
hostname -i | awk '{print $3}' # Ubuntu 
hostname -i # Debian
```
To run the server simply run
```bash
python server/pacman_server.py
```
You will also need to run the client on a HTTP server for the rest of people to connect to it. You can do that very easily by running the following commands:
```bash
cd client
python -m SimpleHTTPServer
```
Now people on the same local network will be able to connect by pointing their browser to `your_ip:8000`.
They will be prompted to write the ip to connect to. They have to write `your_ip:8888`.

Have fun :)
