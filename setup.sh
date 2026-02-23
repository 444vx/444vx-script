#!/usr/bin/env bash
# =============================================================================
#  SETUP SCRIPT — KDE Plasma + NVIDIA + Branding + Apps
#  Obsługuje: Debian/Ubuntu/Mint | Arch/Manjaro | Fedora/RHEL
# =============================================================================

# UWAGA: set -e wyłączone celowo — używamy || do obsługi błędów ręcznie,
# żeby jeden nieudany pakiet nie kończył całego skryptu.
set -uo pipefail

# ─────────────────────────────────────────────
#  KONFIGURACJA — zmień tutaj swoje ustawienia
# ─────────────────────────────────────────────
DISTRO_NAME="MyLinux"
DISTRO_PRETTY="MyLinux OS"
DISTRO_VERSION="1.0"
DISTRO_HOME_URL="https://example.com"

# ─────────────────────────────────────────────
#  KOLORY
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${NC}";
            echo -e "${BOLD}${CYAN}  $*${NC}";
            echo -e "${BOLD}${CYAN}══════════════════════════════════════${NC}\n"; }

# Zmienne globalne — uzupełniane przez detect_distro()
PKG_FAMILY=""
ORIG_USER=""

# ─────────────────────────────────────────────
#  SPRAWDŹ ROOT
# ─────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    error "Uruchom skrypt jako root: sudo bash $0"
fi

# Pobierz oryginalnego użytkownika (nie root) — potrzebne do yay/AUR
ORIG_USER="${SUDO_USER:-}"
if [[ -z "$ORIG_USER" ]]; then
    ORIG_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
fi
if [[ -z "$ORIG_USER" ]]; then
    warn "Nie można wykryć zwykłego użytkownika — operacje AUR mogą nie działać"
fi

# ─────────────────────────────────────────────
#  WYKRYJ DYSTRYBUCJĘ
# ─────────────────────────────────────────────
detect_distro() {
    [[ -f /etc/os-release ]] || error "Brak /etc/os-release — nieobsługiwany system"

    local id id_like name
    id=$(. /etc/os-release && echo "${ID:-}")
    id_like=$(. /etc/os-release && echo "${ID_LIKE:-}")
    name=$(. /etc/os-release && echo "${NAME:-Linux}")

    id="${id,,}"
    id_like="${id_like,,}"

    if [[ "$id" =~ ^(debian|ubuntu|linuxmint|pop|elementary|zorin|neon|kali)$ ]] \
       || [[ "$id_like" =~ debian ]] || [[ "$id_like" =~ ubuntu ]]; then
        PKG_FAMILY="debian"
    elif [[ "$id" =~ ^(arch|manjaro|endeavouros|garuda|artix|cachyos)$ ]] \
         || [[ "$id_like" =~ arch ]]; then
        PKG_FAMILY="arch"
    elif [[ "$id" =~ ^(fedora|rhel|centos|almalinux|rocky|ol)$ ]] \
         || [[ "$id_like" =~ fedora ]] || [[ "$id_like" =~ rhel ]]; then
        PKG_FAMILY="fedora"
    else
        error "Nieobsługiwana dystrybucja: $id (ID_LIKE: $id_like)"
    fi

    success "Wykryto: ${name} (rodzina: ${PKG_FAMILY})"
}

# ─────────────────────────────────────────────
#  AKTUALIZACJA + ZALEŻNOŚCI
# ─────────────────────────────────────────────
update_system() {
    header "Aktualizacja systemu"
    case "$PKG_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get upgrade -y -q
            apt-get install -y -q \
                curl wget software-properties-common \
                apt-transport-https gnupg lsb-release \
                flatpak pciutils \
                || error "Nie udało się zainstalować zależności (Debian)"
            ;;
        arch)
            pacman -Syu --noconfirm
            pacman -S --noconfirm --needed curl wget flatpak pciutils base-devel git

            if ! command -v yay &>/dev/null && ! command -v paru &>/dev/null; then
                info "Instaluję yay (AUR helper)..."
                if [[ -n "$ORIG_USER" ]]; then
                    sudo -u "$ORIG_USER" bash -c "
                        set -e
                        cd /tmp
                        rm -rf yay-bin
                        git clone https://aur.archlinux.org/yay-bin.git
                        cd yay-bin
                        makepkg -si --noconfirm
                    " || warn "Nie udało się zainstalować yay — AUR niedostępny"
                else
                    warn "Brak użytkownika do instalacji yay — AUR niedostępny"
                fi
            fi
            ;;
        fedora)
            dnf update -y -q
            dnf install -y -q curl wget flatpak pciutils

            local fedora_ver
            fedora_ver=$(rpm -E %fedora)
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                dnf install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
                    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm" \
                    || warn "Nie udało się dodać RPM Fusion — niektóre pakiety mogą być niedostępne"
            else
                info "RPM Fusion już zainstalowane"
            fi
            ;;
    esac
    success "System zaktualizowany"
}

