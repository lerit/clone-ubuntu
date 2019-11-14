#!/bin/bash

# NAME: clone-ubuntu.sh
# PATH: /usr/local/bin
# DESC: Written for AU Q&A: https://askubuntu.com/questions/1028604/bash-seemless-safe-script-to-upgrade-16-04-to-18-04/1028605#1028605
# REFERENCE: https://askubuntu.com/questions/1028604/bash-script-to-backkup-clone-ubuntu-to-another-partition/1028605#1028605

# $TERM variable may be missing when called via desktop shortcut
CurrentTERM=$(env | grep TERM)
if [[ $CurrentTERM == "" ]] ; then
    notify-send --urgency=critical \ 
                "$0 cannot be run from GUI without TERM environment variable."
    exit 1
fi

# Must run as root
if [[ $(id -u) -ne 0 ]] ; then echo "Usage: sudo $0" ; exit 1 ; fi

#
# Create unqique temporary file names
#

tmpPart=$(mktemp /tmp/clone-ubuntu.XXXXX)   # Partitions list
tmpMenu=$(mktemp /tmp/clone-ubuntu.XXXXX)   # Menu list
tmpInf1=$(mktemp /tmp/clone-ubuntu.XXXXX)   # Soucre (Booted) Ubuntu Info
tmpInf2=$(mktemp /tmp/clone-ubuntu.XXXXX)   # Target (Cloned) Ubuntu Info
tmpInf3=$(mktemp /tmp/clone-ubuntu.XXXXX)   # Work file used by DistInfo ()

#
# Function Cleanup () Removes temporary files
#

CleanUp () {
    [[ -f "$tmpPart" ]] && rm -f "$tmpPart" # If we created temp files
    [[ -f "$tmpMenu" ]] && rm -f "$tmpMenu" #  at various program stages
    [[ -f "$tmpInf1" ]] && rm -f "$tmpInf1" #  then remove them before
    [[ -f "$tmpInf2" ]] && rm -f "$tmpInf2" #  exiting.
    [[ -f "$tmpInf3" ]] && rm -f "$tmpInf3"

    if  [[  -d "$TargetMnt" ]]; then        # Did we create a clone mount?
        umount "$TargetMnt" -l              # Unmount the clone
        rm  -d "$TargetMnt"                 # Remove clone directory
    fi
}

#
# Function GetUUID () gets UUIDs of source and clone target partitions in menu.
#

GetUUID () {

    SrchLine="$1"                           # menu line passed to function
    UUID_col=0                              # start column of UUID in line
    lsblk -o NAME,UUID > "$tmpPart"         # Get list of UUID's

    while read -r UUID_Line; do             # Read through UUID list

        # Establish UUID position on line
        if [[ $UUID_col == 0 ]] ; then      # First time will be heading
            UUID_col="${UUID_Line%%UUID*}"  # Establish column number
            UUID_col="${#UUID_col}"         #  where UUID appears on line
            NameLen=$(( UUID_col - 1 ))     # Max length of partition name
            continue                        # Skip to read next line
        fi

        # Check if Passed line name (/dev/sda1, /nvme01np8, etc.) matches.
        if [[ "${UUID_Line:0:$NameLen}" == "${SrchLine:0:$NameLen}" ]] ; then
            FoundUUID="${UUID_Line:UUID_col:999}"
            break                           # exit function
        fi

    done < "$tmpPart"                       # Read next line & loop back
}


#
# Function DistInfo () builds information about source & target partitions
#

DistInfo () {

    Mount="$1"                              # Mount name is '/' or $TargetMnt
    FileName="$2"                           # "$tmpInf1" or "$tmpInf2" work file
    cat "$Mount"/etc/lsb-release >> "$FileName"
    sed -i 's/DISTRIB_//g' "$FileName"      # Remove DISTRIB_ prefix.
    sed -i 's/=/:=/g' "$FileName"           # Change "=" to ":="
    sed -i 's/"//g' "$FileName"             # Remove " around "Ubuntu 16.04...".

    # Align columns from "Xxxx:=Yyyy" to "Xxxx:      Yyyy"
    cat "$FileName" | column -t -s '=' > "$tmpInf3"
    cat "$tmpInf3" > "$FileName"
}


#
# Mainline
#

lsblk -o NAME,FSTYPE,LABEL,SIZE,MOUNTPOINT > "$tmpMenu"

i=0
SPACES='                                                                     '
DoHeading=true
AllPartsArr=()      # All partitions.

# Build whiptail menu tags ($i) and text ($Line) into array

