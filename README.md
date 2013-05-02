Pacman
======

A multiplayer version of the classic arcade. Try it online [here](http://ec2-54-244-207-36.us-west-2.compute.amazonaws.com/) (beware of the lag).

![Screenshot](https://raw.github.com/santialbo/Pacman/master/screenshots/screenshot000.png)
![Screenshot](https://raw.github.com/santialbo/Pacman/master/screenshots/screenshot002.png)
![Screenshot](https://raw.github.com/santialbo/Pacman/master/screenshots/screenshot001.png)

Installation
------------
In order to run the server there is some dependencies in `requirements.txt that need to be installed. You can do that by running the following command.
```bash
pip install -r requirements.txt
```

Running the server
--------------------------
To run the server simply run
```bash
python server/pacman_server.py
```
You will also need to run the client on a HTTP server for the rest of people to connect to it. If you want to test it locally you can run:
```bash
cd client
python -m SimpleHTTPServer
```
Now people on the same local network will be able to connect by pointing their browser to `your_ip:8000`.

Have fun :)
