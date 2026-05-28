#!/bin/bash
# Lab HTTP/S amb Nginx — Script de gestió
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.lab-stage"
DOMAIN="demohttp.publicvm.com"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${BLUE}>>> $*${NC}"; }
ok()      { echo -e "${GREEN}    OK: $*${NC}"; }
warn()    { echo -e "${YELLOW}    AVÍS: $*${NC}"; }
error()   { echo -e "${RED}    ERROR: $*${NC}"; exit 1; }
section() { echo -e "\n${CYAN}=== $* ===${NC}\n"; }

# ─── Ajuda ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Ús: $0 <comanda> [opcions]

COMANDES:
  check           Verifica els prerequisits (Docker, containerlab, mkcert)
  build           Construeix les imatges Docker personalitzades
  certs [N]       Genera certificats mkcert per a l'etapa N (per defecte: totes)
  deploy N        Desplega l'etapa N (1–6)
  setup N         Configuració post-desplegament de l'etapa N
  acme            Obté certificat real amb acme.sh (DNS challenge, etapa 5)
  status          Mostra l'etapa activa i els contenidors
  shell [node]    Obre una shell en un node (per defecte: nginx-proxy o nginx)
  destroy         Destrueix el lab actiu
  help            Mostra aquesta ajuda

ETAPES:
  1  HTTP bàsic — Nginx servint web estàtica per HTTP
  2  HTTPS mkcert — Certificats de desenvolupament amb mkcert
  3  Reverse proxy — Nginx com a proxy invers (web01/web02/web03)
  4  Autenticació bàsica — Basic Auth amb htpasswd
  5  HTTPS acme.sh — Certificat real via DNS challenge (DNSExit)
  6  Gestió de logs — Formats, rotació i anàlisi de logs

EXEMPLES:
  $0 check
  $0 certs 2
  $0 deploy 3
  $0 setup 4
  $0 shell web01
  $0 destroy
EOF
    exit 0
}

# ─── Prerequisits ─────────────────────────────────────────────────────────────
cmd_check() {
    section "Verificant prerequisits"
    local ok=true

    info "Docker..."
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        ok "Docker $(docker --version | awk '{print $3}' | tr -d ',')"
    else
        warn "Docker no disponible o dimoni aturat"; ok=false
    fi

    info "Containerlab..."
    if command -v containerlab &>/dev/null; then
        ok "Containerlab $(containerlab version 2>/dev/null | grep 'Version:' | awk '{print $2}' || echo 'instal·lat')"
    else
        warn "Containerlab no instal·lat (https://containerlab.dev/install/)"; ok=false
    fi

    info "mkcert..."
    if command -v mkcert &>/dev/null; then
        ok "mkcert $(mkcert --version 2>/dev/null || echo 'instal·lat')"
    else
        warn "mkcert no instal·lat (apt install mkcert o https://github.com/FiloSottile/mkcert)"; ok=false
    fi

    info "apache2-utils (htpasswd)..."
    if command -v htpasswd &>/dev/null; then
        ok "htpasswd disponible"
    else
        warn "apache2-utils no instal·lat (apt install apache2-utils)"; ok=false
    fi

    info "Python 3 + weasyprint + jinja2 + pyyaml (per als exàmens)..."
    if python3 -c "import weasyprint, jinja2, yaml" 2>/dev/null; then
        ok "Python deps disponibles"
    else
        warn "Falten deps Python: pip3 install weasyprint jinja2 pyyaml"
    fi

    info "Fitxer .env..."
    if [ -f "$SCRIPT_DIR/.env" ]; then
        ok ".env trobat"
    else
        warn ".env no trobat — copia .env.example com .env i omple els valors"
    fi

    if $ok; then
        echo -e "\n${GREEN}Tots els prerequisits satisfets.${NC}\n"
    else
        echo -e "\n${YELLOW}Alguns prerequisits falten. Revisa els avisos.${NC}\n"
    fi
}

# ─── Build ────────────────────────────────────────────────────────────────────
cmd_build() {
    section "Construint imatges Docker"
    info "Construint nginx-lab-switch:latest (switch L2 containeritzat)..."
    docker build -f "$SCRIPT_DIR/docker/Dockerfile.switch" \
                 -t nginx-lab-switch:latest \
                 "$SCRIPT_DIR/docker/"
    ok "nginx-lab-switch:latest construïda"

    info "Construint nginx-lab-logs:latest (nginx + logrotate per a etapa 6)..."
    docker build -f "$SCRIPT_DIR/docker/Dockerfile.nginx-logs" \
                 -t nginx-lab-logs:latest \
                 "$SCRIPT_DIR/docker/"
    ok "nginx-lab-logs:latest construïda"
}

