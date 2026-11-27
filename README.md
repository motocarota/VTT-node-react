# VTT — Virtual Tabletop per D&D e altri TTRPG

Tavolo virtuale per il DM: campo di battaglia a livelli, party e tracker di iniziativa.
Uso locale (un solo utente), con backend Node già pronto per il multiplayer.

## Avvio

```bash
pnpm install
pnpm dev          # client http://localhost:5173 + API http://127.0.0.1:3001
```

Produzione (Fastify serve anche il client compilato):

```bash
pnpm build && pnpm start   # http://127.0.0.1:3001
```

I dati (SQLite + immagini caricate) vanno in `data/`; si può cambiare cartella con `VTT_DATA_DIR`.
Altre variabili: `PORT` (3001), `HOST` (127.0.0.1).

## Comandi

| Comando | Cosa fa |
|---|---|
| `pnpm test` | Vitest su tutti i pacchetti |
| `pnpm typecheck` | `tsc` su tutti i pacchetti |

## Deploy locale (separato dallo sviluppo)

Un'istanza "stabile" sulla porta **8080**, indipendente da `pnpm dev` (3001/5173): codice e dati propri. È raggiungibile da questo Mac (http://127.0.0.1:8080) e dai dispositivi della rete locale: `start` e `status` stampano gli indirizzi da dare ai giocatori.

```bash
pnpm release        # pubblica l'ULTIMO COMMIT: test + build, sostituisce la release e riavvia
pnpm prod status    # stato, release installata, percorsi
pnpm prod start | stop | restart
pnpm prod logs      # segue il log
```

- Si pubblica solo ciò che è committato: le modifiche in corso in sviluppo non finiscono nel deploy.
- Tutto sta in `~/Library/Application Support/VTT/`: `app/` (release attuale), `app.prev/` (precedente, ripristinata in automatico se l'avvio fallisce), `data/` (database e immagini, mai toccati dalle release), `vtt.log`.
- Variabili opzionali: `VTT_PORT`, `VTT_HOST` (default `0.0.0.0`, tutta la rete locale; `127.0.0.1` per tenerla solo su questo Mac), `VTT_HOME`.
- Al primo avvio macOS può chiedere se consentire a `node` le connessioni in entrata: va accettato, altrimenti il firewall blocca i dispositivi in rete.
- L'istanza non riparte da sola dopo un riavvio del Mac: `pnpm prod start`.

## Deploy su NAS Synology (Docker)

L'immagine (`Dockerfile`) contiene solo Node 24, il server in un unico bundle e il client compilato: la versione di Node installata sul NAS non conta. Serve **Container Manager** (Centro pacchetti, DSM 7.2+).

1. Sul Mac, crea l'archivio dell'ultimo commit (come `pnpm release`, si pubblica solo ciò che è committato):
   ```bash
   git archive --format=tar.gz -o vtt-nas.tar.gz HEAD
   ```
2. In File Station crea la cartella `docker/vtt`, carica l'archivio ed estrailo lì dentro (tasto destro → Estrai → Estrai qui).
3. Container Manager → **Progetto** → **Crea**: nome `vtt`, percorso `docker/vtt`, sorgente "Usa docker-compose.yml esistente" → Avanti → Fine. Il primo build richiede qualche minuto.
4. Apri `http://<IP-del-NAS>:8080`. I link per i giocatori usano lo stesso indirizzo.

- I dati (SQLite + immagini) sono in `docker/vtt/data`, inclusi nei backup del NAS (Hyper Backup).
- Il container riparte da solo dopo un riavvio del NAS (`restart: unless-stopped`).
- **Aggiornare**: rifai i passi 1–2 sovrascrivendo i file (la cartella `data/` non viene toccata), poi Progetto `vtt` → Azione → **Build** (ricostruisce l'immagine e riavvia il container).
- Porta occupata? Cambia la parte sinistra di `"8080:8080"` in `docker-compose.yml`.
- Se il firewall del NAS è attivo, consenti la porta 8080 dalla rete locale (Pannello di controllo → Sicurezza → Firewall).
- L'app non ha login: **non esporla su Internet** (niente port forwarding sul router). Da fuori casa usa la VPN del NAS o Tailscale.
- Cronologia dal Mac: `pnpm history --url http://<IP-del-NAS>:8080 list` (stessi comandi di sotto).

## Più tab, sincronizzazione e cronologia

- Ogni documento (PG, scena, combattimento, tiro) ha una **versione**. Un salvataggio dichiara la versione su cui si basa (`If-Match`): se nel frattempo un altro tab ha salvato, il server risponde `409` e **non sovrascrive**. Il tab scarica la versione nuova e riapplica sopra solo le proprie modifiche.
- Tutti i tab ricevono le modifiche **in tempo reale** (`/api/events`, Server-Sent Events). Se la connessione cade compare "● Non connesso"; al ritorno i dati vengono riallineati.
- Un tab aperto con una versione vecchia dell'app non può più scrivere (`428`): basta ricaricarlo.
- Il server conserva le **versioni precedenti** (ultime 200 per documento; le modifiche ravvicinate entro 5 s contano come una). Si recuperano anche documenti eliminati:

```bash
pnpm history list                            # documenti e numero di versioni
pnpm history show combat current             # versioni del combattimento
pnpm history restore combat current 12       # ripristina la versione 12 (arriva subito ai tab aperti)
pnpm history --prod list                     # stessa cosa sull'istanza di deploy (8080)
```

## Esporta / importa

- **⬇ Esporta** (in alto a destra) scarica tutto lo stato in un file `vtt-AAAA-MM-GG-HHMM.json`: PG, scene, combattimento, tiri del DM e le immagini usate (in base64), quindi il file funziona anche su un'altra installazione.
- **⬆ Importa** sostituisce tutto lo stato con quello del file, previa conferma: i documenti assenti dal file vengono eliminati. Il file viene validato per intero prima di scrivere qualsiasi cosa; lo stato sostituito resta recuperabile con `pnpm history`.

## Struttura

- `packages/shared` — schemi zod (PG, PNG, combattimento, scene), dadi, griglia, PF e logica pura dell'iniziativa
- `apps/server` — Fastify + `node:sqlite`: REST su `/api/characters`, `/api/scenes`, `/api/combat`, upload su `/api/uploads`
- `apps/client` — React + Vite + Zustand; mappa con react-konva

## Uso rapido

- **Party**: “Nuovo PG”, poi si modificano i campi direttamente nella scheda (salvataggio automatico).
- **Iniziativa**: “Aggiungi party” / “Aggiungi PNG”, d20 inserito a mano o 🎲 / “Tira tutti”, poi “Inizia combattimento”.
  “Turno successivo” spunta chi è di turno; quando hanno agito tutti si passa al round seguente.
  La spunta si può mettere anche a mano, fuori ordine. ↑/↓ servono solo per i pareggi esatti.
- **Campo di battaglia**: si sceglie il livello attivo (solo quello è modificabile); 👁 nasconde, 🔒 blocca.
  Rotella = zoom, Spazio o tasto centrale + trascina = sposta la vista, Canc = elimina la selezione, Esc = annulla.
