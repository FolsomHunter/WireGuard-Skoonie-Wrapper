#!/bin/bash

##--------------------------------------------------------------------------------------------------
##--------------------------------------------------------------------------------------------------
# 
# WireGuard Skoonie Wrapper servers as a wrapper for WireGuard, helping to simplify and automate
# many processes.
#
# This program creates and stores all of its configuraion files in the same directory that the 
# main bash file wg-skoonie.sh is stored. Be sure to put the file in the appropriate directory.
#
# It helps with the following:
#
# > adding and removing interfaces by automatically handling necessary configuration files.
#
# > adding and removing devices
#	> automatically determines the IP address of a new device by incrementing the highest IP address
#		of pre-existing devices in the interfaces
#	> automatically generating and deleting necessary configuration files
#	> allows for devices to have names and descriptions associated with them.
#	> auomatically generates the tunnel configuration file for the client device when a device is added.
#
# For a more comprehensive list of what this program can do, run "./wg-skoonie.sh --help
# 

##--------------------------------------------------------------------------------------------------
# ::Global Variables

readonly PROGRAM_NAME="WireGuard Skoonie Wrapper"
readonly VERSION_NUMBER="1.0.6"

readonly WG_SKOONIE_INTERFACES_FOLDER_PATH="interfaces"
readonly WG_INTERFACES_FOLDER_PATH="/etc/wireguard"

declare -a deviceIpAddresses
declare -a devicePublicKeys
declare -a deviceNames
declare -a deviceDescriptions

declare -a deviceIpAddressesSorted

# end of ::Global Variables
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::addDeviceToSkoonieFilesAndGenerateClientConfigruationFile
# 
# Adds a device to the skoonie configuration files
#

addDeviceToSkoonieIniFileAndGenerateClientConfigruationFile() {

	local -n pNetworkValues=$1
	
	# $1	Client device index.
	# $2	Client private key.
	# $3	Client public key.
	# $4	Client IP address.
	# $5	Server public key.
	# $6	Allowed IP addresses from server and peers.
	# $7	Server enpoint. IP address or domain with port (e.g. wg.pushin.com:3666)
	# $8	CIDR for client and server IP addresses.
	# $9	Folder to save to.
	# $10	WireGuard Interface Name.
	deviceClientConfigFilePath=$(generateClientConfigFile "${pNetworkValues["KEY_NEW_DEVICE_INDEX"]}" "${pNetworkValues["KEY_NEW_DEVICE_PRIVATE_KEY"]}" "${pNetworkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]}" "${pNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}" "${pNetworkValues["KEY_SERVER_PUBLIC_KEY"]}" "${pNetworkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}" "${pNetworkValues["KEY_SERVER_ENDPOINT"]}" "${pNetworkValues["KEY_SUBNET_MASK_CIDR_NOTATION"]}" "${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${pInterfaceName}" "${pNetworkValues["KEY_INTERFACE_NAME"]}")
	
	addDeviceToSkoonieIniFile "$interfaceSkoonieIniFilePath" "${pNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}" "${pNetworkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]}" "${pNetworkValues["KEY_NEW_DEVICE_NAME"]}" "${pNetworkValues["KEY_NEW_DEVICE_DESC"]}"
	
	pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_FILE_ABS_PATH"]=$(realpath "${deviceClientConfigFilePath}")
	
}
# end of ::addDeviceToSkoonieConfigurationFilesAndGenerateClientConfigruationFile
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::addDeviceToWireGuard
# 
# Attempts to add the new device found in pNetworkDetails to WireGuard.
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values. Will be modified.
#
# Return:
# 
# Returns 0 upon success; 1 upon failure.
#

addDeviceToWireGuard() {

	local -n pNetworkValues=$1

	# Add device to WireGuard
	addDeviceToWireGuardCmd='wg set '"${pNetworkValues["KEY_INTERFACE_NAME"]}"' peer '"${pNetworkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]}"' allowed-ips "'"${pNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}"'"  2>&1'
	
	addDeviceWireGuardOutput=$(eval "${addDeviceToWireGuardCmd}")
	
	listDevicesWireGuard=$(sudo wg)

	echo "$listDevicesWireGuard" | grep -q "${pNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}"
	addToWireGuardWasSuccessful=$?
	
	if [[ ${addToWireGuardWasSuccessful} != "0" ]] ; then
		local errorMessage="	Failed to add device to WireGuard."
		errorMessage+="\n\n	Command used:"
		errorMessage+="\n\n		${addDeviceToWireGuardCmd}"
		errorMessage+="\n\n	Output message from WireGuard after command: "
		errorMessage+="\n\n		${addDeviceWireGuardOutput}"
		logDeviceNotAddedSuccessfullyMessage "${errorMessage}"
		return 1
	fi
	
	return 0
	
}
# end of ::addDeviceToWireGuard
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::addDeviceToSkoonieIniFile
# 
# Adds a new device to the skoonie ini file for the WireGuard interface.
#
# Parameters:
# $1	File path to skoonie ini file for the WireGuard interface.
# $2	IP address of new device.
# $3	New device public key.
# $4	Name of new device.
# $5	Description of new device.
#

addDeviceToSkoonieIniFile() {

	local pSkoonieIniFilePath=$1
	local pNewIpAddress=$2
	local pNewDevicePublicKey=$3
	local pNewDeviceName=$4
	local pNewDeviceDescription=$5

	cat << EOF >> $pSkoonieIniFilePath

[Device]
IP Address=${pNewIpAddress}
Public Key=${pNewDevicePublicKey}
Name=${pNewDeviceName}
Description=${pNewDeviceDescription}
EOF

}
# end of ::addDeviceToSkoonieIniFile
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::addDevice
# 
# Adds a new device to WireGuard and to the skoonieini files. The IP address is automatically 
# calculated by incrementing the IP address of the highest IP address found in the skoonieini 
# configuration file for the interface.
#
# $1	Interface name to add device to.
# $2	Name of new device.
# $3	Description of new device.
#

