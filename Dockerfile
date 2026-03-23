FROM openjdk:21-jdk-slim

# Instalar dependências
RUN apt update && apt install -y \
    curl \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /minecraft

# Baixar PaperMC
RUN curl -o server.jar https://api.papermc.io/v2/projects/paper/versions/1.20.4/builds/416/downloads/paper-1.20.4-416.jar

# Aceitar EULA
RUN echo "eula=true" > eula.txt

# Baixar playit
RUN curl -L -o playit https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 \
    && chmod +x playit

# Criar script Python watchdog
RUN echo '\
import subprocess, time\n\
\n\
JAVA_FLAGS = [\n\
"java",\n\
"-Xms8G",\n\ 
"-Xmx16G",\n\ 
"-XX:+UseG1GC",\n\
"-XX:+ParallelRefProcEnabled",\n\
"-XX:MaxGCPauseMillis=200",\n\
"-XX:+UnlockExperimentalVMOptions",\n\
"-XX:+DisableExplicitGC",\n\
"-XX:+AlwaysPreTouch",\n\
"-XX:G1NewSizePercent=30",\n\
"-XX:G1MaxNewSizePercent=40",\n\
"-XX:G1HeapRegionSize=8M",\n\
"-XX:G1ReservePercent=20",\n\
"-XX:G1HeapWastePercent=5",\n\
"-XX:G1MixedGCCountTarget=4",\n\
"-XX:InitiatingHeapOccupancyPercent=15",\n\
"-XX:G1MixedGCLiveThresholdPercent=90",\n\
"-XX:G1RSetUpdatingPauseTimePercent=5",\n\
"-XX:SurvivorRatio=32",\n\
"-XX:+PerfDisableSharedMem",\n\
"-XX:MaxTenuringThreshold=1",\n\
"-jar","server.jar","nogui"\n\
]\n\
\n\
def start():\n\
    print(\"\\n🚀 Iniciando servidor Minecraft...\\n\")\n\
    return subprocess.Popen(JAVA_FLAGS)\n\
\n\
while True:\n\
    p = start()\n\
    p.wait()\n\
    print(\"⚠️ Servidor caiu! Reiniciando em 5s...\")\n\
    time.sleep(5)\n\
' > watchdog.py

# Criar script principal
RUN echo '\
#!/bin/bash\n\
clear\n\
echo \"=====================================\"\n\
echo \"   🟩 MINECRAFT DOCKER SERVER 🟩\"\n\
echo \"=====================================\"\n\
echo \"\"\n\
echo \"Iniciando Playit...\"\n\
./playit &\n\
sleep 5\n\
echo \"\"\n\
echo \"🌍 Configure o túnel no link acima\"\n\
echo \"Depois use o IP gerado para conectar\"\n\
echo \"\"\n\
echo \"=====================================\"\n\
python3 watchdog.py\n\
' > start.sh && chmod +x start.sh

EXPOSE 25565

CMD ["bash", "start.sh"]
