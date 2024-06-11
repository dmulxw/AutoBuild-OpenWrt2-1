#!/bin/bash
#=================================================
# Bash Module name: mt7621Rtk4G
# Description: MT7621A 4G RTK Device script
# License: MIT
# Author: Lixiaowei
# Email: 267199@qq.com
#=================================================

# 1. Modify default IP
sed -i 's/192.168.1.1/192.168.5.1/g' openwrt/package/base-files/files/bin/config_generate

# 2. Set login password to 'admin'
PASSWORD_HASH=$(openssl passwd -1 "admin")
sed -i "s|root::0:0:99999:7:::|root:${PASSWORD_HASH}:18297:0:99999:7:::|g" openwrt/package/base-files/files/etc/shadow

# 3. Configure Ntrip services
uci set ntripclient.@ntripclient[0].server='rtk.gpspos.com'
uci set ntripclient.@ntripclient[0].port='2101'
uci set ntripclient.@ntripclient[0].username='rtk_username'
uci set ntripclient.@ntripclient[0].password='rtk_password'
uci set ntripclient.@ntripclient[0].interval='10'
uci set ntripclient.@ntripclient[0].device='/dev/ttyS1'
uci commit ntripclient

# 4. Configure network settings
cat << 'EOF' > /etc/init.d/netconfig
#!/bin/sh /etc/rc.common

START=99

boot() {
    while true; do
        if [ -e /dev/ttyUSB0 ]; then
            if ! ip link show dev wwan0 &>/dev/null; then
                echo "Switching to 4G module..."
                uci set network.wan.ifname='wwan0'
                uci commit network
                ifup wan
            fi
        else
            if ip link show dev wwan0 &>/dev/null; then
                echo "Switching to WAN..."
                uci set network.wan.ifname='eth0'
                uci commit network
                ifup wan
            fi
        fi
        sleep 30
    done
}
EOF

chmod +x /etc/init.d/netconfig
/etc/init.d/netconfig enable

# 5. Configure WiFi settings and output to serial port if unchanged
INITIAL_CONFIG="/etc/config/initial_wifi_config"
DEFAULT_PASSWORD="12345678"

if [ ! -f "$INITIAL_CONFIG" ]; then
    RANDOM_SUFFIX=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 6)
    RANDOM_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)
    uci set wireless.@wifi-iface[0].ssid="GSTN$RANDOM_SUFFIX"
    uci set wireless.@wifi-iface[0].key="$RANDOM_PASSWORD"
    uci commit wireless

    # Output SSID and Password to Serial Port 0
    echo "WiFi SSID: GSTN$RANDOM_SUFFIX" > /dev/ttyS0
    echo "WiFi Password: $RANDOM_PASSWORD" > /dev/ttyS0

    # Mark as initialized
    echo "$RANDOM_PASSWORD" > "$INITIAL_CONFIG"
else
    # Check if WiFi password has changed
    INITIAL_PASSWORD=$(cat "$INITIAL_CONFIG")
    CURRENT_PASSWORD=$(uci get wireless.@wifi-iface[0].key)
    if [ "$CURRENT_PASSWORD" == "$INITIAL_PASSWORD" ]; then
        SSID=$(uci get wireless.@wifi-iface[0].ssid)
        echo "WiFi SSID: $SSID" > /dev/ttyS0
        echo "WiFi Password: $CURRENT_PASSWORD" > /dev/ttyS0
    fi
fi

# 6. Create Luci interface for Ntrip settings
mkdir -p openwrt/package/ntripclient/files/etc/config
cat << 'EOF' > openwrt/package/ntripclient/files/etc/config/ntripclient
config ntripclient 'general'
	option server 'rtk.gpspos.com'
	option port '2101'
	option username 'rtk_username'
	option password 'rtk_password'
	option interval '10'
	option device '/dev/ttyS1' # Default to ttyS1 (Serial Port 1)
EOF

# Add Luci module for ntripclient
mkdir -p openwrt/package/ntripclient/luasrc/controller
cat << 'EOF' > openwrt/package/ntripclient/luasrc/controller/ntripclient.lua
module("luci.controller.ntripclient", package.seeall)

function index()
    entry({"admin", "services", "ntripclient"}, cbi("ntripclient"), _("Ntrip Client"), 100).dependent = true
end
EOF

mkdir -p openwrt/package/ntripclient/luasrc/model/cbi
cat << 'EOF' > openwrt/package/ntripclient/luasrc/model/cbi/ntripclient.lua
m = Map("ntripclient", translate("Ntrip Client"))

s = m:section(TypedSection, "ntripclient", translate("Settings"))
s.addremove = false
s.anonymous = true

o = s:option(Value, "server", translate("Server"))
o.datatype = "host"

o = s:option(Value, "port", translate("Port"))
o.datatype = "port"

o = s:option(Value, "username", translate("Username"))
o.datatype = "string"

o = s:option(Value, "password", translate("Password"))
o.password = true

o = s:option(Value, "interval", translate("Interval"))
o.datatype = "uinteger"

o = s:option(ListValue, "device", translate("Device"))
o:value("/dev/ttyS0", "Serial Port 0")
o:value("/dev/ttyS1", "Serial Port 1")
o:value("/dev/ttyS2", "Serial Port 2")
o:value("/dev/ttyUSB0", "USB Port")

return m
EOF

echo "Script execution completed successfully."
