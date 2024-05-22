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
readonly VERSION_NUMBER="1.1.0"

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
# ::addDeviceToSkoonieFilesAndGenerateConfigFilesAndSetupScripts
# 
# Adds a device to the skoonie configuration files, generates client configuration files, and
# generates setup scripts.
#

addDeviceToSkoonieFilesAndGenerateConfigFilesAndSetupScripts() {

	local -n pNetworkValues=$1
	
	addDeviceToSkoonieIniFile "${pNetworkValues["KEY_INTERFACE_INI_FILE_ABS_PATH"]}" "${pNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}" "${pNetworkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]}" "${pNetworkValues["KEY_NEW_DEVICE_NAME"]}" "${pNetworkValues["KEY_NEW_DEVICE_DESC"]}"
	
	generateNewDeviceClientConfigFilesAndSetupScripts pNetworkValues
	
}
# end of ::addDeviceToSkoonieFilesAndGenerateConfigFilesAndSetupScripts
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
	
	networkValues["KEY_INTERFACE_NAME"]="${pInterfaceName}"
	networkValues["KEY_INTERFACE_INI_FILE_ABS_PATH"]="${interfaceSkoonieIniFileAbsolutePath}"
	
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
	
	addDeviceToSkoonieFilesAndGenerateConfigFilesAndSetupScripts networkValues
	
	logDeviceAddedSuccessfullyMessage networkValues
	
}
# end of ::addDevice
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::addDeviceSpecIp
# 
# Adds a new device to WireGuard and to the skoonieini files with the specified IP address.
#
# $1	Interface name to add device to.
# $2	Specified IP address dotted-decimal format of new device.
# $3	Name of new device.
# $4	Description of new device.
#

addDeviceSpecIp() {

	local pInterfaceName=$1
	local pNewDeviceIpDottedDecimal=$2
	local pNewDeviceName=$3
	local pNewDeviceDescription=$4
	
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
	
	# Convert user inputted IP address from dotted-decimal format to integer format
	local newDeviceIpAsInteger="$(convertIpAddressDottedDecimalToInteger "${pNewDeviceIpDottedDecimal}")"
	
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
# end of ::addDeviceSpecIp
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
	
	local postUpCommands
	
	# Add rule allowing all incoming traffic on the WireGuard interface from the network subnet
	postUpCommands+="iptables -A INPUT -i ${pInterfaceName} -s ${pNetworkAddressDottedDecimal}/${pSubnetMaskAsCidrNotation} -j ACCEPT; "
	
	# Add rule allowing all outgoing traffic on the WireGuard interface to the network subnet
	postUpCommands+="iptables -A OUTPUT -o ${pInterfaceName} -d ${pNetworkAddressDottedDecimal}/${pSubnetMaskAsCidrNotation} -j ACCEPT; "
	
	# Add rule forwarding all traffic from devices with IP address within the network 
	# subnet other devices within the network subnet on the WireGuard interface
	postUpCommands+="iptables -A FORWARD -i ${pInterfaceName} -o ${pInterfaceName} -s ${pNetworkAddressDottedDecimal}/${pSubnetMaskAsCidrNotation} -d ${pNetworkAddressDottedDecimal}/${pSubnetMaskAsCidrNotation} -j ACCEPT; "
	
	local postDownCommands
	
	# Remove rule allowing all incoming traffic on the WireGuard interface from the network subnet
	postDownCommands+="iptables -D INPUT -i ${pInterfaceName} -s ${pNetworkAddressDottedDecimal}/${pSubnetMaskAsCidrNotation} -j ACCEPT; "
	
	# Remove rule allowing all outgoing traffic on the WireGuard interface to the network subnet
	postDownCommands+="iptables -D OUTPUT -o ${pInterfaceName} -d ${pNetworkAddressDottedDecimal}/${pSubnetMaskAsCidrNotation} -j ACCEPT; "
	
	# Remove rule forwarding all traffic from devices with IP address within the network 
	# subnet other devices within the network subnet on the WireGuard interface
	postDownCommands+="iptables -D FORWARD -i ${pInterfaceName} -o ${pInterfaceName} -s ${pNetworkAddressDottedDecimal}/${pSubnetMaskAsCidrNotation} -d ${pNetworkAddressDottedDecimal}/${pSubnetMaskAsCidrNotation} -j ACCEPT; "
	
	local interfaceDetails
	interfaceDetails+="[Interface]"
	interfaceDetails+="\n"
	interfaceDetails+="PrivateKey = ${privateKey}"
	interfaceDetails+="\n"
	interfaceDetails+="Address = ${pServerIpAddress}/${pSubnetMaskAsCidrNotation}"
	interfaceDetails+="\n"
	interfaceDetails+="ListenPort = ${pListeningPort}"
	interfaceDetails+="\n"
	interfaceDetails+="PostUp = ${postUpCommands}"
	interfaceDetails+="\n"
	interfaceDetails+="PostDown = ${postDownCommands}"
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
# ::generateNewDeviceClientConfigFilesAndSetupScripts
# 
# Generates the client configuration files and setup scripts for different operating systems.
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values.
#

generateNewDeviceClientConfigFilesAndSetupScripts() {

    local -n pNetworkValues786=$1
	
	pNetworkValues786["KEY_NEW_DEVICE_CLIENT_CONFIG_FILES_FOLDER"]="${WG_SKOONIE_INTERFACES_FOLDER_PATH}/${pNetworkValues786["KEY_INTERFACE_NAME"]}/device${pNetworkValues786["KEY_NEW_DEVICE_INDEX"]}"
	
	generateNewDeviceConfigFileAndSetupScriptForRaspbian pNetworkValues786
	
	generateNewDeviceConfigFileAndSetupScriptForUbuntuLessThanV17_10 pNetworkValues786
	
	generateNewDeviceConfigFileAndSetupScriptForUbuntuGreaterThanOrEqualToV17_10 pNetworkValues786
	
	generateNewDeviceConfigFileForWindows pNetworkValues786

}
# end of ::generateNewDeviceClientConfigFilesAndSetupScripts
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNewDeviceConfigFileAndSetupScriptForRaspbian
# 
# Generates the client configuration file using the passed in parameters for a machine running
# Raspbian.
#
# Raspbian is still using the traditional ipdownup network management tools.
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values.
#
# Return:
# 
# Upon return, the client configuration file will be saved to:
#
# 	[Folder]/[WireGuard Interface Name]/device[Device Index]/Raspbian/[WireGuard Interface Name].conf
# 
# 	For example: /etc/wireguard/wg0/device0/Raspbian/wg0.conf
#
# Upon return, the setup script will be saved to:
#
# 	[Folder]/[WireGuard Interface Name]/device[Device Index]/Raspbian/[WireGuard Interface Name]-setup.sh
# 
# 	For example: /etc/wireguard/wg0/device0/Raspbian/wg0-setup.conf
#
# Upon return, the connecitivity connector script meant to be run as a cronjob will be saved to:
#
# 	[Folder]/[WireGuard Interface Name]/device[Device Index]/Raspbian/wg-skoonie-cronjob-[WireGuard Interface Name].sh
# 
# 	For example: /etc/wireguard/wg0/device0/Raspbian/wg-skoonie-cronjob-wg0.conf
#

generateNewDeviceConfigFileAndSetupScriptForRaspbian() {

	local -n pNetworkValues825=$1
	
	local folderPath="${pNetworkValues825["KEY_NEW_DEVICE_CLIENT_CONFIG_FILES_FOLDER"]}/Raspbian"
	local configFilePath="${folderPath}/${pNetworkValues825["KEY_INTERFACE_NAME"]}.conf"
	local setupScriptFilePath="${folderPath}/${pNetworkValues825["KEY_INTERFACE_NAME"]}-setup.sh"
	local connectivityScriptFilePath="${folderPath}/wg-skoonie-cronjob-${pNetworkValues825["KEY_INTERFACE_NAME"]}.sh"
	
	pNetworkValues825["KEY_NEW_DEVICE_CLIENT_CONFIG_RASPBIAN_FILE_PATH"]="${configFilePath}"
	pNetworkValues825["KEY_NEW_DEVICE_CLIENT_RASPBIAN_SETUP_SCRIPT_FILE_PATH"]="${setupScriptFilePath}"
	pNetworkValues825["KEY_NEW_DEVICE_CLIENT_RASPBIAN_CONNECTIVITY_CHECKER_SCRIPT_FILE_PATH"]="${connectivityScriptFilePath}"
	
	mkdir -p "${folderPath}"
	
	generateNewDeviceConfigFileForTraditionalifupdown "${pNetworkValues825["KEY_NEW_DEVICE_CLIENT_CONFIG_RASPBIAN_FILE_PATH"]}" pNetworkValues825
	generateNewDeviceSetupScriptForTraditionalifupdown "${pNetworkValues825["KEY_NEW_DEVICE_CLIENT_RASPBIAN_SETUP_SCRIPT_FILE_PATH"]}" pNetworkValues825
	generateNewDeviceConnectivityCheckerScriptForTraditionalifupdown "${pNetworkValues825["KEY_NEW_DEVICE_CLIENT_RASPBIAN_CONNECTIVITY_CHECKER_SCRIPT_FILE_PATH"]}" pNetworkValues825
	
	pNetworkValues825["KEY_NEW_DEVICE_CLIENT_CONFIG_RASPBIAN_FILE_ABS_PATH"]=$(realpath "${pNetworkValues825["KEY_NEW_DEVICE_CLIENT_CONFIG_RASPBIAN_FILE_PATH"]}")
	pNetworkValues825["KEY_NEW_DEVICE_CLIENT_RASPBIAN_SETUP_SCRIPT_FILE_ABS_PATH"]=$(realpath "${pNetworkValues825["KEY_NEW_DEVICE_CLIENT_RASPBIAN_SETUP_SCRIPT_FILE_PATH"]}")
	pNetworkValues825["KEY_NEW_DEVICE_CLIENT_RASPBIAN_CONNECTIVITY_CHECKER_SCRIPT_FILE_ABS_PATH"]=$(realpath "${pNetworkValues825["KEY_NEW_DEVICE_CLIENT_RASPBIAN_CONNECTIVITY_CHECKER_SCRIPT_FILE_PATH"]}")

}
# end of ::generateNewDeviceConfigFileAndSetupScriptForRaspbian
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNewDeviceConfigFileAndSetupScriptForUbuntuLessThanV17_10
# 
# Generates the client configuration file using the passed in parameters for a machine running
# an Ubuntu distribution with a version less than 17.10.
#
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values.
#
# Return:
# 
# Upon return, the client configuration file will be saved to:
#
# 	[Folder]/[WireGuard Interface Name]/device[Device Index]/Ubuntu-lt-17_10/[WireGuard Interface Name].conf
# 
# 	For example: /etc/wireguard/wg0/device0/Ubuntu-lt-V17_10/wg0.conf
#
# Upon return, the setup script will be saved to:
#
# 	[Folder]/[WireGuard Interface Name]/device[Device Index]/Ubuntu-lt-17_10/[WireGuard Interface Name]-setup.sh
# 
# 	For example: /etc/wireguard/wg0/device0/Ubuntu-lt-V17_10/wg0-setup.conf
#
# Upon return, the connecitivity connector script meant to be run as a cronjob will be saved to:
#
# 	[Folder]/[WireGuard Interface Name]/device[Device Index]/Ubuntu-lt-17_10/wg-skoonie-cronjob-[WireGuard Interface Name].sh
# 
# 	For example: /etc/wireguard/wg0/device0/Ubuntu-lt-17_10/wg-skoonie-cronjob-wg0.conf
#

generateNewDeviceConfigFileAndSetupScriptForUbuntuLessThanV17_10() {

	local -n pNetworkValues1170=$1
	
	local folderPath="${pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_CONFIG_FILES_FOLDER"]}/Ubuntu-lt-V17_10"
	local configFilePath="${folderPath}/${pNetworkValues1170["KEY_INTERFACE_NAME"]}.conf"
	local scriptFilePath="${folderPath}/${pNetworkValues1170["KEY_INTERFACE_NAME"]}-setup.sh"
	local connectivityScriptFilePath="${folderPath}/wg-skoonie-cronjob-${pNetworkValues1170["KEY_INTERFACE_NAME"]}.sh"
	
	pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_CONFIG_UBUNTU_LT_17-10_FILE_PATH"]="${configFilePath}"
	pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_UBUNTU_LT_17-10_SETUP_SCRIPT_FILE_PATH"]="${scriptFilePath}"
	pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_UBUNTU_LT_17-10_CONNECTIVITY_CHECKER_SCRIPT_FILE_PATH"]="${connectivityScriptFilePath}"
	
	mkdir -p "$folderPath"
	
	generateNewDeviceConfigFileForTraditionalifupdown "${pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_CONFIG_UBUNTU_LT_17-10_FILE_PATH"]}" pNetworkValues1170
	generateNewDeviceSetupScriptForTraditionalifupdown "${pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_UBUNTU_LT_17-10_SETUP_SCRIPT_FILE_PATH"]}" pNetworkValues1170
	generateNewDeviceConnectivityCheckerScriptForTraditionalifupdown "${pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_UBUNTU_LT_17-10_CONNECTIVITY_CHECKER_SCRIPT_FILE_PATH"]}" pNetworkValues1170
	
	pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_CONFIG_UBUNTU_LT_17-10_FILE_ABS_PATH"]=$(realpath "${pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_CONFIG_UBUNTU_LT_17-10_FILE_PATH"]}")
	pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_UBUNTU_LT_17-10_SETUP_SCRIPT_FILE_ABS_PATH"]=$(realpath "${pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_UBUNTU_LT_17-10_SETUP_SCRIPT_FILE_PATH"]}")
	pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_UBUNTU_LT_17-10_CONNECTIVITY_CHECKER_SCRIPT_FILE_ABS_PATH"]=$(realpath "${pNetworkValues1170["KEY_NEW_DEVICE_CLIENT_UBUNTU_LT_17-10_CONNECTIVITY_CHECKER_SCRIPT_FILE_PATH"]}")

}
# end of ::generateNewDeviceConfigFileAndSetupScriptForUbuntuLessThanV17_10
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNewDeviceConfigFileAndSetupScriptForUbuntuGreaterThanOrEqualToV17_10
# 
# Generates the client configuration file using the passed in parameters for a machine running
# an Ubuntu distribution with a version greater than or equal to 17.10.
#
# Ubuntu started using Netplan network management tools in version 17.10.
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values.
#
# Return:
# 
# Upon return, the client configuration file will be saved to:
#
# 	[Folder]/[WireGuard Interface Name]/device[Device Index]/Ubuntu-gte-17_10/[WireGuard Interface Name].conf
# 
# 	For example: /etc/wireguard/wg0/device0/Ubuntu-gte-V17_10/wg0.conf
#
# Upon return, the setup script will be saved to:
#
# 	[Folder]/[WireGuard Interface Name]/device[Device Index]/Ubuntu-gte-17_10/[WireGuard Interface Name]-setup.sh
# 
# 	For example: /etc/wireguard/wg0/device0/Ubuntu-gte-V17_10/wg0-setup.conf
#
# Upon return, the connecitivity connector script meant to be run as a cronjob will be saved to:
#
# 	[Folder]/[WireGuard Interface Name]/device[Device Index]/Ubuntu-gte-17_10/wg-skoonie-cronjob-[WireGuard Interface Name].sh
# 
# 	For example: /etc/wireguard/wg0/device0/Ubuntu-gte-17_10/wg-skoonie-cronjob-wg0.conf
#

