// iOSProxy 0.2: Native HTTP/SOCKS5 TCP proxy, no Python dependency.
// Does not modify wifid, misd, sharingd or Personal Hotspot settings.
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <time.h>
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif
#define MAX_HEADERS 32768
#define BUFSIZE 32768
typedef struct { int fd; int is_socks; } worker_args;
static volatile int proxy_enabled=1;
static volatile unsigned long accepted_clients=0;
static char panel_token[33];
static int sendall(int fd,const void *buf,size_t size) {
    const uint8_t *p=buf;
    while(size) {
        ssize_t n=send(fd,p,size,MSG_NOSIGNAL);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) return -1;
        p+=n;size-=(size_t)n;
    }
    return 0;
}
static int readall(int fd,void *buf,size_t size) {
    uint8_t *p=buf;
    while(size) {
        ssize_t n=recv(fd,p,size,0);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) return -1;
        p+=n;size-=(size_t)n;
    }
    return 0;
}
static int dial(const char *host,int port) {
    char port_str[8];snprintf(port_str,sizeof(port_str),"%d",port);
    struct addrinfo hints={0},*all=NULL,*p;
    hints.ai_family=AF_UNSPEC;hints.ai_socktype=SOCK_STREAM;
    if(getaddrinfo(host,port_str,&hints,&all)!=0) return -1;
    int result=-1;
    for(p=all;p;p=p->ai_next) {
        int fd=socket(p->ai_family,p->ai_socktype,p->ai_protocol);
        if(fd<0) continue;
        struct timeval timeout={.tv_sec=12};
        setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
        if(connect(fd,p->ai_addr,p->ai_addrlen)==0) {
            timeout.tv_sec=0;
            setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
            result=fd;break;
        }
        close(fd);
    }
    freeaddrinfo(all);return result;
}
static void bridge(int a,int b) {
    uint8_t buf[BUFSIZE];
    for(;;) {
        fd_set f;FD_ZERO(&f);FD_SET(a,&f);FD_SET(b,&f);
        struct timeval t={.tv_sec=1800};
        int n=select((a>b?a:b)+1,&f,NULL,NULL,&t);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) break;
        int src=FD_ISSET(a,&f)?a:b,dst=src==a?b:a;
        ssize_t len=recv(src,buf,sizeof(buf),0);
        if(len<=0 || sendall(dst,buf,(size_t)len)<0) break;
    }
}
static int allowed(int fd) {
    struct sockaddr_in sa={0};socklen_t len=sizeof(sa);
    if(getpeername(fd,(struct sockaddr *)&sa,&len)!=0||sa.sin_family!=AF_INET) return 0;
    uint32_t ip=ntohl(sa.sin_addr.s_addr);
    return (ip&0xffffff00U)==0xac140a00U || (ip&0xff000000U)==0x7f000000U;
}
static int socks_target(int fd,char *host,size_t hostlen,int *port) {
    uint8_t init[2];
    if(readall(fd,init,2)<0||init[0]!=5||init[1]==0) return -1;
    uint8_t methods[255];
    if(readall(fd,methods,init[1])<0) return -1;
    int ok=0;for(int i=0;i<init[1];i++) if(methods[i]==0) ok=1;
    uint8_t response[]={5,(uint8_t)(ok?0:255)};
    if(sendall(fd,response,2)<0||!ok) return -1;
    uint8_t h[4];
    if(readall(fd,h,4)<0||h[0]!=5||h[1]!=1) return -1;
    if(h[3]==1||h[3]==4) {
        uint8_t raw[16];int n=h[3]==1?4:16;
        if(readall(fd,raw,(size_t)n)<0||!inet_ntop(h[3]==1?AF_INET:AF_INET6,raw,host,(socklen_t)hostlen)) return -1;
    } else if(h[3]==3) {
        uint8_t len;
        if(readall(fd,&len,1)<0||len==0||len>=hostlen||readall(fd,host,len)<0) return -1;
        host[len]=0;
    } else return -1;
    uint8_t p[2];if(readall(fd,p,2)<0) return -1;
    *port=(p[0]<<8)|p[1];return 0;
}
static void handle_socks(int fd) {
    char host[256]={0};int port=0;
    if(socks_target(fd,host,sizeof(host),&port)<0) return;
    int peer=dial(host,port);
    uint8_t rep[]={5,(uint8_t)(peer<0?5:0),0,1,0,0,0,0,0,0};
    sendall(fd,rep,sizeof(rep));
    if(peer>=0) {bridge(fd,peer);close(peer);}
}
static char *header_end(char *b,size_t len) {
    for(size_t i=3;i<len;i++)
        if(b[i-3]=='\r'&&b[i-2]=='\n'&&b[i-1]=='\r'&&b[i]=='\n') return b+i+1;
    return NULL;
}
static int authority(const char *value,char *host,size_t capacity,int *port,int fallback) {
    const char *end=NULL,*p=NULL;
    if(!value||!*value) return -1;
    if(value[0]=='[') {
        end=strchr(value,']');
        if(!end||(size_t)(end-value-1)>=capacity) return -1;
        memcpy(host,value+1,(size_t)(end-value-1));
        host[end-value-1]=0;p=end[1]==':'?end+2:NULL;
    } else {
        end=strrchr(value,':');
        size_t n=end?(size_t)(end-value):strlen(value);
        if(!n||n>=capacity) return -1;
        memcpy(host,value,n);host[n]=0;p=end?end+1:NULL;
    }
    *port=fallback;
    if(p) {
        char *stop=NULL;long n=strtol(p,&stop,10);
        if(!*p||*stop||n<1||n>65535) return -1;
        *port=(int)n;
    }
    return 0;
}
static void handle_http(int fd) {
    char head[MAX_HEADERS+1];size_t have=0;char *end=NULL;
    while(have<MAX_HEADERS) {
        ssize_t n=recv(fd,head+have,MAX_HEADERS-have,0);
        if(n<=0) return;
        have+=(size_t)n;
        end=header_end(head,have);
        if(end) break;
    }
    if(!end) return;
    head[have]=0;
    size_t headbytes=(size_t)(end-head);
    char method[16]={0},target[2048]={0},version[24]={0};
    if(sscanf(head,"%15s %2047s %23s",method,target,version)!=3) return;
    char host[256]={0};int port=0;int tunnel=!strcmp(method,"CONNECT");
    const char *path="/";
    if(tunnel) {
        if(authority(target,host,sizeof(host),&port,443)<0) return;
    } else {
        if(strncmp(target,"http://",7)!=0) return;
        const char *base=target+7,*slash=strchr(base,'/'),*q=strchr(base,'?');
        if(!slash||(q&&q<slash)) slash=q;
        char copy[512];size_t n=slash?(size_t)(slash-base):strlen(base);
        if(!n||n>=sizeof(copy)) return;
        memcpy(copy,base,n);copy[n]=0;
        if(authority(copy,host,sizeof(host),&port,80)<0) return;
        path=slash?slash:"/";
    }
    int peer=dial(host,port);
    if(peer<0) {
        static const char err[]="HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n";
        sendall(fd,err,sizeof(err)-1);return;
    }
    if(tunnel) {
        static const char ok[]="HTTP/1.1 200 Connection Established\r\n\r\n";
        if(sendall(fd,ok,sizeof(ok)-1)==0) {
            if(have>headbytes) sendall(peer,head+headbytes,have-headbytes);
            bridge(fd,peer);
        }
    } else {
        char firstline[2300];
        int n=snprintf(firstline,sizeof(firstline),"%s %s %s",method,path,version);
        char *newline=strstr(head,"\r\n");
        if(n>0&&(size_t)n<sizeof(firstline)&&newline&&sendall(peer,firstline,(size_t)n)==0
           &&sendall(peer,newline,headbytes-(size_t)(newline-head))==0) {
            if(have>headbytes) sendall(peer,head+headbytes,have-headbytes);
            bridge(fd,peer);
        }
    }
    close(peer);
}
static void *worker(void *opaque) {
    worker_args *args=opaque;
    int fd=args->fd,is_socks=args->is_socks;free(args);
    if(!allowed(fd)||!proxy_enabled) {close(fd);return NULL;}
    __sync_fetch_and_add(&accepted_clients,1);
    struct timeval tv={.tv_sec=20};
    setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv));
    if(is_socks) handle_socks(fd);else handle_http(fd);
    close(fd);return NULL;
}
static void *listen_port(void *opaque) {
    int port=*(int *)opaque;
    int listener=socket(AF_INET,SOCK_STREAM,0);
    if(listener<0) return NULL;
    int yes=1;setsockopt(listener,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));
    struct sockaddr_in a={.sin_family=AF_INET,.sin_port=htons((uint16_t)port),.sin_addr.s_addr=htonl(INADDR_ANY)};
    if(bind(listener,(struct sockaddr *)&a,sizeof(a))!=0||listen(listener,64)!=0) {
        perror("listen");close(listener);return NULL;
    }
    fprintf(stderr,"iOSProxy listening on %d\n",port);
    for(;;) {
        int client=accept(listener,NULL,NULL);
        if(client<0) {if(errno==EINTR) continue;break;}
        worker_args *args=malloc(sizeof(*args));
        if(!args) {close(client);continue;}
        args->fd=client;args->is_socks=(port==9876);
        pthread_t tid;
        if(pthread_create(&tid,NULL,worker,args)==0) pthread_detach(tid);
        else {free(args);close(client);}
    }
    close(listener);return NULL;
}