# ─────────────────────────────────────────────
#  KDE PLASMA
# ─────────────────────────────────────────────
install_kde() {
    header "Instalacja KDE Plasma"

    if systemctl is-active --quiet sddm 2>/dev/null; then
        warn "SDDM już działa — KDE może być już zainstalowane, kontynuuję..."
    fi

    case "$PKG_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -y \
                kde-plasma-desktop sddm \
                plasma-nm plasma-pa \
                dolphin konsole kate \
                kscreen plasma-widgets-addons \
                || warn "Niektóre pakiety KDE nie zainstalowały się poprawnie"
            ;;
        arch)
            pacman -S --noconfirm --needed \
                plasma sddm \
                dolphin konsole kate \
                || warn "Niektóre pakiety KDE nie zainstalowały się poprawnie"
            ;;
        fedora)
            dnf group install -y "KDE Plasma Workspaces" \
                || warn "Nie udało się zainstalować grupy KDE"
            dnf install -y sddm dolphin konsole kate \
                || warn "Niektóre pakiety KDE nie zainstalowały się poprawnie"
            ;;
    esac

    systemctl enable sddm 2>/dev/null || warn "Nie udało się włączyć sddm.service"
    systemctl set-default graphical.target 2>/dev/null || warn "Nie udało się ustawić graphical.target"

    success "KDE Plasma zainstalowane"
}

# ─────────────────────────────────────────────
#  STEROWNIKI NVIDIA
# ─────────────────────────────────────────────
install_nvidia() {
    header "Sterowniki NVIDIA"

    if ! command -v lspci &>/dev/null; then
        warn "Brak lspci — nie można wykryć karty NVIDIA. Pomijam."
        return 0
    fi

    if ! lspci | grep -iE 'nvidia|geforce|quadro|tesla|rtx|gtx' &>/dev/null; then
        warn "Nie wykryto karty NVIDIA — pomijam instalację sterowników"
        return 0
    fi

    local card
    card=$(lspci | grep -iE 'nvidia|geforce|quadro|tesla|rtx|gtx' | head -1)
    info "Wykryto GPU: $card"

    case "$PKG_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive

            # Dodaj contrib non-free jeśli Debian (nie Ubuntu)
            if grep -q "^deb " /etc/apt/sources.list 2>/dev/null \
               && ! grep -qE "non-free" /etc/apt/sources.list; then
                sed -i 's/^\(deb .*main\)$/\1 contrib non-free non-free-firmware/' \
                    /etc/apt/sources.list
                apt-get update -qq
            fi

            # Linux headers
            apt-get install -y "linux-headers-$(uname -r)" 2>/dev/null \
                || apt-get install -y linux-headers-generic 2>/dev/null \
                || warn "Nie udało się zainstalować linux-headers"

            # Wykryj sterownik
            if apt-cache show nvidia-detect &>/dev/null 2>&1; then
                apt-get install -y nvidia-detect
                local detected_pkg
                detected_pkg=$(nvidia-detect 2>/dev/null \
                    | grep -oP 'nvidia-driver-\d+|nvidia-driver' | head -1 || echo "")
                if [[ -n "$detected_pkg" ]]; then
                    info "nvidia-detect sugeruje: $detected_pkg"
                    apt-get install -y "$detected_pkg" nvidia-settings \
                        || warn "Nie udało się zainstalować $detected_pkg"
                else
                    apt-get install -y nvidia-driver nvidia-settings \
                        || warn "Nie udało się zainstalować nvidia-driver"
                fi
            elif command -v ubuntu-drivers &>/dev/null; then
                info "Używam ubuntu-drivers autoinstall..."
                ubuntu-drivers autoinstall \
                    || warn "ubuntu-drivers autoinstall nie zadziałał"
            else
                apt-get install -y nvidia-driver nvidia-settings \
                    || warn "Nie udało się zainstalować nvidia-driver"
            fi
            ;;

        arch)
            # Znajdź zainstalowany kernel i dobierz headers
            local kernel_pkg
            kernel_pkg=$(pacman -Q linux linux-lts linux-zen linux-hardened 2>/dev/null \
                | awk '{print $1; exit}')
            if [[ -n "$kernel_pkg" ]]; then
                pacman -S --noconfirm --needed "${kernel_pkg}-headers" 2>/dev/null \
                    || warn "Nie udało się zainstalować ${kernel_pkg}-headers"
            fi

            pacman -S --noconfirm --needed nvidia nvidia-utils nvidia-settings \
                || warn "Nie udało się zainstalować sterownika NVIDIA"
            ;;

        fedora)
            dnf install -y \
                akmod-nvidia \
                xorg-x11-drv-nvidia \
                xorg-x11-drv-nvidia-cuda \
                xorg-x11-drv-nvidia-cuda-libs \
                nvidia-settings \
                || warn "Nie udało się zainstalować sterowników NVIDIA"

            info "Buduję moduł NVIDIA (akmods) — może chwilę zająć..."
            akmods --force 2>/dev/null || true
            dracut --force 2>/dev/null || true
            ;;
    esac

    # Wyłącz Nouveau + przebuduj initramfs
    if [[ ! -f /etc/modprobe.d/blacklist-nouveau.conf ]]; then
        cat > /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
        info "Nouveau wyłączony (blacklist)"
        case "$PKG_FAMILY" in
            debian) update-initramfs -u 2>/dev/null || true ;;
            arch)   mkinitcpio -P 2>/dev/null || true ;;
            fedora) dracut --force 2>/dev/null || true ;;
        esac
    fi

    success "Sterowniki NVIDIA zainstalowane — wymagany restart"
}