generateNewDeviceConfigFileAndSetupScriptForUbuntuGreaterThanOrEqualToV17_10() {

	local -n pNetworkValues925=$1
	
	local folderPath="${pNetworkValues925["KEY_NEW_DEVICE_CLIENT_CONFIG_FILES_FOLDER"]}/Ubuntu-gte-V17_10"
	local configFilePath="${folderPath}/${pNetworkValues925["KEY_INTERFACE_NAME"]}.conf"
	local scriptFilePath="${folderPath}/${pNetworkValues925["KEY_INTERFACE_NAME"]}-setup.sh"
	local connectivityScriptFilePath="${folderPath}/wg-skoonie-cronjob-${pNetworkValues925["KEY_INTERFACE_NAME"]}.sh"
	
	pNetworkValues925["KEY_NEW_DEVICE_CLIENT_CONFIG_UBUNTU_GTE_17-10_FILE_PATH"]="${configFilePath}"
	pNetworkValues925["KEY_NEW_DEVICE_CLIENT_UBUNTU_GTE_17-10_SETUP_SCRIPT_FILE_PATH"]="${scriptFilePath}"
	pNetworkValues925["KEY_NEW_DEVICE_CLIENT_UBUNTU_GTE_17-10_CONNECTIVITY_CHECKER_SCRIPT_FILE_PATH"]="${connectivityScriptFilePath}"
	
	mkdir -p "$folderPath"
	
	generateNewDeviceConfigFileForNetplan "${pNetworkValues925["KEY_NEW_DEVICE_CLIENT_CONFIG_UBUNTU_GTE_17-10_FILE_PATH"]}" pNetworkValues925
	generateNewDeviceSetupScriptForNetplan "${pNetworkValues925["KEY_NEW_DEVICE_CLIENT_UBUNTU_GTE_17-10_SETUP_SCRIPT_FILE_PATH"]}" pNetworkValues925
	generateNewDeviceConnectivityCheckerScriptForNetplan "${pNetworkValues925["KEY_NEW_DEVICE_CLIENT_UBUNTU_GTE_17-10_CONNECTIVITY_CHECKER_SCRIPT_FILE_PATH"]}" pNetworkValues925
	
	pNetworkValues925["KEY_NEW_DEVICE_CLIENT_CONFIG_UBUNTU_GTE_17-10_FILE_ABS_PATH"]=$(realpath "${pNetworkValues925["KEY_NEW_DEVICE_CLIENT_CONFIG_UBUNTU_GTE_17-10_FILE_PATH"]}")
	pNetworkValues925["KEY_NEW_DEVICE_CLIENT_UBUNTU_GTE_17-10_SETUP_SCRIPT_FILE_ABS_PATH"]=$(realpath "${pNetworkValues925["KEY_NEW_DEVICE_CLIENT_UBUNTU_GTE_17-10_SETUP_SCRIPT_FILE_PATH"]}")
	pNetworkValues925["KEY_NEW_DEVICE_CLIENT_UBUNTU_GTE_17-10_CONNECTIVITY_CHECKER_SCRIPT_FILE_ABS_PATH"]=$(realpath "${pNetworkValues925["KEY_NEW_DEVICE_CLIENT_UBUNTU_GTE_17-10_CONNECTIVITY_CHECKER_SCRIPT_FILE_PATH"]}")

}
# end of ::generateNewDeviceConfigFileAndSetupScriptForUbuntuGreaterThanOrEqualToV17_10
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNewDeviceConfigFileForTraditionalifupdown
# 
# Generates a client configuration file for when the new device is using the traditional ifupdown
# network management tools.
#
# The configuration file the traditional ipdownup network management tools cannot contain the 
# Address key-value pair for the device (e.g., "Address = 10.8.0.3/24"). Having the Address key-value
# pair causes an error to be logged when executing command  `sudo ifup [Interface Name]` saying that:
#		Line unrecognized: `Address=10.8.0.3/24'
#
# Parameters:
#
# $1	File path to save configuration file to.
# $2	Reference to associative array key-value pair for network values.
#
# Return:
#
# On return, the configuration file will be saved to pFilePath.
#

