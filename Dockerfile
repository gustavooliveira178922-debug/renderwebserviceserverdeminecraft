FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl wget git unzip nano \
    python3 python3-pip \
    openjdk-8-jdk \
    openjdk-11-jdk \
    openjdk-17-jdk \
    openjdk-21-jdk \
    nodejs npm \
    nginx \
    supervisor \
    && apt-get clean

# Create app directory
WORKDIR /app

# Backend (Python FastAPI)
RUN pip3 install fastapi uvicorn psutil

# Create backend
RUN mkdir -p /app/backend
RUN echo '
from fastapi import FastAPI
import psutil, os, subprocess

app = FastAPI()

servers = {}

@app.get("/")
def root():
    return {"status": "online"}

@app.get("/servers")
def list_servers():
    data = []
    for name, proc in servers.items():
        running = proc.poll() is None
        data.append({
            "name": name,
            "running": running,
            "cpu": psutil.cpu_percent(),
            "ram": psutil.virtual_memory().percent
        })
    return data

@app.post("/create/{name}")
def create_server(name: str):
    os.makedirs(f"/servers/{name}", exist_ok=True)
    return {"created": name}

@app.post("/start/{name}")
def start_server(name: str):
    cmd = ["java", "-Xmx1G", "-Xms1G", "-jar", "server.jar", "nogui"]
    proc = subprocess.Popen(cmd, cwd=f"/servers/{name}")
    servers[name] = proc
    return {"started": name}

@app.post("/stop/{name}")
def stop_server(name: str):
    if name in servers:
        servers[name].terminate()
    return {"stopped": name}
' > /app/backend/main.py

# Frontend
RUN mkdir -p /app/frontend
RUN echo '
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
<div class="sidebar">Menu</div>
<div class="sidebar">Servers</div>
<div class="sidebar">Settings</div>
<div class="content">
<h1>Painel Minecraft</h1>
<div id="servers"></div>
</div>
<script>
async function load(){
 let res = await fetch("/api/servers");
 let data = await res.json();
 let div = document.getElementById("servers");
 div.innerHTML="";
 data.forEach(s=>{
   div.innerHTML += `<div class="card">${s.name} - ${s.running}</div>`;
 });
}
load();
</script>
</body>
</html>
' > /app/frontend/index.html

# Nginx config
RUN rm /etc/nginx/sites-enabled/default
RUN echo '
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
' > /etc/nginx/sites-enabled/mcpanel

# Supervisor config
RUN echo '
[supervisord]
nodaemon=true

[program:backend]
command=uvicorn main:app --host 0.0.0.0 --port 8000
directory=/app/backend

[program:nginx]
command=nginx -g "daemon off;"
' > /etc/supervisor/conf.d/supervisord.conf

# Create servers directory
RUN mkdir -p /servers

# Auto account file
RUN echo "admin:admin" > /app/account.txt

# Expose port
EXPOSE 8080

# Start everything
CMD ["/usr/bin/supervisord"]