# ─────────────────────────────────────────────
#  BRANDING
# ─────────────────────────────────────────────
apply_branding() {
    header "Aplikuję branding: $DISTRO_PRETTY"

    # Odczytaj PRZED nadpisaniem
    local orig_id orig_ver orig_like
    orig_id=$(. /etc/os-release 2>/dev/null && echo "${ID:-linux}")
    orig_ver=$(. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-}")
    orig_like=$(. /etc/os-release 2>/dev/null && echo "${ID_LIKE:-}")

    cp /etc/os-release /etc/os-release.bak
    info "Backup: /etc/os-release.bak"

    cat > /etc/os-release <<EOF
NAME="${DISTRO_PRETTY}"
PRETTY_NAME="${DISTRO_PRETTY} ${DISTRO_VERSION}"
VERSION="${DISTRO_VERSION}"
VERSION_ID="${orig_ver}"
ID=${orig_id}
ID_LIKE="${orig_like}"
HOME_URL="${DISTRO_HOME_URL}"
EOF

    # TTY login banner
    cat > /etc/issue <<EOF
${DISTRO_PRETTY} ${DISTRO_VERSION} \n \l

EOF

    # SSH banner
    echo "${DISTRO_PRETTY} ${DISTRO_VERSION}" > /etc/issue.net

    # KDE — "O systemie"
    mkdir -p /etc/xdg
    cat > /etc/xdg/kcm-about-distrorc <<EOF
[General]
Name=${DISTRO_PRETTY}
Version=${DISTRO_VERSION}
Website=${DISTRO_HOME_URL}
Logo=
EOF

    success "Branding zastosowany"
    info "Widoczne w: Ustawienia → O systemie, TTY, SSH"
}

# ─────────────────────────────────────────────
#  FLATPAK (helper functions)
# ─────────────────────────────────────────────
setup_flatpak() {
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null \
        || warn "Nie udało się dodać Flathub"
}

flatpak_install() {
    local app_id="$1"
    local app_name="${2:-$1}"
    info "Instaluję $app_name przez Flatpak..."
    flatpak install -y --noninteractive flathub "$app_id" 2>/dev/null \
        && success "$app_name zainstalowany (Flatpak)" \
        || warn "Nie udało się zainstalować $app_name przez Flatpak"
}