addDevice() {

	local pInterfaceName=$1
	local pNewDeviceName=$2
	local pNewDeviceDescription=$3
	
	local interfaceSkoonieIniFilePath="${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${pInterfaceName}/${pInterfaceName}.skoonieini"
	local interfaceSkoonieIniFileAbsolutePath="${PWD}/${interfaceSkoonieIniFilePath}"
	
	local statusGood=0
	
	checkInterfaceValidity "${pInterfaceName}" "${interfaceSkoonieIniFilePath}"
	statusGood=$?
	
	# Return with error if status not good
	if [[ "${statusGood}" -ne 0 ]] ; then
		return 1
	fi
	
	local -A networkValues
	
	# Read existing devices on this interface from file
	readInterfaceIniFile "$interfaceSkoonieIniFilePath" networkValues
	
	# Determine the index of the next device (new device)
	networkValues["KEY_NEW_DEVICE_INDEX"]=$(( ${#deviceIpAddresses[@]} + 1 ))
	
	# Determine the most recent IP addrress used (might be server address)
	local mostRecentIpAddressDottedDecimal
	
	if [[ ${#deviceIpAddressesSorted[@]} -eq 0 ]]; then
		mostRecentIpAddressDottedDecimal="${networkValues["KEY_SERVER_IP_ADDRESS_ON_VPN"]}"
	else
		mostRecentIpAddressDottedDecimal="${deviceIpAddressesSorted[-1]}"
	fi

	initializeNetworkValues "${pInterfaceName}" "${networkValues["KEY_SUBNET_MASK_CIDR_NOTATION"]}" "${networkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}" "${mostRecentIpAddressDottedDecimal}" networkValues
	
	# Calculate next consecutive IP address by adding 1 to the most recent IP address
	local newDeviceIpAsInteger="$(( ${networkValues["KEY_MOST_RECENT_IP_ADDRESS_INTEGER"]}+1 ))"
	
	# Stuff user input into network values
	setNewDeviceValues "${newDeviceIpAsInteger}" "${pNewDeviceName}" "${pNewDeviceDescription}" networkValues
	
	outputNetworkValuesToConsole networkValues
	
	# Check if IP address is allowed
	if [[ "${networkValues["KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET"]}" != "1" ]]
	then
		logDeviceNotAddedSuccessfullyMessage "${networkValues["KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET_MSG"]}"
		return 1
	fi
	
	# Generate private and public keys for the new device
	networkValues["KEY_NEW_DEVICE_PRIVATE_KEY"]=$(wg genkey)
    networkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]=$(echo "${networkValues["KEY_NEW_DEVICE_PRIVATE_KEY"]}" | wg pubkey)
	
	addDeviceToWireGuard networkValues
	statusGood=$?
	
	# Return with error if status not good
	if [[ "${statusGood}" -ne 0 ]] ; then
		return 1
	fi
	
	addDeviceToSkoonieIniFileAndGenerateClientConfigruationFile networkValues
	
	generateNewDeviceSetUpScriptForLinux networkValues
	
	logDeviceAddedSuccessfullyMessage networkValues
	
}
# end of ::addDevice
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::addDeviceToSkoonieOnly
# 
# Adds a new device to the skoonieini files but does not add the device to WireGuard. This is used
# when a device was previously added to WireGuard, but not added to the wireguard skoonie wrapper.
#
# Parameters:
#
# $1	Interface name.
# $2	New device public key.
# $3	New device IP address in dotted-decimal format.
# $4	New device name.
# $5	New device Description.
#

addDeviceToSkoonieOnly() {

	local pInterfaceName=$1
	local pNewDevicePublicKey=$2
	local pNewDeviceIpDottedDecimal=$3
	local pNewDeviceName=$4
	local pNewDeviceDescription=$5
	
	local interfaceSkoonieIniFilePath="${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${pInterfaceName}/${pInterfaceName}.skoonieini"
	local interfaceSkoonieIniFileAbsolutePath="${PWD}/${interfaceSkoonieIniFilePath}"
	
	local statusGood=0
	
	checkInterfaceValidity "${pInterfaceName}" "${interfaceSkoonieIniFilePath}"
	statusGood=$?
	
	# Return with error if status not good
	if [[ "${statusGood}" -ne 0 ]] ; then
		return 1
	fi
	
	local -A networkValues
	
	# Read existing devices on this interface from file
	readInterfaceIniFile "$interfaceSkoonieIniFilePath" networkValues

	# Determine the most recent IP addrress used
	local mostRecentIpAddressInteger="${deviceIpAddressesSorted[-1]}"

	initializeNetworkValues "${pInterfaceName}" "${networkValues["KEY_SUBNET_MASK_CIDR_NOTATION"]}" "${networkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}" "${mostRecentIpAddressInteger}" networkValues
	
	# Convert user inputted IP address from dotted-decimal format to integer format
	local newDeviceIpAsInteger="$(convertIpAddressDottedDecimalToInteger "${pNewDeviceIpDottedDecimal}")"	
	
	# Stuff user input into network values
	setNewDeviceValues "${newDeviceIpAsInteger}" "${pNewDeviceName}" "${pNewDeviceDescription}" networkValues
	
	# Check if IP address is allowed
	if [[ "${networkValues["KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET"]}" != "1" ]]
	then
		logDeviceNotAddedSuccessfullyMessage "${networkValues["KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET_MSG"]}"
		return 1
	fi
	
	# Private key is not known since user only supplies public key. Not necessary anyways since
	# client tunnel configuration file will not be generated
	networkValues["KEY_NEW_DEVICE_PRIVATE_KEY"]=""
	
    # Public key was provided by user
	networkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]="${pNewDevicePublicKey}"
	
	addDeviceToSkoonieIniFile "$interfaceSkoonieIniFilePath" "${networkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}" "${networkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]}" "${networkValues["KEY_NEW_DEVICE_NAME"]}" "${networkValues["KEY_NEW_DEVICE_DESC"]}"
	
	logDeviceAddedToSkoonieOnlySuccessfullyMessage networkValues

}
# end of ::addDeviceToSkoonieOnly
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::addInterface
# 
# Adds a new interface to WireGuard and to the skoonieini files.
#
# $1	Name of interface to add.
# $2 	Server endpoint (IP address or Domain Name with port).
# $3	Listening port.
# $4	Network address in dotted-decimal format.
# $5	Subnet mask in CIDR notation.
# $6	Server IP address on VPN.
#

addInterface() {

	local pInterfaceName=$1
	local pServerEndpoint=$2
	local pListeningPort=$3
	local pNetworkAddressDottedDecimal=$4
	local pSubnetMaskAsCidrNotation=$5
	local pServerIpAddress=$6
	
	local sanitizedInterfaceName="${pInterfaceName// /-}"
	
	local yellowFontColor="\033[33m"
	local resetColors="\033[0m"
	
	local interfaceSkoonieIniFilePath="${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}/${sanitizedInterfaceName}.skoonieini"
	local interfaceSkoonieIniFileAbsolutePath="${PWD}/${interfaceSkoonieIniFilePath}"
	
	mkdir -p "${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}/"

	# Generate the private key
	local privateKey=$(wg genkey)

	# Generate the public key from the private key
	local publicKey=$(echo "${privateKey}" | wg pubkey)

	# Save the private key to a file
	echo "${privateKey}" > "${WG_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}-private.key"

	# Save the public key to a file
	echo "${publicKey}" > "${WG_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}-public.key"

	# Removes any permissions on the file for users and groups other than the root 
	# user to ensure that only it can access the private key:
	sudo chmod go= ${WG_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}-private.key
	
	local interfaceDetails
	interfaceDetails+="[Interface]"
	interfaceDetails+="\n"
	interfaceDetails+="PrivateKey = ${privateKey}"
	interfaceDetails+="\n"
	interfaceDetails+="Address = ${pServerIpAddress}/${pSubnetMaskAsCidrNotation}"
	interfaceDetails+="\n"
	interfaceDetails+="ListenPort = ${pListeningPort}"
	interfaceDetails+="\n"
	
	# Interface file should have SaveConfig set to false when first turning on the
	# interface. This is because the interface sometimes has to be turned on and off
	# a few times until it detects the config file. SaveConfig has to be set to false
	# because if the interface is turned on while SaveConfig is true but the Interface
	# failed to load settings from the config file, the config file will be overwritten
	# with the blank details read in by WireGuard.
	local interfaceFileOutputWithSaveConfigFalse="${interfaceDetails}"
	interfaceFileOutputWithSaveConfigFalse+="SaveConfig = false"
	echo -e "${interfaceFileOutputWithSaveConfigFalse}" > "${WG_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}.conf"
	
	# Allow traffic to specified port:
	sudo ufw allow ${pListeningPort}/udp
	
	# Enable wireguard interface to start on boot
	sudo systemctl enable wg-quick@${sanitizedInterfaceName}.service
	
	local errorStatus=1
	for (( i=0; i<=10; i++ )); do
		
		sudo wg-quick up ${pInterfaceName}
		echo "wg-quick up attempt #${i}"
	
		if sudo wg show ${pInterfaceName} 2>/dev/null | grep -q 'public key'; then
			errorStatus=0
			break
		else
			sudo wg-quick down ${pInterfaceName}
			sleep 1
		fi
		
	done
	
	if [[ "${errorStatus}" -ne 0 ]]
	then
		local msg
		msg+="Failed to start interface."
		msg+="\n"
		msg+="\n"
		msg+="	Please see above for details."
		logErrorMessage "${msg}"
		return 1
	fi
	
	# Resave interface file with SaveConfig set to true
	
	sudo wg-quick down ${pInterfaceName}
	
	local interfaceFileOutputWithSaveConfigFalse="${interfaceDetails}"
	interfaceFileOutputWithSaveConfigFalse+="SaveConfig = true"
	echo -e "${interfaceFileOutputWithSaveConfigFalse}" > "${WG_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}.conf"
	
	sudo wg-quick up ${pInterfaceName}
	
	# Output service status:
	sudo systemctl status wg-quick@${sanitizedInterfaceName}.service
	
	# initialize network values to be saved to file
	local -A networkValues
	networkValues["KEY_SERVER_ENDPOINT"]="${pServerEndpoint}"
	networkValues["KEY_SERVER_LISTENING_PORT"]="${pListeningPort}"
	networkValues["KEY_SERVER_PUBLIC_KEY"]="${publicKey}"
	networkValues["KEY_SERVER_IP_ADDRESS_ON_VPN"]="${pServerIpAddress}"
	networkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]="${pNetworkAddressDottedDecimal}"
	networkValues["KEY_SUBNET_MASK_CIDR_NOTATION"]="${pSubnetMaskAsCidrNotation}"
	
	# Output network details to skoonieini file
	local skoonieIniFileOutput
	skoonieIniFileOutput+=$(generateNetworkDetailsForSkoonieIniFile networkValues)
	echo -e "${skoonieIniFileOutput}" > "${interfaceSkoonieIniFilePath}"
	
	# Made it to here, which means we had success
	local msg
	msg+="	Interface '${sanitizedInterfaceName}' was added successfully."
	msg+="\n"
	msg+="\n"
	msg+="	The interface configuration file for WireGuard was saved to:"
	msg+="\n"
	msg+="\n"
	msg+="		${yellowFontColor}${WG_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}.conf${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	The public key for the server was saved to:"
	msg+="\n"
	msg+="\n"
	msg+="		${yellowFontColor}${WG_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}-public.key${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	The private key for the server was saved to:"
	msg+="\n"
	msg+="\n"
	msg+="		${yellowFontColor}${WG_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}-private.key${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	The interface configuration file for wg-skoonie was saved to:"
	msg+="\n"
	msg+="\n"
	msg+="		${yellowFontColor}${interfaceSkoonieIniFileAbsolutePath}${resetColors}"
	logSuccessMessage "${msg}"
	
}
# end of ::addInterface
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::checkInterfaceValidity
# 
# Determines if pInterfaceName is a valid interface in both WireGuard and the Skoonie WireGuard 
# wrapper. Errors will be logged if it is not valid.
#
# Parameters:
#
# $1	Interface name to check for.
# $2	File path to interface skoonieini configuration file.
#
# Return:
#
# true if interface is valid in both WireGuard and Skoonie WireGuard wrapper; false otherwise.
#

checkInterfaceValidity() {

	local pInterfaceName=$1
	local pInterfaceSkoonieIniFilePath=$2
	local interfaceSkoonieIniFileAbsolutePath="${PWD}/${pInterfaceSkoonieIniFilePath}"
	
	local yellowFontColor="\033[33m"
	local resetColors="\033[0m"
	
	statusGood=0

	wg show "${pInterfaceName}" &> /dev/null
	local interfaceExistsInWireGuard=$?

	[ -e "${pInterfaceSkoonieIniFilePath}" ]
	local interfaceSkoonieIniFileExists=$?

	if [[ $interfaceExistsInWireGuard -ne 0 && $interfaceSkoonieIniFileExists -ne 0 ]]; then
		local errorMsg=""
		errorMsg+="Interface '${pInterfaceName}' cannot be found in WireGuard and the wg-skoonie skoonieini configuration file cannot be found."
		errorMsg+="\n"
		errorMsg+="\n	File path  used for skoonieini configruation file:"
		errorMsg+="\n"
		errorMsg+="\n		${yellowFontColor}${interfaceSkoonieIniFileAbsolutePath}${resetColors}"
		logErrorMessage "${errorMsg}"
		statusGood=1
	elif [[ $interfaceExistsInWireGuard -ne 0 ]]; then
		logErrorMessage "Interface '${pInterfaceName}' cannot be found in WireGuard."
		statusGood=1
	elif [[ $interfaceSkoonieIniFileExists -ne 0 ]]; then
		local errorMsg=""
		errorMsg+="The wg-skoonie skoonieini configuration file cannot be found for interface '${pInterfaceName}'."
		errorMsg+="\n"
		errorMsg+="\n	File path expected for skoonieini configruation file:"
		errorMsg+="\n"
		errorMsg+="\n		${yellowFontColor}${interfaceSkoonieIniFileAbsolutePath}${resetColors}"
		logErrorMessage "${errorMsg}"
		statusGood=1
	fi
	
	return "${statusGood}"
	
}
# end of ::checkInterfaceValidity
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::convertIpAddressDottedDecimalToInteger
# 
# Converts the passed in IP address represented by the conventional dottted-decimal format to an
# integer.
#
# For example, 255.255.255.0 is converted to 4294967040.
#
# Parameters:
#
# $1	IP address represented by the conventional dottted-decimal format.
#
# Return:
#
# Returns the IP address represented as an integer.
#

convertIpAddressDottedDecimalToInteger() {

    local ipAddressAsDottedDecimal=$1
	
	local octets

	IFS='.' read -r -a octets <<< "$ipAddressAsDottedDecimal"

	resultsInteger=$(( (${octets[0]} << 24) | (${octets[1]} << 16) | (${octets[2]} << 8) | (${octets[3]}) ))

	echo $resultsInteger
   
}
# end of ::convertIpAddressDottedDecimalToInteger
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::convertIpAddressIntegerToPadded32BitBinaryString
# 
# Converts the passed in IP address represented by an integer to binary format in a string. The 
# binary expression is padded with 0s to be a full 32 bits.
#
# For example:
# 	4294967040 	converted to	11111111111111111111111100000000
# 	184549120	converted to	00001010111111111111111100000000
#
# Parameters:
#
# $1	IP address represented as an integer.
#
# Return:
#
# Returns the IP address represented as a 32-bit binary value in a string.
#

convertIpAddressIntegerToPadded32BitBinaryString() {

    local ipAddressAsInteger=$1

	# Desired width of the binary number with padding
	local width=32

	# Create string with thirty-two 0s
	local zerosPadding=$(printf '%0*d' $width)

	binary=$(echo "obase=2; $ipAddressAsInteger" | bc)
	
	binaryWithPadding=$(echo "${zerosPadding:0:$width-${#binary}}$binary")
	
	echo $binaryWithPadding
   
}
# end of ::convertIpAddressIntegerToPaddedBinaryString
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::convertIpAddressIntegerToDottedDecimalString
# 
# Converts the passed in IP address represented by an integer to the conventional dottted-decimal
# string.
#
# For example, 4294967040 is converted to 255.255.255.0.
#
# Parameters:
#
# $1	IP address represented as an integer.
#
# Return:
#
# Returns the IP address represented as the conventional dottted-decimal format in a string.
#

convertIpAddressIntegerToDottedDecimalString() {

    local ipAddressAsInteger=$1

	local -a stringArray

	for (( i=0; i<=3; i++ )); do

		local bitshift=$(( ${i} * 8 ))

		local octet=$(( (ipAddressAsInteger >> ${bitshift}) & 0xFF ))
		
		stringArray+=("${octet}")
		
	done
   
	resultsString="${stringArray[3]}.${stringArray[2]}.${stringArray[1]}.${stringArray[0]}"

	echo $resultsString
   
}
# end of ::convertIpAddressIntegerToDottedDecimalString
##--------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------------------------
# ::convertSubnetMaskCidrToSubnetMaskDottedDecimal
# 
# Converts the passed in subnet mask in CIDR notation to the equivalent subnet mask in 
# dotted-decimal notation.
#
# For example:
#	IP Address & CIDR	CIDR	Subnet Mask		IP Addresses Ranges
#	10.255.255.0/24		24		255.255.255.0	10.255.255.0 to 10.255.255.255
#	10.255.255.0/22		24		255.255.252.0	10.255.252.0 to 10.255.255.255
#
#	Note that IP addresses 10.255.255.0 (lowest) and 10.255.255.255 (highest) values are typically
#	reserved for special functions.
#
# Parameters:
#
# $1	Subnet mask in CIDR notation to convert to the equivalent subnet mask in dotted-decimal 
#		notation.
#
# Return:
#
# Returns the dotted-decimal subnet mask derived from the passed in CIDR dotted-decimal.
#

convertCidrToSubnetMask() {

    local cidr=$1

    # Calculate the number of network bits
    local network_bits=$(( 32 - cidr ))

    # Create a bitmask with the leftmost n bits set to 1
    local bitmask=$(( (1 << network_bits) - 1 ))

    # Convert the bitmask to dotted-decimal notation
    local octet1=$(( bitmask >> 24 & 255 ))
    local octet2=$(( bitmask >> 16 & 255 ))
    local octet3=$(( bitmask >> 8 & 255 ))
    local octet4=$(( bitmask & 255 ))

    # Print the subnet mask
    echo "$(( 255 - octet1 )).$(( 255 - octet2 )).$(( 255 - octet3 )).$(( 255 - octet4 ))"
	
}
# end of ::convertCidrToSubnetMask
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateClientConfigFile
# 
# Generates the client configuration file using the passed in parameters.
#
# Upon return, the client configuration file will be saved to:
# 	[Folder]/[WireGuard Interface Name]/device[Device index]/[WireGuard Interface Name].conf
# 
# For example:
#	/etc/wireguard/pickwick/device0/pickwick.conf
#
# Parameters:
#
# $1	Client device index.
# $2	Client private key.
# $3	Client public key.
# $4	Client IP address.
# $5	Server public key.
# $6	Allowed IP addresses from server and peers.
# $7	Server enpoint. IP address or domain with port (e.g. wg.pushin.com:3666)
# $8	Subnet mask in CIDR notation for client and server IP addresses.
# $9	Folder to save to.
# $10	WireGuard Interface Name.
#
# Return:
#
# The file path to the client configuration file.
#


generateClientConfigFile() {

    local clientDeviceIndex=$1
	local clientPrivateKey=$2
	local clientPublicKey=$3
	local clientIpAddress=$4
	
	local serverPublicKey=$5
	local allowedIps=$6
	local serverEndpoint=$7
	
	local subnetMaskCidrNotation=$8
	
	local folder=$9
	local wireguardInterfaceName=${10}
	
	local folderPath="$folder/device$clientDeviceIndex"
	local filePath="$folderPath/$wireguardInterfaceName.conf"
	
	mkdir -p "$folderPath"
	
	cat > "$filePath" <<EOF
[Interface]
PrivateKey = $clientPrivateKey
Address = $clientIpAddress/$subnetMaskCidrNotation

[Peer]
PublicKey = $serverPublicKey
Endpoint = $serverEndpoint
AllowedIPs = $allowedIps/$subnetMaskCidrNotation
EOF

	echo "$filePath"

}
# end of ::generateClientConfigFile
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateDeviceDetails
# 
# Generates and echos device details for the device specified by index.
#
# Parameters:
#
# $1	Index of device to generate details for.
#

generateDeviceDetails() {

	local pDeviceIndex=$1
	
	local msg=""
	msg+="	Device details according to wg-skoonie:"
	msg+="\n"
	msg+="\n"
	msg+="	Device IP Address	${deviceIpAddresses[$pDeviceIndex]}"
	msg+="\n"
	msg+="	Device Public Key	${devicePublicKeys[$pDeviceIndex]}"
	msg+="\n"
	msg+="	Device Name		${deviceNames[$pDeviceIndex]}"
	msg+="\n"
	msg+="	Device Description	${deviceDescriptions[$pDeviceIndex]}"
	
	echo "${msg}"

}
# end of ::generateDeviceDetails
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNetworkDetailsForSkoonieIniFile
# 
# Generates and returns network details that can be written to the skoonie ini file.
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values.
#

generateNetworkDetailsForSkoonieIniFile() {

	local -n pNetworkValues724=$1
	
	local output
	
	output+="[Network]"
	output+="\n"
	output+="Server Endpoint=${pNetworkValues724["KEY_SERVER_ENDPOINT"]}"
	output+="\n"
	output+="Server Listening Port=${pNetworkValues724["KEY_SERVER_LISTENING_PORT"]}"
	output+="\n"
	output+="Server Public Key=${pNetworkValues724["KEY_SERVER_PUBLIC_KEY"]}"
	output+="\n"
	output+="Server IP Address On VPN=${pNetworkValues724["KEY_SERVER_IP_ADDRESS_ON_VPN"]}"
	output+="\n"
	output+="Network Address=${pNetworkValues724["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}"
	output+="\n"
	output+="Subnet Mask CIDR Notation=${pNetworkValues724["KEY_SUBNET_MASK_CIDR_NOTATION"]}"
	
	echo "${output}"

}
# end of ::generateNetworkDetailsForSkoonieIniFile
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNewDeviceSetUpScriptForLinux
# 
# Generates a linux setup script for the new device that helps install the tunnel configuration 
# file.
#
# On Windows, importing a tunnel configuration file is a very simple process. On Linux, it is more
# involved.
#
# Upon return, the client configuration file will be saved to:
# 	[Device Folder]/[WireGuard Interface Name]-setup.sh
#
# 	[Device Folder] is extracted from pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_FILE_ABS_PATH"]
# 
# For example:
#	/etc/wireguard/pickwick/device0/pickick-setup.sh
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values.
#


generateNewDeviceSetUpScriptForLinux() {

    local -n pNetworkValues=$1
	
	# Extract the directory path
	local folderAbsPath=$(dirname "${pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_FILE_ABS_PATH"]}")
	
	# Extract the interface name for the new device without the config file extension
	local interfaceConfigFile=$(basename "${pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_FILE_ABS_PATH"]}")	# Get filename from path
	local interfaceName="${interfaceConfigFile%.*}"															# Strip the extension
	
	local scriptFilename="${interfaceName}-setup.sh"
	
	local scriptFileAbsPath="${folderAbsPath}/${scriptFilename}"
	
	pNetworkValues["NEW_DEVICE_CLIENT_CONFIG_FILE_SET_UP_SCRIPT_ABS_PATH"]="${scriptFileAbsPath}"
	
	cat > "${scriptFileAbsPath}" <<EOF
#!/bin/bash

readonly WG_INTERFACES_FOLDER_PATH="${WG_INTERFACES_FOLDER_PATH}"
readonly INTERFACE_NAME="${interfaceName}"
readonly INTERFACE_CONFIG_FILENAME="\${INTERFACE_NAME}.conf"

greenBackground="\033[30;42m"
redBackground="\033[41m"
yellowFontColor="\033[33m"
resetColors="\033[0m"

exitStatus=0
backgroundColor=""
headerMessage=""
msg=""

exitProgram() {

	output=""
	output+="\n"
	output+="\n"
	output+="\${backgroundColor}"
	output+="\n"
	output+="	!! \${headerMessage} !! start"
	output+="\${resetColors}"
	output+="\n"
	output+="\n"
	output+="\n	\${msg}"
	output+="\n"
	output+="\n"
	output+="\${backgroundColor}"
	output+="\n"
	output+="	!! \${headerMessage} !! end"
	output+="\${resetColors}"
	output+="\n"
	output+="\n"

	printf "\${output}"

	exit "\${exitStatus}"

}


# Check if wireguard is installed
if ! command -v wg >/dev/null 2>&1; then

	# Error
	
	exitStatus="1"
	
	backgroundColor="\${redBackground}"
	
	headerMessage="ERROR"
	
	msg+="An installation of WireGuard cannot be found on this system."
	
	exitProgram

fi

if [[ ! -d "\${WG_INTERFACES_FOLDER_PATH}" ]]; then
	echo ""
    echo "WireGuard interfaces folder path does not already exist. Creating now:"
	echo ""
	echo "	\${yellowFontColor}\${WG_INTERFACES_FOLDER_PATH}\${resetColors}"
	echo ""
	sudo mkdir -p "\${WG_INTERFACES_FOLDER_PATH}"
fi

echo ""
echo "Moving configuration file to WireGuard interfaces folder."
echo "	from 	\${yellowFontColor}\${INTERFACE_CONFIG_FILENAME}\${resetColors}"
echo "	to 		\${yellowFontColor}\${WG_INTERFACES_FOLDER_PATH}\${resetColors}"

sudo mv -iv "\${INTERFACE_CONFIG_FILENAME}" "\${WG_INTERFACES_FOLDER_PATH}"

echo ""
echo "Enabling interface to start on boot."

# Enable wireguard interface to start on boot
sudo systemctl enable wg-quick@\${INTERFACE_NAME}.service

echo ""
echo "Starting interface now...."

errorStatus=1
for (( i=0; i<=10; i++ )); do
	
	sudo wg-quick up \${INTERFACE_NAME}
	echo ""
	echo "wg-quick up attempt #\${i}"

	if sudo wg show \${INTERFACE_NAME} 2>/dev/null | grep -q 'public key'; then
		errorStatus=0
		break
	else
		sudo wg-quick down \${INTERFACE_NAME}
		sleep 1
	fi
	
done

exitStatus=0
backgroundColor=""
headerMessage=""
msg=""

if [[ "\${errorStatus}" -ne 0 ]]
then

	# Error
	
	exitStatus="1"
	
	backgroundColor="\${redBackground}"
	
	headerMessage="ERROR"
	
	msg+="Failed to start interface '\${INTERFACE_NAME}'."
	msg+="\n"
	msg+="\n"
	msg+="	Please see above for details."
	
	exitProgram

else

	#SUCCESS
	
	exitStatus="0"
	
	backgroundColor="\${greenBackground}"
	
	headerMessage="SUCCESS"
	
	msg+="Interface '\${INTERFACE_NAME}' was added and started successfully."
	msg+="\n"
	msg+="\n"
	msg+="	Please see above for details."
	msg+="\n"
	msg+="\n"
	msg+="	The following command can now be used at any time to verify that the interface is running"
	msg+="\n"
	msg+="	and connected to the VPN:"
	msg+="\n"
	msg+="\n"
	msg+="		\${yellowFontColor}sudo wg show \${INTERFACE_NAME}\${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	If this system is properly connected to the VPN, the output will look something like this:"
	msg+="\n"
	msg+="\n"
	msg+="\${yellowFontColor}"
	msg+="		interface: stests"
	msg+="\n"
	msg+="		public key: YR2/kYQ0cyTGxG/Xl8DT08Qz3OR30R4psNgp19ZyDhA="
	msg+="\n"
	msg+="		private key: (hidden)"
	msg+="\n"
	msg+="		listening port: 31491"
	msg+="\n"
	msg+="\n"
	msg+="		peer: IwjK4SklFZPc/ethaO6eGTqRTZ+1cn2+vPHtJaptCH4="
	msg+="\n"
	msg+="		endpoint: 98.32.230.166:1001"
	msg+="\n"
	msg+="		allowed ips: 10.7.0.0/24"
	msg+="\n"
	msg+="		latest handshake: 35 seconds ago"
	msg+="\n"
	msg+="		transfer: 329.96 KiB received, 107.75 KiB sent"
	msg+="\${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	If this system is NOT properly connected to the VPN, the output will look something like this:"
	msg+="\n"
	msg+="\n"
	msg+="\${yellowFontColor}"
	msg+="		interface: stests"
	msg+="\n"
	msg+="		public key: YR2/kYQ0cyTGxG/Xl8DT08Qz3OR30R4psNgp19ZyDhA="
	msg+="\n"
	msg+="		private key: (hidden)"
	msg+="\n"
	msg+="		listening port: 31491"
	msg+="\n"
	msg+="\n"
	msg+="		peer: IwjK4SklFZPc/ethaO6eGTqRTZ+1cn2+vPHtJaptCH4="
	msg+="\n"
	msg+="		endpoint: 98.32.230.166:1001"
	msg+="\n"
	msg+="		allowed ips: 10.7.0.0/24"
	msg+="\${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	This setup script file can now be deleted from the system."
	
	exitProgram

fi
EOF

}
# end of ::generateNewDeviceSetUpScriptForLinux
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::initializeNetworkValues
# 
# Initializes network values based on passed in parameters. All initialized values are stored in
# the passed networkValues array as key-value pairs.
#
# Parameters:
#
# $1	Interface name.
# $2	Subnet mask in CIDR notation format.
# $3	Network address in dotted-decimal format.
# $4	Most recently saved IP address in dotted-decimal format.
# $5	Reference to associative array key-value pair for network values. Will be modified.
#
# Return:
#
# All initialized values are stored in the passed in networkValues array as key-value pairs. 
#

