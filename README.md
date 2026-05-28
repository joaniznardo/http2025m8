# Lab HTTP/S amb Nginx i Containerlab

**Institut TIC de Barcelona — Serveis de xarxa 2025–2026**

Laboratori pràctic per aprendre a desplegar i configurar el servidor web Nginx en sis etapes progressives, treballant HTTP, HTTPS, proxy invers, autenticació i gestió de logs amb eines reals de la indústria.

---

## Prerequisits

### Instal·lació de les eines necessàries

```bash
# Docker (si no el tens)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Containerlab
bash -c "$(curl -sL https://get.containerlab.dev)"

# mkcert (certificats de desenvolupament)
sudo apt install mkcert
# o: brew install mkcert (macOS)

# htpasswd (per a l'autenticació bàsica)
sudo apt install apache2-utils

# Python + dependències per als exàmens PDF
pip3 install weasyprint jinja2 pyyaml
```

### Configuració inicial

```bash
# 1. Clonar/accedir al directori del lab
cd test019-http

# 2. Crear fitxer de secrets
cp .env.example .env
# Editar .env amb les dades reals:
#   DNSEXIT_APIKEY=...  (API key de DNSExit)
#   AUTH_USER=admin
#   AUTH_PASS=la-teva-contrasenya

# 3. Verificar prerequisits
./lab.sh check
```

---

## Etapa 1 — HTTP bàsic

**Objectiu:** Entendre el funcionament bàsic de Nginx servint contingut estàtic per HTTP.

**Topologia:**
```
Host:80 ──► [nginx:10.20.0.10] ──br-web──► [client:10.20.0.20]
```

**Desplegament:**
```bash
./lab.sh deploy 1
```

**Verificació:**
```bash
# Des del navegador del host
curl http://localhost

# Des del contenidor client (xarxa interna)
docker exec -it clab-http-lab-e1-client curl http://10.20.0.10

# Estat nginx
curl http://localhost/status

# Logs en temps real
docker exec clab-http-lab-e1-nginx tail -f /var/log/nginx/access.log
```

**Conceptes treballats:**
- Estructura de la configuració de Nginx (`worker_processes`, `events`, `http`, `server`, `location`)
- Directiva `root` i `index`
- `stub_status` per monitoritzar Nginx
- Format de log `combined`

---

## Etapa 2 — HTTPS amb mkcert

**Objectiu:** Activar HTTPS amb certificats de desenvolupament i configurar el redirect HTTP→HTTPS.

**Prerequisit:**
```bash
./lab.sh certs
```

Això genera `certs/nginx.crt` i `certs/nginx.key` usant la CA local de mkcert. Per confiar en el certificat al navegador, mkcert hauria d'haver instal·lat la CA (`mkcert -install`).

**Desplegament:**
```bash
./lab.sh deploy 2
```

**Verificació:**
```bash
# HTTPS
curl -k https://localhost
# o si tens la CA de mkcert al sistema de confiança:
curl https://localhost

# Verificar redirect HTTP→HTTPS
curl -v http://localhost 2>&1 | grep "Location:"

# Informació del certificat
echo | openssl s_client -connect localhost:443 -servername localhost 2>/dev/null | openssl x509 -text -noout | grep -A2 "Subject:"

# Capçaleres de seguretat
curl -I https://localhost
```

**Conceptes treballats:**
- Directives `ssl_certificate` i `ssl_certificate_key`
- `ssl_protocols` (TLS 1.2/1.3) i `ssl_ciphers`
- Redirect permanent HTTP→HTTPS (`return 301`)
- HSTS (`Strict-Transport-Security`)
- Capçaleres de seguretat: `X-Content-Type-Options`, `X-Frame-Options`

---

## Etapa 3 — Reverse Proxy

**Objectiu:** Configurar Nginx com a proxy invers que distribueix peticions a tres backends per virtual hosts.

**Topologia:**
```
Internet
   │
Host:80/443
   │
[nginx-proxy:10.20.0.10]
   ├── web01.demohttp.publicvm.com ──► [web01:10.20.0.11]
   ├── web02.demohttp.publicvm.com ──► [web02:10.20.0.12]
   └── web03.demohttp.publicvm.com ──► [web03:10.20.0.13]
```