while read -r Line; do
    if [[ $DoHeading == true ]] ; then
        DoHeading=false                     # First line is the heading.
        MenuText="$Line"                    # Heading for whiptail.
        FSTYPE_col="${Line%%FSTYPE*}"           
        FSTYPE_col="${#FSTYPE_col}"         # Required to ensure `ext4`.
        MOUNTPOINT_col="${Line%%MOUNTPOINT*}"
        MOUNTPOINT_col="${#MOUNTPOINT_col}" # Required to ensure not mounted.
        continue
    fi

    Line="$Line$SPACES"                     # Pad extra white space.
    Line=${Line:0:74}                       # Truncate to 74 chars for menu.

    if [[ "${Line:MOUNTPOINT_col:4}" == "/   " ]] ; then
        GetUUID "$Line"
        SourceUUID=$FoundUUID
        # Build "/dev/Xxxxx" FS name from "├─Xxxxx" lsblk line
        SourceDev="${Line%% *}"
        SourceDev=/dev/"${SourceDev:2:999}"
    fi

    AllPartsArr+=($i "$Line")               # Menu array entry = Tag# + Text.
    (( i++ ))

done < "$tmpMenu"                           # Read next "lsblk" line.

#
# Display whiptail menu in while loop until no errors, or escape,
# or valid partion selection .
#

DefaultItem=0

while true ; do

    # Call whiptail in loop to paint menu and get user selection
    Choice=$(whiptail \
        --title "Use arrow, page, home & end keys. Tab toggle option" \
        --backtitle "Clone 16.04 for upgrade.  ONLY CLONES / PARTITION" \
        --ok-button "Select unmounted partition" \
        --cancel-button "Exit" \
        --notags \
        --default-item "$DefaultItem" \
        --menu "$MenuText" 24 80 16 \
        "${AllPartsArr[@]}" \
        2>&1 >/dev/tty)

    clear                                   # Clear screen.
    if [[ $Choice == "" ]]; then            # Escape or dialog "Exit".
        CleanUp
        exit 0;
     fi

    DefaultItem=$Choice                     # whiptail start option.
    ArrNdx=$(( $Choice * 2 + 1))            # Calculate array offset.
    Line="${AllPartsArr[$ArrNdx]}"          # Array entry into $Line.

    # Validation - Don't wipe out Windows or Ubuntu 16.04:
    # - Partition must be ext4 and cannot be mounted.

    if [[ "${Line:FSTYPE_col:4}" != "ext4" ]] ; then
        echo "Only 'ext4' partitions can be clone targets."
        read -p "Press <Enter> to continue"
        continue
    fi

    if [[ "${Line:MOUNTPOINT_col:4}" != "    " ]] ; then
        echo "A Mounted partition cannot be a clone target."
        read -p "Press <Enter> to continue"
        continue
    fi

    GetUUID "$Line"                         # Get UUID of target partition.
    TargetUUID=$FoundUUID

    # Build "/dev/Xxxxx" FS name from "├─Xxxxx" menu line
    TargetDev="${Line%% *}"
    TargetDev=/dev/"${TargetDev:2:999}"

    break                                   # Validated: Break menu loop.

done                                        # Loop while errors.

#
# Mount Clone Target partition
#

Release=$(lsb_release -rs)                  # Source version ie: '16.04'
TargetMnt="/mnt/clone$Release"

echo ""
echo "====================================================================="
echo "Mounting clone partition $TargetDev as $TargetMnt"
mkdir -p "$TargetMnt"                       # '-p' directory may already exist
mount -t auto -v $TargetDev "$TargetMnt" > /dev/null

# Confirm partition is empty. If not empty confirm it's Ubuntu. If not exit.
# If Ubuntu display prompt with the version it contains and get confirmation.

echo ""
echo "====================================================================="
echo "PLEASE: Carefully confirm Source (Live) and Target (Clone) partitions"

# Build source information (our current boot partition)
echo "SOURCE (BOOT /)=$SourceDev"  > "$tmpInf1"
DistInfo "/" "$tmpInf1"                     # /etc/lsb_release information
df -h --output=size,used,avail,pcent "$SourceDev" >> "$tmpInf1"

# Build target information (the partition selected for cloning to)
LineCnt=$(ls "$TargetMnt" | wc -l)
if (( LineCnt > 1 )) ; then 
    # More than /Lost+Found exist so it's not an empty partition.
    if [[ -f "$TargetMnt"/etc/lsb-release ]] ; then
        echo "TARGET (CLONE)=$TargetDev" > "$tmpInf2"
        DistInfo "$TargetMnt" "$tmpInf2"    # /etc/lsb_release information
    else
        # TO-DO: might be cloning /boot or /home on separate partitions.
        #        the source partition is still `/` so can display message.
        echo "Selected partition has data which is not Ubuntu OS. Aborting."
        CleanUp                             # Remove temporary files
        exit 1
    fi