initializeNetworkValues() {

	local pInterfaceName=$1
	local pSubnetMaskAsCidrNotation=$2
	local pNetworkAddressAsDottedDecimalString=$3
    local pMostRecentIpAddressAsDottedDecimalString=$4
	local -n pNetworkValues=$5
	
	# Get subnet mask from CIDR read in from ini file
	local subnetMaskAsDottedDecimalNotation=$(convertCidrToSubnetMask "$pSubnetMaskAsCidrNotation")
	
	pNetworkValues["KEY_INTERFACE_NAME"]="${pInterfaceName}"

	pNetworkValues["KEY_SUBNET_MASK_INTEGER"]="$(convertIpAddressDottedDecimalToInteger "${subnetMaskAsDottedDecimalNotation}")"
	pNetworkValues["KEY_SUBNET_MASK_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_SUBNET_MASK_INTEGER"]}")"
	pNetworkValues["KEY_SUBNET_MASK_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_SUBNET_MASK_INTEGER"]}")"
	
	pNetworkValues["KEY_INVERTED_SUBNET_MASK_INTEGER"]="$(( ~(${pNetworkValues["KEY_SUBNET_MASK_INTEGER"]}) & 0xFFFFFFFF ))"
	pNetworkValues["KEY_INVERTED_SUBNET_MASK_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_INVERTED_SUBNET_MASK_INTEGER"]}")"
	pNetworkValues["KEY_INVERTED_SUBNET_MASK_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_INVERTED_SUBNET_MASK_INTEGER"]}")"

	pNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"]="$(convertIpAddressDottedDecimalToInteger "${pNetworkAddressAsDottedDecimalString}")"
	pNetworkValues["KEY_NETWORK_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"]}")"
	pNetworkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"]}")"
	
	pNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_INTEGER"]="$(( pNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"] & pNetworkValues["KEY_SUBNET_MASK_INTEGER"] ))"
	pNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_INTEGER"]}")"
	pNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_INTEGER"]}")"
	
	pNetworkValues["KEY_BROADCAST_ADDRESS_INTEGER"]="$(( ${pNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"]} | ${pNetworkValues["KEY_INVERTED_SUBNET_MASK_INTEGER"]} ))"
	pNetworkValues["KEY_BROADCAST_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_BROADCAST_ADDRESS_INTEGER"]}")"
	pNetworkValues["KEY_BROADCAST_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_BROADCAST_ADDRESS_INTEGER"]}")"
	
	pNetworkValues["KEY_SERVER_IP_ADDRESS_ON_VPN_INTEGER"]="$(convertIpAddressDottedDecimalToInteger "${pNetworkValues["KEY_SERVER_IP_ADDRESS_ON_VPN"]}")"
	pNetworkValues["KEY_SERVER_IP_ADDRESS_ON_VPN_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_SERVER_IP_ADDRESS_ON_VPN_INTEGER"]}")"
	pNetworkValues["KEY_SERVER_IP_ADDRESS_ON_VPN_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_SERVER_IP_ADDRESS_ON_VPN_INTEGER"]}")"
	
	pNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_INTEGER"]="$(convertIpAddressDottedDecimalToInteger "${pMostRecentIpAddressAsDottedDecimalString}")"
	pNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_INTEGER"]}")"
	pNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_INTEGER"]}")"
	
}
# end of ::initializeNetworkValues
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::isIndexInArray
# 
# Checks if pIndex is in pArray.
#
# Parameters:
#
# $1	Index of device to remove.
# $2	Reference to array if index exists in.
#
# Return:
#
# Returns 0 if pIndex is in pArray; 1 if it is not.
#

