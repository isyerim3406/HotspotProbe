#!/var/jb/usr/bin/python3
"""Standalone rootless SOCKS5/HTTP proxy; no misd/wifid hooks."""
import ipaddress,select,socket,socketserver,struct,threading,urllib.parse,logging
logging.basicConfig(level=logging.INFO)
def permit(peer):
 try:
  x=ipaddress.ip_address(peer[0]);return x.is_loopback or x in ipaddress.ip_network("172.20.10.0/24")
 except ValueError:return False
def relay(a,b):
 a.settimeout(None);b.settimeout(None)
 try:
  while True:
   ready,_,_=select.select((a,b),(),(),120)
   if not ready:return
   for src in ready:
    data=src.recv(65536)
    if not data:return
    (b if src is a else a).sendall(data)
 except OSError:pass
class Server(socketserver.ThreadingMixIn,socketserver.TCPServer):
 allow_reuse_address=True
 daemon_threads=True
class Handler(socketserver.BaseRequestHandler):
 def getn(self,n):
  out=b""
  while len(out)<n:
   v=self.request.recv(n-len(out))
   if not v:raise OSError("closed")
   out+=v
  return out
 def handle(self):
  if not permit(self.client_address):return
  c=self.request;c.settimeout(15)
  try:
   if self.server.server_address[1]==9876:
    ver,n=self.getn(2)
    if ver!=5 or 0 not in self.getn(n):return
    c.sendall(b"\x05\x00")
    ver,cmd,_,kind=self.getn(4)
    if ver!=5 or cmd!=1:return
    if kind==1:host=socket.inet_ntop(socket.AF_INET,self.getn(4))
    elif kind==4:host=socket.inet_ntop(socket.AF_INET6,self.getn(16))
    elif kind==3:host=self.getn(self.getn(1)[0]).decode("idna")
    else:return
    port=struct.unpack("!H",self.getn(2))[0]
    with socket.create_connection((host,port),12) as s:
     c.sendall(b"\x05\x00\x00\x01"+b"\0"*6);relay(c,s)
   else:
    request=b""
    while b"\r\n\r\n" not in request and len(request)<65536:
     block=c.recv(4096)
     if not block:return
     request+=block
    hdr,_,tail=request.partition(b"\r\n\r\n")
    lines=hdr.split(b"\r\n")
    method,target,version=lines[0].decode("latin1").split(" ",2)
    if method.upper()=="CONNECT":
     if target.startswith("["):
      host,port=target.rsplit("]:",1);host=host[1:]
     else:host,port=target.rsplit(":",1)
     with socket.create_connection((host,int(port)),12) as s:
      c.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
      if tail:s.sendall(tail)
      relay(c,s)
    else:
     u=urllib.parse.urlsplit(target)
     if u.scheme!="http" or not u.hostname:return
     path=urllib.parse.urlunsplit(("","",u.path or "/",u.query,""))
     headers=[h for h in lines[1:] if not h.lower().startswith((b"connection:",b"proxy-connection:"))]
     payload=(f"{method} {path} {version}\r\n".encode()+b"\r\n".join(headers)+b"\r\nConnection: close\r\n\r\n"+tail)
     with socket.create_connection((u.hostname,u.port or 80),12) as s:
      s.sendall(payload);relay(c,s)
  except (OSError,ValueError,UnicodeError):
   pass
def main():
 for port in (9876,9877):
  srv=Server(("0.0.0.0",port),Handler)
  threading.Thread(target=srv.serve_forever,daemon=True).start()
 logging.info("iOSProxy SOCKS5=9876 HTTP=9877")
 threading.Event().wait()
if __name__=="__main__":main()