else
    echo "Target (Clone) partition appears empty" > "$tmpInf2"
    echo "/Lost+Found normal in empty partition" >> "$tmpInf2"
    echo "Head of '/Clone/' files & directories:" >> "$tmpInf2"
    ls "$TargetMnt" | head -n2 >> "$tmpInf2"
fi

# Target device free bytes
df -h --output=size,used,avail,pcent "$TargetDev" >> "$tmpInf2"

# Display source and target partitions side-by-side using bold text.
echo $(tput bold)       # Set to bold text
paste -d '|' "$tmpInf1" "$tmpInf2" | column -t -s '|'
echo $(tput sgr0)       # Reset to normal text

echo "NOTE: If you are recloning, new files in clone will be deleted,"
echo "      modified files are reset to current source content and,"
echo "      files deleted from clone are added back from source."
echo ""

read -p "Type Y (or y) to proceed. Any other key to exit: " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]] ; then
    CleanUp             # Remove temporary files
    exit 0
fi

# Copy non-virtual directories to clone. Credit to TikTak's Ask Ubuntu answer:
# https://askubuntu.com/questions/319805/is-it-safe-to-clone-the-current-used-disk?utm_medium=organic&utm_source=google_rich_qa&utm_campaign=google_rich_qa

SECONDS=0
echo ""
echo "====================================================================="
echo "Using rsync to clone / to $TargetDev mounted as $TargetMnt"
rsync -haxAX --stats --delete --info=progress2 --info=name0 --inplace  \
      /* "$TargetMnt"                                                   \
      --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found}
# For 16GB on Samsung Pro 960: First time 98 seconds, second time 27 seconds.
rsyncTime=$SECONDS  
echo ""
echo "Time to clone files: $rsyncTime Seconds"

# Change /etc/update-manager/release-upgrades prompt from never to LTS
echo ""
echo "====================================================================="
echo "Making changes in: $TargetMnt/etc/update-manager/release-upgrades"
echo "     from Prompt=: never"
echo "       to Prompt=: lts"
echo "Allows running 'do-release-upgrade -d' when rebooting clone target"
echo "Consider 'do-release-upgrade -d -f DistUpgradeViewNonInteractive' This"
echo "allows you to go to bed or go to lunch whilst upgrade runs."
echo ""
echo "* * *  When you Upgrade, TURN OFF screen locking for inactivity. * * *"
echo ""
sed -i 's/Prompt=never/Prompt=lts/' "$TargetMnt"/etc/update-manager/release-upgrades

## This section commented out to prevent surprises. You may uncomment.
## You may want to revise to include `cron.daily`, `cron.hourly`, etc.
# Move `/etc/cron.d` reboot jobs to `/etc/cron.d/hold` to prevent running
# scripts such as daily backup or Ubuntu 16.04 specific problem fixes.
#echo ""
#echo "====================================================================="
#echo "Moving '$TargetMnt/etc/cron.d' to '.../hold' to prevent running."
#echo "After booting clone, move back individual files you want to run"
#if [[ ! -d "$TargetMnt"/etc/cron.d/hold ]]; then
#    mkdir "$TargetMnt"/etc/cron.d/hold
#fi
#cp -p  "$TargetMnt"/etc/cron.d/* "$TargetMnt"/etc/cron.d/hold/
#rm -fv "$TargetMnt"/etc/cron.d/*

# Update /etc/fstab on clone partition with clone's UUID
echo ""
echo "====================================================================="
echo "Making changes in: $TargetMnt/etc/fstab"
echo "        from UUID: $SourceUUID"
echo "          to UUID: $TargetUUID"
sed -i "s/$SourceUUID/$TargetUUID/g" "$TargetMnt"/etc/fstab

# Update /boot/grub/grub.cfg on clone partition with clone's UUID
echo ""
echo "====================================================================="
echo "Making changes in: $TargetMnt/boot/grub/grub.cfg"
echo "        from UUID: $SourceUUID"
echo "          to UUID: $TargetUUID"
echo "Also change 'quiet splash' to 'nosplash' for environmental awareness"
echo "Suggest first time booting clone you make wallpaper unique"
sed -i "s/$SourceUUID/$TargetUUID/g" "$TargetMnt"/boot/grub/grub.cfg
sed -i "s/quiet splash/nosplash/g" "$TargetMnt"/boot/grub/grub.cfg

# Update grub boot menu
echo ""
echo "====================================================================="
echo "Calling 'update-grub' to create new boot menu"
update-grub

# Unmount and exit

echo ""
echo "====================================================================="
echo "Unmounting $TargetDev as $TargetMnt"

CleanUp             # Remove temporary files

exit 0
