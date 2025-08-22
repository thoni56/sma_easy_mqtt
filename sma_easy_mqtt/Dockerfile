# addons/local/sma_easy_mqtt/Dockerfile
FROM sbfspot/sbfspot:latest

USER 0
RUN apk add --no-cache jq mosquitto-clients
COPY run.sh /run.sh
RUN chmod +x /run.sh
USER 5000

ENTRYPOINT ["/run.sh"]