isIndexInArray() {
	
	local pIndex=$1
	local -n pArray=$2

	if [ ${pIndex} -ge 0 ] && [ ${pIndex} -lt ${#pArray[@]} ]; then
        return 0  # Index exists
    else
        return 1  # Index does not exist
    fi
	
}
# end of ::isIndexInArray
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::logErrorMessage
# 
# Log error message telling user that device was not added.
#

logErrorMessage() {

	local errorMessage=$1
	
	local redBackground="\033[41m"
	local resetColors="\033[0m"

	local output=""
	
	output+="${redBackground}"
	output+="\n"
	output+="	!! ERROR !! start"
	output+="${resetColors}"
	output+="\n"
	output+="\n"
	output+="\n	${errorMessage}"
	output+="\n"
	output+="\n"
	output+="${redBackground}"
	output+="\n"
	output+="	!! ERROR !! end"
	output+="${resetColors}"
	output+="\n"
	output+="\n"
	
	printf "${output}"
}
# end of ::logErrorMessage
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::logDeviceAddedSuccessfullyMessage
# 
# Logs success message telling user that device was successfully added.
#
# Parameters:
#
# $1	Reference to network values containing information that can be used in the message.
#

logDeviceAddedSuccessfullyMessage() {

	local -n pNetworkValues=$1
	
	# Extract the interface name for the new device without the config file extension
	local interfaceConfigFile=$(basename "${pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_FILE_ABS_PATH"]}")	# Get filename from path
	local interfaceName="${interfaceConfigFile%.*}" # Strip the extension
	
	local scriptFilename="${interfaceName}-setup.sh"
	
	local yellowFontColor="\033[33m"
	local resetColors="\033[0m"

	local msg=""
	
	msg+="	Device was successfully added to WireGuard interface '${pNetworkValues["KEY_INTERFACE_NAME"]}'."
	msg+="\n"
	msg+="\n"
	msg+="	Device IP Address	${networkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}"
	msg+="\n"
	msg+="	Device Public Key	${pNetworkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]}"
	msg+="\n"
	msg+="	Device Name		${pNetworkValues["KEY_NEW_DEVICE_NAME"]}"
	msg+="\n"
	msg+="	Device Description	${pNetworkValues["KEY_NEW_DEVICE_DESC"]}"
	msg+="\n"
	msg+="\n"
	msg+="	The tunnel configuration file for the newly added device has been saved to the following location:"
	msg+="\n"
	msg+="\n"
	msg+="		${yellowFontColor}${pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_FILE_ABS_PATH"]}${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	The configuration file can be imported into a client's WireGuard service to add a tunnel to the interface."
	msg+="\n"
	msg+="\n	Since it contains the client's private key, it is not recommended to keep the file on this machine after"
	msg+="\n	it has been added to the client; storing the private key for a WireGuard peer in multiple locations can"
	msg+="\n	be a security risk."
	msg+="\n"
	msg+="\n"
	msg+="	In case the device being added to the VPN is a Linux device, a setup script has been created and saved"
	msg+="\n"
	msg+="	to the following location to assist with the process:"
	msg+="\n"
	msg+="\n"
	msg+="		${yellowFontColor}${pNetworkValues["NEW_DEVICE_CLIENT_CONFIG_FILE_SET_UP_SCRIPT_ABS_PATH"]}${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	To use the setup script, put the tunnel configuration file and the setup script file in the same directory on"
	msg+="\n"
	msg+="	the device to be added to the VPN."
	msg+="\n"
	msg+="\n"
	msg+="	Once the files have been put onto the device being added to the VPN, navigate to the directory containing the"
	msg+="\n"
	msg+="	files and run the following commands:"
	msg+="\n"
	msg+="\n"
	msg+="		${yellowFontColor}sudo chmod +x ${scriptFilename}${resetColors}"
	msg+="\n"
	msg+="		${yellowFontColor}sudo ./${scriptFilename}${resetColors}"
	
	logSuccessMessage "${msg}"
	
}
# end of ::logDeviceAddedSuccessfullyMessage
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::logDeviceAddedToSkoonieOnlySuccessfullyMessage
# 
# Logs success message telling user that device was successfully added.
#
# Parameters:
#
# $1	Reference to network values containing information that can be used in the message.
#

