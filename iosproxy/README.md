# iOSProxy — independent Dopamine rootless package (0.1.0)

A small Python 3 SOCKS5 and HTTP proxy service inspired by the **approach** in nneonneo/iOS-SOCKS-Server. This is a separate implementation, not Tethera, TetherM3, or a repackaged commercial tweak.

- Rootless iOS 15+ / Dopamine. **Requires Procursus Python 3** (installed via Sileo dependency).
- Installed background service: `com.chatin.iosproxy`; log `/var/mobile/iosproxy.log`; errors `/var/mobile/iosproxy.err`.
- HTTP proxy on port **9877**, SOCKS5 on port **9876**.
- Only accepts clients from `172.20.10.0/24` (typical iOS Personal Hotspot) or loopback.
- Does **not** create Wi-Fi, change hotspot state, patch `wifid`/`misd`/`sharingd`, or fix iPhone Wi-Fi disconnect after locking. It only proxies TCP while devices have an existing network link.
- Does not provide a full device-wide VPN and does not proxy UDP. No authentication, so do not broaden client allowlist without protecting access.

## Install and use

From GitHub Actions, download `iOSProxy-rootless-DEB`, extract and install the DEB using Sileo. On the iPhone 6s, first enable Apple's normal Personal Hotspot. On the iPhone 15, connect to its Wi-Fi and open **Settings > Wi-Fi > (i) > Configure Proxy > Manual**, server `172.20.10.1`, port `9877`; no authentication.

Test Safari browsing while the Wi-Fi link remains connected. Note that this does **not** prevent iPhone 15 from intentionally leaving a hotspot when locked.

To uninstall: remove `iOS Proxy Server` in Sileo. The service will be stopped; no tethering system settings are changed.

Original research project: https://github.com/nneonneo/iOS-SOCKS-Server
