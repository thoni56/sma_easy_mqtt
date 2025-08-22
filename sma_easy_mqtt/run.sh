#!/bin/sh
set -e

OPTS=/data/options.json

# Vänta max 10s på att /data/options.json blir läsbar
for i in $(seq 1 10); do
  if [ -r "$OPTS" ]; then break; fi
  [ "$i" -eq 1 ] && echo "[sma-easy-mqtt] Waiting for $OPTS to become readable..."
  sleep 1
done
if [ ! -r "$OPTS" ]; then
  echo "[sma-easy-mqtt] ERROR: $OPTS is not readable. Exiting."
  ls -l /data || true
  exit 1
fi

# Läs options
INV_IP=$(jq -r '.inverter_ip // empty' "$OPTS")
INV_PW=$(jq -r '.inverter_user_password // empty' "$OPTS")
PLANT=$(jq -r '.plant_name // "MyPlant"' "$OPTS")
MQTT_HOST=$(jq -r '.mqtt_host // "homeassistant"' "$OPTS")
MQTT_PORT=$(jq -r '.mqtt_port // 1883' "$OPTS")
MQTT_USER=$(jq -r '.mqtt_username // empty' "$OPTS")
MQTT_PASS=$(jq -r '.mqtt_password // empty' "$OPTS")
TOPIC=$(jq -r '.mqtt_topic // "sbfspot/{plantname}/{serial}"' "$OPTS")
INTERVAL=$(jq -r '.interval_seconds // 30' "$OPTS")

echo "[sma-easy-mqtt] UID=$(id -u) GID=$(id -g)  inverter_ip=${INV_IP} plant=${PLANT} broker=${MQTT_HOST}:${MQTT_PORT} topic=${TOPIC} interval=${INTERVAL}s"

# Validering
IP_RE='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
echo "$INV_IP" | grep -Eq "$IP_RE" || { echo "[sma-easy-mqtt] ERROR: invalid inverter_ip '$INV_IP'"; exit 1; }
[ -n "$TOPIC" ] || { echo "[sma-easy-mqtt] ERROR: mqtt_topic must not be empty"; exit 1; }

# Paths
CFG_DIR=/config/sbfspot
OUT_DIR=$CFG_DIR/out
CFG=$CFG_DIR/SBFspot.default.cfg
WRAP=$CFG_DIR/mqtt_pub.sh
mkdir -p "$OUT_DIR"

# Basera på default vid första start
[ -f "$CFG" ] || cp /usr/local/bin/sbfspot.3/SBFspot.default.cfg "$CFG"

# Tvinga Speedwire och rätt inställningar
# – kommentera BTAddress
sed -i 's/^[[:space:]]*BTAddress=.*/#BTAddress=00:00:00:00:00:00/' "$CFG"
# – MIS_Enabled=1
grep -q '^MIS_Enabled=' "$CFG" && \
  sed -i 's/^MIS_Enabled=.*/MIS_Enabled=1/' "$CFG" || \
  printf '\nMIS_Enabled=1\n' >> "$CFG"

# Patcha konfig
sed -i "s|^OutputPath=.*|OutputPath=$OUT_DIR/%Y|" "$CFG"
sed -i "s|^OutputPathEvents=.*|OutputPathEvents=$OUT_DIR|" "$CFG"
sed -i "s|^IP_Address=.*|IP_Address=$INV_IP|" "$CFG"
sed -i "s|^Password=.*|Password=$INV_PW|" "$CFG"
grep -q '^Plantname=' "$CFG" && \
  sed -i "s|^Plantname=.*|Plantname=$PLANT|" "$CFG" || \
  printf '\nPlantname=%s\n' "$PLANT" >> "$CFG"
sed -i "s|^MQTT_Host=.*|MQTT_Host=$MQTT_HOST|" "$CFG"
sed -i "s|^MQTT_Port=.*|MQTT_Port=$MQTT_PORT|" "$CFG"
sed -i "s|^MQTT_Topic=.*|MQTT_Topic=$TOPIC|" "$CFG"
sed -i "s|^MQTT_Publisher=.*|MQTT_Publisher=$WRAP|" "$CFG"
sed -i 's|^MQTT_PublisherArgs=.*|MQTT_PublisherArgs=-h {host} -t {topic} -m "{{message}}"|' "$CFG"
grep -q '^DecimalPoint=' "$CFG" && \
  sed -i "s|^DecimalPoint=.*|DecimalPoint=point|" "$CFG" || \
  printf '\nDecimalPoint=point\n' >> "$CFG"

# Wrapper för mosquitto_pub med auth
cat > "$WRAP" <<EOF
#!/bin/sh
exec /usr/bin/mosquitto_pub ${MQTT_USER:+-u '${MQTT_USER}'} ${MQTT_PASS:+-P '${MQTT_PASS}'} "\$@"
EOF
chmod +x "$WRAP"

echo "[sma-easy-mqtt] Starting loop…"
while true; do
  /usr/local/bin/sbfspot.3/SBFspot_nosql \
    -cfg:"$CFG" -ip:"$INV_IP" \
    -mqtt -ad0 -am0 -ae0 -nocsv -nosql -finq
  sleep "$INTERVAL"
done
