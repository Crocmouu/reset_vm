#!/bin/bash

# ============================================
# Script : change_vm_config.sh
# Description :
# Ce script permet de configurer une machine virtuelle (VM) clonée sous Ubuntu.
# Il effectue les actions suivantes :
# - Change le nom d'hôte de la machine pour garantir qu'il soit unique.
# - Modifie le mot de passe de l'utilisateur spécifié pour assurer la sécurité.
# - Définit la timezone de la machine selon la configuration fournie.
# - Configure le réseau en statique ou en DHCP selon les valeurs fournies.
# - Supprime les paquets spécifiés pour alléger l'installation.
# - Nettoie les logs système et l'historique Bash pour préserver la confidentialité.
# - Régénère les clés SSH pour assurer la sécurité des connexions.
# - Régénère l'identifiant de la machine et DUID pour une identification unique dans le réseau.
#
# Ce script lit les configurations à partir d'un fichier config.ini.
# Si certaines valeurs ne sont pas définies dans ce fichier, elles seront générées automatiquement.
#
# Exemples d'utilisation :
# 1. Pour exécuter le script :
#    ./change_vm_config.sh
#
# 2. Pour exécuter le script avec des privilèges root (si nécessaire) :
#    sudo ./change_vm_config.sh
#
# 3. Assurez-vous que le fichier config.ini est dans le même répertoire que ce script.
# ============================================

# Fonction pour afficher les messages de log
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> execution.log
}

# Fonction pour récupérer la valeur d'une clé dans le fichier config.ini
get_config_value() {
    local section=$1
    local key=$2
    local default_value=$3
    local value=$(awk -F "=" "/^\[$section\]/ {found=1; next} found && /^\[/{found=0} found && /^\s*$/{next} found && \$1==\"$key\" {print \$2; exit}" config.ini | xargs)
    echo "${value:-$default_value}"
}

# Fonction pour sauvegarder les résultats dans result.ini
save_result() {
    local key=$1
    local value=$2
    echo "$key = $value" >> result.ini
}

# Fonction pour changer le nom d'hôte
change_hostname() {
    local hostname=$(get_config_value "General" "hostname" "$(openssl rand -hex 4)")
    sudo hostnamectl set-hostname "$hostname"
    save_result "hostname" "$hostname"
    log "Nom d'hôte changé en $hostname."
}

# Fonction pour changer le mot de passe de l'utilisateur
change_password() {
    local user=$(get_config_value "General" "user" "ubuntu")
    local password=$(get_config_value "General" "password" "$(openssl rand -base64 12)")

    echo "$user:$password" | sudo chpasswd
    save_result "password" "$password"
    log "Mot de passe de l'utilisateur $user changé."
}

# Fonction pour configurer la timezone
change_timezone() {
    local timezone=$(get_config_value "General" "timezone" "UTC")
    sudo timedatectl set-timezone "$timezone"
    save_result "timezone" "$timezone"
    log "Timezone changée en $timezone."
}

# Fonction pour configurer le réseau (DHCP ou statique)
configure_network() {
    local interface="ens33"
    local ip_address=$(get_config_value "Network" "ip_address" "")
    local gateway=$(get_config_value "Network" "gateway" "")
    local dns=$(get_config_value "Network" "dns" "")

    # Configurer le réseau
    if [[ -z "$ip_address" ]]; then
        # Configuration DHCP
        sudo bash -c "cat > /etc/netplan/01-netcfg.yaml <<EOF
network:
    version: 2
    renderer: networkd
    ethernets:
        $interface:
            dhcp4: true
EOF"
        log "Configuration réseau en DHCP pour l'interface $interface."
    else
        # Configuration statique
        sudo bash -c "cat > /etc/netplan/01-netcfg.yaml <<EOF
network:
    version: 2
    renderer: networkd
    ethernets:
        $interface:
            dhcp4: false
            addresses:
                - $ip_address/24  # Remplacez par le préfixe approprié
            gateway4: $gateway
            nameservers:
                addresses: [$dns]
EOF"
        log "Configuration réseau statique pour l'interface $interface avec IP $ip_address."
    fi

    # Appliquer les configurations de réseau
	sudo chmod 600 /etc/netplan/01-netcfg.yaml
    sudo netplan apply
    save_result "ip_address" "$ip_address"
    save_result "gateway" "$gateway"
    save_result "dns" "$dns"
}

# Fonction pour supprimer les paquets spécifiés
remove_packages() {
    local packages=$(get_config_value "Packages" "packages_to_remove" "")
    if [ -n "$packages" ]; then
        sudo apt-get remove --purge -y $packages
        log "Paquets supprimés : $packages."
    else
        log "Aucun paquet à supprimer."
    fi
}

# Fonction pour nettoyer les logs système
clean_logs() {
    if [[ $(get_config_value "Logging" "clean_logs" "true") == "true" ]]; then
        sudo journalctl --rotate
        sudo journalctl --vacuum-time=1s
        log "Logs système nettoyés."
    fi
}

# Fonction pour nettoyer l'historique Bash
clean_bash_history() {
    if [[ $(get_config_value "Logging" "clean_bash_history" "true") == "true" ]]; then
        history -c
        log "Historique Bash nettoyé."
    fi
}

# Fonction pour régénérer les clés SSH
regenerate_ssh_keys() {
    if [[ $(get_config_value "Advanced" "regenerate_ssh_keys" "true") == "true" ]]; then
        sudo rm -f /etc/ssh/ssh_host_*
        sudo dpkg-reconfigure openssh-server
        log "Clés SSH régénérées."
    fi
}

# Fonction pour régénérer l'identifiant machine et DUID
regenerate_machine_id() {
    if [[ $(get_config_value "Advanced" "regenerate_machine_id" "true") == "true" ]]; then
        sudo rm -f /etc/machine-id
        sudo systemd-machine-id-setup
        log "Identifiant machine et DUID régénérés."
    fi
}

# Exécution des fonctions
change_hostname
change_password
change_timezone
configure_network
remove_packages
clean_logs
clean_bash_history
regenerate_ssh_keys
regenerate_machine_id

log "Configuration terminée."