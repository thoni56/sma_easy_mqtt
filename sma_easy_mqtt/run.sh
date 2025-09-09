#!/bin/sh
set -e

echo "[sma-easy-mqtt] PID=$$ started at $(date)"

OPTS=/data/options.json

# 1) Vänta max 10s på att /data/options.json blir läsbar
for i in $(seq 1 10); do
  [ -r "$OPTS" ] && break
  [ "$i" -eq 1 ] && echo "[sma-easy-mqtt] Waiting for $OPTS to become readable..."
  sleep 1
done
if [ ! -r "$OPTS" ]; then
  echo "[sma-easy-mqtt] ERROR: $OPTS is not readable. Exiting."
  ls -l /data || true
  exit 1
fi

# 2) Läs options (nu säkert)
INV_IP=$(jq -r '.inverter_ip // empty' "$OPTS")
INV_PW=$(jq -r '.inverter_user_password // empty' "$OPTS")
INV_SER=$(jq -r '.inverter_serial // empty' "$OPTS")
PLANT=$(jq -r '.plant_name // "MyPlant"' "$OPTS")
MQTT_HOST=$(jq -r '.mqtt_host // "homeassistant"' "$OPTS")
MQTT_PORT=$(jq -r '.mqtt_port // 1883' "$OPTS")
MQTT_USER=$(jq -r '.mqtt_username // empty' "$OPTS")
MQTT_PASS=$(jq -r '.mqtt_password // empty' "$OPTS")
TOPIC=$(jq -r '.mqtt_topic // "sbfspot/{plantname}/{serial}"' "$OPTS")
INTERVAL=$(jq -r '.interval_seconds // 30' "$OPTS")
DEBUG=$(jq -r '.debug // false' /data/options.json)

echo "[sma-easy-mqtt] UID=$(id -u) GID=$(id -g)"
echo "[sma-easy-mqtt] Options:"
echo "  inverter_ip=${INV_IP}"
echo "  inverter_user_password=********"
echo "  plant_name=${PLANT}"
echo "  mqtt_host=${MQTT_HOST}"
echo "  mqtt_port=${MQTT_PORT}"
echo "  mqtt_username=${MQTT_USER}"
[ -n "$MQTT_PASS" ] && echo "  mqtt_password=********" || echo "  mqtt_password=(empty)"
echo "  mqtt_topic=${TOPIC}"
echo "  interval_seconds=${INTERVAL}"
echo "  debug=${DEBUG}"

# 3) Validering
IP_RE='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
echo "$INV_IP" | grep -Eq "$IP_RE" || { echo "[sma-easy-mqtt] ERROR: invalid inverter_ip '$INV_IP'"; exit 1; }
[ -n "$TOPIC" ] || { echo "[sma-easy-mqtt] ERROR: mqtt_topic must not be empty"; exit 1; }

# 4) Paths & cfg
CFG_DIR=/config/sbfspot
OUT_DIR=$CFG_DIR/out
CFG=$CFG_DIR/SBFspot.default.cfg
WRAP=$CFG_DIR/mqtt_pub.sh
mkdir -p "$OUT_DIR"

[ -f "$CFG" ] || cp /usr/local/bin/sbfspot.3/SBFspot.default.cfg "$CFG"

# 5) Tvinga Speedwire (ingen BT) och patcha konfig
#   – kommentera BTAddress om den finns
sed -i 's/^[[:space:]]*BTAddress=.*/#BTAddress=00:00:00:00:00:00/' "$CFG"
#   – MIS_Enabled=1
if grep -q '^MIS_Enabled=' "$CFG"; then
  sed -i 's/^MIS_Enabled=.*/MIS_Enabled=1/' "$CFG"
else
  printf '\nMIS_Enabled=1\n' >> "$CFG"
fi

#   – Grundinställningar
sed -i "s|^OutputPath=.*|OutputPath=$OUT_DIR/%Y|" "$CFG"
sed -i "s|^OutputPathEvents=.*|OutputPathEvents=$OUT_DIR|" "$CFG"
if grep -q '^IP_Address=' "$CFG"; then
  sed -i "s|^IP_Address=.*|IP_Address=$INV_IP|" "$CFG"
else
  printf '\nIP_Address=%s\n' "$INV_IP" >> "$CFG"
fi
sed -i "s|^Password=.*|Password=$INV_PW|" "$CFG"
if grep -q '^Plantname=' "$CFG"; then
  sed -i "s|^Plantname=.*|Plantname=$PLANT|" "$CFG"
else
  printf '\nPlantname=%s\n' "$PLANT" >> "$CFG"
fi

#   – MQTT via wrapper (auth injiceras här)
sed -i "s|^MQTT_Host=.*|MQTT_Host=$MQTT_HOST|" "$CFG"
sed -i "s|^MQTT_Port=.*|MQTT_Port=$MQTT_PORT|" "$CFG"
sed -i "s|^MQTT_Topic=.*|MQTT_Topic=$TOPIC|" "$CFG"
sed -i "s|^MQTT_Publisher=.*|MQTT_Publisher=$WRAP|" "$CFG"
sed -i 's|^MQTT_PublisherArgs=.*|MQTT_PublisherArgs=-h {host} -t {topic} -m "{{message}}"|' "$CFG"
if grep -q '^DecimalPoint=' "$CFG"; then
  sed -i "s|^DecimalPoint=.*|DecimalPoint=point|" "$CFG"
else
  printf '\nDecimalPoint=point\n' >> "$CFG"
fi

# 6) Wrapper för mosquitto_pub med auth
cat > "$WRAP" <<EOF
#!/bin/sh
exec /usr/bin/mosquitto_pub ${MQTT_USER:+-u '${MQTT_USER}'} ${MQTT_PASS:+-P '${MQTT_PASS}'} "\$@"
EOF
chmod +x "$WRAP"

