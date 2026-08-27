# SirrOS
[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=102)](https://github.com/commander-z3r0?tab=repositories)

**[SirrOS](https://sirr-os.github.io/)** is a privacy-focused Linux distribution based on Mobian, designed for users who value privacy, anonymity, and digital freedom on mobile devices. Sirr — meaning "secret" in Arabic — enhances Mobian's core with additional tools tailored for secure and anonymous online communication. It aims at activists, privacy advocates, journalists, and all users who demand privacy on their devices.

## Included Tools

| Tool           | Purpose                                    |
|----------------|--------------------------------------------|
| Carburetor     | Anonymous web browsing and routing         |
| torsocks       | Redirect applications through Tor          |
| dnscrypt-proxy | Encrypt and secure DNS queries             |
| proxychains    | Force any TCP connection through proxy (Tor, SOCKS, etc.) |
| macchanger     | Spoof MAC address                           |
| seahorse      | GUI for managing encryption keys and passwords |
| cryptsetup    | Disk encryption management (LUKS)           |
| thunderbird   | Email client with encryption support        |
| gnupg         | Encryption, signing, and key management      |
| mat2          | Remove metadata from files                    |
| onionshare    | Anonymous file sharing via Tor                |

## Roadmap

### Completed

- [x] Initial release based on Mobian
- [x] Set up GitHub Pages for the project
- [x] Configure GitHub Actions to compile images and upload them to Gofile
- [x] Integration of core privacy tools (Carburetor, torsocks, dnscrypt-proxy, proxychains, etc.)
- [x] Disk encryption support (cryptsetup/LUKS)
- [x] Set dnscrypt-proxy as the system’s default DNS resolver
- [X] Add package to manage [LUKS passphrases](https://github.com/Sirr-OS/sirrluks)
- [x] Add package to manage [AT commands](https://github.com/Sirr-OS/sirrat)
- [x] Add package to enable [duress PIN support in Phosh](https://github.com/Sirr-OS/phosh-pam-duress/)

### In Progress
- [ ] Add browser hardening profiles
- [ ] GUI helper for DNSCrypt-proxy status
- [ ] Sirr OS hardened kernel builds
- [ ] Hardened default system settings

## Installation

1. Download the latest SirrOS image from the [official repository](https://sirr-os.github.io/).
2. Flash it to your supported device(EMMC or SD card using tools like `dd` or Etcher.
3. Boot the device and follow the two-boot methode.
4. **Set date/time graphically**: Go to Settings > System > Date & Time.
5. **Restart DNSCrypt-proxy**: Open terminal and run ``sudo systemctl restart dnscrypt-proxy``. Verify with ping google.com
6. Enjoy a privacy-centered mobile experience.


## Contributing

Contributions, bug reports, and feature requests are welcome. Please fork the repository, make your changes, and open a pull request.

## License

SirrOS is open-source software licensed under the GNU General Public License v3.0.

***

**Privacy is a right. Take it back — in your pocket.**
