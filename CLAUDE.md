# CLAUDE.md

Laboratori modular de HTTP/S amb Nginx i Containerlab. Sis etapes progressives:
HTTP bàsic → HTTPS mkcert → Reverse proxy → Autenticació bàsica → HTTPS acme.sh → Gestió de logs.

## Comandes principals

```bash
./lab.sh check           # Verifica prerequisits (Docker, containerlab, mkcert, htpasswd)
./lab.sh certs           # Genera certificats mkcert (necessari etapes 2–4)
./lab.sh deploy N        # Desplega etapa N (1–6)
./lab.sh setup 4         # Crea .htpasswd per a l'etapa 4 (llegeix .env)
./lab.sh acme            # Obté certificat real Let's Encrypt via DNS challenge DNSExit
./lab.sh status          # Estat del lab actiu
./lab.sh shell [node]    # Shell al contenidor (nginx-proxy, web01, web02, web03, client)
./lab.sh destroy         # Destrueix el lab actiu
```

## Arquitectura

- **etapa1-http/**: Nginx estàtic HTTP port 80
- **etapa2-https-mkcert/**: HTTPS amb certificats mkcert + redirect HTTP→HTTPS
- **etapa3-proxy/**: Nginx proxy invers, virtual hosts web01/02/03.demohttp.publicvm.com
- **etapa4-auth/**: Igual que etapa3 + Basic Auth (htpasswd) a web02
- **etapa5-acme/**: Igual que etapa3 + certificat Let's Encrypt real (acme.sh + DNS challenge)
- **etapa6-logs/**: Igual que etapa3 + formats log combinat/JSON/debug, logrotate, logs per vhost

## Xarxa interna (totes les etapes)

| Node         | IP interna    | Funció                      |
|--------------|---------------|-----------------------------|
| nginx / nginx-proxy | 10.20.0.10 | Frontend / reverse proxy |
| web01        | 10.20.0.11    | Backend #1 (blau)           |
| web02        | 10.20.0.12    | Backend #2 (lila)           |
| web03        | 10.20.0.13    | Backend #3 (taronja)        |
| client       | 10.20.0.20    | Node de proves (netshoot)   |

## Domini i certificats

- **Domini**: `demohttp.publicvm.com` + `web01/02/03.demohttp.publicvm.com`
- **mkcert** (etapes 2–4): `certs/nginx.crt` + `certs/nginx.key`
- **acme.sh** (etapa 5): `certs/acme/fullchain.crt` + `certs/acme/nginx.key`
- **DNSExit API key**: al `.env` com `DNSEXIT_APIKEY` (mai al codi)

## Secrets i fitxers privats

- `.env` — API key DNSExit, credencials auth — al `.gitignore`
- `certs/*.pem`, `certs/*.key`, `certs/*.crt` — al `.gitignore`
- `certs/acme/` — al `.gitignore`
- `etapa4-auth/configs/auth/.htpasswd` — al `.gitignore`

## Switch containeritzat

El node `switch` de cada topologia usa la imatge `nginx-lab-switch:latest` (Alpine + iproute2).
El script `/usr/local/bin/switch-init.sh` detecta automàticament totes les interfaces eth1+ i les connecta al bridge `br0` intern del contenidor.
Per construir/reconstruir la imatge: `./lab.sh build`

## Notes importants

- L'etapa5 requereix accés real a internet i que `demohttp.publicvm.com` estigui apuntant a la IP pública del host
- Per a proves locals d'etapes 3–6 sense DNS real, afegir al `/etc/hosts` del host:
  `127.0.0.1 demohttp.publicvm.com web01.demohttp.publicvm.com web02.demohttp.publicvm.com web03.demohttp.publicvm.com`
- Containerlab crea el bridge `br-web` automàticament des de la topologia (kind: bridge)
- Els contenidors backends (web01/02/03) usen nginx:alpine per defecte sense configuració addicional
- Per a l'etapa 6, el directori `etapa6-logs/logs/` es munta com a volum persistent

## Qüestionari d'avaluació

```bash
cd assessment/v01
pip3 install weasyprint jinja2 pyyaml
python3 genera-examen.py   # Genera model-a.pdf, model-b.pdf, model-c.pdf, model-d.pdf + solucions-all.pdf
```
