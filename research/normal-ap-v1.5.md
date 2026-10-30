# v1.5 normal-AP research (2026-10-30)

## Verified signal
Reverse engineering of Apple Personal Hotspot beacons describes vendor-specific IE (element ID 221 / 0xDD), OUI 00:17:F2, OUI type 6. Example: `DD 0A 00 17 F2 06 01 01 03 03 00 00`.

- https://reverseengineering.stackexchange.com/questions/31710/decoding-the-apple-vendor-tag-in-the-802-11-beacon
- https://apple.stackexchange.com/questions/199163/how-does-ios-and-os-x-detect-when-a-wi-fi-network-is-a-personal-hotspot
- https://furiousmac.com/files/Reverse-Engineering-Apples-BLE-Continuity-Protocol-For-Tracking-OS-Fingerprinting-and-Behavioral-Profiling.pdf

## Device observation
iPhone 6s Plus (iOS 15/Dopamine) SoftAP with iPhone 15 client: client leaves when locked, sometimes while SoftAP remains on. v1.4 changed a *wifid notification callback argument* from `isInstantHotspot=YES` to `NO` but did not change beacon/probe-response frames; it did not fix disconnects. Bluetooth-off test also failed.

## Development gate
Find a validated iOS 15/Broadcom SoftAP firmware/control interface for setting beacon/probe response vendor IEs **before changing frames**. Neither `WiFiUsageSoftApSession` callbacks nor `sharingd` BLE changes change over-the-air 802.11 IEs. Keep existing personal hotspot NAT/DHCP intact. Do not modify arbitrary packet bytes or private IOCTLs without verifying signatures/semantics; could destabilize `wifid`.

## Test
Once a real on-air IE override exists: A/B compare client identification and locked-screen Wi-Fi continuity. No repeated diagnostic logging requested.
