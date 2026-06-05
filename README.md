# ez_airodump
A basic script that takes in the args I usually use for airodump-ng but automates most of the setup and cleanup for running airodump.
*************************************************************************************************************************************

ez_airodump.sh is a quick Bash helper script for doing easy, quick captures with airodump-ng.

It automates the repetitive setup steps needed before running airodump-ng, including:

- Unblocking Wi-Fi with rfkill
- Bringing the selected wireless interface down
- Killing processes that interfere with monitor mode
- Starting monitor mode with airmon-ng
- Identifying the created monitor interface
- Launching airodump-ng
- Optionally writing captures to disk
- Cleaning up monitor mode and restoring network services on exit

This script is intended for authorized wireless lab work, training, and assessment of networks you own or have explicit permission to test.
I use it for authorized Penetration Testing, keyword "authorized".

USING PENETRATION TESTING/RED TEAMING/HACKING TOOLS AGAINST SYSTEMS YOU DO NOT HAVE WRITTEN PERMISSION TO INTERACT WITH IS A CRIME

---

## Requirements

This script assumes the required tools are already installed and up to date.

Required tools:

- airmon-ng
- airodump-ng
- iw
- ip
- rfkill
- systemctl

These tools are all present on the current build of Kali Linux at time of commit.

## Typical packages that provide these tools include:

sudo apt install aircrack-ng iw iproute2 rfkill