# ─── Certs mkcert ─────────────────────────────────────────────────────────────
cmd_certs() {
    local stage="${1:-all}"
    section "Generant certificats mkcert"

    if ! command -v mkcert &>/dev/null; then
        error "mkcert no instal·lat"
    fi

    info "Instal·lant CA local de mkcert..."
    mkcert -install

    mkdir -p "$SCRIPT_DIR/certs"
    cd "$SCRIPT_DIR/certs"

    info "Generant certificat per a $DOMAIN i subdominis..."
    mkcert \
        "$DOMAIN" \
        "www.$DOMAIN" \
        "web01.$DOMAIN" \
        "web02.$DOMAIN" \
        "web03.$DOMAIN" \
        "localhost" \
        "127.0.0.1"

    # Reanomenar a noms estàndard
    local cert_src=$(ls "${DOMAIN}+6.pem" 2>/dev/null || ls "${DOMAIN}*.pem" 2>/dev/null | head -1)
    local key_src=$(ls "${DOMAIN}+6-key.pem" 2>/dev/null || ls "${DOMAIN}*-key.pem" 2>/dev/null | head -1)

    if [ -n "$cert_src" ]; then
        cp "$cert_src" "$SCRIPT_DIR/certs/nginx.crt"
        cp "$key_src"  "$SCRIPT_DIR/certs/nginx.key"
        ok "Certificat: certs/nginx.crt"
        ok "Clau:       certs/nginx.key"
    else
        # mkcert naming can vary
        find . -name "*.pem" ! -name "*-key.pem" -exec cp {} "$SCRIPT_DIR/certs/nginx.crt" \;
        find . -name "*-key.pem" -exec cp {} "$SCRIPT_DIR/certs/nginx.key" \;
        ok "Certificats copiats a certs/"
    fi
    cd "$SCRIPT_DIR"
    echo ""
    ok "Certificats mkcert generats. Vàlids per a: $DOMAIN, web01/02/03.$DOMAIN, localhost"
}

# ─── acme.sh DNS challenge ────────────────────────────────────────────────────
cmd_acme() {
    section "Obtenint certificat real amb acme.sh (DNSExit)"

    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        error "Crea .env amb DNSEXIT_APIKEY= (copia .env.example)"
    fi

    # Carregar .env
    set -a; source "$SCRIPT_DIR/.env"; set +a

    if [ -z "$DNSEXIT_APIKEY" ] || [ "$DNSEXIT_APIKEY" = "LA_TEVA_API_KEY_AQUI" ]; then
        error "DNSEXIT_APIKEY no configurat al .env"
    fi

    info "Instal·lant acme.sh si no existeix..."
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        curl https://get.acme.sh | sh -s email=admin@"$DOMAIN"
    fi

    info "Obtenint certificat wildcard per *.$DOMAIN ..."
    export DNSEXIT_API_KEY="$DNSEXIT_APIKEY"

    "$HOME/.acme.sh/acme.sh" \
        --issue \
        --dns dns_dnsexit \
        -d "$DOMAIN" \
        -d "*.$DOMAIN" \
        --server letsencrypt \
        --force

    mkdir -p "$SCRIPT_DIR/certs/acme"

    info "Instal·lant certificat a certs/acme/ ..."
    "$HOME/.acme.sh/acme.sh" \
        --install-cert \
        -d "$DOMAIN" \
        --cert-file    "$SCRIPT_DIR/certs/acme/nginx.crt" \
        --key-file     "$SCRIPT_DIR/certs/acme/nginx.key" \
        --ca-file      "$SCRIPT_DIR/certs/acme/ca.crt" \
        --fullchain-file "$SCRIPT_DIR/certs/acme/fullchain.crt"

    ok "Certificat Let's Encrypt instal·lat a certs/acme/"
    ok "Reinicia el contenidor nginx per carregar el nou certificat:"
    echo "    docker restart clab-http-lab-e5-nginx-proxy"
}

