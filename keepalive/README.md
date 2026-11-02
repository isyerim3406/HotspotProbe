# Hotspot Keepalive experimental iOS 15 rootless DEB

Source pinned to maliv2/ios-hotspot-vpn-keepalive `2a92ed122fc9fd95ca48eb1999c8763fafa1637c`, MIT licensed. Only `hotspot.py`, `keepawake.py`, `hshold.py`, and signed `misctl` are packaged; VPN/pftun and proxy are excluded. This is not an officially supported upstream release and has not been tested on iPhone 6s Plus / iOS 15.

Requires rootless jailbreak with Procursus **python3** available in Sileo. No forced installation of dependencies, no backups, no changes to NAT/pf.

Crucial: iPhone 15 must be **Wi-Fi sync paired with a computer**, so port 62078 can be accessed from the iPhone 6s. Otherwise the hshold technique will not keep the client awake.

The script sets power assertions only while hotspot interface exists (KEEPAWAKE_ON_AC=0). hshold starts two lockdownd connections and tries misctl discover-session rearming. This may drain battery and private API compatibility is unverified on iOS 15.

Logs: `/var/jb/var/log/keepawake.log`, `/var/jb/var/log/hshold.log`. Removal: uninstall via Sileo; prerm stops daemon. This deliberately does NOT include pftun (kernel panic risk upstream notes).

Original: https://github.com/maliv2/ios-hotspot-vpn-keepalive