logDeviceAddedToSkoonieOnlySuccessfullyMessage() {

	local -n pNetworkValues=$1
	
	local greenBackground="\033[30;42m"
	local resetColors="\033[0m"

	local msg=""
	
	msg+="	Device was successfully added to the wg-skoonie wrapper for interface '${pNetworkValues["KEY_INTERFACE_NAME"]}'."
	msg+="\n"
	msg+="\n"
	msg+="	Device IP Address	${networkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}"
	msg+="\n"
	msg+="	Device Public Key	${pNetworkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]}"
	msg+="\n"
	msg+="	Device Name		${pNetworkValues["KEY_NEW_DEVICE_NAME"]}"
	msg+="\n"
	msg+="	Device Description	${pNetworkValues["KEY_NEW_DEVICE_DESC"]}"
	msg+="\n"
	msg+="\n"
	msg+="	Please note that the device was NOT added to WireGuard, only to the skoonieini configuration files."
	msg+="\n"
	msg+="	This command is used when a device was already added to WireGuard but want it to be tracked using"
	msg+="\n"
	msg+="	the wg-skoonie wrapper."
	msg+="\n"
	msg+="\n"
	msg+="	A tunnel configuration file for the newly added device was not generated because it is assumed the"
	msg+="\n"
	msg+="	device was previously configured."
	
	logSuccessMessage "${msg}"
	
}
# end of ::logDeviceAddedToSkoonieOnlySuccessfullyMessage
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::logDeviceNotAddedSuccessfullyMessage
# 
# Logs device not added successfully message using details in pMsg.
#
# Parameters:
#
# $1	Message details.
#

logDeviceNotAddedSuccessfullyMessage() {

	local pMsg=$1
	
	local msg="Device was not added. Please see below for more details."
	msg+="\n"
	msg+="\n"
	msg+="	${pMsg}"
	
	logErrorMessage "${msg}"
	
}
# end of ::logDeviceNotAddedSuccessfullyMessage
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::logPartialSuccessMessage
# 
# Logs the passed in message as a partial success message encapsulated by yellow lines.
#
# Parameters:
#
# $1	Message.
#

logPartialSuccessMessage() {

	local pMsg=$1

	local yellowBackground="\033[30;43m"
	local resetColors="\033[0m"

	local output=""
	
	output+="${yellowBackground}"
	output+="\n"
	output+="	!! PARTIAL SUCCESS !! start"
	output+="${resetColors}"
	output+="\n"
	output+="\n	${msg}"
	output+="\n"
	output+="${yellowBackground}"
	output+="\n"
	output+="	!! PARTIAL SUCCESS !! end"
	output+="${resetColors}"
	output+="\n"
	output+="\n"
	
	printf "${output}"

}
# end of ::logPartialSuccessMessage
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::logSuccessMessage
# 
# Logs the passed in message as a success message encapsulated by yellow lines.
#
# Parameters:
#
# $1	Message.
#

logSuccessMessage() {

	local pMsg=$1
	
	local greenBackground="\033[30;42m"
	local resetColors="\033[0m"

	local msg=""
	
	msg+="${greenBackground}"
	msg+="\n"
	msg+="	!! SUCCESS !! start"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="\n"
	msg+="${pMsg}"
	msg+="\n"
	msg+="\n"
	msg+="${greenBackground}"
	msg+="\n"
	msg+="	!! SUCCESS !! end"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	
	printf "${msg}"
	
}
# end of ::logSuccessMessage
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::outputHelp
# 
# Outputs help instructions.
#

outputHelp() {
	
	local yellowFontColor="\033[33m"
	local resetColors="\033[0m"
		
	local msg=""
	
	# addInterface Command
	msg+="\n"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="addInterface [Interface Name] [Server Endpoint] [Listening Port] [Network Address] [Subnet Mask CIDR Notation] [Server IP Address on VPN]"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Adds a new WireGuard interface and starts it. For WireGuard, adding a new interface is the"
	msg+="\n"
	msg+="	equivalent of adding a new Virtual Private Network (VPN)."
	msg+="\n"
	msg+="\n"
	msg+="	The system will be configured to start the interface automatically on system startup."
	msg+="\n"
	msg+="\n"
	msg+="	Make sure that the port specified in [Server Endpoint] and [Listening Port] is directed"
	msg+="\n"
	msg+="	to the device running the WireGuard server. If the server is installed behind an internet"
	msg+="\n"
	msg+="	router, ensure that the router is forwarding all traffic for the specified port to the server."
	msg+="\n"
	msg+="\n"
	msg+="	Multiple interfaces are NOT able to listen on the same port, so each interface needs its own"
	msg+="\n"
	msg+="	port specified in [Server Endpoint] and [Listening Port]. This does NOT check to see if"
	msg+="\n"
	msg+="	another interface is already listening on the specified port. That is the responsibility of"
	msg+="\n"
	msg+="	the user."
	msg+="\n"
	msg+="\n"
	msg+="	This does NOT check to see if a previous interface with the same name already exists. It is the "
	msg+="\n"
	msg+="	responsibility of the user to verify this to ensure there are no conflicts."
	msg+="\n"
	msg+="\n"
	msg+="	Currently, devices are only allowed IPv4 addresses on the Virtual Private Network (VPN) for"
	msg+="\n"
	msg+="	any interface. Support for IPv6 will be added at a later date. WireGuard supports IPv6, but"
	msg+="\n"
	msg+="	wg-skoonie does not."
	msg+="\n"
	msg+="\n"
	msg+="	Example 1:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh addInterface \"wg0\" \"90.47.205.206:1111\" \"1111\" \"10.27.0.0\" \"24\" \"10.27.0.1\""
	msg+="\n"
	msg+="\n"
	msg+="	Example 2:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh addInterface \"wg0\" \"90.47.205.206:1211\" \"1211\" \"10.27.0.0\" \"24\" \"10.27.0.1\""
	msg+="\n"
	msg+="\n"
	msg+="	Example 2:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh addInterface \"wg0\" \"wg.website.com:1211\" \"1211\" \"10.27.255.0\" \"24\" \"10.27.255.1\""
	
	# removeInterface Command
	msg+="\n"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="removeInterface [Interface Name]"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Removes a WireGuard interface by name."
	msg+="\n"
	msg+="\n"
	msg+="	This will remove all associated files and data from both WireGuard and wg-skoonie."
	msg+="\n"
	msg+="\n"
	msg+="	This will also automatically delete the ufw rule added to open the port."
	msg+="\n"
	msg+="\n"
	msg+="	Use with caution. This command cannot be undone."
	msg+="\n"
	msg+="\n"
	msg+="	Example Usage:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh removeInterface \"wg0\""
	
	# addDevice Command
	msg+="\n"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="addDevice [Interface Name] [New Device Name] [New Device Description]"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Adds a new device to the specified interface. The IP address is auomatically calculated"
	msg+="\n"
	msg+="	by incrementing the highest IP address found in the wg-skoonie configuration files by 1."
	msg+="\n"
	msg+="\n"
	msg+="	If the resulting IP address is not within the subnet based on the network details found in"
	msg+="\n"
	msg+="	the wg-skoonie configuration files, errors are thrown."
	msg+="\n"
	msg+="\n"
	msg+="	The tunnel configuration file, including private and public keys, are automatically generated"
	msg+="\n"
	msg+="	for the newly added device."
	msg+="\n"
	msg+="\n"
	msg+="	Currently, devices are only allowed IPv4 addresses on the Virtual Private Network (VPN) for"
	msg+="\n"
	msg+="	any interface. Support for IPv6 will be added at a later date. WireGuard supports IPv6, but"
	msg+="\n"
	msg+="	wg-skoonie does not."
	msg+="\n"
	msg+="\n"
	msg+="	Example usage:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh addDevice \"wg0\" \"Kelly's Computer\" \"Kelly's main computer that he uses at home.\""
	
	# addDeviceSkoonieOnly Command
	msg+="\n"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="addDeviceSkoonieOnly [Interface Name] [New Device Public Key] [New Device IP Address] [New Device Name] [New Device Description]"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Adds a new device to the wg-skoonie configuration files for the specified interface, but"
	msg+="\n"
	msg+="	does NOT add the device to WireGuard."
	msg+="\n"
	msg+="\n"
	msg+="	This command is used when a device already exists in WireGuard and it now needs to be"
	msg+="\n"
	msg+="	logged by wg-skoonie."
	msg+="\n"
	msg+="\n"
	msg+="	Currently, devices are only allowed IPv4 addresses on the Virtual Private Network (VPN) for"
	msg+="\n"
	msg+="	any interface. Support for IPv6 will be added at a later date. WireGuard supports IPv6, but"
	msg+="\n"
	msg+="	wg-skoonie does not."
	msg+="\n"
	msg+="\n"
	msg+="	Example usage:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh addDeviceSkoonieOnly \"wg0\" \"Y+bTUNHoyoyrlu9kTT6jEZNyW5l6cS7MMZ/CQs1KqDc=\" \"10.8.0.1\" \"Kelly's Computer\" \"Kelly's main computer that he uses at home.\""
	
	# removeDevice Command
	msg+="\n"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="removeDevice [Interface Name] [Device to Remove Index]"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Removes the device specified by index from the specified interface."
	msg+="\n"
	msg+="\n"
	msg+="	The device is removed from both wg-skoonie and from WireGuard."
	msg+="\n"
	msg+="\n"
	msg+="	To determine a device index, use command 'showInterfaceSkoonie [Interface Name]'."
	msg+="\n"
	msg+="\n"
	msg+="	Example usage:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh removeDevice \"wg0\" \"37\""
	
	# showAllInterfacesSkoonie Command
	msg+="\n"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="showAllInterfacesSkoonie [Interface Name]"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Lists all of the interfaces and the network details saved by skoonie."
	msg+="\n"
	msg+="	Does not output the devices for each interface."
	msg+="\n"
	msg+="\n"
	msg+="	Example usage:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh showAllInterfacesSkoonie"
	
	# showInterfaceSkoonie Command
	msg+="\n"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="showInterfaceSkoonie [Interface Name]"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Outputs the details saved by wg-skoonie for the specified interface."
	msg+="\n"
	msg+="\n"
	msg+="	Example usage:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh showInterfaceSkoonie \"wg0\""
	
	# showInterfaceWireGuard Command
	msg+="\n"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="showInterfaceWireGuard [Interface Name]"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Outputs the details saved by WireGuard for the specified interface."
	msg+="\n"
	msg+="\n"
	msg+="	Example usage:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh showInterfaceWireGuard \"wg0\""
	
	msg+="\n"
	msg+="\n"
	
	printf "${msg}"
	
}
# end of ::outputHelp
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::outputVersion
# 
# Outputs program name and version number.
#

