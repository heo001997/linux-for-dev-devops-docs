webmin-setup-repos-explain.sh

#!/bin/sh
# shellcheck disable=SC1090 disable=SC2059 disable=SC2164 disable=SC2181
# setup-repos.sh
# Configures Webmin repository for RHEL and Debian systems (derivatives)

webmin_download="https://download.webmin.com"
webmin_key="jcameron-key.asc"
webmin_key_download="$webmin_download/$webmin_key"
debian_repo_file="/etc/apt/sources.list.d/webmin.list"
rhel_repo_file="/etc/yum.repos.d/webmin.repo"
download_wget="/usr/bin/wget"
# The -nv option is used to disable the verbose mode of wget. When -nv option is used, wget will only print out error messages.
download="$download_wget -nv"

# Temporary colors
NORMAL=''
GREEN=''
RED=''
ITALIC=''
BOLD=''
# man tty -s:
# -s, --silent, --quiet  print nothing, only return an exit status
# The script uses the tty to check if the shell session is connected to a terminal. If it's connected so it will return nothing, if it's not will return error, so skip all the assign color below.
# What is tty (support input/output), and compare to terminal (show), console (admin-helper, provide access to system), shell (command-line interface to run programs and script...)
if tty -s; then
  NORMAL="$(tput sgr0)"
  GREEN=$(tput setaf 2)
  RED="$(tput setaf 1)"
  BOLD=$(tput bold)
  ITALIC=$(tput sitm)
fi

# Check user permission
# Superuser id will always be 0
# heo001997@DESKTOP-834OPA3:/tmp$ id -u
# 1000
# heo001997@DESKTOP-834OPA3:/tmp$ sudo su
# root@DESKTOP-834OPA3:/tmp# id -u
# 0
if [ "$(id -u)" -ne 0 ]; then
    echo "${RED}Error:${NORMAL} \`setup-repos.sh\` script must be run as root!" >&2
    exit 1
fi

# Go to temp
# Syntax:
# The numbers refer to the file descriptors (fd).
# 0 is stdin
# 1 is stdout
# 2 is stderr
# -----
# cd "/tmp" 1>/dev/null
# output the result of cd action to /dev/null
# /dev/null is a special filesystem object that discards everything written into it. Redirecting a stream into it means hiding your program's output.
# cd "/tmp" 1>/dev/null 2>&1
# After discard output result of action cd /tmp. Here 2>&1 mean redirects fd 2 (stderr) to 1 (stdout). We want to show program errors to output.
# Note:
# cd "/tmp" == cd /tmp
# Can remove number 1 and keep the same result when redirect to file
# cd "/tmp" 1> == cd "/tmp" >
# -----
# More info about why cannot change order of 1>/dev/null and 2>&1
# https://stackoverflow.com/questions/10508843/what-is-dev-null-21
# https://stackoverflow.com/questions/818255/what-does-21-mean
# 2>&1 Mean stderr to stdout
# 2>1 Mean stderr to file name 1
# Change order of 2 code phrase gonna create something like this:
# START
# heo001997@heo001997server:~$ ls -ld /tmp /tnt >1 2>&1 | sed 's/^.*$/<-- & --->/'
# heo001997@heo001997server:~$ cat 1
# ls: cannot access '/tnt': No such file or directory
# drwxrwxrwt 23 root root 4096 Feb 25 06:31 /tmp
# heo001997@heo001997server:~$ ls -ld /tmp /tnt 2>&1 >1 | sed 's/^.*$/<-- & --->/'
# <-- ls: cannot access '/tnt': No such file or directory --->
# heo001997@heo001997server:~$ cat 1
# drwxrwxrwt 23 root root 4096 Feb 25 06:31 /tmp
# END
# >1 2>&1
# Correct order, all result will go to file 1 => To not show any response
# 2>&1 >1
# Incorrect order, errors correct to file 1 and error go the terminal => To only shot error
cd "/tmp" 1>/dev/null 2>&1
# $? expands to the exit status of the most recently executed foreground pipeline. See the Special Parameters section of the Bash manual. 
# Exitcode == 0 => TRUE
# Exitcode == 1 => FALSE
if [ "$?" != "0" ]; then
  # Use \` instead of only \, because it will wrap the special character in a string.
  echo "${RED}Error:${NORMAL} Failed to switch to \`/tmp\` directory!"
  exit 1
fi

# Check for OS release file
osrelease="/etc/os-release"
# ! mean reverse the result
# -f mean check if it's a valid normal file exist
# you can see the detail of the OS in the osrelease file
if [ ! -f "$osrelease" ]; then
  echo "${RED}Error:${NORMAL} Cannot detect OS!"
  exit 1
fi

