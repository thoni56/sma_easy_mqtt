#!/bin/sh
set -e

OPTS=/data/options.json

# --- Läs options ---
INV_IP=$(jq -r '.inverter_ip // empty' "$OPTS")
INV_PW=$(jq -r '.inverter_user_password // empty' "$OPTS")
PLANT=$(jq -r '.plant_name // "MyPlant"' "$OPTS")
MQTT_HOST=$(jq -r '.mqtt_host // "homeassistant"' "$OPTS")
MQTT_PORT=$(jq -r '.mqtt_port // 1883' "$OPTS")
MQTT_USER=$(jq -r '.mqtt_username // empty' "$OPTS")
MQTT_PASS=$(jq -r '.mqtt_password // empty' "$OPTS")
TOPIC=$(jq -r '.mqtt_topic // "sbfspot/{plantname}/{serial}"' "$OPTS")
INTERVAL=$(jq -r '.interval_seconds // 30' "$OPTS")

INV_IP=$(jq -r '.inverter_ip // empty' "$OPTS")
INV_PW=$(jq -r '.inverter_user_password // empty' "$OPTS")
PLANT=$(jq -r '.plant_name // "MyPlant"' "$OPTS")
MQTT_HOST=$(jq -r '.mqtt_host // "homeassistant"' "$OPTS")
MQTT_PORT=$(jq -r '.mqtt_port // 1883' "$OPTS")
MQTT_USER=$(jq -r '.mqtt_username // empty' "$OPTS")
MQTT_PASS=$(jq -r '.mqtt_password // empty' "$OPTS")
TOPIC=$(jq -r '.mqtt_topic // "sbfspot/{plantname}/{serial}"' "$OPTS")
INTERVAL=$(jq -r '.interval_seconds // 30' "$OPTS")

# --- Validering ---
IP_RE='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
if [ -z "$INV_IP" ] || ! echo "$INV_IP" | grep -Eq "$IP_RE"; then
  echo "[sma-easy-mqtt] ERROR: inverter_ip måste vara en giltig IPv4 (fick: '$INV_IP')" >&2
  exit 1
fi
if [ -z "$TOPIC" ]; then
  echo "[sma-easy-mqtt] ERROR: mqtt_topic får inte vara tom." >&2
  exit 1
fi

# --- Förbered kataloger/paths ---
CFG_DIR=/config/sbfspot
OUT_DIR=$CFG_DIR/out
CFG=$CFG_DIR/SBFspot.default.cfg
WRAP=$CFG_DIR/mqtt_pub.sh

mkdir -p "$OUT_DIR"

# --- Skapa/uppdatera config första gången ---
if [ ! -f "$CFG" ]; then
  cp /usr/local/bin/sbfspot.3/SBFspot.default.cfg "$CFG"
fi

# Tvinga in rätt värden i konfigen
# Paths
sed -i "s|^OutputPath=.*|OutputPath=$OUT_DIR/%Y|" "$CFG"
sed -i "s|^OutputPathEvents=.*|OutputPathEvents=$OUT_DIR|" "$CFG"

# Inverter & plant
sed -i "s|^IP_Address=.*|IP_Address=$INV_IP|" "$CFG"
sed -i "s|^Password=.*|Password=$INV_PW|" "$CFG"
# Plantname kan saknas i default → lägg till eller ersätt
grep -q '^Plantname=' "$CFG" && \
  sed -i "s|^Plantname=.*|Plantname=$PLANT|" "$CFG" || \
  printf '\nPlantname=%s\n' "$PLANT" >> "$CFG"

# MQTT broker
sed -i "s|^MQTT_Host=.*|MQTT_Host=$MQTT_HOST|" "$CFG"
sed -i "s|^MQTT_Port=.*|MQTT_Port=$MQTT_PORT|" "$CFG"
# Topic (SBFspot accepterar {plantname}/{serial})
sed -i "s|^MQTT_Topic=.*|MQTT_Topic=$TOPIC|" "$CFG"

# Publisher: använd wrapper som injicerar user/pass
sed -i "s|^MQTT_Publisher=.*|MQTT_Publisher=$WRAP|" "$CFG"
# Ingen retain i default (live-data), JSON payload
sed -i 's|^MQTT_PublisherArgs=.*|MQTT_PublisherArgs=-h {host} -t {topic} -m "{{message}}"|' "$CFG"

# JSON-formatteringen (behåll komma som delimiter)
sed -i 's|^MQTT_ItemFormat=.*|MQTT_ItemFormat="{key}": {value}|' "$CFG"
sed -i 's|^MQTT_ItemDelimiter=.*|MQTT_ItemDelimiter=comma|' "$CFG"

# (valfritt) Säkerställ decimalpunkt i JSON-siffror
grep -q '^DecimalPoint=' "$CFG" && \
  sed -i "s|^DecimalPoint=.*|DecimalPoint=point|" "$CFG" || \
  printf '\nDecimalPoint=point\n' >> "$CFG"

# --- Skapa wrapper för mosquitto_pub med auth ---
cat > "$WRAP" <<EOF
#!/bin/sh
exec /usr/bin/mosquitto_pub ${MQTT_USER:+-u '${MQTT_USER}'} ${MQTT_PASS:+-P '${MQTT_PASS}'} "\$@"
EOF
chmod +x "$WRAP"

echo "[sma-easy-mqtt] Using inverter $INV_IP, plant '$PLANT', topic '$TOPIC', broker $MQTT_HOST:$MQTT_PORT, interval ${INTERVAL}s"

# --- Kör i loop ---
while true; do
  /usr/local/bin/sbfspot.3/SBFspot_nosql \
    -cfg:"$CFG" \
    -mqtt -ad0 -am0 -ae0 -nocsv -nosql -finq
  sleep "$INTERVAL"
done