outputVersion() {
	
	local yellowFontColor="\033[33m"
	local resetColors="\033[0m"
		
	local msg=""
	
	# addInterface Command
	msg+="\n"
	
	msg="\n"
	msg+="${yellowFontColor}"
	msg+="${PROGRAM_NAME}"
	msg+="\n"
	msg+="Version: ${VERSION_NUMBER}"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	
	printf "${msg}"
	
}
# end of ::outputVersion
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::outputNetworkValuesToConsole
# 
# Outputs the network values to the console in a user-friendly format.
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values.
#
# Return:
#
# Network values are output to the console in a user-friendly format. 
#

outputNetworkValuesToConsole() {

	local -n ppNetworkValues=$1

	subnetMaskInteger="${ppNetworkValues["KEY_SUBNET_MASK_INTEGER"]}"
	subnetMaskBinaryWithPadding="${ppNetworkValues["KEY_SUBNET_MASK_BINARY_WITH_PADDING"]}"
	subnetMaskDottedDecimal="${ppNetworkValues["KEY_SUBNET_MASK_DOTTED_DECIMAL"]}"

	invertedSubnetMaskInteger="${ppNetworkValues["KEY_INVERTED_SUBNET_MASK_INTEGER"]}"
	invertedSubnetMaskBinaryWithPadding="${ppNetworkValues["KEY_INVERTED_SUBNET_MASK_BINARY_WITH_PADDING"]}"
	invertedSubnetMaskDottedDecimal="${ppNetworkValues["KEY_INVERTED_SUBNET_MASK_DOTTED_DECIMAL"]}"

	networkAddressInteger="${ppNetworkValues["KEY_NETWORK_ADDRESS_INTEGER"]}"
	networkAddressBinaryWithPadding="${ppNetworkValues["KEY_NETWORK_ADDRESS_BINARY_WITH_PADDING"]}"
	networkAddressDottedDecimal="${ppNetworkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}"

	networkAddressBaseAddressInteger="${ppNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_INTEGER"]}"
	networkAddressBaseAddressBinaryWithPadding="${ppNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_BINARY_WITH_PADDING"]}"
	networkAddressBaseAddressDottedDecimal="${ppNetworkValues["KEY_NETWORK_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL"]}"

	broadcastAddressInteger="${ppNetworkValues["KEY_BROADCAST_ADDRESS_INTEGER"]}"
	broadcastAddressBinaryWithPadding="${ppNetworkValues["KEY_BROADCAST_ADDRESS_BINARY_WITH_PADDING"]}"
	broadcastAddressDottedDecimal="${ppNetworkValues["KEY_BROADCAST_ADDRESS_DOTTED_DECIMAL"]}"

	ipAddressInteger="${ppNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_INTEGER"]}"
	ipAddressBinaryWithPadding="${ppNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_BINARY_WITH_PADDING"]}"
	ipAddressDottedDecimal="${ppNetworkValues["KEY_MOST_RECENT_IP_ADDRESS_DOTTED_DECIMAL"]}"

	nextIpAddressInteger="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]}"
	nextIpAddressBinaryWithPadding="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BINARY_WITH_PADDING"]}"
	nextIpAddressDottedDecimal="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}"

	nextIpAddressBaseAddressInteger="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL"]}"
	nextIpAddressBaseAddressBinaryWithPadding="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_BINARY_WITH_PADDING"]}"
	nextIpAddressBaseAddressDottedDecimal="${ppNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL"]}"
	

	echo ""
	echo ""
	echo ""
	
	echo "Network Values According to Skoonie Configuration Files:"
	
	echo ""

	echo "${subnetMaskDottedDecimal}	${subnetMaskBinaryWithPadding}	Subnet Mask"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${invertedSubnetMaskDottedDecimal}	${invertedSubnetMaskBinaryWithPadding}	Subnet Mask Inverted"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${networkAddressDottedDecimal}	${networkAddressBinaryWithPadding}	Network Address"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${networkAddressBaseAddressDottedDecimal}	${networkAddressBaseAddressBinaryWithPadding}	Network Address Base Address"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${broadcastAddressDottedDecimal}	${broadcastAddressBinaryWithPadding}	Broadcast Address"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${ipAddressDottedDecimal}	${ipAddressBinaryWithPadding}	Previous IP Address"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${nextIpAddressDottedDecimal}	${nextIpAddressBinaryWithPadding}	Next IP Address"

	echo "		||||||||||||||||||||||||||||||||"

	echo "${nextIpAddressBaseAddressDottedDecimal}	${nextIpAddressBaseAddressBinaryWithPadding}	Next IP Address Base Address"

	echo ""
	echo ""
	echo ""
	
}
# end of ::outputNetworkValuesToConsole
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::readInterfaceIniFile
# 
# Reads in the previously assigned IP addresses from the [network interface name]-assignedIPs.ini
# file.
#
# Parameters: 	
#
# $1	File path to interface skoonieini file.
# $2	Reference to associative array key-value pair for network values.
#
# Return:
#
#	All keys read from the ini file will be stored in global array $ipAddressesKeys.
#	All values read from the ini file will be stored in global array $ipAddressesKeys.
#

readInterfaceIniFile() {
	
	local pFilePath=$1
	local -n pNetworkValues=$2

	# Read in all key-value pairs in the file
	if [ -f "${pFilePath}" ]; then

		while IFS='' read -r line; do
		 
			# Remove carriage returns
			line=$(echo "${line}" | tr -d '\r')
		
			# Remove leading and trailing whitespaces
            line="${line#"${line%%[![:space:]]*}"}"  # Remove leading whitespace
			line="${line%"${line##*[![:space:]]}"}"  # Remove trailing whitespace

            # Skip empty lines and lines that start with # or [
            if [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^# || "$line" =~ ^\[ ]]; then
                continue
            fi

            # Split the line at the first equals sign
            key="${line%%=*}"
            value="${line#*=}"

            # Trim whitespace from key after splitting
			key="${key#"${key%%[![:space:]]*}"}"  # Remove leading whitespace
			key="${key%"${key##*[![:space:]]}"}"  # Remove trailing whitespace
			
			# Trim whitespace from value after splitting
			value="${value#"${value%%[![:space:]]*}"}"  # Remove leading whitespace
			value="${value%"${value##*[![:space:]]}"}"  # Remove trailing whitespace
			
			case "$key" in
			
				"Server Public Key")
					pNetworkValues["KEY_SERVER_PUBLIC_KEY"]="${value}"
					;;
				
				"Server Endpoint")
					pNetworkValues["KEY_SERVER_ENDPOINT"]="${value}"
					;;
					
				"Server Listening Port")
					pNetworkValues["KEY_SERVER_LISTENING_PORT"]="${value}"
					;;
					
				"Server IP Address On VPN")
					pNetworkValues["KEY_SERVER_IP_ADDRESS_ON_VPN"]="${value}"
					;;
			
				"Network Address")
					pNetworkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]="${value}"
					;;
			
				"Subnet Mask CIDR Notation")
					pNetworkValues["KEY_SUBNET_MASK_CIDR_NOTATION"]="${value}"
					;;
			
				"IP Address")
					deviceIpAddresses+=("$value")
					;;
					
				"Public Key")
					devicePublicKeys+=("$value")
					;;
					
				"Name")
					deviceNames+=("$value")
					;;
					
				"Description")
					deviceDescriptions+=("$value")
					;;
			
			esac
			
		done < "$pFilePath"
	fi
	
	# Sort the IP addresses in ascending order
    deviceIpAddressesSorted=($(printf "%s\n" "${deviceIpAddresses[@]}" | sort -V))

}
# end of ::readInterfaceIniFile
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::removeDeviceByIndex
# 
# Outputs details saved in WireGuard for the passed in interface.
#
# Parameters:
#
# $1	Interface name.
# $2	Index of device to remove.
#