# 7) Availability (retained) + offline på stopp
AVAIL_T="sma-easy-mqtt/availability"
$WRAP -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$AVAIL_T" -m "online" -r || true
trap '$WRAP -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$AVAIL_T" -m "offline" -r || true; exit 0' INT TERM EXIT

# 8) Auto-publish MQTT Discovery om serial finns
if [ -n "$SER" ]; then
  base="homeassistant/sensor/sma_${INV_SER}"
  state_topic="sbfspot/${PLANT}/${INV_SER}"
  # Power
  $WRAP -h "$MQTT_HOST" -p "$MQTT_PORT" -t "${base}/power/config" -r -m "{
    \"name\":\"SMA Power\",
    \"uniq_id\":\"sma_${INV_SER}_power\",
    \"stat_t\":\"${state_topic}\",
    \"avty_t\":\"sma-easy-mqtt/availability\",
    \"val_tpl\":\"{{ value_json.PACTot | float(0) }}\",
    \"unit_of_meas\":\"W\",
    \"dev_cla\":\"power\",
    \"stat_cla\":\"measurement\",
    \"dev\":{\"ids\":[\"sma_${INV_SER}\"],\"name\":\"SMA Inverter ${INV_SER}\",\"mf\":\"SMA\",\"mdl\":\"STP 25000TL-30\"}
  }"
  # Energy Today
  $WRAP -h "$MQTT_HOST" -p "$MQTT_PORT" -t "${base}/etoday/config" -r -m "{
    \"name\":\"SMA Energy Today\",
    \"uniq_id\":\"sma_${INV_SER}_etoday\",
    \"stat_t\":\"${state_topic}\",
    \"avty_t\":\"sma-easy-mqtt/availability\",
    \"val_tpl\":\"{{ value_json.EToday | float(0) }}\",
    \"unit_of_meas\":\"kWh\",
    \"dev_cla\":\"energy\",
    \"stat_cla\":\"total\",
    \"dev\":{\"ids\":[\"sma_${INV_SER}\"],\"name\":\"SMA Inverter ${INV_SER}\",\"mf\":\"SMA\",\"mdl\":\"STP 25000TL-30\"}
  }"
  # Energy Total
  $WRAP -h "$MQTT_HOST" -p "$MQTT_PORT" -t "${base}/etotal/config" -r -m "{
    \"name\":\"SMA Energy Total\",
    \"uniq_id\":\"sma_${INV_SER}_etotal\",
    \"stat_t\":\"${state_topic}\",
    \"avty_t\":\"sma-easy-mqtt/availability\",
    \"val_tpl\":\"{{ value_json.ETotal | float(0) }}\",
    \"unit_of_meas\":\"kWh\",
    \"dev_cla\":\"energy\",
    \"stat_cla\":\"total_increasing\",
    \"dev\":{\"ids\":[\"sma_${INV_SER}\"],\"name\":\"SMA Inverter ${INV_SER}\",\"mf\":\"SMA\",\"mdl\":\"STP 25000TL-30\"}
  }"
  # Temperature
  $WRAP -h "$MQTT_HOST" -p "$MQTT_PORT" -t "${base}/temp/config" -r -m "{
    \"name\":\"SMA Inverter Temperature\",
    \"uniq_id\":\"sma_${INV_INV_SER}_temp\",
    \"stat_t\":\"${state_topic}\",
    \"avty_t\":\"sma-easy-mqtt/availability\",
    \"val_tpl\":\"{{ value_json.InvTemperature | float(0) }}\",
    \"unit_of_meas\":\"°C\",
    \"dev_cla\":\"temperature\",
    \"stat_cla\":\"measurement\",
    \"dev\":{\"ids\":[\"sma_${INV_SER}\"],\"name\":\"SMA Inverter ${INV_SER}\",\"mf\":\"SMA\",\"mdl\":\"STP 25000TL-30\"}
  }"
  # Status
  $WRAP -h "$MQTT_HOST" -p "$MQTT_PORT" -t "${base}/status/config" -r -m "{
    \"name\":\"SMA Status\",
    \"uniq_id\":\"sma_${INV_SER}_status\",
    \"stat_t\":\"${state_topic}\",
    \"avty_t\":\"sma-easy-mqtt/availability\",
    \"val_tpl\":\"{{ value_json.InvStatus }}\",
    \"icon\":\"mdi:solar-power\",
    \"dev\":{\"ids\":[\"sma_${INV_SER}\"],\"name\":\"SMA Inverter ${INV_SER}\",\"mf\":\"SMA\",\"mdl\":\"STP 25000TL-30\"}
  }"
fi

# 9) Dumpa effektiv konfig (nyckelrader)
echo "[sma-easy-mqtt] --- Effective config (key lines) ---"
grep -E '^(#?BTAddress|IP_Address|MIS_Enabled|Plantname|MQTT_Host|MQTT_Port|MQTT_Topic|MQTT_Publisher)=' "$CFG" || true
echo "[sma-easy-mqtt] -------------------------------------"
echo "[sma-easy-mqtt] Starting loop…"

# 10) Kör SBFspot i loop (OBS: ingen -ip-flagga – IP sätts i cfg)
SBF_ARGS="-cfg:$CFG -mqtt -ad0 -am0 -ae0 -nocsv -nosql -finq"
[ "$DEBUG" = "true" ] && SBF_ARGS="-cfg:$CFG -v5 -mqtt -ad0 -am0 -ae0 -nocsv -nosql -finq"

while true; do
  echo "[sma-easy-mqtt] $(date '+%F %T') tick (debug=$DEBUG)"
  /usr/local/bin/sbfspot.3/SBFspot_nosql $SBF_ARGS
  sleep "$INTERVAL"
done