**Configuració /etc/hosts** (necessari per a proves locals sense DNS real):
```bash
echo "127.0.0.1 demohttp.publicvm.com web01.demohttp.publicvm.com web02.demohttp.publicvm.com web03.demohttp.publicvm.com" | sudo tee -a /etc/hosts
```

**Desplegament:**
```bash
./lab.sh deploy 3
```

**Verificació:**
```bash
# Cada virtual host
curl -k https://web01.demohttp.publicvm.com
curl -k https://web02.demohttp.publicvm.com
curl -k https://web03.demohttp.publicvm.com

# Des del client intern (sense passar pel host)
docker exec clab-http-lab-e3-client sh -c \
  "curl -H 'Host: web01.demohttp.publicvm.com' http://10.20.0.10"

# Capçaleres de proxy (X-Forwarded-For etc.)
curl -kv https://web01.demohttp.publicvm.com 2>&1 | grep "X-"

# Provar la ruta /web02/ des del domini principal
curl -k https://demohttp.publicvm.com/web02/
```

**Conceptes treballats:**
- Blocs `upstream` i `proxy_pass`
- `server_name` per virtual hosts
- Capçaleres `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`
- `proxy_http_version 1.1` i `Connection keep-alive`
- `default_server` a nginx

---

## Etapa 4 — Autenticació bàsica

**Objectiu:** Protegir un virtual host amb autenticació HTTP bàsica usant htpasswd.

**Prerequisit:**
```bash
# Configura AUTH_USER i AUTH_PASS al .env, llavors:
./lab.sh setup 4
```

Això crea `etapa4-auth/configs/auth/.htpasswd` amb les credencials xifrades.

**Desplegament:**
```bash
./lab.sh deploy 4
```

**Verificació:**
```bash
# web02 requereix autenticació
curl -k https://web02.demohttp.publicvm.com
# → 401 Unauthorized

# Amb credencials correctes
curl -k -u admin:la-teva-contrasenya https://web02.demohttp.publicvm.com

# web01 i web03 segueixen lliures
curl -k https://web01.demohttp.publicvm.com

# Verificar la capçalera WWW-Authenticate
curl -kI https://web02.demohttp.publicvm.com | grep "WWW-Authenticate"
```

**Conceptes treballats:**
- Directives `auth_basic` i `auth_basic_user_file`
- Format `.htpasswd` (bcrypt/MD5/SHA)
- Generació d'usuaris amb `htpasswd`
- Codi 401 Unauthorized i capçalera `WWW-Authenticate`

---

## Etapa 5 — HTTPS real amb acme.sh (Let's Encrypt)

**Objectiu:** Obtenir un certificat TLS real de Let's Encrypt usant el DNS challenge amb el proveïdor DNSExit.

**Prerequisit:**
- El domini `demohttp.publicvm.com` ha d'apuntar a la IP pública del host
- La API key de DNSExit ha d'estar al `.env`

```bash
# Obtenir certificat real (executa des del host, no dins del contenidor)
./lab.sh acme
```

Quan acme.sh fa el DNS challenge, DNSExit afegeix automàticament un registre TXT `_acme-challenge.demohttp.publicvm.com`. Un cop validat, Let's Encrypt emet el certificat.

**Desplegament:**
```bash
./lab.sh deploy 5
```

**Verificació:**
```bash
# Certificat real (sense -k!)
curl https://web01.demohttp.publicvm.com
curl https://web02.demohttp.publicvm.com
curl https://web03.demohttp.publicvm.com

# Informació del certificat
echo | openssl s_client -connect web01.demohttp.publicvm.com:443 2>/dev/null \
  | openssl x509 -text -noout | grep -E "Issuer|Subject|Not After"

# Verificar que és Let's Encrypt
curl -I https://demohttp.publicvm.com | head -10
```