removeDeviceByIndex() {

	local pInterfaceName=$1
	local pDeviceToRemoveIndex=$2

	local interfaceSkoonieIniFilePath="${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${pInterfaceName}/${pInterfaceName}.skoonieini"
	local interfaceSkoonieIniFileAbsolutePath="${PWD}/${interfaceSkoonieIniFilePath}"
	
	local statusGood=0
	
	checkInterfaceValidity "${pInterfaceName}" "${interfaceSkoonieIniFilePath}"
	statusGood=$?
	
	# Return with error if status not good
	if [[ "${statusGood}" -ne 0 ]] ; then
		return 1
	fi
	
	local -A networkValues
	
	# Read existing devices on this interface from file
	readInterfaceIniFile "$interfaceSkoonieIniFilePath" networkValues
	
	isIndexInArray ${pDeviceToRemoveIndex} deviceIpAddresses
	statusGood=$?
	
	# Return with error if status not good
	local yellowFontColor="\033[33m"
	local resetColors="\033[0m"
	
	if [[ "${statusGood}" -ne 0 ]] ; then
		local msg="Device index '${pDeviceToRemoveIndex}' was not found in interface '${pInterfaceName}' so device was NOT removed."
		msg+="\n"
		msg+="\n"
		msg+="	Details for interface '${pInterfaceName}' for wg-skoonie were loaded from:"
		msg+="\n"
		msg+="\n"
		msg+="		${yellowFontColor}${interfaceSkoonieIniFileAbsolutePath}${resetColors}"
		logErrorMessage	"${msg}"
		return 1
	fi
	
	local deviceDetailsMsg=$(generateDeviceDetails "${pDeviceToRemoveIndex}")
	
	# Erase device by writing all other devices to file, excluding the device marked for removal
	rewriteInterfaceFileExcludingDeviceAtIndex "${pInterfaceName}" "${pDeviceToRemoveIndex}" networkValues "${interfaceSkoonieIniFilePath}"
	
	# Remove device from WireGuard
	removeDeviceFromWireGuard "${pInterfaceName}" "${pDeviceToRemoveIndex}" "${deviceDetailsMsg}"
	statusGood=$?
	
	# Bail if status not good
	if [[ "${statusGood}" -ne 0 ]] ; then
		return 1
	fi
	
	# Removal was a success
	local msg="	Device was successfully removed from wg-skoonie and successfully removed from WireGuard."
	msg+="\n"
	msg+="\n"
	msg+="${deviceDetailsMsg}"
	
	logSuccessMessage "${msg}"

}
# end of ::removeDeviceByIndex
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::removeDeviceFromWireGuard
# 
# Removes the device referenced by the specified index from WireGuard.
#
# Parameters:
#
# $1	Interface name.
# $2	Index of device to remove.
# $3	Device details in a format that can be outputted to console.
#

removeDeviceFromWireGuard() {

	local pInterfaceName=$1
	local pDeviceToRemoveIndex=$2
	local pDeviceDetailsOutputMsg=$3

	local removeDeviceFromWireGuardCmd="wg set ${pInterfaceName} peer ${devicePublicKeys[$pDeviceToRemoveIndex]} remove"
	
	local removeDeviceFromWireGuardOutput
	removeDeviceFromWireGuardOutput=$(${removeDeviceFromWireGuardCmd} 2>&1)
	local removedFromWgStatus=$?
	
	# Check if device removal from WireGuard was successful
	if [[ "${removedFromWgStatus}" -ne 0 ]] ; then
	
		local yellowBackground="\033[30;43m"
		local resetColors="\033[0m"
		
		local msg="Device was successfully removed from wg-skoonie, but was not successfully removed from WireGuard."
		msg+="\n"
		msg+="\n"
		msg+="${pDeviceDetailsOutputMsg}"
		msg+="\n"
		msg+="\n"
		msg+="	Command used to remove device from WireGuard:"
		msg+="\n"
		msg+="\n"
		msg+="		${removeDeviceFromWireGuardCmd}"
		msg+="\n"
		msg+="\n"
		msg+="	Output message from WireGuard after command: "
		msg+="\n"
		msg+="\n"
		msg+="		${removeDeviceFromWireGuardOutput}"
		
		logPartialSuccessMessage "${msg}"
		
		return 1
		
	fi
	
	return 0

}
# end of ::removeDeviceFromWireGuard
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::removeInterface
# 
# Remvoes the specified interface from WireGuard and from wg-skoonie.
#
# $1	Name of interface to add.
#

