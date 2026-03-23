FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Instala dependências
RUN apt-get update && apt-get install -y \
    curl wget git unzip nano python3 python3-pip \
    openjdk-8-jdk openjdk-11-jdk openjdk-17-jdk openjdk-21-jdk \
    nodejs npm nginx supervisor sudo unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Criação de diretórios
WORKDIR /app
RUN mkdir -p /app/backend /app/frontend /servers

# Backend Python
RUN pip3 install --no-cache-dir fastapi uvicorn psutil python-multipart

# Backend main.py
RUN bash -c "cat <<'EOF' > /app/backend/main.py
from fastapi import FastAPI, UploadFile, File
import psutil, os, subprocess, socket

app = FastAPI()
servers = {}
account_file = '/app/account.txt'

if not os.path.exists(account_file):
    with open(account_file, 'w') as f:
        f.write('admin:admin')

def get_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))
        return s.getsockname()[0]
    except:
        return '127.0.0.1'
    finally:
        s.close()

@app.get('/')
def root():
    return {'status':'online','ip':get_ip()}

@app.get('/servers')
def list_servers():
    data = []
    for name, proc in servers.items():
        running = proc.poll() is None
        data.append({
            'name': name,
            'running': running,
            'cpu': psutil.cpu_percent(),
            'ram': psutil.virtual_memory().percent
        })
    return data

@app.post('/create/{name}')
def create_server(name: str):
    os.makedirs(f'/servers/{name}', exist_ok=True)
    return {'created': name}

@app.post('/start/{name}')
def start_server(name: str):
    jar_path = f'/servers/{name}/server.jar'
    if not os.path.exists(jar_path):
        return {'error':'server.jar not found'}
    cmd = ['java','-Xmx2G','-Xms1G','-jar','server.jar','nogui']
    proc = subprocess.Popen(cmd, cwd=f'/servers/{name}')
    servers[name] = proc
    return {'started': name}

@app.post('/stop/{name}')
def stop_server(name: str):
    if name in servers:
        servers[name].terminate()
        return {'stopped': name}
    return {'error':'server not running'}

@app.post('/upload/{name}')
async def upload_file(name: str, file: UploadFile = File(...)):
    path = f'/servers/{name}/{file.filename}'
    with open(path,'wb') as f:
        f.write(await file.read())
    return {'uploaded': file.filename}
EOF"

# Frontend index.html
RUN bash -c "cat <<'EOF' > /app/frontend/index.html
<!DOCTYPE html>
<html>
<head>
<title>Minecraft Panel</title>
<style>
body {margin:0; font-family:Arial; display:flex;}
.sidebar {width:200px; background:#1e1e2f; color:white; height:100vh; padding:10px;}
.content {flex:1; padding:20px;}
.card {background:#2e2e3f; color:white; padding:10px; margin:10px; border-radius:8px;}
</style>
</head>
<body>
<div class='sidebar'>Menu</div>
<div class='sidebar'>Servers</div>
<div class='sidebar'>Settings</div>
<div class='content'>
<h1>Painel Minecraft</h1>
<div id='servers'></div>
<div id='ip'></div>
</div>
<script>
async function load(){
 let res = await fetch('/api/servers');
 let data = await res.json();
 let div = document.getElementById('servers');
 div.innerHTML='';
 data.forEach(s=>{
   div.innerHTML += `<div class='card'>${s.name} - Online: ${s.running} - CPU: ${s.cpu}% - RAM: ${s.ram}%</div>`;
 });
 let ipres = await fetch('/api/');
 let ipdata = await ipres.json();
 document.getElementById('ip').innerText = 'IP: '+ipdata.ip;
}
load();
</script>
</body>
</html>
EOF"

# Configura Nginx
RUN rm /etc/nginx/sites-enabled/default
RUN bash -c "cat <<'EOF' > /etc/nginx/sites-enabled/mcpanel
server {
    listen 8080;
    location / {
        root /app/frontend;
        index index.html;
    }
    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
    }
}
EOF"

# Configura Supervisor
RUN bash -c "cat <<'EOF' > /etc/supervisor/conf.d/supervisord.conf
[supervisord]
nodaemon=true

[program:backend]
command=uvicorn main:app --host 0.0.0.0 --port 8000
directory=/app/backend
autostart=true
autorestart=true
stdout_logfile=/var/log/backend.log
stderr_logfile=/var/log/backend_err.log

[program:nginx]
command=nginx -g 'daemon off;'
autostart=true
autorestart=true
stdout_logfile=/var/log/nginx.log
stderr_logfile=/var/log/nginx_err.log
EOF"

# Porta do painel
EXPOSE 8080

# Inicializa supervisor
CMD ["/usr/bin/supervisord"]