**Conceptes treballats:**
- Protocol ACME (Automatic Certificate Management Environment)
- DNS challenge vs HTTP challenge
- Wildcards: `*.demohttp.publicvm.com`
- acme.sh i els proveïdors de DNS
- Renovació automàtica de certificats

---

## Etapa 6 — Gestió de logs

**Objectiu:** Configurar formats de log avançats, logs per virtual host i rotació de logs.

**Desplegament:**
```bash
./lab.sh deploy 6
```

**Verificació i pràctiques:**
```bash
# Generar tràfic de prova
for i in $(seq 1 20); do curl -sk https://web01.demohttp.publicvm.com > /dev/null; done
for i in $(seq 1 10); do curl -sk https://web02.demohttp.publicvm.com > /dev/null; done

# Veure logs en temps real per vhost
docker exec clab-http-lab-e6-nginx-proxy tail -f /var/log/nginx/web01/access.log
docker exec clab-http-lab-e6-nginx-proxy tail -f /var/log/nginx/web02/access.log

# Llegir logs JSON i parsejar amb jq (si disponible)
docker exec clab-http-lab-e6-nginx-proxy cat /var/log/nginx/web01/access.json | \
  docker exec -i clab-http-lab-e6-client jq '.status'

# Logs de redirecció HTTP
docker exec clab-http-lab-e6-nginx-proxy cat /var/log/nginx/redirect.log

# Forçar rotació de logs
docker exec clab-http-lab-e6-nginx-proxy logrotate -f /etc/logrotate.d/nginx

# Verificar que s'han creat els fitxers .gz
docker exec clab-http-lab-e6-nginx-proxy ls -la /var/log/nginx/web01/

# Estadístiques bàsiques del log
docker exec clab-http-lab-e6-nginx-proxy \
  awk '{print $9}' /var/log/nginx/web01/access.log | sort | uniq -c | sort -rn

# Temps de resposta del backend (camp urt= al log combinat)
docker exec clab-http-lab-e6-nginx-proxy \
  grep "urt=" /var/log/nginx/web01/access.log | awk -F'urt=' '{print $2}' | sort -n
```

**Conceptes treballats:**
- Directiva `log_format` amb variables nginx
- Format JSON per a tractament automàtic (ELK, Loki, etc.)
- `access_log off` per a rutes internes
- Logrotate: `daily`, `rotate`, `compress`, `postrotate`
- Senyal `USR1` a nginx per reobrir fitxers de log sense aturar el servei
- Variables d'upstream en els logs: `$upstream_connect_time`, `$upstream_response_time`

---

## Destruir el lab

```bash
./lab.sh destroy
```

---

## Qüestionari d'avaluació

```bash
cd assessment/v01
python3 genera-examen.py
# Genera: model-a.pdf, model-b.pdf, model-c.pdf, model-d.pdf
#         solucions-all.pdf
```

---

## Estructura del projecte

```
test019-http/
├── lab.sh                     # Script principal de gestió
├── .env.example               # Plantilla de secrets
├── .gitignore
├── CLAUDE.md
├── README.md                  # Aquest fitxer (pas a pas)
├── certs/                     # Certificats (al .gitignore)
│   ├── nginx.crt              # mkcert
│   ├── nginx.key
│   └── acme/                  # acme.sh / Let's Encrypt
├── etapa1-http/
│   ├── topology.clab.yml
│   └── configs/nginx/nginx.conf
├── etapa2-https-mkcert/
│   ├── topology.clab.yml
│   └── configs/nginx/nginx.conf
├── etapa3-proxy/
│   ├── topology.clab.yml
│   └── configs/nginx/{nginx.conf,sites/}
├── etapa4-auth/
│   ├── topology.clab.yml
│   └── configs/{nginx/,auth/}
├── etapa5-acme/
│   ├── topology.clab.yml
│   └── configs/nginx/nginx.conf
├── etapa6-logs/
│   ├── topology.clab.yml
│   ├── configs/nginx/{nginx.conf,logrotate.conf}
│   └── logs/                  # Volum persistent de logs
└── assessment/
    └── v01/
        ├── questions.yaml
        ├── genera-examen.py
        └── model-[a-d].pdf + solucions-all.pdf
```
