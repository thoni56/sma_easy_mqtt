# SMA Easy MQTT (SBFspot) – Home Assistant Add-on

Read SMA inverter data locally (via Speedwire/WebConnect) using **SBFspot**, and publish it to **MQTT** for Home Assistant.  
No cloud connectivity required – all data stays on your local network.

---

## Features
- Works with SMA inverters supporting Speedwire/WebConnect
- Runs SBFspot in a loop inside Home Assistant OS
- Publishes live inverter data as JSON to MQTT
- Configurable MQTT topic (default: `sbfspot/{plantname}/{serial}`)
- Uses your own MQTT broker (e.g. Mosquitto Add-on)
- Lightweight and simple compared to full SMA integrations

---

## Installation
1. Add this repository to the **Add-on Store** in Home Assistant  
   → *Settings → Add-ons → Add-on Store → ⋮ → Repositories*  
   → paste the GitHub URL of this repo.
2. Find **SMA Easy MQTT (SBFspot)** under *Local add-ons* and click **Install**.
3. Configure inverter IP, inverter password, MQTT connection details.
4. Start the add-on.

---

## Configuration Options
All options are set in the add-on UI:

| Option                   | Description                                                                 | Default                         |
|--------------------------|-----------------------------------------------------------------------------|---------------------------------|
| `inverter_ip`            | IP address of your SMA inverter (required)                                  | `192.168.12.146`                |
| `inverter_user_password` | Inverter user password (required)                                           | `0000`                          |
| `plant_name`             | Logical plant name                                                          | `MyPlant`                       |
| `mqtt_host`              | MQTT broker host                                                            | `homeassistant`                 |
| `mqtt_port`              | MQTT broker port                                                            | `1883`                          |
| `mqtt_username`          | MQTT username                                                               | `sbfspot`                       |
| `mqtt_password`          | MQTT password                                                               | *(empty)*                       |
| `mqtt_topic`             | MQTT topic template (supports `{plantname}` and `{serial}` placeholders)    | `sbfspot/{plantname}/{serial}` |
| `interval_seconds`       | Interval between SBFspot polls                                              | `30`                            |

---

## MQTT
- The add-on publishes inverter data as JSON messages to the configured MQTT topic.
- You can either:
  - Use **MQTT Discovery** (recommended) by publishing discovery messages, or
  - Define your own sensors with `mqtt.sensor:` in `configuration.yaml`.

Example MQTT payload:
```json
{
  "Timestamp": "12/08/2025 08:07:47",
  "InvName": "STP 25000TL-30 243",
  "InvTemperature": 54.5,
  "EToday": 2.408,
  "ETotal": 79855.544,
  "PACTot": 1935.000,
  "UDC1": 748.32,
  "IDC1": 2.24
}
```

## Home Assistant MQTT Discovery

This add-on publishes raw inverter data on:

```
sbfspot/<plant>/<serial>
```

To have Home Assistant create sensors automatically, publish **MQTT Discovery** config messages. Two options:

### Option A: Automatic (recommended)

1. In the add-on **Configuration**, add your inverter serial:

```yaml
inverter_serial: "1901344243"
```

2. Restart the add-on.  
   On startup it will publish discovery configs for:
   - **SMA Power** (`W`)
   - **SMA Energy Today** (`kWh`)
   - **SMA Energy Total** (`kWh`)
   - **SMA Inverter Temperature** (`°C`)
   - **SMA Status** (text)

Availability is tracked via the retained topic `sma-easy-mqtt/availability` so sensors stay online/offline correctly.

### Option B: Manual

If you prefer not to store the serial in options, publish discovery yourself (once). These messages are **retained** by the broker.

Replace `<serial>`, `<plant>`, `<mqtt_host>`, `<mqtt_user>`, `<mqtt_pass>`:

```bash
# Power
mosquitto_pub -h <mqtt_host> -u <mqtt_user> -P '<mqtt_pass>' \
 -t homeassistant/sensor/sma_<serial>/power/config -r -m '{
  "name":"SMA Power",
  "uniq_id":"sma_<serial>_power",
  "stat_t":"sbfspot/<plant>/<serial>",
  "avty_t":"sma-easy-mqtt/availability",
  "val_tpl":"{{ value_json.PACTot | float(0) }}",
  "unit_of_meas":"W",
  "dev_cla":"power",
  "stat_cla":"measurement",
  "dev":{"ids":["sma_<serial>"],"name":"SMA Inverter <serial>","mf":"SMA","mdl":"STP 25000TL-30"}
}'

# Energy Today
mosquitto_pub -h <mqtt_host> -u <mqtt_user> -P '<mqtt_pass>' \
 -t homeassistant/sensor/sma_<serial>/etoday/config -r -m '{
  "name":"SMA Energy Today",
  "uniq_id":"sma_<serial>_etoday",
  "stat_t":"sbfspot/<plant>/<serial>",
  "avty_t":"sma-easy-mqtt/availability",
  "val_tpl":"{{ value_json.EToday | float(0) }}",
  "unit_of_meas":"kWh",
  "dev_cla":"energy",
  "stat_cla":"total",
  "dev":{"ids":["sma_<serial>"],"name":"SMA Inverter <serial>","mf":"SMA","mdl":"STP 25000TL-30"}
}'

# Energy Total
mosquitto_pub -h <mqtt_host> -u <mqtt_user> -P '<mqtt_pass>' \
 -t homeassistant/sensor/sma_<serial>/etotal/config -r -m '{
  "name":"SMA Energy Total",
  "uniq_id":"sma_<serial>_etotal",
  "stat_t":"sbfspot/<plant>/<serial>",
  "avty_t":"sma-easy-mqtt/availability",
  "val_tpl":"{{ value_json.ETotal | float(0) }}",
  "unit_of_meas":"kWh",
  "dev_cla":"energy",
  "stat_cla":"total_increasing",
  "dev":{"ids":["sma_<serial>"],"name":"SMA Inverter <serial>","mf":"SMA","mdl":"STP 25000TL-30"}
}'

# Inverter Temperature
mosquitto_pub -h <mqtt_host> -u <mqtt_user> -P '<mqtt_pass>' \
 -t homeassistant/sensor/sma_<serial>/temp/config -r -m '{
  "name":"SMA Inverter Temperature",
  "uniq_id":"sma_<serial>_temp",
  "stat_t":"sbfspot/<plant>/<serial>",
  "avty_t":"sma-easy-mqtt/availability",
  "val_tpl":"{{ value_json.InvTemperature | float(0) }}",
  "unit_of_meas":"°C",
  "dev_cla":"temperature",
  "stat_cla":"measurement",
  "dev":{"ids":["sma_<serial>"],"name":"SMA Inverter <serial>","mf":"SMA","mdl":"STP 25000TL-30"}
}'

# Status
mosquitto_pub -h <mqtt_host> -u <mqtt_user> -P '<mqtt_pass>' \
 -t homeassistant/sensor/sma_<serial>/status/config -r -m '{
  "name":"SMA Status",
  "uniq_id":"sma_<serial>_status",
  "stat_t":"sbfspot/<plant>/<serial>",
  "avty_t":"sma-easy-mqtt/availability",
  "val_tpl":"{{ value_json.InvStatus }}",
  "icon":"mdi:solar-power",
  "dev":{"ids":["sma_<serial>"],"name":"SMA Inverter <serial>","mf":"SMA","mdl":"STP 25000TL-30"}
}'
```

**Change discovery later?** Clear the retained config first, then republish:

```bash
mosquitto_pub -h <mqtt_host> -u <mqtt_user> -P '<mqtt_pass>' \
 -t homeassistant/sensor/sma_<serial>/power/config -r -n
```

## Notes

The first run will generate /config/sbfspot/SBFspot.default.cfg inside your HA configuration folder.
You can manually tweak this if needed.

Make sure your inverter allows local access via Speedwire/WebConnect.

Recommended poll interval: 5-30 seconds (avoid stressing the inverter).

## Credits
- [SBFspot](https://github.com/SBFspot/SBFspot) – tool for SMA inverter communication

