#!/bin/bash

while getopts ":h:d:b:c:a" o; do case "${o}" in
	h) printf "[-d dotfiles ] [-c csv ] [-a AUR helper ] [ -h this message ] \\n" && exit ;;
	d) dotfiles=${OPTARG} && git ls-remote "$dotfiles" || exit ;;
	b) branch=${OPTARG} ;;
	c) csv=${OPTARG} ;;
	a) helper=${OPTARG} ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit ;;
esac done

# Prepare variables
[ -z "$dotfiles" ] && dotfiles="https://github.com/xon-dev/rice.git"
[ -z "$csv" ] && csv="https://raw.githubusercontent.com/xon-dev/autorice/test/apps.csv"
[ -z "$helper" ] && helper="yay"
[ -z "$repobranch" ] && repobranch="master"

distro="arch"
grepseq="\"^[PGA]*,\""

installpkg() { pacman --noconfirm --needed -S "$1" &>/dev/null; }

error() { clear; printf "ERROR:\\n%s\\n" "$1"; exit; }

welcomemsg() {
	read -rp "Welcome to installation script"
	read -rp "Continue? y/N" -n 1
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]
	then
		error "Bye"
	fi
}

getuserandpass() {
	name=''
	read -rp "Account name: " name
	while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" &> /dev/null; do
		read -rp "Not valid username: " name
	done
	pass1=''; pass2=''
	read -rp "Password:" -s pass1; echo
	read -rp "Retype:" -s pass2; echo
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		echo 'Passwords not match'
		read -rp "Password:" -s pass1; echo
		read -rp "Retype:" -s pass2; echo
	done
}

usercheck() {
	! (id -u "$name" &>/dev/null) ||
	{ read -rp 'Warning! User exists in system. Continue?' -n 1
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]
	then
		error "Bye"
		exit 1
	fi; }
}

preinstallmsg() {
	read -rp "Start installation? y/N" -n 1
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]
	then
		error "Bye"
		exit 1
	fi
}

adduserandpass() {
	# Adds user `$name` with password $pass1.
	echo "Adding user \"$name\"..."
	useradd -m -g wheel -s /bin/bash "$name" &> /dev/null ||
	usermod -a -G wheel "$name" && mkdir -p /home/"$name" \
						/home/"$name"/vids \
						/home/"$name"/pics \
						/home/"$name"/music/plists \
						/home/"$name"/dloads/tors \
						/home/"$name"/dloads/browser \
						/home/"$name"/docs \
						/home/"$name"/src \
						/home/"$name"/work && chown -R "$name":wheel /home/"$name"
	repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel $(dirname "$repodir")
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2
}

refreshkeys() {
	echo "Refreshing Keyring"
	pacman --noconfirm -Sy archlinux-keyring &> /dev/null
}

newperms() {
	sed -i "/#XON/d" /etc/sudoers
	echo "$* #XON" >> /etc/sudoers ;
}

manualinstall() {
	[ -f "/usr/bin/$1" ] || (
	echo "Installing \"$1\""
	cd /tmp || exit
	rm -rf /tmp/"$1"*
	curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
	sudo -u "$name" tar -xvf "$1".tar.gz &>/dev/null &&
	cd "$1" &&
	sudo -u "$name" makepkg --noconfirm -si &>/dev/null
	cd /tmp || return);
}

maininstall() {
	echo "[$n/$total] \`$1\` | \'pacman\'"
	installpkg "$1"
}

gitmakeinstall() {
	progname="$(basename "$1" .git)"
	dir="$repodir/$progname"
	echo "[$n/$total] \`$progname\` | \`git\` + \`make\`"
	sudo -u "$name" git clone --depth 1 "$1" "$dir" &> /dev/null || { cd "$dir" || return ; sudo -u "$name" git pull --force origin master;}
	cd "$dir" || exit
	make &> /dev/null
	make install &> /dev/null
	cd /tmp || return ;
}

