# addons/local/sma_easy_mqtt/Dockerfile
FROM sbfspot/sbfspot:latest

# Installera jq (läsa /data/options.json) och mosquitto_pub
RUN apt-get update && \
    apt-get install -y --no-install-recommends jq mosquitto-clients && \
    rm -rf /var/lib/apt/lists/*

# Lägg in startscriptet
COPY run.sh /run.sh
RUN chmod +x /run.sh

# Kör add-onen
ENTRYPOINT ["/run.sh"]