removeInterface() {

	local pInterfaceName=$1
	
	local sanitizedInterfaceName="${pInterfaceName// /-}"
	
	local interfaceSkoonieIniFilePath="${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}/${sanitizedInterfaceName}.skoonieini"
	local interfaceSkoonieIniFileAbsolutePath="${PWD}/${interfaceSkoonieIniFilePath}"
	
	local -A networkValues
	readInterfaceIniFile "$interfaceSkoonieIniFilePath" networkValues
	
	# Bring service down. Deletes ip link device
	sudo wg-quick down ${sanitizedInterfaceName}
	
	# Disable starting service on boot up
	sudo systemctl disable wg-quick@${sanitizedInterfaceName}.service
	
	# Remove firewall rule allowing traffic on the interface port
	sudo ufw delete allow ${networkValues["KEY_SERVER_LISTENING_PORT"]}/udp

	local interfaceKeysFolderPath="/etc/wireguard"
	
	local -a filesToDelete
	
	# Delete WireGuard interface file
	filesToDelete+=("${interfaceKeysFolderPath}/${pInterfaceName}.conf")
	
	# Delete private key file
	filesToDelete+=("${interfaceKeysFolderPath}/${pInterfaceName}-private.key")
	
	# Delete public key file
	filesToDelete+=("${interfaceKeysFolderPath}/${pInterfaceName}-public.key")

	# Delete wg-skoonie interface folder
	filesToDelete+=("${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${sanitizedInterfaceName}")
	
	local errorStatus=0
	
	for ((i = 0; i < ${#filesToDelete[@]}; i++)); do
	
		local fileToDeleteAbsPath
	
		if [[ "${filesToDelete[$i]}" == /* ]]; then
			# Absolute path already used
			fileToDeleteAbsPath="${filesToDelete[$i]}"
		else
			# Convert to absolute path
			fileToDeleteAbsPath="${PWD}/${filesToDelete[$i]}"
		fi
	
		# Delete file/directory if it exists
		if [[ -f "${filesToDelete[$i]}" ]] || [[ -d "${filesToDelete[$i]}" ]]; 
		then
			
			sudo rm -r "${filesToDelete[$i]}"
			
			local loopErrorStatus=$?
			
			if [[ "${loopErrorStatus}" -ne 0 ]] ; 
			then
				echo "Error removing file/directory:"
				echo "	${fileToDeleteAbsPath}"
			else
				echo "File/Directory removed:"
				echo "	${fileToDeleteAbsPath}"
			fi
			
			# Store error status, making sure not to overwrite any previous error statuses
			# (assumes all error status are 1s)
			errorStatus=$(( ${errorStatus} | ${loopErrorStatus} ))
			
		else
			echo "File/Directory was already removed:"
			echo "	${fileToDeleteAbsPath}"
		fi
	
	done
	
	# Return with error if status not good
	if [[ "${statusGood}" -ne 0 ]] ; then
		local msg
		msg+="	Removing interface '${"sanitizedInterfaceName"} was NOT successful."
		msg+="\n"
		msg+="\n"
		msg+="	Please see above for details."
		logErrorMessage "${msg}"
		return 1
	fi
	
	local msg
	msg+="	Removing interface '${sanitizedInterfaceName}' was successful."
	msg+="\n"
	msg+="\n"
	msg+="	Note that this command did not check to see if the interface previously"
	msg+="\n"
	msg+="	existed. If it did exist, associated files were removed and the necessary"
	msg+="\n"
	msg+="	commands to remove the interface were executed. If it did not exist, the"
	msg+="\n"
	msg+="	program still attempted to remove all files and still executed the same"
	msg+="\n"
	msg+="	commands. This is done to ensure that an interface that was not properly"
	msg+="\n"
	msg+="	set up can still be removed."
	msg+="\n"
	msg+="\n"
	msg+="	Please see above for details."
	logSuccessMessage "${msg}"
	return 1
	
}
# end of ::removeInterface
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::rewriteInterfaceFileExcludingDeviceAtIndex
# 
# Rewrites the interface file excluding the specified device at index.
#
# Parameters:
#
# $1	Interface name.
# $2	Index of device to exclude from file rewrite.
# $3	Reference to associative array key-value pair for network values.
# $4 	File path to interface skoonieini file.
#

rewriteInterfaceFileExcludingDeviceAtIndex() {

	local pInterfaceName=$1
	local pDeviceToExcludeIndex=$2
	local -n pNetworkValues=$3
	local pInterfaceSkoonieIniFilePath=$4
	
	# Erase device by writing all other devices to file, excluding the device marked for removal
	
	local output
	
	output+="\n"
	
	output+=$(generateNetworkDetailsForSkoonieIniFile pNetworkValues)
	
	
	for ((i = 0; i < ${#deviceIpAddresses[@]}; i++)); do
	
		if [[ "${i}" == "${pDeviceToExcludeIndex}" ]] ; then
			continue;
		fi
		
		output+="\n"
		output+="\n"
		output+="[Device]"
		output+="\n"
		output+="IP Address=${deviceIpAddresses[$i]}"
		output+="\n"
		output+="Public Key=${devicePublicKeys[$i]}"
		output+="\n"
		output+="Name=${deviceNames[$i]}"
		output+="\n"
		output+="Description=${deviceDescriptions[$i]}" >> "${pInterfaceSkoonieIniFilePath}"
	
	done
	
	echo -e "${output}" > "${pInterfaceSkoonieIniFilePath}"

}
# end of ::rewriteInterfaceFileExcludingDeviceAtIndex
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::setNewDeviceValues
# 
# Sets the new devie values using the passed in values.
#
#
# Whether or not the next IP address is a valid IP address within the subnet is also saved in the
# passed in pNetworkValues.
#
# Parameters:
#
# $1	New device IP address in integer format.
# $2	New device name.
# $3	New device description.
# $4	Reference to associative array key-value pair for network values. Will be modified.
#
# Return:
#
# All initialized values are stored in the passed networkValues array as key-value pairs. 
#
# Key-value pairs stored:
#
# KEY_NEW_DEVICE_IP_ADDRESS_INTEGER								Next consecutive IP address integer format.
# KEY_NEW_DEVICE_IP_ADDRESS_BINARY_WITH_PADDING					Next consecutive IP address binary with padding format.
# KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL						Next consecutive IP address dotted-decimal format.
#
# KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_INTEGER				Base address of next consecutive IP address integer format.
# KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_BINARY_WITH_PADDING	Base address of next consecutive IP address binary with padding format.
# KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL			Base address of next consecutive IP address dotted-decimal format.
#
# KEY_NEW_DEVICE_NAME											Name of new device.
# KEY_NEW_DEVICE_DESC											Name of new description.
#
# KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET						0 if NOT in subnet or if equal to network address or broadcast address.
#																1 if in subnet.
#
# KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET_MSG					Descriptive message about whether or not the next IP address is in the subnet.
#

setNewDeviceValues() {

	local pNewDeviceIpInteger1046=$1
	local pNewDeviceName1046=$2
	local pNewDeviceDescription1046=$3
	local -n pNetworkValues1046=$4

	pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]="$(( ${pNewDeviceIpInteger1046} ))"
	pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]}")"
	pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]}")"
	
	pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_INTEGER"]="$(( pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"] & pNetworkValues1046["KEY_SUBNET_MASK_INTEGER"] ))"
	pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_BINARY_WITH_PADDING"]="$(convertIpAddressIntegerToPadded32BitBinaryString "${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_INTEGER"]}")"
	pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_DOTTED_DECIMAL"]="$(convertIpAddressIntegerToDottedDecimalString "${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_INTEGER"]}")"
	
	pNetworkValues1046["KEY_NEW_DEVICE_NAME"]="${pNewDeviceName1046}"
	pNetworkValues1046["KEY_NEW_DEVICE_DESC"]="${pNewDeviceDescription1046}"
	
	local isInSubnet
	local msg
	
	if [[ "${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]}" -eq "${pNetworkValues1046["KEY_NETWORK_ADDRESS_INTEGER"]}" ]]
	then
		
		isInSubnet="0"
		msg="Next IP address ${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]} is INVALID because it is equal to the network address."

	elif [[ "${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_INTEGER"]}" -eq "${pNetworkValues1046["KEY_BROADCAST_ADDRESS_INTEGER"]}" ]]
	then

		isInSubnet="0"
		msg="Next IP address ${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]} is INVALID because it is equal to the broadcast address."

	elif [[ "${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_BASE_ADDRESS_INTEGER"]}" -eq "${pNetworkValues1046["KEY_NETWORK_ADDRESS_BASE_ADDRESS_INTEGER"]}" ]]
	then

		isInSubnet="1"
		msg="Next IP address ${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]} is VALID because it is within the subnet and not equal to the network address or the broadcast address."
			
	else
	
		isInSubnet="0"
		msg="Next IP address ${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]} is INVALID because it is not within the subnet."
		
	fi
	
	pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET"]="${isInSubnet}"
	pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_IS_IN_SUBNET_MSG"]="${msg}"
	
}
# end of ::setNewDeviceValues
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::showAllInterfacesSkoonie
# 
# Outputs the network details saved in the skoonie ini files for all interfaces.
#
# Does not output the devices on each interface.
#

showAllInterfacesSkoonie() {
	
	local statusGood=0
	
	# Get list of interfaces by getting list of folders
	# List directories and store them in an array, stripping out directory names from full file paths
	local interfaceNames
	for dir in "${WG_SKOONIE_INTERFACES_FOLDER_PATH}"/*/; do
		local extractedName=$(basename "${dir}")
		interfaceNames+=("${extractedName}")
	done
	
	local yellowFontColor="\033[33m"
	local resetColors="\033[0m"
	
	msg+="\n"
	msg+="\n"
	msg+="Interfaces were loaded from: "
	msg+="\n"
	msg+="\n"
	msg+="	${yellowFontColor}${PWD}/${WG_SKOONIE_INTERFACES_FOLDER_PATH}${resetColors}"
	msg+="\n"
	msg+="\n"
	
	for ((i = 0; i < ${#interfaceNames[@]}; i++)); do
		
		local interfaceFilePath="${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${interfaceNames[$i]}/${interfaceNames[$i]}.skoonieini"
		
		local -A networkValues
		
		readInterfaceIniFile "$interfaceFilePath" networkValues
		
		msg+="\n"
		msg+="${yellowFontColor}"
		msg+="[${i}]"
		msg+="	${interfaceNames[$i]}			Interface Name"
		msg+="${resetColors}"
		msg+="\n"
		msg+="	${networkValues["KEY_SERVER_ENDPOINT"]}	Server Endpoint"
		msg+="\n"
		msg+="	${networkValues["KEY_SERVER_LISTENING_PORT"]}			Server Listening Port"
		msg+="\n"
		msg+="	${networkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}		Network Address"
		msg+="\n"
		msg+="	${networkValues["KEY_SUBNET_MASK_CIDR_NOTATION"]}			Network Address Subnet Mask in CIDR Notation"
		msg+="\n"
		msg+="	${networkValues["KEY_SERVER_IP_ADDRESS_ON_VPN"]}		Server IP Address on VPN"
		msg+="\n"
		
	done
	
	msg+="\n"
	
	printf "${msg}"
	
}
# end of ::showAllInterfacesSkoonie
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::showInterfaceDetailsFromSkoonieIniFiles
# 
# Outputs details saved in the skoonie ini files for the passed in interface.
#
# Parameters:
#
# $1	Interface name.
#

showInterfaceDetailsFromSkoonieIniFiles() {

	pInterfaceName=$1

	local interfaceSkoonieIniFilePath="${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${pInterfaceName}/${pInterfaceName}.skoonieini"
	local interfaceSkoonieIniFileAbsolutePath="${PWD}/${interfaceSkoonieIniFilePath}"
	
	local statusGood=0
	
	checkInterfaceValidity "${pInterfaceName}" "${interfaceSkoonieIniFilePath}"
	statusGood=$?
	
	# Return with error if status not good
	if [[ "${statusGood}" -ne 0 ]] ; then
		return 1
	fi
	
	local -A networkValues
	
	# Read existing devices on this interface from file
	readInterfaceIniFile "${interfaceSkoonieIniFilePath}" networkValues
	
	local yellowFontColor="\033[33m"
	local resetColors="\033[0m"
	
	local msg=""
	
	msg+="\n"
	msg+="\n"
	msg+="Details for interface '${pInterfaceName}' for wg-skoonie were loaded from:"
	msg+="\n"
	msg+="\n"
	msg+="	${yellowFontColor}${interfaceSkoonieIniFileAbsolutePath}${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="Server Endpoint"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="	${networkValues["KEY_SERVER_ENDPOINT"]}"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="Server Listening Port"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="	${networkValues["KEY_SERVER_LISTENING_PORT"]}"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="Server Public Key"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="	${networkValues["KEY_SERVER_PUBLIC_KEY"]}"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="Server IP Address On VPN"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="	${networkValues["KEY_SERVER_IP_ADDRESS_ON_VPN"]}"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="Network Address"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="	${networkValues["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="Subnet Mask CIDR Notation"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="	${networkValues["KEY_SUBNET_MASK_CIDR_NOTATION"]}"
	msg+="${resetColors}"
	msg+="\n"
	
	for ((i = 0; i < ${#deviceIpAddresses[@]}; i++)); do
		msg+="\n"
		msg+="${yellowFontColor}"
		msg+="[${i}]"
		msg+="	${deviceIpAddresses[$i]}"
		msg+="${resetColors}"
		msg+="\n"
		msg+="	${devicePublicKeys[$i]}"
		msg+="\n"
		msg+="	${deviceNames[$i]}"
		msg+="\n"
		msg+="	${deviceDescriptions[$i]}"
		msg+="\n"
	done
	
	msg+="\n"
	
	printf "${msg}"
	
}
# end of ::showInterfaceDetailsFromSkoonieIniFiles
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::showInterfaceDetailsFromWireGuard
# 
# Outputs details saved in WireGuard for the passed in interface.
#
# Parameters:
#
# $1	Interface name.
#

showInterfaceDetailsFromWireGuard() {

	pInterfaceName=$1

	local interfaceSkoonieIniFilePath="${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${pInterfaceName}/${pInterfaceName}.skoonieini"
	local interfaceSkoonieIniFileAbsolutePath="${PWD}/${interfaceSkoonieIniFilePath}"
	
	local statusGood=0
	
	checkInterfaceValidity "${pInterfaceName}" "${interfaceSkoonieIniFilePath}"
	statusGood=$?
	
	# Return with error if status not good
	if [[ "${statusGood}" -ne 0 ]] ; then
		return 1
	fi
	
	# This command will output details for the interface to console
	wg show "${pInterfaceName}"
	
}
# end of ::showInterfaceDetailsFromWireGuard
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::handleUserCommand
# 
# Handles user commands.
#
# Parameters:
#
# Varies depending on command.
#

case "$1" in

	"--help")
		outputHelp
		;;
		
	"--version")
		outputVersion
		;;
			
	"addDevice")
		# $2	Interface name to add device to.
		# $3	Name of new device.
		# $4	Description of new device.
		addDevice "${2}" "${3}" "${4}"
		;;

	"addDeviceSkoonieOnly")
		# $2	Interface name.
		# $3	Device public key.
		# $4	Device IP address.
		# $5	Device name.
		# $6	Device Description.
		addDeviceToSkoonieOnly "${2}" "${3}" "${4}" "${5}" "${6}"
		;;
		
	"removeDevice")
		# $2	Interface name.
		# $3	Device index.
		removeDeviceByIndex "${2}" "${3}"
		;;
		
	"addInterface")
		# $2	Name of interface to add.
		# $3 	Server endpoint (IP address or Domain Name with port).
		# $4	Listening port.
		# $5	Network address in dotted-decimal format.
		# $6	Subnet mask in CIDR notation.
		# $7	Server IP address on VPN.
		addInterface "${2}" "${3}" "${4}" "${5}" "${6}" "${7}"
		;;
		
	"removeInterface")
		# $2	Interface name.
		removeInterface "${2}"
		;;
		
	"showAllInterfacesSkoonie")
		showAllInterfacesSkoonie
		;;
	
	"showInterfaceSkoonie")
		# $2	Interface name.
		showInterfaceDetailsFromSkoonieIniFiles "${2}"
		;;
		
	"showInterfaceWireGuard")
		# $2	Interface name.
		showInterfaceDetailsFromWireGuard "${2}"
		;;

esac

# end of ::handleUserCommand
##--------------------------------------------------------------------------------------------------