aurinstall() { \
	echo "[$n/$total] \`$1\` | \'AUR\'"
	echo "$aurinstalled" | grep "^$1$" &> /dev/null && return
	sudo -u "$name" $helper -S --noconfirm "$1" &> /dev/null
}

pipinstall() { \
	echo "[$n/$total] \`$1\` | \'pip\'"
	command -v pip || installpkg python-pip &> /dev/null
	yes | pip install "$1"
}

installationloop() { \
	([ -f "$csv" ] && cp "$csv" /tmp/progs.csv) || curl -Ls "$csv" | sed '/^#/d' | eval grep "$grepseq" > /tmp/progs.csv
	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep "^\".*\"$" &> /dev/null && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"A") aurinstall "$program" ;;
			"G") gitmakeinstall "$program" ;;
			"P") pipinstall "$program" ;;
			*) maininstall "$program" ;;
		esac
	done < /tmp/progs.csv ;
}

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
welcomemsg        || error "User exited."
getuserandpass    || error "User exited."
usercheck         || error "User exited."
preinstallmsg     || error "User exited."
adduserandpass    || error "Error adding username and/or password."
refreshkeys       || error "Error automatically refreshing Arch keyring. Consider doing so manually."

echo "Preparing install."
installpkg curl   || error "Exited on curl"
installpkg base-devel   || error "Exited on base-devel"
installpkg git   || error "Exited on git"
installpkg ntp   || error "Exited on ntp"

echo "Synchronizing system time to ensure successful and secure installation of software..."
ntpdate 0.us.pool.ntp.org &>/dev/null 

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman and yay colorful and adds eye candy on the progress bar because why not.
grep "^Color" /etc/pacman.conf >/dev/null || sed -i "s/^#Color$/Color/" /etc/pacman.conf
grep "ILoveCandy" /etc/pacman.conf >/dev/null || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

manualinstall $helper || error "Failed to install AUR helper."

installationloop

echo "Finally, installing \`libxft-bgra\` to enable color emoji in suckless software without crashes."
#yes | sudo -u "$name" $helper -S libxft-bgra &> /dev/null

#?#?#?#?#?#?#?#?#?#?#?#?#?#?#?#?#?#?
git clone https://gitlab.freedesktop.org/xorg/lib/libxft.git libxft &>/dev/null
cd libxft
wget -qO- 'https://gitlab.freedesktop.org/xorg/lib/libxft/merge_requests/1.patch' | patch -p1
./autogen.sh &>/dev/null
./configure --prefix=/usr --sysconfdir=/etc --disable-static &>/dev/null
make &> /dev/null
make install &>/dev/null
cd /tmp
#?#?#?#?#?#?#?#?#?#?#?#?#?#?#?#?#?#?

# Putgitrepo
echo "Downloading and installing config files..."
dir=$(mktemp -d)
[ ! -d "/home/$name" ] && mkdir -p "/home/$name"
chown -R "$name":wheel "$dir" "$dotfiles"
sudo -u "$name" git clone --recurse-submodules -b "$repobranch" "$dotfiles" "$dir" &> /dev/null
sudo -u "$name" cp -rfT "$dir" "$dotfiles"

# Additional
sudo -u "$name" mv "/home/$name/.config/wallpapers" "/home/$name/pics/walls"
sudo -u "$name" mv "/home/$name/.config/icons" "/home/$name/pics/icons"

# System beep off
echo "Getting rid of that retarded error beep sound..."
rmmod pcspkr
echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" &> /dev/null
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

# dbus UUID must be generated for Artix runit.
dbus-uuidgen > /var/lib/dbus/machine-id

# Start/restart PulseAudio.
killall pulseaudio; sudo -u "$name" pulseaudio --start

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
[ "$distro" = arch ] && newperms "%wheel ALL=(ALL) ALL #LARBS
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay,/usr/bin/pacman -Syyuw --noconfirm"

# Last message! Install complete!
echo "Congrats! Installation successfull"
clear
