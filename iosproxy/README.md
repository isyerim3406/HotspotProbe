# iOSProxy v0.2.0 — standalone ARM64 rootless proxy

This fixes the v0.1.0 unresolved-dependencies installation problem by **removing Python 3**. The executable is compiled with Apple's iPhoneOS SDK and ad-hoc signed; no Pythonista or Python runtime is required.

- iOS 15+ / Dopamine rootless (iPhone 6s Plus)
- HTTP proxy: 9877; SOCKS5 TCP proxy: 9876
- Accessible only from 172.20.10.0/24 hotspot subnet and local loopback
- On iPhone 15: Settings → Wi-Fi → [your hotspot] → HTTP Proxy → Manual: Server 172.20.10.1, Port 9877, no authentication
- Installed as `com.chatin.iosproxy` launch daemon using `/var/jb/usr/libexec/iosproxy/iosproxyd`
- No changes to Apple's Personal Hotspot, sharing, NAT, DHCP, wifid or misd.
- Does NOT keep a sleeping iPhone 15 associated to an idle hotspot, and does not support UDP proxying. Apps ignoring HTTP proxy settings may not use it.
- Logs: `/var/mobile/iosproxy.err`.

Uninstall using Sileo. The older v0.1.0 is replaced in-place by v0.2.0.

## Development

GitHub Actions builds `iosproxyd.c` for iOS arm64 using the iPhoneOS SDK, checks the signature, then packs a rootless DEB using Ubuntu's dpkg-deb.

Protocol inspiration: https://github.com/nneonneo/iOS-SOCKS-Server
