#!/var/jb/usr/bin/python3
"""Small standalone HTTP CONNECT / SOCKS5 TCP proxy for the iOS hotspot subnet.
Does not modify Wi-Fi, Apple networking daemons, routing or NAT.
"""
import ipaddress, logging, select, socket, socketserver, struct, threading, urllib.parse

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s')
ALLOW = ipaddress.ip_network('172.20.10.0/24')

def accepted(peer):
    try:
        ip = ipaddress.ip_address(peer[0].split('%')[0]); return ip.is_loopback or ip in ALLOW
    except ValueError: return False

def bridge(a,b):
    try:
        a.settimeout(None); b.settimeout(None)
        while True:
            readable,_,_=select.select([a,b],[],[],120)
            if not readable: break
            for x in readable:
                buf=x.recv(32768)
                if not buf: return
                (b if x is a else a).sendall(buf)
    except (OSError,ValueError): pass

class TCPServer(socketserver.ThreadingMixIn,socketserver.TCPServer):
    allow_reuse_address=True
    daemon_threads=True
    request_queue_size=64

class Base(socketserver.BaseRequestHandler):
    def allowed(self):
        return accepted(self.client_address)
    def connect_remote(self,host,port):
        return socket.create_connection((host,port),timeout=12)

class Socks(Base):
    def handle(self):
        if not self.allowed(): return
        conn=self.request; conn.settimeout(15)
        try:
            def exact(n):
                r=b''
                while len(r)<n:
                    chunk=conn.recv(n-len(r))
                    if not chunk: raise OSError('EOF')
                    r+=chunk
                return r
            version,n=exact(2)
            if version!=5 or 0 not in exact(n):
                conn.sendall(b'\x05\xff');return
            conn.sendall(b'\x05\x00')
            version,cmd,_,typ=exact(4)
            if version!=5 or cmd!=1:
                conn.sendall(b'\x05\x07\x00\x01'+b'\0'*6);return
            if typ==1: host=socket.inet_ntop(socket.AF_INET,exact(4))
            elif typ==4: host=socket.inet_ntop(socket.AF_INET6,exact(16))
            elif typ==3: host=exact(exact(1)[0]).decode('idna')
            else: return
            port=struct.unpack('!H',exact(2))[0]
            with self.connect_remote(host,port) as remote:
                conn.sendall(b'\x05\x00\x00\x01'+b'\0'*6)
                bridge(conn,remote)
        except (OSError,ValueError,UnicodeError):
            pass

class Http(Base):
    def handle(self):
        if not self.allowed(): return
        conn=self.request;conn.settimeout(15)
        try:
            packet=b''
            while b'\r\n\r\n' not in packet and len(packet)<65536:
                v=conn.recv(4096)
                if not v:return
                packet+=v
            head,sep,extra=packet.partition(b'\r\n\r\n')
            if not sep:return
            lines=head.split(b'\r\n')
            method,target,version=lines[0].decode('latin1').split(' ',2)
            if method.upper()=='CONNECT':
                if target.startswith('['):
                    host,port=target.rsplit(']:',1);host=host[1:]
                else: host,port=target.rsplit(':',1)
                with self.connect_remote(host,int(port)) as remote:
                    conn.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
                    if extra: remote.sendall(extra)
                    bridge(conn,remote)
            else:
                url=urllib.parse.urlsplit(target)
                if url.scheme!='http' or not url.hostname: return
                path=urllib.parse.urlunsplit(('','',url.path or '/',url.query,''))
                port=url.port or 80
                headers=[v for v in lines[1:] if not v.lower().startswith((b'proxy-connection:',b'connection:'))]
                request=(f'{method} {path} {version}\r\n'.encode('latin1') + b'\r\n'.join(headers) + b'\r\nConnection: close\r\n\r\n'+extra)
                with self.connect_remote(url.hostname,port) as remote:
                    remote.sendall(request);bridge(conn,remote)
        except (OSError,ValueError,UnicodeError):
            try:conn.sendall(b'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n')
            except OSError:pass

def main():
    # Bind on all IPv4 addresses, but reject connections outside the iOS hotspot subnet.
    servers=[TCPServer(('0.0.0.0',9876),Socks),TCPServer(('0.0.0.0',9877),Http)]
    for server in servers:
        threading.Thread(target=server.serve_forever,daemon=True).start()
    logging.info('iOSProxy running SOCKS5 9876, HTTP 9877; allowed hotspot 172.20.10.0/24')
    threading.Event().wait()

if __name__=='__main__': main()
