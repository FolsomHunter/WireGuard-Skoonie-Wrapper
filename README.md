
WireGuard Skoonie Wrapper servers as a wrapper for WireGuard, helping to simplify and automate many processes.

This program creates and stores all of its configuraion files in the same directory that the main bash file wg-skoonie.sh is stored. Be sure to put the file in the appropriate directory.

It helps with the following:

> adding and removing interfaces by automatically handling necessary configuration files.

> adding and removing devices
	> automatically determines the IP address of a new device by incrementing the highest IP address of pre-existing devices in the interfaces
	> automatically generating and deleting necessary configuration files
	> allows for devices to have names and descriptions associated with them.
	> auomatically generates the tunnel configuration file for the client device when a device is added.

For a more comprehensive list of what this program can do, run "./wg-skoonie.sh --help