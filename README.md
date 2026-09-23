# HotspotProbe

Diagnostic rootless tweak for an iPhone 6s Plus on iOS 15.x / Dopamine.

It does **not change Wi-Fi or hotspot behaviour**. It only loads into:

- `misd`
- `sharingd`
- `wifid`

and writes hotspot / HostAP / Wi-Fi related loaded images, Objective-C class names and method names to:

`/var/mobile/HotspotProbe.log`

## Build

GitHub Actions builds the `.deb` automatically.

1. Create a GitHub repository.
2. Upload all files/folders in this project.
3. Open **Actions**.
4. Run **Build HotspotProbe** if it did not start automatically.
5. Open the completed run.
6. Download the `HotspotProbe-rootless` artifact.
7. Extract it on the iPhone and install the `.deb` with Sileo or Filza.

## After install

Do **not** STOP/kill `misd`, `wifid` or `sharingd`.

Use Dopamine -> **Userspace Reboot** once, then enable Personal Hotspot and connect the iPhone 15.

After the hotspot has been active for about 30 seconds, run:

```sh
cat /var/mobile/HotspotProbe.log
```

If the output is large:

```sh
grep -Ei 'hostap|hotspot|tether|beacon|vendor|80211|wifi|internetsharing' /var/mobile/HotspotProbe.log
```

The log is diagnostic only. The next version can target the specific API revealed here.