generateNewDeviceConfigFileForTraditionalifupdown() {

	local pFilePath=$1
	local -n pNetworkValues864=$2
	
	cat > "${pFilePath}" <<EOF
[Interface]
PrivateKey = ${pNetworkValues864["KEY_NEW_DEVICE_PRIVATE_KEY"]}

[Peer]
PublicKey = ${pNetworkValues864["KEY_SERVER_PUBLIC_KEY"]}
Endpoint = ${pNetworkValues864["KEY_SERVER_ENDPOINT"]}
AllowedIPs = ${pNetworkValues864["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}/${pNetworkValues864["KEY_SUBNET_MASK_CIDR_NOTATION"]}
PersistentKeepalive = 25
EOF

}
# end of ::generateNewDeviceConfigFileForTraditionalifupdown
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNewDeviceSetupScriptForTraditionalifupdown
# 
# Generates a linux setup script for when the new device is using the traditional ifupdown network
# management tools.
#
# The `sudo wg-quick up [Interface Name]` command does not properly set up the interface and does
# not create the necessary files in /etc/network/interfaces.d/
#
# In place of the `sudo wg-quick up [Interface Name]` command, the command `sudo ifup [Interface Name]`
# is used. The `sudo wg-quick down [Interface Name]` is used along with  `sudo ifdown [Interface Name]`
# when performing multiple start attempts to ensure the wireguard interface is properly brought down.
#
# Upon return, the setup script file will be saved to the file path in:
#
# 	pNetworkValues["KEY_NEW_DEVICE_CLIENT_RASPBIAN_SETUP_SCRIPT_FILE_ABS_PATH"]
#
# Parameters:
#
# $1	File path to save script file to.
# $2	Reference to associative array key-value pair for network values.
#
# Return:
#
# On return, the setup script file will be saved to pFilePath.
#

generateNewDeviceSetupScriptForTraditionalifupdown() {

	local pFilePath=$1
    local -n pNetworkValues907=$2
	
	local exitFunction=$(generateScriptContentExitProgramFunction)
	local cronJobFunctions=$(generateScriptContentAddAndRemoveCronJobFunctions)
	
	cat > "${pFilePath}" << EOF
#!/bin/bash

readonly WG_INTERFACES_FOLDER_PATH="${WG_INTERFACES_FOLDER_PATH}"
readonly INTERFACE_NAME="${pNetworkValues907["KEY_INTERFACE_NAME"]}"
readonly INTERFACE_CONFIG_FILENAME="\${INTERFACE_NAME}.conf"
readonly NETWORK_INTERFACE_CONFIG_FILE_ABS_PATH="/etc/network/interfaces.d/\${INTERFACE_NAME}"

readonly INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME="wg-skoonie-cronjob-\${INTERFACE_NAME}.sh"
readonly WG_SKOONIE_CRONJOBS_FOLDER_PATH="/etc/cron.wg-skoonie"

greenBackground="\033[30;42m"
redBackground="\033[41m"
yellowFontColor="\033[33m"
resetColors="\033[0m"

exitStatus=0
backgroundColor=""
headerMessage=""
msg=""

${exitFunction}

${cronJobFunctions}

# Check if wireguard is installed
if ! command -v wg >/dev/null 2>&1; then

	# Error
	
	exitStatus="1"
	
	backgroundColor="\${redBackground}"
	
	headerMessage="ERROR"
	
	msg+="An installation of WireGuard cannot be found on this system."
	msg+="\n"
	msg+="\n"
	msg+="	Try using \"sudo apt install wireguard\"."
	
	exitProgram "\${headerMessage}" "\${msg}" "\${backgroundColor}" "\${exitStatus}"

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
echo "	to 	\${yellowFontColor}\${WG_INTERFACES_FOLDER_PATH}\${resetColors}"

sudo mv -iv "\${INTERFACE_CONFIG_FILENAME}" "\${WG_INTERFACES_FOLDER_PATH}"

echo ""
echo "Enabling interface to start on boot."


# Create network interface configuration file for traditional ifupdown

cat > "\${NETWORK_INTERFACE_CONFIG_FILE_ABS_PATH}" <<EOFE

# indicate that interface should be created when the system boots, and on ifup -a
auto \${INTERFACE_NAME}

# describe wg0 as an IPv4 interface with static address
iface \${INTERFACE_NAME} inet static

		# the IP address of this client on the WireGuard network
        address ${pNetworkValues907["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}/${pNetworkValues907["KEY_SUBNET_MASK_CIDR_NOTATION"]}

        # before ifup, create the device with this ip link command
        pre-up ip link add \${INTERFACE_NAME} type wireguard

        # before ifup, set the WireGuard config from earlier
        pre-up wg setconf \${INTERFACE_NAME} \${WG_INTERFACES_FOLDER_PATH}/\${INTERFACE_NAME}.conf

        # after ifdown, destroy the wg0 interface
        post-down ip link del \${INTERFACE_NAME}

EOFE

# end of Create network interface configuration file for traditional ifupdown

# Set up cronjob connectivity checker script

echo ""
echo "Moving wg-skoonie cronjob script for verifying connectivity to VPN."
echo "	from 	\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME}"
echo "	to 	\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}/\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME}"

sudo mkdir -p "\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}"

sudo mv -iv "\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME}" "\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}"

# Change ownership to root for additional security
sudo chown root:root "\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}/\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME}"

# Make file executable
sudo chmod +x "\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}/\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME}"

echo ""
echo "Adding cronjob to root's crontab to call wg-skoonie connectivity checker every 15 minutes."
echo "	*/15 * * * * \${WG_SKOONIE_CRONJOBS_FOLDER_PATH}/\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME} >/dev/null 2>&1\${resetColors}"

addCronJob "*/15 * * * *" "\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}/\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME} >/dev/null 2>&1"

# end of Set up cronjob connectivity checker script

echo ""
echo "Starting interface now...."

errorStatus=1
for (( i=0; i<=10; i++ )); do
	
	sudo ifup \${INTERFACE_NAME}
	echo ""
	echo "ifup attempt #\${i}"

	if sudo wg show \${INTERFACE_NAME} 2>/dev/null | grep -q 'public key'; then
		errorStatus=0
		break
	else
		sudo wg-quick down \${INTERFACE_NAME}
		sudo ifdown \${INTERFACE_NAME}
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
	
	exitProgram "\${headerMessage}" "\${msg}" "\${backgroundColor}" "\${exitStatus}"

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
	msg+="\n"
	msg+="		persistent keepalive: every 25 seconds"
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
	
	exitProgram "\${headerMessage}" "\${msg}" "\${backgroundColor}" "\${exitStatus}"

fi
EOF

}
# end of ::generateNewDeviceSetupScriptForTraditionalifupdown
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNewDeviceConnectivityCheckerScriptForTraditionalifupdown
# 
# Generates a linux bash script that checks if the device its ran in is connected to the WireGuard 
# VPN. The script generated is meant to be ran on devices using the traditional ifupdown network
# management tools.
#
# To check if the device is connected to the WireGuard VPN, it attempts to ping the server's IP 
# address on the VPN subnet. 
#
# If the server cannot be reached, the WireGuard interface is brought down and then back up. This 
# is primarily done to force a DNS lookup in case a domain name was used as the server's endpoint. 
# WireGuard only performs a DNS lookup when the interface is brought up. If Dynamic DNS is being 
# used, a change in IP address will not be detected until WireGuard is brought down and back up 
# again.
#
# The server is pinged every 10 minutes to verify connectivity.
#
# Parameters:
#
# $1	File path to save script file to.
# $2	Reference to associative array key-value pair for network values.
#
# Return:
#
# On return, the setup script file will be saved to pFilePath.
#

generateNewDeviceConnectivityCheckerScriptForTraditionalifupdown() {

	local pFilePath=$1
    local -n pNetworkValues1317=$2
	
	local headerComments=$(generateScriptContentCronjobHeaderComments)
	
	local bringWireGuardInterfaceDownThenUpFunction=$(generateScriptContentBringWireGuardInterfaceDownThenUpFunctionForDevicesUsingTraditionalifupdown)
	
	local attemptServerPingFunction=$(generateScriptContentAttemptServerPing)
	
	local variablesWithValuesInjectedFromMainScript=$(generateScriptContentCronjobVariablesWithValuesInjectedFromMainScript pNetworkValues1317)
	
	local variablesWithoutValuesInjectedFromMainScript=$(generateScriptContentCronjobVariablesWithoutValuesInjectedFromMainScript)
	
	local mainCode=$(generateScriptContentCronjobMainCode)

	cat > "${pFilePath}" << EOF
#!/bin/bash

${headerComments}

${attemptServerPingFunction}
	
${bringWireGuardInterfaceDownThenUpFunction}
	
${variablesWithValuesInjectedFromMainScript}

${variablesWithoutValuesInjectedFromMainScript}

${mainCode}

EOF

}
# end of ::generateNewDeviceConnectivityCheckerScriptForTraditionalifupdown
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNewDeviceConfigFileForNetplan
# 
# Generates a client configuration file for when the new device is using the new Netplan network 
# management tools.
#
# The configuration file the new Netplan network management tools CAN and MUST contain the Address 
# key-value pair for the device (e.g., "Address = 10.8.0.3/24").
#
# Parameters:
#
# $1	File path to save configuration file to.
# $2	Reference to associative array key-value pair for network values.
#
# Return:
#
# On return, the configuration file will be saved to pFilePath.
#

generateNewDeviceConfigFileForNetplan() {

	local pFilePath=$1
	local -n pNetworkValues1229=$2
	
	cat > "${pFilePath}" <<EOF
[Interface]
PrivateKey = ${pNetworkValues1229["KEY_NEW_DEVICE_PRIVATE_KEY"]}
Address = ${pNetworkValues1229["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}/${pNetworkValues1229["KEY_SUBNET_MASK_CIDR_NOTATION"]}

[Peer]
PublicKey = ${pNetworkValues1229["KEY_SERVER_PUBLIC_KEY"]}
Endpoint = ${pNetworkValues1229["KEY_SERVER_ENDPOINT"]}
AllowedIPs = ${pNetworkValues1229["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}/${pNetworkValues1229["KEY_SUBNET_MASK_CIDR_NOTATION"]}
PersistentKeepalive = 25
EOF

}
# end of ::generateNewDeviceConfigFileForNetplan
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNewDeviceSetupScriptForNetplan
# 
# Generates a linux setup script for when the new device is using the new Netplan network management
# tools.
#
# The `sudo wg-quick up [Interface Name]` command can be used to initialize the interface.
#
# Parameters:
#
# $1	File path to save script file to.
# $2	Reference to associative array key-value pair for network values.
#
# Return:
#
# On return, the setup script file will be saved to pFilePath.
#

generateNewDeviceSetupScriptForNetplan() {

	local pFilePath=$1
    local -n pNetworkValues1268=$2
	
	local exitFunction=$(generateScriptContentExitProgramFunction)
	local cronJobFunctions=$(generateScriptContentAddAndRemoveCronJobFunctions)
	
	cat > "${pFilePath}" <<EOF
#!/bin/bash

readonly WG_INTERFACES_FOLDER_PATH="${WG_INTERFACES_FOLDER_PATH}"
readonly INTERFACE_NAME="${pNetworkValues1268["KEY_INTERFACE_NAME"]}"
readonly INTERFACE_CONFIG_FILENAME="\${INTERFACE_NAME}.conf"
readonly NETWORK_INTERFACE_CONFIG_FILE_ABS_PATH="/etc/network/interfaces.d/\${INTERFACE_NAME}"

readonly INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME="wg-skoonie-cronjob-\${INTERFACE_NAME}.sh"
readonly WG_SKOONIE_CRONJOBS_FOLDER_PATH="/etc/cron.wg-skoonie"

greenBackground="\033[30;42m"
redBackground="\033[41m"
yellowFontColor="\033[33m"
resetColors="\033[0m"

exitStatus=0
backgroundColor=""
headerMessage=""
msg=""

${exitFunction}

${cronJobFunctions}

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
echo "	from 	\${INTERFACE_CONFIG_FILENAME}"
echo "	to 	\${WG_INTERFACES_FOLDER_PATH}"

sudo mv -iv "\${INTERFACE_CONFIG_FILENAME}" "\${WG_INTERFACES_FOLDER_PATH}"

# Set up cronjob connectivity checker script

echo ""
echo "Moving wg-skoonie cronjob script for verifying connectivity to VPN."
echo "	from 	\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME}"
echo "	to 	\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}/\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME}"

sudo mkdir -p "\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}"

sudo mv -iv "\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME}" "\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}"

# Change ownership to root for additional security
sudo chown root:root "\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}/\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME}"

# Make file executable
sudo chmod +x "\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}/\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME}"

echo ""
echo "Adding cronjob to root's crontab to call wg-skoonie connectivity checker every 15 minutes."
echo "	\${yellowFontColor}\*/15 * * * * \${WG_SKOONIE_CRONJOBS_FOLDER_PATH}/\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME} >/dev/null 2>&1\${resetColors}"
generateCronJobFunctionsForScripts
addCronJob "*/15 * * * *" "\${WG_SKOONIE_CRONJOBS_FOLDER_PATH}/\${INTERFACE_CRONJOB_CONNECTIVITY_CHECKER_FILENAME} >/dev/null 2>&1"

# end of Set up cronjob connectivity checker script

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
	msg+="\n"
	msg+="		persistent keepalive: every 25 seconds"
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
# end of ::generateNewDeviceSetupScriptForNetplan
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNewDeviceConnectivityCheckerScriptForNetplan
# 
# Generates a linux bash script that checks if the device its ran in is connected to the WireGuard 
# VPN. The script generated is meant to be ran on devices using the Netplan network management 
# tools.
#
# To check if the device is connected to the WireGuard VPN, it attempts to ping the server's IP 
# address on the VPN subnet. 
#
# If the server cannot be reached, the WireGuard interface is brought down and then back up. This 
# is primarily done to force a DNS lookup in case a domain name was used as the server's endpoint. 
# WireGuard only performs a DNS lookup when the interface is brought up. If Dynamic DNS is being 
# used, a change in IP address will not be detected until WireGuard is brought down and back up 
# again.
#
# The server is pinged every 10 minutes to verify connectivity.
#
# Parameters:
#
# $1	File path to save script file to.
# $2	Reference to associative array key-value pair for network values.
#
# Return:
#
# On return, the setup script file will be saved to pFilePath.
#

generateNewDeviceConnectivityCheckerScriptForNetplan() {

	local pFilePath=$1
    local -n pNetworkValues1669=$2
	
	local headerComments=$(generateScriptContentCronjobHeaderComments)
	
	local bringWireGuardInterfaceDownThenUpFunction=$(generateScriptContentBringWireGuardInterfaceDownThenUpFunctionForDevicesUsingNetplan)
	
	local attemptServerPingFunction=$(generateScriptContentAttemptServerPing)
	
	local variablesWithValuesInjectedFromMainScript=$(generateScriptContentCronjobVariablesWithValuesInjectedFromMainScript pNetworkValues1669)
	
	local variablesWithoutValuesInjectedFromMainScript=$(generateScriptContentCronjobVariablesWithoutValuesInjectedFromMainScript)
	
	local mainCode=$(generateScriptContentCronjobMainCode)

	cat > "${pFilePath}" << EOF
#!/bin/bash

${headerComments}

${attemptServerPingFunction}
	
${bringWireGuardInterfaceDownThenUpFunction}
	
${variablesWithValuesInjectedFromMainScript}

${variablesWithoutValuesInjectedFromMainScript}

${mainCode}

EOF

}
# end of ::generateNewDeviceConnectivityCheckerScriptForNetplan
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateNewDeviceConfigFileForWindows
# 
# Generates the client configuration file using the passed in parameters for a Windows machine.
#
# No setup script is generated because using the GUI to import a tunnel configuration file is 
# extremely easy on Windows.
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values.
#
# Return:
#
# Upon return, the client configuration file will be saved to:
#
# 	[Folder]/[WireGuard Interface Name]/device[Device index]/Windows/[WireGuard Interface Name].conf
# 
# 	For example: /etc/wireguard/wg0/device0/Windows/wg0.conf
#
# The absolute file path of the configuration file is stored at:
#	pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_FILE_WINDOWS_ABS_PATH"]
#

generateNewDeviceConfigFileForWindows() {

	local -n pNetworkValues1516=$1
	
	local folderPath="${pNetworkValues1516["KEY_NEW_DEVICE_CLIENT_CONFIG_FILES_FOLDER"]}/Windows"
	local configFilePath="${folderPath}/${pNetworkValues1516["KEY_INTERFACE_NAME"]}.conf"
	pNetworkValues1516["KEY_NEW_DEVICE_CLIENT_CONFIG_WINDOWS_FILE_PATH"]="${configFilePath}"
	
	mkdir -p "$folderPath"
	
	cat > "${pNetworkValues1516["KEY_NEW_DEVICE_CLIENT_CONFIG_WINDOWS_FILE_PATH"]}" <<EOF
[Interface]
PrivateKey = ${pNetworkValues1516["KEY_NEW_DEVICE_PRIVATE_KEY"]}
Address = ${pNetworkValues1516["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}/${pNetworkValues1516["KEY_SUBNET_MASK_CIDR_NOTATION"]}

[Peer]
PublicKey = ${pNetworkValues1516["KEY_SERVER_PUBLIC_KEY"]}
Endpoint = ${pNetworkValues1516["KEY_SERVER_ENDPOINT"]}
AllowedIPs = ${pNetworkValues1516["KEY_NETWORK_ADDRESS_DOTTED_DECIMAL"]}/${pNetworkValues1516["KEY_SUBNET_MASK_CIDR_NOTATION"]}
PersistentKeepalive = 25
EOF

	pNetworkValues1516["KEY_NEW_DEVICE_CLIENT_CONFIG_FILE_WINDOWS_ABS_PATH"]=$(realpath "${pNetworkValues1516["KEY_NEW_DEVICE_CLIENT_CONFIG_WINDOWS_FILE_PATH"]}")

}
# end of ::generateNewDeviceConfigFileForWindows
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
# ::generateScriptContentAttemptServerPing
# 
# Generates and echos the text for a function that is capable of pinging a server's IP address on
# the VPN.
#
# Return:
#
# On return, the generated texts are echoed.
#

generateScriptContentAttemptServerPing() {
	
	local text=$(cat << 'EOF'
##--------------------------------------------------------------------------------------------------
# ::attemptServerPing
#

attemptServerPing() {

	local pServerIpOnVpn=$1
	
	local exitStatus=1
	
	# Attempts pinging 4 times
	for (( i=0; i<=4; i++ )); do
	
		# Ping the server
		ping -c 1 "${pServerIpOnVpn}" > /dev/null 2>&1
		
		local pingExitStatus=$?
		
		# One successful ping is considered a success
		if [[ ${pingExitStatus} -eq 0 ]]; then
			exitStatus=0
			break
		fi
		
	done

	# Return results (0 on success, 1 on failure)
	return ${exitStatus}
	
}
# end of ::attemptServerPing
##--------------------------------------------------------------------------------------------------

EOF
)

	echo "${text}"
	
}
# end of ::generateScriptContentAttemptServerPing
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateScriptContentBringWireGuardInterfaceDownThenUpFunctionForDevicesUsingTraditionalifupdown
# 
# Generates and echos the text for a function that is capable of bringing WireGuard interface down
# and then back up again on a device using the traditional ifupdown network management tools. The 
# generated text can be put in a bash script file.
#
# Return:
#
# On return, the generated texts are echoed.
#

generateScriptContentBringWireGuardInterfaceDownThenUpFunctionForDevicesUsingTraditionalifupdown() {
	
	local text=$(cat << 'EOF'
##--------------------------------------------------------------------------------------------------
# ::bringWireGuardDownAndForceDnsUpdate
#

bringWireGuardDownAndForceDnsUpdate() {

	local pInterfaceName=$1
	local pServerEndpointAddress=$2

	# Bring the interface down
	sudo wg-quick down ${pInterfaceName}
	sudo ifdown ${pInterfaceName}
	
	# Get the address info of the VPN server endpoint. If 
	# this is a domain name, this typically causes the DNS
	# cache on this device to be updated. Useful for Dynamic
	# DNS setups
	resolvedIpAddress=$(sudo getent ahosts "${pServerEndpointAddress}" | grep "STREAM" | awk '{ print $1 }')
	
}
# end of ::bringWireGuardDownAndForceDnsUpdate
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::bringWireGuardInterfaceDownThenUp
#

bringWireGuardInterfaceDownThenUp() {

	local pInterfaceName=$1
	local pServerEndpointAddress=$2
	local pServerIpOnVpn=$3

	bringWireGuardDownAndForceDnsUpdate "${pInterfaceName}" "${pServerEndpointAddress}"
	
	# Attempt to bring up interface and ping server 2 times
	local errorStatus=1
	for (( i=0; i<=2; i++ )); do

		sudo ifup ${pInterfaceName}
		echo ""
		echo "ifup attempt #${i}"

		if sudo wg show ${pInterfaceName} 2>/dev/null | grep -q 'public key' && attemptServerPing "${pServerIpOnVpn}"; then
		
			# If the wg show command properly presented the interface
			# and the server can be pinged on the VPN, consider it a
			# success
			errorStatus=0
			break
			
		else
		
			# Interface not started properly or server could not be
			# reached
			bringWireGuardDownAndForceDnsUpdate "${pInterfaceName}" "${pServerEndpointAddress}"
			
			# Wait 1 second and then try again
			sleep 1
			
		fi

	done
	
	return "${errorStatus}"
	
}
# end of ::bringWireGuardInterfaceDownThenUp
##--------------------------------------------------------------------------------------------------

EOF
)

	echo "${text}"
	
}
# end of ::generateScriptContentBringWireGuardInterfaceDownThenUpFunctionForDevicesUsingTraditionalifupdown
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateScriptContentBringWireGuardInterfaceDownThenUpFunctionForDevicesUsingNetplan
# 
# Generates and echos the text for a function that is capable of bringing WireGuard interface down
# and then back up again on a device using the Netplan network management tools. The generated text 
# can be put in a bash script file.
#
# Return:
#
# On return, the generated texts are echoed.
#

generateScriptContentBringWireGuardInterfaceDownThenUpFunctionForDevicesUsingNetplan() {

	local text=$(cat << 'EOF'
##--------------------------------------------------------------------------------------------------
# ::bringWireGuardDownAndForceDnsUpdate
#

bringWireGuardDownAndForceDnsUpdate() {

	local pInterfaceName=$1
	local pServerEndpointAddress=$2

	# Bring the interface down
	sudo wg-quick down ${pInterfaceName}
	
	# Get the address info of the VPN server endpoint. If 
	# this is a domain name, this typically causes the DNS
	# cache on this device to be updated. Useful for Dynamic
	# DNS setups
	resolvedIpAddress=$(sudo getent ahosts "${pServerEndpointAddress}" | grep "STREAM" | awk '{ print $1 }')
	
}
# end of ::bringWireGuardDownAndForceDnsUpdate
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::bringWireGuardInterfaceDownThenUp
#

bringWireGuardInterfaceDownThenUp() {

	local pInterfaceName=$1
	local pServerEndpointAddress=$2
	local pServerIpOnVpn=$3

	bringWireGuardDownAndForceDnsUpdate "${pInterfaceName}" "${pServerEndpointAddress}"
	
	# Attempt to bring up interface and ping server 10 times
	local errorStatus=1
	for (( i=0; i<=10; i++ )); do

		sudo wg-quick up ${pInterfaceName}
		echo ""
		echo "wg-quick up attempt #${i}"

		if sudo wg show ${pInterfaceName} 2>/dev/null | grep -q 'public key' && attemptServerPing "${pServerIpOnVpn}"; then
		
			# If the wg show command properly presented the interface
			# and the server can be pinged on the VPN, consider it a
			# success
			errorStatus=0
			break
			
		else
		
			# Interface not started properly or server could not be
			# reached
			bringWireGuardDownAndForceDnsUpdate "${pInterfaceName}" "${pServerEndpointAddress}"
			
			# Wait 1 second and then try again
			sleep 1
			
		fi

	done
	
	return "${errorStatus}"
	
}
# end of ::bringWireGuardInterfaceDownThenUp
##--------------------------------------------------------------------------------------------------

EOF
)

	echo "${text}"
	
}
# end of ::generateScriptContentBringWireGuardInterfaceDownThenUpFunctionForDevicesUsingNetplan
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateScriptContentAddAndRemoveCronJobFunctions
# 
# Generates functions for adding and removing cron jobs and echos them as a string.
#
# This function is useful when generating other bash scripts.
#
# Example usage:
#
# 	cronJobFunctions=$(generateCronJobFunctionsForScripts)
#
# Return:
#
# On return, the generated texts are echoed.
#

generateScriptContentAddAndRemoveCronJobFunctions() {
	
	local header="##--------------------------------------------------------------------------------------------------"
	local colons="::"
	
	local output=$(cat << EOF
${header}
# ${colons}addCronJob
# 
# Adds a cron job to root's crontab.
#
# Example usage: 
#
#	Run the cron job at 2:00 AM:
#
#		addCronJob "0 2 * * *" "/path/to/your-script.sh"
#
# 	Run the cron job every 15 minutes:
#
#		addCronJob "*/15 * * * *" "/path/to/your-script.sh"
#
# Cron schedule format:
#
# 	* * * * * 
# 	| | | | | 
# 	| | | | +---- Day of the week (0 - 7) (Sunday is both 0 and 7)
# 	| | | +------ Month (1 - 12)
# 	| | +-------- Day of the month (1 - 31)
# 	| +---------- Hour (0 - 23)
# 	+------------ Minute (0 - 59)
#
# Parameters:
#
# \$1	Cron schedule.
# \$2	Absolute file path to script.
#

addCronJob() {

    local pCronSchedule="\$1"
    local pScriptPath="\$2"
	
    local newCronJob="\${pCronSchedule} \${pScriptPath}"

    # Temporary file to hold the current crontab
    local cronTempFile
    cronTempFile=\$(mktemp)

    # Save the current crontab to a temporary file
    sudo crontab -l > "\${cronTempFile}" 2>/dev/null

    # Check if the cron job already exists
    if ! grep -Fxq "\${newCronJob}" "\${cronTempFile}"; then
	
        # Add the new cron job to the temporary file
		echo "" >> "\${cronTempFile}"
        echo "\${newCronJob}" >> "\${cronTempFile}"

        # Install the new crontab from the temporary file
        sudo crontab "\${cronTempFile}"

        echo "New cron job added: \${newCronJob}"
		
    else
	
        echo "Cron job already exists: \${newCronJob}"
		
    fi

    # Clean up the temporary file
    rm "\${cronTempFile}"
	
}
# end of ${colons}addCronJob
${header}

${header}
# ${colons}removeCronJob
# 
# Removes the specified cron job from root's crontab if it exists.
#
# Example usage:
#
#	removeCronJob "0 2 * * *" "/path/to/your-script.sh"
#
#	removeCronJob "*/15 * * * *" "/path/to/your-script.sh >/dev/null 2>&1"
#
# Parameters:
#
# \$1	Cron schedule to remove.
# \$2	Absolute file path to script.
#

removeCronJob() {

    local pCronSchedule="\$1"
    local pScriptPath="\$2"
	
    local cronJobToRemove="\${pCronSchedule} \${pScriptPath}"

    # Temporary file to hold the current crontab
    local cronTempFile
    cronTempFile=\$(mktemp)

    # Save the current crontab to a temporary file
    sudo crontab -l > "\${cronTempFile}" 2>/dev/null

    # Check if the cron job exists
    if grep -Fxq "\${cronJobToRemove}" "\${cronTempFile}"; then
	
        # Remove the cron job from the temporary file
        grep -Fxv "\${cronJobToRemove}" "\${cronTempFile}" > "\${cronTempFile}.tmp" && mv "\${cronTempFile}.tmp" "\${cronTempFile}"

        # Install the new crontab from the temporary file
        sudo crontab "\${cronTempFile}"

        echo "Cron job removed: \${cronJobToRemove}"
		
    else
	
        echo "Cron job not found: \${cronJobToRemove}"
		
    fi

    # Clean up the temporary file
    rm "\${cronTempFile}"
	
}
# end of ${colons}removeCronJob
${header}

EOF
)

	echo "${output}"
}
# end of ::generateScriptContentAddAndRemoveCronJobFunctions
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateScriptContentExitProgramFunction
# 
# Generates a functions for exiting the program and echos it as a string.
#
# This function is useful when generating other bash scripts.
#
# Return:
#
# On return, the generated texts are echoed.
#

generateScriptContentExitProgramFunction() {
	
	local output=$(cat << 'EOF'
##--------------------------------------------------------------------------------------------------
# ::exitProgram
# 
# Exits the program.
#
# Parameters:
#
# $1	Header message.
# $2	Message.
# $3 	Background color.
# $4	Exit status.
#

exitProgram() {

	local pHeaderMsg="${1}"
	local pMsg="${2}"
	local pBackgroundColor="${3}"
	local pExitStatus="${4}"
	
	local resetColors="\033[0m"

	output=""
	output+="\n"
	output+="\n"
	output+="${pBackgroundColor}"
	output+="\n"
	output+="	!! ${pHeaderMsg} !! start"
	output+="${resetColors}"
	output+="\n"
	output+="\n"
	output+="\n	${pMsg}"
	output+="\n"
	output+="\n"
	output+="${pBackgroundColor}"
	output+="\n"
	output+="	!! ${pHeaderMsg} !! end"
	output+="${resetColors}"
	output+="\n"
	output+="\n"

	printf "${output}"

	exit "${pExitStatus}"

}
# end of ::exitProgram
##--------------------------------------------------------------------------------------------------

EOF
)

	echo "${output}"
}
# end of ::generateScriptContentExitProgramFunction
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateScriptContentCronjobHeaderComments
# 
# Generates and echos the comments for the wg-skoonie cronjob script header.
#
# Return:
#
# On return, the generated texts are echoed.
#

generateScriptContentCronjobHeaderComments() {
	
	local text=$(cat << 'EOF'
	
##--------------------------------------------------------------------------------------------------
##-------------------------------------------------------------------------------------------------- 
#
# This cron job script was generated as part of the WireGuard Skoonie Wrapper (wg-skoonie).
#
# This script verifies that the device it is ran on is connected to the WireGuard VPN. 
#
# To check if the device is connected to the WireGuard VPN, it attempts to ping the server's IP 
# address on the VPN subnet. 
#
# If the server cannot be reached, the WireGuard interface is brought down and then back up. This 
# is primarily done to force a DNS lookup in case a domain name was used as the server's endpoint. 
# WireGuard only performs a DNS lookup when the interface is brought up. If Dynamic DNS is being 
# used, a change in IP address will not be detected until WireGuard is brought down and back up 
# again.
#
# By default, this cron job script is set to be ran every 15 minutes.
#

EOF
)

	echo "${text}"
	
}
# end of ::generateScriptContentCronjobHeaderComments
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateScriptContentCronjobMainCode
# 
# Generates and echos the text for the wg-skoonie cron job script's main code.
#
# Return:
#
# On return, the generated texts are echoed.
#

generateScriptContentCronjobMainCode() {
	
	local text=$(cat << 'EOF'
	
resolvedIpAddress=""

logMsg=""

# If the server cannot be reached, bring the WireGuard interface down then back up
if ! attemptServerPing "${SERVER_IP_ON_VPN}"; then
	
	logMsg+="Issues reported at ${CURRENT_DATETIME}"
	logMsg+="\n"
	logMsg+="	Server ping on VPN at ${SERVER_IP_ON_VPN} failed."
	
	if bringWireGuardInterfaceDownThenUp "${INTERFACE_NAME}" "${SERVER_ENDPOINT_ADDRESS}" "${SERVER_IP_ON_VPN}"; then
		
		# Log success
		logMsg+="\n"
		logMsg+="	Reconnected to server at endpoint ${resolvedIpAddress}."
		logMsg+="\n"
		logMsg+="	Server ping on VPN at ${SERVER_IP_ON_VPN} success."
	
	else
	
		# Log failure
		logMsg+="\n"
		logMsg+="	Could not reconnect to server at endpoint ${resolvedIpAddress}."
		
	fi
	
fi

# If there is a log message, write it to file
if [ ! -z "${logMsg}" ]; then
	echo -e "${logMsg}" >> "${LOG_FILEPATH}"
fi

EOF
)

	echo "${text}"
	
}
# end of ::generateScriptContentCronjobMainCode
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateScriptContentCronjobVariablesWithValuesInjectedFromMainScript
# 
# Generates and echos the text for declaring variables whose values come from this main script.
#
# This is done separately so that 'EOF' is not used and the generated text will replace variables
# references with variables from this script.
#
# Return:
#
# On return, the generated texts are echoed.
#
# Parameters:
#
# $1	Reference to associative array key-value pair for network values.
#

generateScriptContentCronjobVariablesWithValuesInjectedFromMainScript() {
	
	local -n pNetworkValues2333=$1
	
	local text=$(cat << EOF
	
# WireGuard VPN Interface name
readonly INTERFACE_NAME="${pNetworkValues2333["KEY_INTERFACE_NAME"]}"

# Server IP address on VPN subnet
readonly SERVER_IP_ON_VPN="${pNetworkValues2333["KEY_SERVER_IP_ADDRESS_ON_VPN"]}"

# WireGuard server endpoint address. IP address or domain name.
readonly SERVER_ENDPOINT_ADDRESS="${pNetworkValues2333["KEY_SERVER_ENDPOINT"]%%:*}"

EOF
)

	echo "${text}"
	
}
# end of ::generateScriptContentCronjobVariablesWithValuesInjectedFromMainScript
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
# ::generateScriptContentCronjobVariablesWithoutValuesInjectedFromMainScript
# 
# Generates and echos the text for declaring variables whose values do NOT come from this main script.
#
# This is done separately so that 'EOF' can be used and the generated text will NOT replace variables
# references with variables from this script.
#
# Return:
#
# On return, the generated texts are echoed.
#

generateScriptContentCronjobVariablesWithoutValuesInjectedFromMainScript() {
	
	local text=$(cat << 'EOF'
	
# Script File Path
readonly SCRIPT_FILEPATH="${BASH_SOURCE[0]}"

# Script Name
readonly SCRIPT_NAME=$(basename "${SCRIPT_FILEPATH}" .sh)

# Script Directory
readonly SCRIPT_DIR=$(dirname "${SCRIPT_FILEPATH}")

# Log filename
readonly LOG_FILENAME="${SCRIPT_NAME}.log"

# Log filepath
readonly LOG_FILEPATH="${SCRIPT_DIR}/${LOG_FILENAME}"

readonly CURRENT_DATETIME=$(date +"%Y-%m-%d %H:%M:%S")

EOF
)

	echo "${text}"
	
}
# end of ::generateScriptContentCronjobVariablesWithoutValuesInjectedFromMainScript
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
# ::isValueInArray
# 
# Checks if pValue is in pArray.
#
# Parameters:
#
# $1	Value to check for.
# $2	Reference to array.
#
# Return:
#
# Returns 0 if pValue is in pArray; 1 if it is not.
#

isValueInArray() {

	local pValue=$1
	local -n pArray=$2
	
	local isInArray=1
	
	for ((i = 0; i < ${#pArray[@]}; i++)); do
		
		if [[ "${pArray[i]}" == "${pValue}" ]]
		then
			isInArray=0
			break;
		fi
		
	done
	
	return "${isInArray}"
	
}
# end of ::isValueInArray
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
	
	local interfaceName="${pNetworkValues["KEY_INTERFACE_NAME"]}"
	
	local scriptFilename="${interfaceName}-setup.sh"
	
	local yellowFontColor="\033[33m"
	local resetColors="\033[0m"

	local msg=""
	
	msg+="	Device was successfully added to WireGuard interface:"
	msg+="\n"
	msg+="	${yellowFontColor}${pNetworkValues["KEY_INTERFACE_NAME"]}${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Device IP Address"
	msg+="\n"
	msg+="	${yellowFontColor}${pNetworkValues["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Device Public Key"
	msg+="\n"
	msg+="	${yellowFontColor}${pNetworkValues["KEY_NEW_DEVICE_PUBLIC_KEY"]}${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Device Name"
	msg+="\n"
	msg+="	${yellowFontColor}${pNetworkValues["KEY_NEW_DEVICE_NAME"]}${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Device Description"
	msg+="\n"
	msg+="	${yellowFontColor}${pNetworkValues["KEY_NEW_DEVICE_DESC"]}${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Tunnel configuration files for different operating systems have"
	msg+="\n"
	msg+="	been generated for the newly added device."
	msg+="\n"
	msg+="\n"
	msg+="	The configuration file can be imported into a client's WireGuard"
	msg+="\n"
	msg+="	service to add a tunnel to the interface."
	msg+="\n"
	msg+="\n"
	msg+="	Since it contains the client's private key, it is not"
	msg+="\n"
	msg+="	recommended to keep the file on this machine after it has been"
	msg+="\n"
	msg+="	added to the client; storing the private key for a WireGuard"
	msg+="\n"
	msg+="	peer in multiple locations can be a security risk."
	msg+="\n"
	msg+="\n"
	msg+="	For some Operating Systems, setup scripts have been created."
	msg+="\n"
	msg+="\n"
	msg+="	To use the setup scripts, copy the entire folder for that OS"
	msg+="\n"
	msg+="	onto the device to be added to the VPN. The setup script"
	msg+="\n"
	msg+="	file expects to be in the same directory as the tunnel"
	msg+="\n"
	msg+="	configuration file and all other necessary files."
	msg+="\n"
	msg+="\n"
	msg+="	Once the folder has been put onto the device being added to the"
	msg+="\n"
	msg+="	VPN, navigate to the directory containing the files and run the"
	msg+="\n"
	msg+="	following commands:"
	msg+="\n"
	msg+="\n"
	msg+="	${yellowFontColor}sudo chmod +x ${scriptFilename}${resetColors}"
	msg+="\n"
	msg+="	${yellowFontColor}sudo ./${scriptFilename}${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="\n"
	msg+="	Tunnel configuration files and setup scripts were generated for"
	msg+="\n"
	msg+="	the following systems:"
	msg+="\n"
	msg+="\n"
	msg+="\n"
	msg+="	${yellowFontColor}Windows OS${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Tunnel configuration file:"
	msg+="\n"
	msg+="	${pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_FILE_WINDOWS_ABS_PATH"]}"
	msg+="\n"
	msg+="\n"
	msg+="	Setup script file:"
	msg+="\n"
	msg+="	None. Importing the tunnel configuration file via WireGuard GUI"
	msg+="\n"
	msg+="	on Windows handles everything."
	msg+="\n"
	msg+="\n"
	msg+="\n"
	msg+="	${yellowFontColor}Ubuntu Versions Less Than Version 17.10${resetColors}"
	msg+="\n"
	msg+="	(using traditional ifupdown network management tools)"
	msg+="\n"
	msg+="\n"
	msg+="	Tunnel configuration file:"
	msg+="\n"
	msg+="	${pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_UBUNTU_LT_17-10_FILE_ABS_PATH"]}"
	msg+="\n"
	msg+="\n"
	msg+="	Setup script file:"
	msg+="\n"
	msg+="	${pNetworkValues["KEY_NEW_DEVICE_CLIENT_UBUNTU_LT_17-10_SETUP_SCRIPT_FILE_ABS_PATH"]}"
	msg+="\n"
	msg+="\n"
	msg+="	Connectivity checker cronjob bash file:"
	msg+="\n"
	msg+="	${pNetworkValues["KEY_NEW_DEVICE_CLIENT_UBUNTU_LT_17-10_CONNECTIVITY_CHECKER_SCRIPT_FILE_ABS_PATH"]}"
	msg+="\n"
	msg+="\n"
	msg+="\n"
	msg+="	${yellowFontColor}Ubuntu Versions 17.10 & Up${resetColors}"
	msg+="\n"
	msg+="	(using new Netplan network management tools)"
	msg+="\n"
	msg+="\n"
	msg+="	Tunnel configuration file:"
	msg+="\n"
	msg+="	${pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_UBUNTU_GTE_17-10_FILE_ABS_PATH"]}"
	msg+="\n"
	msg+="\n"
	msg+="	Setup script file:"
	msg+="\n"
	msg+="	${pNetworkValues["KEY_NEW_DEVICE_CLIENT_UBUNTU_GTE_17-10_SETUP_SCRIPT_FILE_ABS_PATH"]}"
	msg+="\n"
	msg+="\n"
	msg+="	Connectivity checker cronjob bash file:"
	msg+="\n"
	msg+="	${pNetworkValues["KEY_NEW_DEVICE_CLIENT_UBUNTU_GTE_17-10_CONNECTIVITY_CHECKER_SCRIPT_FILE_ABS_PATH"]}"
	msg+="\n"
	msg+="\n"
	msg+="\n"
	msg+="	${yellowFontColor}Raspbian${resetColors}"
	msg+="\n"
	msg+="	(using traditional ifupdown network management tools)"
	msg+="\n"
	msg+="\n"
	msg+="	Tunnel configuration file:"
	msg+="\n"
	msg+="	${pNetworkValues["KEY_NEW_DEVICE_CLIENT_CONFIG_RASPBIAN_FILE_ABS_PATH"]}"
	msg+="\n"
	msg+="\n"
	msg+="\n"
	msg+="	Setup script file:"
	msg+="\n"
	msg+="	${pNetworkValues["KEY_NEW_DEVICE_CLIENT_RASPBIAN_SETUP_SCRIPT_FILE_ABS_PATH"]}"
	msg+="\n"
	msg+="\n"
	msg+="	Connectivity checker cronjob bash file:"
	msg+="\n"
	msg+="	${pNetworkValues["KEY_NEW_DEVICE_CLIENT_RASPBIAN_CONNECTIVITY_CHECKER_SCRIPT_FILE_ABS_PATH"]}"
	msg+="\n"
	msg+="\n"
	msg+="\n"
	msg+="	Note that the Linux setup scripts may work on other operating"
	msg+="\n"
	msg+="	systems as well. The difference between commands in each script"
	msg+="\n"
	msg+="	are all related to the network management tools in use on each"
	msg+="\n"
	msg+="	Linux flavor (traditional ifupdown or Netplan)."
	msg+="\n"
	msg+="\n"
	msg+="	Running the setup scripts on a device will set up the WireGuard"
	msg+="\n"
	msg+="	interface, configure it to start on bootup, and will also set up"
	msg+="\n"
	msg+="	a connectivity checker cronjob to run every 15 minutes. If the"
	msg+="\n"
	msg+="	device cannot ping the server IP address on the VPN, the"
	msg+="\n"
	msg+="	WireGuard interface will be restarted. This restart is intended"
	msg+="\n"
	msg+="	to force the DNS Resolver Cache on the client device to perform"
	msg+="\n"
	msg+="	another DNS lookup for the server's endpoint address. In cases"
	msg+="\n"
	msg+="	where the endpoint address is using Dynamic DNS, this typically"
	msg+="\n"
	msg+="	forces WireGuard to connect to the new IP address if it has"
	msg+="\n"
	msg+="	changed. The cronjob is set up to run every 15 minutes."
	
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
	msg+="	Adds a new WireGuard interface and starts it. For WireGuard,"
	msg+="\n"
	msg+="	adding a new interface is the equivalent of adding a new Virtual"
	msg+="\n"
	msg+="	Private Network (VPN)."
	msg+="\n"
	msg+="\n"
	msg+="	Interfaces added using this command are configured to allow"
	msg+="\n"
	msg+="	client devices on the VPN to communicate with each other. This"
	msg+="\n"
	msg+="	is achieved by using WireGuard's PostUp and PostDown key-value"
	msg+="\n"
	msg+="	pairs in the interface's configuration file to modify the"
	msg+="\n"
	msg+="	server's iptables to forward packets from one client to another"
	msg+="\n"
	msg+="	client, so long as both clients are on the same interface and"
	msg+="\n"
	msg+="	within the same subnet. Clients will not be able to talk to"
	msg+="\n"
	msg+="	other clients on a different interface/VPN."
	msg+="\n"
	msg+="\n"
	msg+="	If it is preferable that client devices NOT to be able to"
	msg+="\n"
	msg+="	communicate with each other, it is recommended to create an"
	msg+="\n"
	msg+="	interface per device. This not only prevents the iptables rules"
	msg+="\n"
	msg+="	added by wg-skoonie from allowing client devices to communicate,"
	msg+="\n"
	msg+="	but it also creates another layer of separation between the"
	msg+="\n"
	msg+="	client devices that may help prevent additional security"
	msg+="\n"
	msg+="	vulnerabilities caused by other iptables rules or services"
	msg+="\n"
	msg+="	running on the system."
	msg+="\n"
	msg+="\n"
	msg+="	The system will be configured to start the interface"
	msg+="\n"
	msg+="	automatically on system startup."
	msg+="\n"
	msg+="\n"
	msg+="	Make sure that the port specified in [Server Endpoint] and"
	msg+="\n"
	msg+="	[Listening Port] is directed to the device running the"
	msg+="\n"
	msg+="	WireGuard server. If the server is installed behind an internet"
	msg+="\n"
	msg+="	router, ensure that the router is forwarding all traffic for the"
	msg+="\n"
	msg+="	specified port to the server."
	msg+="\n"
	msg+="\n"
	msg+="	Multiple interfaces are NOT able to listen on the same port, so"
	msg+="\n"
	msg+="	each interface needs its own port specified in [Server"
	msg+="\n"
	msg+="	Endpoint] and [Listening Port]. This command does NOT check"
	msg+="\n"
	msg+="	to see if another interface is already listening on the"
	msg+="\n"
	msg+="	specified port. That is the responsibility of the user."
	msg+="\n"
	msg+="\n"
	msg+="	This command does NOT check to see if a previous interface with"
	msg+="\n"
	msg+="	the same name already exists. It is the responsibility of the"
	msg+="\n"
	msg+="	user to verify this to ensure there are no conflicts."
	msg+="\n"
	msg+="\n"
	msg+="	Currently, devices are only allowed IPv4 addresses on the"
	msg+="\n"
	msg+="	Virtual Private Network (VPN) for any interface. Support for"
	msg+="\n"
	msg+="	IPv6 will be added at a later date. WireGuard supports IPv6, but"
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
	msg+="	Example 3:"
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
	msg+="	This will remove all associated files and data from both"
	msg+="\n"
	msg+="	WireGuard and wg-skoonie."
	msg+="\n"
	msg+="\n"
	msg+="	This will also automatically delete the ufw rule added to open"
	msg+="\n"
	msg+="	the port."
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
	msg+="	Adds a new device to the specified interface. The IP address is"
	msg+="\n"
	msg+="	automatically calculated by incrementing the highest IP address"
	msg+="\n"
	msg+="	found in the wg-skoonie configuration files by 1."
	msg+="\n"
	msg+="\n"
	msg+="	If the resulting IP address is not within the subnet based on"
	msg+="\n"
	msg+="	the network details found in the wg-skoonie configuration files,"
	msg+="\n"
	msg+="	errors are thrown."
	msg+="\n"
	msg+="\n"
	msg+="	When a device is successfully added, alient tunnel configuration"
	msg+="\n"
	msg+="	file, including private and public keys, is automatically"
	msg+="\n"
	msg+="	generated for all operating systems."
	msg+="\n"
	msg+="\n"
	msg+="	For cases in which the device being added to the VPN is a Linux"
	msg+="\n"
	msg+="	device, a setup script and cronjob connectivity checker script"
	msg+="\n"
	msg+="	will be automatically created to assist with the setup process:"
	msg+="\n"
	msg+="\n"
	msg+="	> Setup script for installing the configuration file,"
	msg+="\n"
	msg+="	configuring the WireGuard interface, and installing the cronjob"
	msg+="\n"
	msg+="	connectivity checker script."
	msg+="\n"
	msg+="\n"
	msg+="	> Cronjob connectivity checker script that periodically checks"
	msg+="\n"
	msg+="	the client device's connection to the VPN. If the device cannot"
	msg+="\n"
	msg+="	ping the server IP address on the VPN, the WireGuard interface"
	msg+="\n"
	msg+="	will be restarted. This restart is intended to force the DNS"
	msg+="\n"
	msg+="	Resolver Cache on the client device to perform another DNS"
	msg+="\n"
	msg+="	lookup for the server's endpoint address. In cases where the"
	msg+="\n"
	msg+="	endpoint address is using Dynamic DNS, this typically forces"
	msg+="\n"
	msg+="	WireGuard to connect to the new IP address if it has changed."
	msg+="\n"
	msg+="	The cronjob is set up to run every 15 minutes."
	msg+="\n"
	msg+="\n"
	msg+="	Note that if Dynamic DNS is being used, the WireGuard interface"
	msg+="\n"
	msg+="	on client devices running Windows OS will have to be manually"
	msg+="\n"
	msg+="	restarted if the IP address changes. wg-skoonie does not"
	msg+="\n"
	msg+="	generate a script to automate this process on Windows devices."
	msg+="\n"
	msg+="\n"
	msg+="	The operating system for the new device is not specified in this"
	msg+="\n"
	msg+="	command. Configuration files and scripts are always generated"
	msg+="\n"
	msg+="	for all supported operating systems."
	msg+="\n"
	msg+="\n"
	msg+="	Currently, devices are only allowed IPv4 addresses on the"
	msg+="\n"
	msg+="	Virtual Private Network (VPN) for any interface. Support for"
	msg+="\n"
	msg+="	IPv6 will be added at a later date. WireGuard supports IPv6, but"
	msg+="\n"
	msg+="	wg-skoonie does not."
	msg+="\n"
	msg+="\n"
	msg+="	Example usage:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh addDevice \"wg0\" \"Kelly's Computer\" \"Kelly's main computer that he uses at home.\""
	
	# addDeviceSpecIp Command
	msg+="\n"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="addDeviceSpecIp [Interface Name] [IP Address] [New Device Name] [New Device Description]"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Adds a new device to the specified interface using the specified"
	msg+="\n"
	msg+="	IP address."
	msg+="\n"
	msg+="\n"
	msg+="	If the resulting IP address is not within the subnet based on"
	msg+="\n"
	msg+="	the network details found in the wg-skoonie configuration files"
	msg+="\n"
	msg+="	or if it is already assigned to another device, errors are"
	msg+="\n"
	msg+="	thrown."
	msg+="\n"
	msg+="\n"
	msg+="	The tunnel configuration file, including private and public"
	msg+="\n"
	msg+="	keys, are automatically generated for the newly added device."
	msg+="\n"
	msg+="\n"
	msg+="	In case the device being added to the VPN is a Linux device, a"
	msg+="\n"
	msg+="	setup script will be automatically created to assist with the"
	msg+="\n"
	msg+="	setup process."
	msg+="\n"
	msg+="\n"
	msg+="	Currently, devices are only allowed IPv4 addresses on the"
	msg+="\n"
	msg+="	Virtual Private Network (VPN) for any interface. Support for"
	msg+="\n"
	msg+="	IPv6 will be added at a later date. WireGuard supports IPv6, but"
	msg+="\n"
	msg+="	wg-skoonie does not."
	msg+="\n"
	msg+="\n"
	msg+="	Example usage:"
	msg+="\n"
	msg+="\n"
	msg+="	sudo ./wg-skoonie.sh addDeviceSpecIp \"wg0\" \"10.8.0.28\" \"Kelly's Computer\" \"Kelly's main computer that he uses at home.\""
	
	# addDeviceSkoonieOnly Command
	msg+="\n"
	msg+="\n"
	msg+="${yellowFontColor}"
	msg+="addDeviceSkoonieOnly [Interface Name] [New Device Public Key] [New Device IP Address] [New Device Name] [New Device Description]"
	msg+="${resetColors}"
	msg+="\n"
	msg+="\n"
	msg+="	Adds a new device to the wg-skoonie configuration files for the"
	msg+="\n"
	msg+="	specified interface, but does NOT add the device to WireGuard."
	msg+="\n"
	msg+="\n"
	msg+="	This command is used when a device already exists in WireGuard"
	msg+="\n"
	msg+="	and it now needs to be logged by wg-skoonie."
	msg+="\n"
	msg+="\n"
	msg+="	Currently, devices are only allowed IPv4 addresses on the"
	msg+="\n"
	msg+="	Virtual Private Network (VPN) for any interface. Support for"
	msg+="\n"
	msg+="	IPv6 will be added at a later date. WireGuard supports IPv6, but"
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
	msg+="	Removes the device specified by index from the specified"
	msg+="\n"
	msg+="	interface."
	msg+="\n"
	msg+="\n"
	msg+="	The device is removed from both wg-skoonie and from WireGuard."
	msg+="\n"
	msg+="\n"
	msg+="	To determine a device index, use command: "
	msg+="\n"
	msg+="		showInterfaceSkoonie [Interface Name]."
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
	msg+="	Lists all of the interfaces and the network details saved by"
	msg+="\n"
	msg+="	wg-skoonie."
	msg+="\n"
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
	msg+="	Outputs the details saved by wg-skoonie for the specified"
	msg+="\n"
	msg+="	interface."
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
	msg+="	Outputs the details saved by WireGuard for the specified"
	msg+="\n"
	msg+="	interface."
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
		
	elif isValueInArray "${pNetworkValues1046["KEY_NEW_DEVICE_IP_ADDRESS_DOTTED_DECIMAL"]}" deviceIpAddresses
	then
	
		# technically within subnet, but already exists.
		isInSubnet="0"
		msg="New device IP address is INVALID because the IP address has already been assigned to another device."
		
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
		
	"addDeviceSpecIp")
		# $2	Interface name to add device to.
		# $3	IP address of new device.
		# $4	Name of new device.
		# $5	Description of new device.
		addDeviceSpecIp "${2}" "${3}" "${4}" "${5}"
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
