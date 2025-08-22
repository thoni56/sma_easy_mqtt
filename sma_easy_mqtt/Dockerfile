# addons/local/sma_easy_mqtt/Dockerfile
FROM sbfspot/sbfspot:latest

USER root
RUN apk add --no-cache jq mosquitto-clients
COPY run.sh /run.sh
RUN chmod +x /run.sh

ENTRYPOINT ["/run.sh"]