# ─── Deploy ───────────────────────────────────────────────────────────────────
get_stage_dir() {
    case "$1" in
        1|http)    echo "etapa1-http" ;;
        2|mkcert)  echo "etapa2-https-mkcert" ;;
        3|proxy)   echo "etapa3-proxy" ;;
        4|auth)    echo "etapa4-auth" ;;
        5|acme)    echo "etapa5-acme" ;;
        6|logs)    echo "etapa6-logs" ;;
        *)         echo "" ;;
    esac
}

cmd_deploy() {
    local stage="$1"
    if [ -z "$stage" ]; then
        error "Especifica una etapa: $0 deploy N (1–6)"
    fi

    local stage_dir
    stage_dir=$(get_stage_dir "$stage")
    if [ -z "$stage_dir" ]; then
        error "Etapa desconeguda: $stage"
    fi

    local topo="$SCRIPT_DIR/$stage_dir/topology.clab.yml"
    if [ ! -f "$topo" ]; then
        error "No s'ha trobat: $topo"
    fi

    # Destruir etapa anterior si n'hi ha
    if [ -f "$STATE_FILE" ]; then
        local prev
        prev=$(cat "$STATE_FILE")
        if [ "$prev" != "$stage_dir" ]; then
            warn "Destruint etapa anterior ($prev)..."
            cmd_destroy_internal "$prev"
        fi
    fi

    section "Desplegant $stage_dir"

    # Prerequisits per etapa
    case "$stage" in
        2|mkcert|3|proxy|4|auth)
            if [ ! -f "$SCRIPT_DIR/certs/nginx.crt" ]; then
                warn "Certificats mkcert no trobats. Executant: $0 certs"
                cmd_certs
            fi
            ;;
        5|acme)
            if [ ! -f "$SCRIPT_DIR/certs/acme/fullchain.crt" ]; then
                warn "Certificats acme.sh no trobats. Executa: $0 acme"
                warn "Per ara usaré els certificats mkcert si existeixen."
            fi
            ;;
        4|auth)
            if [ ! -f "$SCRIPT_DIR/etapa4-auth/configs/auth/.htpasswd" ]; then
                warn ".htpasswd no trobat — executant setup 4..."
                cmd_setup "4"
            fi
            ;;
    esac

    info "Desplegant topologia amb containerlab..."
    cd "$stage_dir" 2>/dev/null || cd "$SCRIPT_DIR/$stage_dir"
    sudo containerlab deploy --topo topology.clab.yml
    cd "$SCRIPT_DIR"

    echo "$stage_dir" > "$STATE_FILE"
    echo ""
    ok "Etapa $stage_dir desplegada."
    _show_stage_info "$stage"
}

_show_stage_info() {
    case "$1" in
        1|http)
            echo ""
            echo "  HTTP bàsic:"
            echo "  - Web: http://localhost"
            echo "  - Client test: docker exec -it clab-http-lab-e1-client curl http://10.20.0.10"
            ;;
        2|mkcert)
            echo ""
            echo "  HTTPS mkcert:"
            echo "  - Web: https://localhost  (cert mkcert, confiar al navegador)"
            echo "  - HTTP redirect: http://localhost → https://localhost"
            ;;
        3|proxy)
            echo ""
            echo "  Reverse proxy (afegir al /etc/hosts del host):"
            echo "  127.0.0.1  $DOMAIN web01.$DOMAIN web02.$DOMAIN web03.$DOMAIN"
            echo ""
            echo "  - https://$DOMAIN"
            echo "  - https://web01.$DOMAIN"
            echo "  - https://web02.$DOMAIN"
            echo "  - https://web03.$DOMAIN"
            ;;
        4|auth)
            echo ""
            echo "  Autenticació bàsica:"
            echo "  - https://web02.$DOMAIN  (requereix usuari/contrasenya)"
            echo "  - Credencials al .env (AUTH_USER / AUTH_PASS)"
            ;;
        5|acme)
            echo ""
            echo "  HTTPS amb Let's Encrypt (acme.sh):"
            echo "  - Certificat real per $DOMAIN i subdominis"
            echo "  - https://$DOMAIN"
            ;;
        6|logs)
            echo ""
            echo "  Gestió de logs:"
            echo "  - Logs: docker exec clab-http-lab-e6-nginx-proxy tail -f /var/log/nginx/access.log"
            echo "  - Logrotate: docker exec clab-http-lab-e6-nginx-proxy logrotate -f /etc/logrotate.d/nginx"
            ;;
    esac
    echo ""
}

