# Two botnet cases at ISP customers: how I found the infected devices

[Read in English](README.en.md) | [Leer en Español](README.md)

Personal project based on two real cases I handled while working at an ISP
(fiber internet with PPPoE customers on MikroTik). I'm sharing it so anyone with
a similar problem can use what I did as a guide.

The data is anonymized: no names, no company and no real customer IPs. The only
real IPs are the botnet servers.

## Tools

- **Wireshark**, on an Ubuntu laptop connected to the customer's ONU.
- **MikroTik Torch**, on the customer's PPPoE interface.
- **The ONU web panel** (over HTTP), to see the connected devices and use the
  blacklist.
- **nmap**, to check the suspicious device's open ports.

## Both cases at a glance

| | Case 1 | Case 2 |
|---|---|---|
| What we saw from the MikroTik | Constant TCP connections to servers on unusual ports, plus UDP bursts | 34 Mbps UDP attack against a whole network (/24) |
| Infected device | Unnamed Wi‑Fi device | Counterfeit "amazon IPTV" stick + a phone |
| Pirate app in the house | MagisTV-like app on a TV box | Xuper TV on the stick |
| Control servers | 43.x / 101.47.x, TCP 100–299 | Alibaba Cloud (47.252.x / 47.90.x), TCP 9377 |
| Main behavior | Residential proxy (uploads as much as it downloads) | UDP DDoS attack (carpet bombing) |
| Did it change its MAC? | No | Yes, 112 different MACs |
| Did the ONU blacklist work? | Yes | No |
| Was the ONU infected? | No | No (confirmed) |

---

## Case 1: the culprit wasn't the TV box

### The problem

From the MikroTik we saw that a residential customer had traffic that wasn't
normal for a home:

- UDP bursts that hit the upload limit of their plan.
- Constant TCP connections to a group of servers, always on **unusual ports**
  (104, 129, 152, 184, 197…), a different one per server.

There was a generic Android TV box in the house, so it was the first suspect.

### Part one: on-site visit

I connected the laptop to a LAN port on the ONU and took two Wireshark captures,
one with the TV box off and one with it on.

What I found:

- **The TV box was connected twice**: by cable (.8) and by Wi‑Fi (.9). I noticed
  because both IPs announced the same Chromecast ID over mDNS. I thought they
  were two different devices.
- **It had ADB open on the network** (Android Debug Bridge). It announced it over
  mDNS as `adb-unidentified._adb._tcp.local`. This is one of the ways botnets
  take control of these devices.
- **It had a pirate IPTV app** (`com.android.msandroid`) with P2P traffic.
- There was another Wi‑Fi device **with no name** (.7), with a Wi‑Fi module from
  a Chinese manufacturer, that stood out.

On a switched network, the laptop can't see the other devices' traffic to the
internet. The capture was useful to know which devices were there and what they
announced, not to see the attack.

### Part two: isolating the device remotely

I did the rest from the office: I took devices off the network with the **ONU
blacklist** and checked in **Torch** whether the connections to the botnet
servers disappeared.

Before starting, Torch showed that almost all the customer's upload went to
those servers, while the download was normal HTTPS browsing. That pattern
(downloads from the internet and uploads the same amount somewhere else) is
what a **residential proxy** looks like: someone is browsing through the
customer's connection.

| Test | Result in Torch |
|---|---|
| TV box off | Botnet traffic continued |
| Blacklist the TV box (Wi‑Fi and cable) and the .7 | Botnet traffic at 0 |
| Enable only the .7 | Botnet traffic comes back |
| TV box connected, .7 blocked | Only normal traffic and the pirate app's P2P |
| .7 blocked permanently | Clean |

### Result

The infected device **was not the TV box**: it was the unnamed Wi‑Fi device (.7).
It was blocked on the ONU and traffic to the botnet dropped to zero. In the check
covering the whole next night (almost 15 hours) there were no connections to the
botnet, and the customer downloaded 17 times more than they uploaded, like any home.

The TV box was still flagged as a risk because of the pirate app and the open ADB.

---

## Case 2: a counterfeit stick that changed its MAC, and a phone

### The problem

Another customer, a few days later. This one wasn't acting as a proxy: **it was
attacking**. During the attack, Torch showed:

- **34 Mbps of sustained upload** (about 3,700 packets per second) and almost no
  download. In 44 seconds, 176 MB went out.
- A **UDP sweep ("carpet bombing")**: packets to all 256 addresses of a single
  /24 network, all from one source port to the same destination port, with no
  replies.
- At the same time, the device opened **119 connections in 40 seconds** to an
  Alibaba Cloud server on **TCP port 9377**. Most likely the server giving it
  orders.

The servers were different from case 1.

### The visit

This time I went on site while a coworker at the office watched Torch.

**1. The ONU device list.** While capturing with Wireshark, I opened the ONU's
connected-devices page in the browser. Since the panel runs over unencrypted
HTTP, the full response ended up in the capture. That's where the weird part
showed up:

- **112 entries with MAC `88:00:33:77:xx:xx`**: the first four bytes the same,
  only the last two changing. All Android 13 and none with a name.
- Every new MAC had requested a new IP, so the ONU's DHCP was already handing
  out addresses up to .137.
- The `88:00:33` vendor isn't registered, and the MAC doesn't have the bit phones
  set when they randomize it. The phones in the house did have names and kept
  their MAC.

It was **a single device making up a new MAC every time it connected**. That's
why the ONU blacklist is useless against it: you block it and it comes back with
another MAC.

**2. UPnP.** As soon as it connected, that device sent an SSDP search
(`M-SEARCH upnp:rootdevice`) looking for a router with UPnP. With UPnP a device
can open ports on the router without asking anyone.

**3. nmap.** The 100 most common TCP ports were closed. That makes sense: the
device doesn't wait for connections, it connects outward.

**4. The device.** Its network settings showed MAC `88:00:33:77:5b:89` and IP
.137: it was a **stick branded "amazon IPTV 5G"**. It's not a real Fire TV, it's
a clone with counterfeit branding. It had the pirate app **Xuper TV** installed.

### On-site isolation

| Time | Test | Result in Torch |
|---|---|---|
| 16:04 | Everything connected | 34 Mbps UDP attack + connections to port 9377 |
| 16:09 | I disconnect the stick | **The attack stops**, but connections to 9377 continue (now to other Alibaba servers) |
| 16:16 | I reset the ONU | — |
| 16:26 | Only the ONU connected, no devices | **Total silence**: the ONU is clean |
| 16:34 | I reconnect everything except the stick | Normal traffic, but **9377 comes back** |
| ~16:45 | I turn off Wi‑Fi on the phones one by one | When I turn off the owner's phone, **9377 disappears** |
| 16:51 | Final measurement | 0.3 Mbps upload vs 25 Mbps download: normal |

### Result

There were **two devices involved**:

1. **The counterfeit "amazon IPTV" stick with Xuper TV**: it was launching the
   UDP attack. The attack stopped as soon as I disconnected it.
2. **A Samsung Galaxy A56 phone** in the house: it kept the channel to the port
   9377 servers open. It had a huge number of apps installed, including a
   little-known browser and about 10 games.

I couldn't determine which app on the phone was responsible. The recommendation
for the owner was to uninstall what she doesn't use, run Google Play Protect and,
if it comes back, factory reset it.

### Still open

- With both devices connected at the same time, I can't tell whether the stick
  also used port 9377 or only the phone did.
- A few connections remained to a Tencent Cloud server on port 8002, with little
  traffic. It may be a legitimate app; I left it under observation.

---

## Prevention on MikroTik

The rules are in [`mikrotik.rsc`](mikrotik.rsc):

1. **Block the botnet servers** from both cases for the whole network. If another
   customer tries to connect to those IPs, the rule drops it and logs it.
2. **Block the port pattern** for suspicious customers: TCP 100–299 (case 1) and
   TCP 9377 (case 2). The server IPs changed several times during the tests, but
   the ports didn't.
3. **Limit new UDP connections** for suspicious customers, to slow down attacks
   like the one in case 2 without cutting off their internet.

A useful detail: after blocking, Torch shows connections with
**Tx > 0 and Rx = 0**. That's the infected device trying to connect and getting
no reply, which means the rule is working.

## What I learned

- **The first suspect isn't always the culprit.** In case 1 the TV box had
  everything to be the one, and it was another device.
- **There can be more than one infected device in the same house.** In case 2
  removing the stick stopped the attack, but the phone was still connected to
  the botnet.
- **A device can be connected by cable and Wi‑Fi at the same time**, or **change
  its MAC on every connection**. Before blocking by MAC, check the ONU's device list.
- **The ONU blacklist only removes Wi‑Fi devices**, and it doesn't work against a
  device that changes its MAC. In that case you need a whitelist or to remove
  the device.
- **To rule out the ONU, leave it alone.** If the line goes silent with no
  devices connected, the ONU is clean.
- **An ONU panel over HTTP is a risk**: anyone capturing on that network sees the
  device list and the panel password.
- **One clean measurement isn't enough.** These botnets can stay quiet for hours.
  It's worth checking again after 24 and 48 hours.

## If something similar happens to you

1. Find on the MikroTik which customer generates the traffic and use **Torch** to
   see which IPs and ports it connects to.
2. At the house, check with **Wireshark** which devices are there and what they
   announce (mDNS, SSDP). Look for open ADB, devices that show up twice and MACs
   that repeat with small variations.
3. Leave the **ONU alone** and measure: if it's silent, the infection is in a device.
4. Connect or **remove devices one by one** (blacklist, or turning off the
   device's Wi‑Fi) and measure with Torch after each change.
5. When you find the device, remove or block it and apply the rules in
   `mikrotik.rsc`.
6. Disable UPnP on the ONU and check again after 24 and 48 hours.

---

**Tools:** Wireshark · nmap · MikroTik RouterOS (Torch, firewall) · GPON ONU