# ─────────────────────────────────────────────
#  APLIKACJE
# ─────────────────────────────────────────────
install_apps() {
    header "Instalacja aplikacji"
    setup_flatpak

    # ── Java (wymagana przez Minecraft/Prism) ──────────────────────────────
    info "Instaluję Javę (wymaganą przez Prism Launcher)..."
    case "$PKG_FAMILY" in
        debian)
            apt-get install -y default-jre-headless 2>/dev/null \
                || warn "Nie udało się zainstalować Javy"
            ;;
        arch)
            pacman -S --noconfirm --needed jre-openjdk-headless 2>/dev/null \
                || warn "Nie udało się zainstalować Javy"
            ;;
        fedora)
            dnf install -y java-latest-openjdk-headless 2>/dev/null \
                || warn "Nie udało się zainstalować Javy"
            ;;
    esac

    # ══════════════════════════════════════════
    #  STEAM
    # ══════════════════════════════════════════
    info "Instaluję Steam..."
    local steam_ok=false

    case "$PKG_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --add-architecture i386
            apt-get update -qq
            apt-get install -y steam-installer 2>/dev/null && steam_ok=true \
                || apt-get install -y steam 2>/dev/null && steam_ok=true
            ;;
        arch)
            # Włącz [multilib] jeśli wykomentowany
            if grep -q "^#\[multilib\]" /etc/pacman.conf; then
                sed -i '/^#\[multilib\]/{s/^#//; n; s/^#//}' /etc/pacman.conf
                pacman -Sy --noconfirm
            fi
            pacman -S --noconfirm --needed steam 2>/dev/null && steam_ok=true
            ;;
        fedora)
            dnf install -y steam 2>/dev/null && steam_ok=true
            ;;
    esac

    [[ "$steam_ok" == true ]] \
        && success "Steam zainstalowany (natywnie)" \
        || { warn "Instalacja natywna nieudana — próbuję Flatpak...";
             flatpak_install "com.valvesoftware.Steam" "Steam"; }

    # ══════════════════════════════════════════
    #  DISCORD
    # ══════════════════════════════════════════
    info "Instaluję Discord..."
    local discord_ok=false

    case "$PKG_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            local tmp_deb="/tmp/discord_setup.deb"
            if wget --timeout=30 -q \
                "https://discord.com/api/download?platform=linux&format=deb" \
                -O "$tmp_deb" && [[ -s "$tmp_deb" ]]; then
                apt-get install -y "$tmp_deb" 2>/dev/null && discord_ok=true
                rm -f "$tmp_deb"
            fi
            ;;
        arch)
            pacman -S --noconfirm --needed discord 2>/dev/null && discord_ok=true
            ;;
        fedora)
            # Fedora nie ma Discorda w repo — od razu Flatpak
            discord_ok=false
            ;;
    esac

    [[ "$discord_ok" == true ]] \
        && success "Discord zainstalowany (natywnie)" \
        || { warn "Instalacja natywna nieudana — próbuję Flatpak...";
             flatpak_install "com.discordapp.Discord" "Discord"; }

    # ══════════════════════════════════════════
    #  PRISM LAUNCHER
    # ══════════════════════════════════════════
    info "Instaluję Prism Launcher..."
    local prism_ok=false

    case "$PKG_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            # PPA dostępne tylko na Ubuntu i pochodnych
            local base_id
            # Czytaj z backupa jeśli branding już nadpisał os-release
            base_id=$(. /etc/os-release.bak 2>/dev/null && echo "${ID:-}" \
                      || . /etc/os-release && echo "${ID:-}")
            if [[ "$base_id" =~ ubuntu|linuxmint|pop|zorin|elementary|neon ]]; then
                if add-apt-repository -y ppa:prismlauncher/prismlauncher 2>/dev/null \
                   && apt-get update -qq \
                   && apt-get install -y prismlauncher 2>/dev/null; then
                    prism_ok=true
                fi
            fi
            # Na Debianie/innym — od razu Flatpak (poniżej)
            ;;
        arch)
            if pacman -S --noconfirm --needed prismlauncher 2>/dev/null; then
                prism_ok=true
            elif [[ -n "$ORIG_USER" ]] && command -v yay &>/dev/null; then
                sudo -u "$ORIG_USER" yay -S --noconfirm prismlauncher 2>/dev/null \
                    && prism_ok=true
            fi
            ;;
        fedora)
            dnf install -y prismlauncher 2>/dev/null && prism_ok=true
            ;;
    esac

    [[ "$prism_ok" == true ]] \
        && success "Prism Launcher zainstalowany (natywnie)" \
        || { warn "Instalacja natywna nieudana — próbuję Flatpak...";
             flatpak_install "org.prismlauncher.PrismLauncher" "Prism Launcher"; }
}

# ─────────────────────────────────────────────
#  PODSUMOWANIE
# ─────────────────────────────────────────────
summary() {
    header "Instalacja zakończona!"
    echo -e "${GREEN}${BOLD}Zainstalowano:${NC}"
    echo -e "  ✔  KDE Plasma + SDDM"
    echo -e "  ✔  Sterowniki NVIDIA (jeśli wykryto kartę)"
    echo -e "  ✔  Branding: ${DISTRO_PRETTY}"
    echo -e "  ✔  Steam"
    echo -e "  ✔  Discord"
    echo -e "  ✔  Prism Launcher + Java"
    echo ""
    echo -e "${YELLOW}${BOLD}⚠  WYMAGANY RESTART${NC}"
    echo -e "   Uruchom: ${CYAN}sudo reboot${NC}"
    echo ""
    echo -e "   Po restarcie zobaczysz ekran logowania SDDM z KDE Plasma."
    echo ""
}

# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║       SETUP SCRIPT v1.1              ║${NC}"
    echo -e "${BOLD}${CYAN}║  KDE + NVIDIA + Branding + Apps      ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    detect_distro
    update_system
    install_kde
    install_nvidia
    apply_branding
    install_apps
    summary
}

main "$@"
