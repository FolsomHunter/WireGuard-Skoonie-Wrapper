
# WireGuard Skoonie Wrapper

This program serves as a wrapper for WireGuard. 

It is intended to assist those managing multiple devices across multiple VPNs. New interfaces (VPNs) can be easily created and devices can be easily added to allow for simplified management and tracking of several deployed networks. Multiple interfaces/VPNs can be ran and active at the same time on the same server. For example, this program allows a company to easily segregate devices deployed in the field by keeping each client's devices in their own VPN. 

This program is a bash script and is written for a Linux computer acting as the server/main connection point for a WireGuard setup.  

The program has been tested on Ubuntu 22.04.4 LTS.

This program creates and stores all of its configuration files in the same directory that the main bash file wg-skoonie.sh is stored. Be sure to put the file in the appropriate directory.

To install the bash script / program:

`wget -P /path/to/directory https://gitlab.com/hunter-schoonover/wireguard-skoonie-wrapper/-/raw/master/wg-skoonie.sh`

`sudo chmod +x /path/to/directory/wg-skoonie.sh`

To run the program:

`cd /path/to/directory`

`sudo ./wg-skoonie.sh`

Before using **wg-skoonie**, WireGuard should already be installed and ufw should already be enabled:

`sudo apt install wireguard`

`sudo ufw enable`

`sudo ufw status`

## Supported Commands

..................

**`addInterface [Interface Name] [Server Endpoint] [Listening Port] [Network Address] [Subnet Mask CIDR Notation] [Server IP Address on VPN]`**

Adds a new WireGuard interface and starts it. For WireGuard, adding a new interface is the equivalent of adding a new Virtual Private Network (VPN).

The system will be configured to start the interface automatically on system startup.

Make sure that the port specified in \[Server Endpoint\] and \[Listening Port\] is directed to the device running the WireGuard server. If the server is installed behind an internet router, ensure that the router is forwarding all traffic for the specified port to the server.

Multiple interfaces are NOT able to listen on the same port, so each interface needs its own port specified in \[Server Endpoint\] and \[Listening Port\]. This does NOT check to see if another interface is already listening on the specified port. That is the responsibility of the user.

This does NOT check to see if a previous interface with the same name already exists. It is the responsibility of the user to verify this to ensure there are no conflicts.

Currently, devices are only allowed IPv4 addresses on the Virtual Private Network (VPN) for any interface. Support for IPv6 will be added at a later date. WireGuard supports IPv6, but wg-skoonie does not.

Example 1:

`sudo ./wg-skoonie.sh addInterface "wg0" "90.47.205.206:1111" "1111" "10.27.0.0" "24" "10.27.0.1"`

Example 2:

`sudo ./wg-skoonie.sh addInterface "wg0" "90.47.205.206:1211" "1211" "10.27.0.0" "24" "10.27.0.1"`

Example 2:

`sudo ./wg-skoonie.sh addInterface "wg0" "wg.website.com:1211" "1211" "10.27.255.0" "24" "10.27.255.1"`

..................

**`removeInterface [Interface Name]`**

Removes a WireGuard interface by name.

This will remove all associated files and data from both WireGuard and wg-skoonie.

This will also automatically delete the ufw rule added to open the port.

Use with caution. This command cannot be undone.

Example Usage:

`sudo ./wg-skoonie.sh removeInterface "wg0"`

..................

**`addDevice [Interface Name] [New Device Name] [New Device Description]`**

Adds a new device to the specified interface. The IP address is automatically calculated by incrementing the highest IP address found in the wg-skoonie configuration files by 1.

If the resulting IP address is not within the subnet based on the network details found in the wg-skoonie configuration files, errors are thrown.

The tunnel configuration file, including private and public keys, are automatically generated for the newly added device.

In case the device being added to the VPN is a Linux device, a setup script will be automatically created to assist with the setup process.

Currently, devices are only allowed IPv4 addresses on the Virtual Private Network (VPN) for any interface. Support for IPv6 will be added at a later date. WireGuard supports IPv6, but wg-skoonie does not.

Example usage:

`sudo ./wg-skoonie.sh addDevice "wg0" "Kelly's Computer" "Kelly's main computer that he uses at home."`

..................

**`addDeviceSkoonieOnly [Interface Name] [New Device Public Key] [New Device IP Address] [New Device Name] [New Device Description]`**

Adds a new device to the wg-skoonie configuration files for the specified interface, but does NOT add the device to WireGuard.

This command is used when a device already exists in WireGuard and it now needs to be logged by wg-skoonie.

Currently, devices are only allowed IPv4 addresses on the Virtual Private Network (VPN) for any interface. Support for IPv6 will be added at a later date. WireGuard supports IPv6, but wg-skoonie does not.

Example usage:

`sudo ./wg-skoonie.sh addDeviceSkoonieOnly "wg0" "Y+bTUNHoyoyrlu9kTT6jEZNyW5l6cS7MMZ/CQs1KqDc=" "10.8.0.1" "Kelly's Computer" "Kelly's main computer that he uses at home."`

..................

**`removeDevice [Interface Name] [Device to Remove Index]`**

Removes the device specified by index from the specified interface.

The device is removed from both wg-skoonie and from WireGuard.

To determine a device index, use command `showInterfaceSkoonie [Interface Name]`.

Example usage:

`sudo ./wg-skoonie.sh removeDevice "wg0" "37"`

..................

**`showAllInterfacesSkoonie [Interface Name]`**

Lists all of the interfaces and the network details saved by skoonie.

Does not output the devices for each interface.

Example usage:

`sudo ./wg-skoonie.sh showAllInterfacesSkoonie`

..................

**`showInterfaceSkoonie [Interface Name]`**

Outputs the details saved by wg-skoonie for the specified interface.

Example usage:

`sudo ./wg-skoonie.sh showInterfaceSkoonie "wg0"`

..................

**`showInterfaceWireGuard [Interface Name]`**

Outputs the details saved by WireGuard for the specified interface.

Example usage:

`sudo ./wg-skoonie.sh showInterfaceWireGuard "wg0"`

..................