# Detect OS and package manager and install command
# Sourcing the file extracting the ID or ID_LIKE... field.
. "$osrelease"
# The variable ID_LIKE and ID downhere get from sourcing the file 
# The -n flag is a test that checks if the length of a string is non-zero. If the variable is not empty, then the condition is true.
if [ -n "${ID_LIKE}" ]; then
    osid="$ID_LIKE"
else
    osid="$ID"
fi
# The -z flag (reverse of -n flag) is a test that checks if the length of a string is zero. If the variable is empty, then the condition is true.
if [ -z "$osid" ]; then
  echo "${RED}Error:${NORMAL} Failed to detect OS!"
  exit 1
fi

# Derivatives precise test
osid_debian_like=$(echo "$osid" | grep "debian\|ubuntu")
osid_rhel_like=$(echo "$osid" | grep "rhel\|fedora\|centos")

# Setup OS dependent
if [ -n "$osid_debian_like" ]; then
  package_type=deb
  install_cmd="apt-get install"
  install="$install_cmd --quiet --assume-yes"
  clean="apt-get clean"
  update="apt-get update"
elif [ -n "$osid_rhel_like" ]; then
  package_type=rpm
  # Funfact: You cannot 'man command', but you can 'help command'
  # command -pv option to check if the dnf command is available. 
  # print the absolute path of the command (if found) and not run any built-in command or shell function with the same name as the specified command.
  if command -pv dnf 1>/dev/null 2>&1; then
    install_cmd="dnf install"
    install="$install_cmd -y"
    clean="dnf clean all"
  else
    install_cmd="yum install"
    install="$install_cmd -y"
    clean="yum clean all"
  fi
else
  echo "${RED}Error:${NORMAL} Unknown OS : $osid"
  exit
fi

# Ask first
printf "Setup Webmin official repository? (y/N) "
# The -r option is used with the read command to prevent backslashes in the user's response from being interpreted as escape characters.
read -r sslyn
if [ "$sslyn" != "y" ] || [ "$sslyn" = "Y" ]; then
  exit
fi

# Check for wget or curl or fetch
# -x check if file is executable
if [ ! -x "$download_wget" ]; then
  if [ -x "/usr/bin/curl" ]; then
    # This is a command to download a file using curl with the following options:
    # -f: fail silently on server errors
    # -s: silent mode, don't show progress or error messages
    # -L: follow redirects
    # -O: write output to a local file using the remote file name.
    download="/usr/bin/curl -f -s -L -O"
  elif [ -x "/usr/bin/fetch" ]; then
    download="/usr/bin/fetch"
  else
    # Try installing wget
    echo "  Installing required ${ITALIC}wget${NORMAL} package from OS repository .."
    $install wget 1>/dev/null 2>&1
    if [ "$?" != "0" ]; then
      echo "  .. failed to install 'wget' package!"
      exit 1
    else
      echo "  .. done"
    fi
  fi
fi


# Check if GPG command is installed
# GPG is a command-line tool for secure communication and data storage, and is commonly used for verifying the authenticity of software packages and other downloads
if [ -n "$osid_debian_like" ]; then
  if [ ! -x /usr/bin/gpg ]; then
    $update 1>/dev/null 2>&1
    $install gnupg 1>/dev/null 2>&1
  fi
fi

# Clean files
rm -f "/tmp/$webmin_key"

# Download key
echo "  Downloading Webmin key .."
download_out=$($download $webmin_key_download 2>/dev/null 2>&1)
if [ "$?" != "0" ]; then
  download_out=$(echo "$download_out" | tr '\n' ' ')
  echo "  ..failed : $download_out"
  exit
else
  echo "  .. done"
fi

# Setup repos
case "$package_type" in
rpm)
  # Install our keys
  echo "  Installing Webmin key .."
  # This command imports the GPG key of the Webmin package repository to the RPM package manager. RPM is the package manager used by some Linux distributions like Fedora, CentOS, and Red Hat Enterprise Linux. By importing the GPG key, RPM verifies that the packages downloaded from the Webmin repository are signed and verified, ensuring their integrity and authenticity.
  rpm --import $webmin_key
  cp -f $webmin_key /etc/pki/rpm-gpg/RPM-GPG-KEY-webmin
  echo "  .. done"
  # Create repo file
  echo "  Setting up Webmin repository .."
  echo "[webmin-noarch]" >$rhel_repo_file
  echo "name=Webmin - noarch" >>$rhel_repo_file
  echo "baseurl=$webmin_download/download/yum" >>$rhel_repo_file
  echo "enabled=1" >>$rhel_repo_file
  echo "gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-webmin" >>$rhel_repo_file
  echo "gpgcheck=1" >>$rhel_repo_file
  echo "  .. done"
  # Clean meta
  echo "  Cleaning repository metadata .."
  $clean 1>/dev/null 2>&1
  echo "  .. done"
  ;;
