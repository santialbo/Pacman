spawn = (require 'child_process').spawn

to_stdio = (emitter) ->
    emitter.stdout.on 'data', (data) -> process.stdout.write data
    emitter.stderr.on 'data', (data) -> process.stderr.write data
    emitter

task 'build', 'Build game file', (options) ->
    to_stdio spawn 'coffee', ['--compile', 'pacman-client.coffee']
