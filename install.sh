#!/bin/bash

# === Configuration ===
DEFAULT_SHELL="/bin/bash"
FALLBACK_SHELL="/bin/sh"

# === Helpers ===
log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

addCockpit () {
    echo -en '\n\n'
    echo "Installing cockpit with 45Drives Navigator add-on..."
    sudo apt -y install cockpit

    echo -en '\n\n'
    echo "Installing 45Drives Navigator plugin for Cockpit..."
    curl -sSL https://repo.45drives.com/setup -o setup-repo.sh
    sudo bash setup-repo.sh
    sudo apt update && sudo apt install cockpit-navigator -y

    echo -en '\n\n'
    read -n1 -p "Do you want to add Docker support to Cockpit? [y/N]" doit 
    case $doit in  
      y|Y) addDocker ;; 
      *) echo -en '\n\n' ;; 
    esac
}

addDocker () {
    echo "Installing Docker extension to Cockpit..."
    wget https://github.com/mrevjd/cockpit-docker/releases/download/v2.0.3/cockpit-docker.tar.gz
    sudo mv cockpit-docker.tar.gz /usr/share/cockpit
    sudo tar xf /usr/share/cockpit/cockpit-docker.tar.gz -C /usr/share/cockpit/
    sudo rm /usr/share/cockpit/cockpit-docker.tar.gz
    echo -en '\n\n'
}

changeHostname () {
    usage() {
       echo "Usage : $0 <new hostname>"
       exit 1
    }
    
    [ "$1" ] || usage
    
    old=$(hostname)
    read -r -p "Enter Hostname: " new
    
    for file in \
       /etc/exim4/update-exim4.conf.conf \
       /etc/printcap \
       /etc/hostname \
       /etc/hosts \
       /etc/ssh/ssh_host_rsa_key.pub \
       /etc/ssh/ssh_host_dsa_key.pub \
       /etc/motd \
       /etc/ssmtp/ssmtp.conf
    do
       [ -f $file ] && sed -i.old -e "s:$old:$new:g" $file

}

valid_username() {
  local u="$1"
  # username: start with letter or underscore, then letters, digits, underscore, dash; 1-32 chars
  if [[ "$u" =~ ^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$ ]]; then
    return 0
  fi
  return 1
}

create_user() {
  local fullname="$1"
  local username="$2"
  local password="$3"

  # Check if user exists
  if id "$username" >/dev/null 2>&1; then
    err "User '$username' already exists — skipping."
    return 1
  fi

  # useradd options:
  # -m : create home
  # -s : shell
  # -c : GECOS / full name
  # -G : supplementary groups (we will add to sudo group)
  sudo useradd -m -s "$DEFAULT_SHELL" -c "$fullname" -G "$SUDO_GROUP" "$username"
  if [ $? -ne 0 ]; then
    err "useradd failed for $username"
    return 1
  fi

  # Set password (via chpasswd). This reads "user:password" from stdin.
  # NOTE: this will store the password in memory briefly; script is run as root so that's necessary.
  printf '%s:%s\n' "$username" "$password" | sudo chpasswd
  if [ $? -ne 0 ]; then
    err "Failed to set password for $username"
    return 1
  fi

  # Force password change at first login
  if command -v chage >/dev/null 2>&1; then
    sudo chage -d 0 "$username"
  else
    # fallback: expire passwd (some systems)
    sudo passwd -e "$username" || true
  fi

  log "Created user: $username (Full name: $fullname). Home: /home/$username Shell: $DEFAULT_SHELL Added to group: $SUDO_GROUP"
  return 0
}

#################
## START HERE ###
#################

# Find all dot files then if the original file exists, create a backup
# Once backed up to {file}.dtbak symlink the new dotfile in place
for file in $(find . -maxdepth 1 -name ".*" -type f  -printf "%f\n" ); do
    if [ -e ~/$file ]; then
        mv -f ~/$file{,.dtbak}
    fi
    ln -s $PWD/$file ~/$file
done

# Check if vim-addon installed, if not, install it automatically
if hash vim-addon  2>/dev/null; then
    echo "vim-addon (vim-scripts)  installed"
else
    echo "vim-addon (vim-scripts) not installed, installing"
    sudo apt update && sudo apt -y install vim-scripts
fi

echo -en '\n\n'
echo "Installing additional programs..."
sudo apt -y install screenfetch curl plocate snmp snmpd tree git
echo -en '\n\n'

if [ "$(dpkg -l | awk '/cockpit/ {print }' | wc -l)" -ge 1 ]; then
    echo "Cockpit installed"
    echo -en '\n\n'
else
    read -n1 -p "Do you want to add Cockpit to this server? [y/N]" doit
    case $doit in
      y|Y) addCockpit ;;
      *) echo -en '\n\n' ;; 
    esac
fi

read -n1 -p "Change hostname? [Y/n]" doit
case $doit in
  n|N) echo -en '\n\n' ;;
  *) changeHostname ;;
esac

# Interactive loop
read -r -p "Add accounts? (y/N): " ADD_ANS
ADD_ANS=${ADD_ANS:-N}
if [[ ! "$ADD_ANS" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  log "No accounts to add. Exiting."
  exit 0
fi

while true; do
  # Full name
  read -r -p "Full name (display name) [leave blank to cancel]: " FULLNAME
  if [ -z "$FULLNAME" ]; then
    log "Blank full name entered — canceling loop and exiting."
    break
  fi

  # Username
  while true; do
    read -r -p "Username (linux login name): " USERNAME
    if [ -z "$USERNAME" ]; then
      log "Blank username — canceling this entry."
      USERNAME=""
      break
    fi
    if ! valid_username "$USERNAME"; then
      err "Invalid username. Must start with a letter or underscore, can contain letters/digits/_/-, max 32 chars."
      continue
    fi
    if id "$USERNAME" >/dev/null 2>&1; then
      err "Username '$USERNAME' already exists. Choose a different username."
      continue
    fi
    break
  done

  [ -z "$USERNAME" ] && continue

  # Password (hidden)
  while true; do
    read -s -r -p "Password: " PASS1
    echo
    if [ -z "$PASS1" ]; then
      err "Password cannot be blank."
      continue
    fi
    read -s -r -p "Confirm Password: " PASS2
    echo
    if [ "$PASS1" != "$PASS2" ]; then
      err "Passwords do not match. Try again."
      continue
    fi
    break
  done

  # Create the user
  if create_user "$FULLNAME" "$USERNAME" "$PASS1"; then
    log "User $USERNAME successfully created."
  else
    err "Failed to create $USERNAME."
  fi

  # Ask to add another
  read -r -p "Add another account? (y/N): " REPEAT
  REPEAT=${REPEAT:-N}
  if [[ ! "$REPEAT" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    log "Done adding accounts. Exiting."
    break
  fi
done

#echo "Installing SSH keys..."
#if [ ! -d ~/.ssh ]; then 
#    mkdir ~/.ssh
#fi
#curl https://github.com/linad181.keys -o ~/.ssh/authorized_keys
#echo -en '\n\n'

echo "Install finished."