deb)
  # Install our keys
  echo "  Installing Webmin key .."
  gpg --import $webmin_key 1>/dev/null 2>&1
  # This command downloads the Webmin repository GPG key in armored format and de-armors it to create the binary version of the key.
  # A GPG key in armored format is a human-readable ASCII representation of a GPG (GNU Privacy Guard) key that can be shared via email, web or other communication channels. 
  # It contains the public key and is used for verifying the authenticity and integrity of signed messages or files. 
	# Armoring the key means that it is converted into a text format that is easily readable and can be transferred without being corrupted. 
	# The armored format begins with a header, which includes the GPG version number and the type of key, followed by the public key data, and ends with a footer. 
  # It is typically identified by the .asc extension.
	# Sample:
	# -----BEGIN PGP PUBLIC KEY BLOCK-----
	# mQINBF2+JfUBEAC0tC1/Bt0A7yKqzLpH+s04mYzexb+1HzsD1lI9Q2B23fcDAggb
	# mJlNedr22fykmwN1cRJQ2Nt15Upse/1lj7VJdVmNq3MPyS5c5ynatwW/pA3Phq5q
	# 4hJ4D0KDWskCz0xQkpysmcAtHPrDgrYJgSDMkArvx7rkX+m/bU6SEsnUb+XXOyo6
	# CFUki1OLv2DxEYalPZoJ6ZNO9XUujfuzUIMaLfx/Ocf1yJ5S32v5jWw5z5/5q5Z4
	# 4o/dnW4N1Rn2xMkkgMTlI0FVwZPE0UNQBlHS7ksuLX1IKV7EJtge3qV7+uYBcvCf
	# YYsBrzKKpvD7T9TbQ/vufOcOjctFyif7R8WwLz2HPsdF4ZDFzppgoe8l0mxX5v5x
	# yBB0BcmO6kbcnMBCozz6Zfn12Gc91H8W7hXJvD6yjOdfyQmOVH/V57cCmmkZcrA2
	# mSXmVtpiR6pLbSLnAWj+C3qyCBblGTrL+M7jW4M8p4fNzIMjp4jv7VWsrUC8Uk7V
	# Ah/w6ix1Mfm2iCzZ/o0dIYaHVOdw/x40p8Pwz0q3qcrLExI04CCejvJ8WFO7s4Y4
	# ERs7VNgvjq8Ww7OeL2DfxBc9+gNzUpMuxiZjQbMHB/iaMf/F61w/7rjjbh93Gyaa
	# OSmZG/CtAP5HRq3m1MYHbwARAQABtBtXZWJtaW5hcGkgV2ViTWluIDx3ZWJtaW5h
	# cGktd2ViaW5AaG90bWFpbC5jb20+iQI9BBMBCgAnBQJdvu+0AhsDBQsJCAcCBhUK
	# CQgLAgQWAgMBAh4BAheAAAoJEHG/6TnLD8/f/qwQAKSazNQyUgXvJzQlWav/BHyt
	# RStaJbGeGm+lFwq3m3E54MDeg+MzF9HyHKlhIWZDLeJZAYGnbIHuyIOxJQOML+TP
	# c7aJ69nPlt9X+Rfs5hScffmQmcRP3AGnVVabG5fJFfltaHdf5z3SR/mgfemv1z
  cat $webmin_key | gpg --dearmor > /usr/share/keyrings/debian-webmin.gpg
  echo "  .. done"
  # Create repo file
  echo "  Setting up Webmin repository .."
  # This line is used to add the Webmin official repository to the list of repositories that the system uses to download and install packages. 
  # The [signed-by=/usr/share/keyrings/debian-webmin.gpg] option specifies that the repository should be verified using the GPG key stored in /usr/share/keyrings/debian-webmin.gpg. 
	# The $webmin_download variable is the URL of the Webmin download page, and the sarge and contrib options specify the release name and package categories, respectively.
  echo "deb [signed-by=/usr/share/keyrings/debian-webmin.gpg] $webmin_download/download/repository sarge contrib" >$debian_repo_file
  echo "  .. done"
  # Clean meta
  echo "  Cleaning repository metadata .."
  $clean 1>/dev/null 2>&1
  echo "  .. done"
  # Update meta
  echo "  Downloading repository metadata .."
  $update 1>/dev/null 2>&1
  echo "  .. done"
  ;;
*)
  echo "${RED}Error:${NORMAL} Cannot setup repositories on this system."
  exit 1
  ;;
esac

# Could not setup
if [ ! -x "/usr/bin/webmin" ]; then
  echo "Webmin package can now be installed using ${GREEN}${BOLD}${ITALIC}$install_cmd webmin${NORMAL} command."
fi

exit 0