# Third-Party Notices

## Kawasaki Rideology BLE protocol

The protocol constants, frame builder, byte-level parsers, and the
`z500_er500f_config.json` model configuration in
`packages/kawasaki_rideology_ble/` are a Dart port derived from:

> **homeassistant-kawasaki-rideology-ble**
> Copyright the project author(s) (GitHub: `Zen3515`)
> https://github.com/Zen3515/homeassistant-kawasaki-rideology-ble
> Licensed under the Apache License, Version 2.0
> http://www.apache.org/licenses/LICENSE-2.0

That project reverse-engineered the BLE GATT protocol Kawasaki's own
"Rideology the App" uses to talk to compatible motorcycles, and published
the result — including working byte-offset field layouts validated against
real captured frames — as free software.

This repository's Dart port (in `packages/kawasaki_rideology_ble/lib/`) is a
derivative work under the terms of the Apache License 2.0:

- The original copyright and license notice is preserved here.
- Ported files carry a header noting they are a Dart translation of the
  upstream Python source, with the specific upstream file named.
- No trademark rights are claimed or implied. "Kawasaki" and the Kawasaki
  logo belong to Kawasaki Motors, Ltd.; this project is unaffiliated.

A copy of the Apache License 2.0 is included at
[`packages/kawasaki_rideology_ble/LICENSE-APACHE-2.0-UPSTREAM.txt`](packages/kawasaki_rideology_ble/LICENSE-APACHE-2.0-UPSTREAM.txt)
for the portions derived from that project.

## Everything else

Original code in this repository (the app, the trip-tracking core, the
plugin architecture, and any code not listed above) is licensed under the
terms in [`LICENSE`](LICENSE) (MIT), unless a subdirectory states otherwise.
