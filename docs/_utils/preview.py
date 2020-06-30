from livereload import Server, shell
server = Server()
server.watch('**/*.rst', shell('make'))
server.watch('*.md', shell('make'))
server.serve(host='localhost', root='_build/dirhtml')
