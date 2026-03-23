# Base image
FROM ubuntu:22.04

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PANEL_PORT=8080
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH=$JAVA_HOME/bin:$PATH

# Install dependencies
RUN apt-get update && apt-get install -y \
    openjdk-17-jdk openjdk-19-jdk openjdk-20-jdk \
    php8.2-cli php8.2-fpm php8.2-mbstring php8.2-xml php8.2-bcmath php8.2-curl php8.2-gd php8.2-sqlite3 \
    nginx supervisor curl unzip wget git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /opt/minecraft-panel

# Create basic HTML/CSS/JS panel with 3 sidebars
RUN mkdir -p /opt/minecraft-panel/public && \
    echo '<!DOCTYPE html>\
<html lang="en">\
<head>\
<meta charset="UTF-8">\
<meta name="viewport" content="width=device-width, initial-scale=1.0">\
<title>Minecraft Panel</title>\
<style>\
body { margin:0; font-family:sans-serif; display:flex; height:100vh; }\
.navbar, .sidebar, .sidebar2 { width:200px; background:#222; color:white; padding:10px; }\
.main { flex:1; padding:10px; overflow:auto; background:#f4f4f4; }\
a { color:white; text-decoration:none; display:block; margin:5px 0; }\
button { margin:5px; }\
</style>\
</head>\
<body>\
<div class="navbar"><h3>Menu</h3><a href=\"#\">Dashboard</a><a href=\"#\">Servers</a></div>\
<div class="sidebar"><h4>Servers</h4><div id="server-list"></div></div>\
<div class="sidebar2"><h4>Actions</h4><button onclick="startServer()">Start</button><button onclick="stopServer()">Stop</button></div>\
<div class="main"><h2>Server Status</h2><pre id="status">Loading...</pre></div>\
<script>\
function updateStatus() {\
  fetch("/status.php").then(r=>r.text()).then(t=>document.getElementById("status").innerText=t);\
}\
function startServer(){fetch("/action.php?action=start");updateStatus();}\
function stopServer(){fetch("/action.php?action=stop");updateStatus();}\
setInterval(updateStatus,2000);\
updateStatus();\
</script>\
</body>\
</html>' > /opt/minecraft-panel/public/index.html

# Create PHP backend to manage server
RUN echo '<?php \
$serverDir="/opt/minecraft-panel/server";\
if(!file_exists($serverDir)){mkdir($serverDir,0777,true);}\
if($_SERVER["REQUEST_URI"]=="/status.php"){\
  $status=file_exists("$serverDir/server.pid")?"Online":"Offline";\
  echo "Server status: $status";\
  exit;\
}\
if($_SERVER["REQUEST_URI"]=="/action.php"){\
  $action=$_GET["action"]??"";\
  $pidFile="$serverDir/server.pid";\
  if($action=="start" && !file_exists($pidFile)){\
    $cmd="java -Xmx1024M -Xms512M -jar $serverDir/server.jar nogui & echo $! > $pidFile";\
    shell_exec($cmd);\
    echo "Server started";\
  }\
  if($action=="stop" && file_exists($pidFile)){\
    $pid=file_get_contents($pidFile);\
    shell_exec("kill $pid");\
    unlink($pidFile);\
    echo "Server stopped";\
  }\
  exit;\
}\
?>' > /opt/minecraft-panel/public/status.php

# Create a dummy server jar placeholder
RUN mkdir -p /opt/minecraft-panel/server && \
    echo 'Placeholder for Minecraft server jar' > /opt/minecraft-panel/server/server.jar

# Configure PHP-FPM
RUN sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.2/fpm/php.ini

# Configure nginx
RUN rm /etc/nginx/sites-enabled/default && \
    echo 'server { \
        listen 8080; \
        server_name localhost; \
        root /opt/minecraft-panel/public; \
        index index.php index.html; \
        location / { try_files $uri /index.php?$query_string; } \
        location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/var/run/php/php8.2-fpm.sock; } \
        location ~ /\.ht { deny all; } \
    }' > /etc/nginx/sites-available/panel.conf && \
    ln -s /etc/nginx/sites-available/panel.conf /etc/nginx/sites-enabled/panel.conf

# Supervisor config
RUN echo '[supervisord] \
nodaemon=true \
[program:php-fpm] \
command=/usr/sbin/php-fpm8.2 -F \
autorestart=true \
stdout_logfile=/var/log/php-fpm.log \
stderr_logfile=/var/log/php-fpm.err \
[program:nginx] \
command=/usr/sbin/nginx -g "daemon off;" \
autorestart=true \
stdout_logfile=/var/log/nginx.log \
stderr_logfile=/var/log/nginx.err' > /etc/supervisor/conf.d/supervisord.conf

# Create entrypoint
RUN echo '#!/bin/bash \
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf' > /entrypoint.sh && chmod +x /entrypoint.sh

# Expose port
EXPOSE 8080

# Start container
CMD ["/entrypoint.sh"]