# ─── Setup post-deploy ────────────────────────────────────────────────────────
cmd_setup() {
    local stage="$1"
    if [ -z "$stage" ]; then
        error "Especifica una etapa: $0 setup N"
    fi

    case "$stage" in
        4|auth)
            section "Setup etapa 4: creant .htpasswd"
            if [ ! -f "$SCRIPT_DIR/.env" ]; then
                error "Crea .env amb AUTH_USER i AUTH_PASS"
            fi
            set -a; source "$SCRIPT_DIR/.env"; set +a

            local user="${AUTH_USER:-admin}"
            local pass="${AUTH_PASS:-}"
            if [ -z "$pass" ]; then
                error "AUTH_PASS no definit al .env"
            fi

            mkdir -p "$SCRIPT_DIR/etapa4-auth/configs/auth"
            htpasswd -bc "$SCRIPT_DIR/etapa4-auth/configs/auth/.htpasswd" "$user" "$pass"
            ok ".htpasswd creat per a l'usuari: $user"
            ;;
        *)
            info "Etapa $stage no requereix setup addicional."
            ;;
    esac
}

# ─── Status ───────────────────────────────────────────────────────────────────
cmd_status() {
    section "Estat del lab"

    if [ -f "$STATE_FILE" ]; then
        ok "Etapa activa: $(cat $STATE_FILE)"
    else
        info "Cap etapa desplegada."
    fi

    echo ""
    info "Contenidors containerlab actius:"
    sudo containerlab inspect --all 2>/dev/null || docker ps --filter "name=clab-http" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
}

# ─── Shell ────────────────────────────────────────────────────────────────────
cmd_shell() {
    local node="${1:-}"
    local stage=""
    [ -f "$STATE_FILE" ] && stage=$(cat "$STATE_FILE" | sed 's/etapa/e/' | tr -d '-' | cut -c1-3)

    if [ -z "$node" ]; then
        # Intentar nginx-proxy primer, llavors nginx
        if docker ps --filter "name=clab-http-lab" --format "{{.Names}}" | grep -q "nginx-proxy"; then
            node="nginx-proxy"
        else
            node="nginx"
        fi
    fi

    local container
    container=$(docker ps --filter "name=clab-http-lab" --filter "name=$node" --format "{{.Names}}" | head -1)

    if [ -z "$container" ]; then
        # Cerca per nom parcial
        container=$(docker ps --filter "name=$node" --format "{{.Names}}" | grep "clab-http" | head -1)
    fi

    if [ -z "$container" ]; then
        error "No s'ha trobat el contenidor '$node'. Usa: $0 status"
    fi

    info "Obrint shell a $container..."
    docker exec -it "$container" sh
}

# ─── Destroy ──────────────────────────────────────────────────────────────────
cmd_destroy_internal() {
    local stage_dir="$1"
    local topo="$SCRIPT_DIR/$stage_dir/topology.clab.yml"
    if [ -f "$topo" ]; then
        (cd "$SCRIPT_DIR/$stage_dir" && sudo containerlab destroy --topo topology.clab.yml --cleanup 2>/dev/null) || true
    fi
}

cmd_destroy() {
    section "Destruint lab"

    if [ -f "$STATE_FILE" ]; then
        local stage_dir
        stage_dir=$(cat "$STATE_FILE")
        info "Destruint $stage_dir..."
        cmd_destroy_internal "$stage_dir"
        rm -f "$STATE_FILE"
        ok "Lab destruït."
    else
        info "Intentant destruir qualsevol lab actiu..."
        for d in etapa1-http etapa2-https-mkcert etapa3-proxy etapa4-auth etapa5-acme etapa6-logs; do
            cmd_destroy_internal "$d" 2>/dev/null || true
        done
        ok "Fet."
    fi
}

# ─── Dispatcher ───────────────────────────────────────────────────────────────
case "${1:-help}" in
    check)   cmd_check ;;
    build)   cmd_build ;;
    certs)   cmd_certs "$2" ;;
    deploy)  cmd_deploy "$2" ;;
    setup)   cmd_setup "$2" ;;
    acme)    cmd_acme ;;
    status)  cmd_status ;;
    shell)   cmd_shell "$2" ;;
    destroy) cmd_destroy ;;
    help|--help|-h) usage ;;
    *) echo "Comanda desconeguda: $1"; usage ;;
esac