static void *panel_server(void *unused) {
    (void)unused;
    int ls=socket(AF_INET,SOCK_STREAM,0);
    if(ls<0)return NULL;
    int yes=1;setsockopt(ls,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));
    struct sockaddr_in a={.sin_family=AF_INET,.sin_port=htons(9878),.sin_addr.s_addr=htonl(0x7f000001U)};
    if(bind(ls,(struct sockaddr*)&a,sizeof(a))<0||listen(ls,8)<0){close(ls);return NULL;}
    for(;;){
        int c=accept(ls,NULL,NULL);if(c<0)continue;
        struct timeval tv={.tv_sec=3};setsockopt(c,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv));
        char req[2048]={0};ssize_t n=recv(c,req,sizeof(req)-1,0);
        if(n<=0){close(c);continue;}
        if(strncmp(req,"POST /toggle ",13)==0 && strstr(req,"\r\nOrigin: http://127.0.0.1:9878") && strstr(req,panel_token)){
            proxy_enabled=!proxy_enabled;
        }
        char html[6000];
        int m=snprintf(html,sizeof(html),
        "<!doctype html><html lang='tr'><meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<meta charset='utf-8'><title>iOSProxy</title>"
        "<style>body{font:17px -apple-system,system-ui;background:#f2f4f8;color:#172236;margin:0;padding:22px}"
        ".box{background:white;border-radius:18px;padding:20px;max-width:500px;margin:0 auto 18px;box-shadow:0 2px 10px #152b4315}"
        "h1{font-size:25px}p{line-height:1.5}button{background:#176ef2;color:white;border:0;border-radius:12px;padding:14px 20px;font-size:17px}"
        ".off{background:#d53b46}.ok{font-weight:bold;color:%s}code{background:#eef2f8;padding:4px;border-radius:6px}"
        "</style><div class='box'><h1>iOSProxy</h1><p class='ok'>%s</p>"
        "<p>Sunucu aktif. Proxy bağlantıları: %lu</p>"
        "<form method='post' action='/toggle'><input type='hidden' name='token' value='%s'>"
        "<button class='%s'>Proxy'yi %s</button></form></div>"
        "<div class='box'><h2>iPhone 15 ayarları</h2><p>Wi-Fi &gt; (i) &gt; HTTP Proxy &gt; Elle</p>"
        "<p>Sunucu: <code>172.20.10.1</code> <button onclick=\"navigator.clipboard.writeText('172.20.10.1')\">Kopyala</button></p>"
        "<p>Port: <code>9877</code> <button onclick=\"navigator.clipboard.writeText('9877')\">Kopyala</button></p>"
        "<p>Kimlik doğrulama: Kapalı</p></div>"
        "<div class='box'><small>Panel sadece bu iPhone'da (127.0.0.1) açılır. Hotspot'u otomatik açmaz ve Wi-Fi uyku davranışını değiştirmez.</small></div></html>",
        proxy_enabled?"#148b52":"#c63b42",proxy_enabled?"Proxy açık":"Proxy kapalı",
        accepted_clients,panel_token,proxy_enabled?"off":"",proxy_enabled?"Kapat":"Aç");
        if(m>0 && (size_t)m<sizeof(html)){
            char hdr[256];
            int k=snprintf(hdr,sizeof(hdr),"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nX-Frame-Options: DENY\r\nContent-Length: %d\r\nConnection: close\r\n\r\n",m);
            if(k>0)sendall(c,hdr,(size_t)k);
            sendall(c,html,(size_t)m);
        }
        close(c);
    }
}

int main(void) {
    signal(SIGPIPE,SIG_IGN);
    FILE *random=fopen("/dev/urandom","rb");unsigned char b[16]={0};
    if(!random||fread(b,1,16,random)!=16){if(random)fclose(random);return 1;}
    fclose(random);
    for(int i=0;i<16;i++)snprintf(panel_token+i*2,3,"%02x",b[i]);
    static int socks_port=9876,http_port=9877;
    pthread_t s,h,p;
    if(pthread_create(&p,NULL,panel_server,NULL)==0)pthread_detach(p);
    if(pthread_create(&s,NULL,listen_port,&socks_port)!=0) return 1;
    if(pthread_create(&h,NULL,listen_port,&http_port)!=0) return 1;
    pthread_join(s,NULL);pthread_join(h,NULL);return 0;
}
