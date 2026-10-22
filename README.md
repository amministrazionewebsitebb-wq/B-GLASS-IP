# B-Glass per iPhone

Lettore IPTV nativo per iPhone (e iPad), scritto in SwiftUI. È il porting di **B-Glass 1.6.0** (l'app Android che avevi costruito): stessa idea e stessa logica,
ripensate per il tocco. Legge **liste M3U/M3U8** e **account Xtream Codes**; ogni persona ha un **profilo** e vede solo i canali, i film e le serie che ha scelto.

> **Nota onesta.** Un APK non si può "convertire" in un IPA: contiene codice Android (Java/Kotlin) e usa API che su iOS non esistono. Questa è una **riscrittura per iOS**
> che parte dai sorgenti di B-Glass: la logica (parser, Xtream, pacchetti di canali, riconoscimento delle qualità, righe per genere, guida TV, profili) è stata
> portata riga per riga e verificata con gli stessi test dell'originale; l'interfaccia e il player sono nuovi e nativi.

## Cosa c'è dentro

Pensata per il telefono: quattro schede, poche funzioni ma fatte bene, grafica scura in stile piattaforma di streaming.

| | |
|---|---|
| **Home** | vetrina che scorre da sola (film e serie con *Guarda* e *La mia lista*), *In onda ora* (preferiti e canali principali), *Continua a guardare*, *La mia lista*, film e serie del momento |
| **TV** | *Principali* (Rai, Mediaset, Sky, La7… riconosciuti da soli nella lista), *Preferiti*, *Tutti*, *Categorie*; ogni canale con programma in onda, avanzamento e prossimo; ricerca; **Guida TV** a griglia |
| **On Demand** | *Film* e *Serie TV* con vetrina, righe per genere e *Vedi tutto* a griglia; pagina del titolo con *Guarda / Riprendi*, *La mia lista*, trama, stagioni ed episodi |
| **Cerca** | un'unica casella per canali, film e serie di tutta la lista, con le ricerche recenti |
| **Player** | **in verticale**: video in alto, sotto il programma in onda e l'elenco dei canali (un tocco cambia canale); **in orizzontale**: schermo intero con una striscia di canali e i tasti canale precedente/successivo. Film ed episodi partono a schermo intero. Picture in Picture, AirPlay, audio in background, comandi in blocco schermo, audio e sottotitoli, qualità del canale, riconnessione automatica, prossimo episodio |
| **VLC** | secondo lettore per ciò che Apple non riproduce (**MKV, AVI, MPEG-TS grezzo**): con *Lettore: Automatico* entra in gioco da solo |
| **Impostazioni** | liste e abbonamento, profili (con PIN e profilo bambini), guida TV, lingua audio e sottotitoli, lettore, stabilità, contenuti per adulti con PIN, test della connessione |

### Compatibilità con i fornitori

Ogni fornitore fa le cose a modo suo; B·Glass si adatta da solo, senza chiedere nulla:

- **Riconoscimento dell'app (User-Agent)**: se il pannello o il sito della lista rifiuta l'app, prova da sola i nomi dei lettori più diffusi (VLC, IPTV Smarters, okhttp, Safari, ffmpeg) e ricorda quello accettato.
- **Indirizzo del pannello**: se il server non risponde come scritto, prova l'altro protocollo (http/https) e le porte usate dai pannelli Xtream (8080, 80, 25461, 8000, 8880, 2082, 2095, 8443, 443). Accetta i certificati HTTPS scaduti o fatti in casa quando sono l'unico problema.
- **Risposte "sporche"**: avvisi PHP prima dei dati, nomi scritti in Latin-1 invece di UTF-8, cataloghi vuoti indicati con `null`, categorie mancanti; un elenco vuoto mandato per errore non cancella i canali che c'erano.
- **Liste M3U scritte in modi diversi**: intestazioni in stile Kodi (`indirizzo|User-Agent=…&Referer=…`), `#EXTVLCOPT` prima o dopo `#EXTINF`, attributi tra apici, righe di testo estranee, più guide nell'intestazione, un link che è un solo canale HLS.
- **Canali**: ogni canale viene provato in tutte le sue forme (HLS, MPEG-TS, indirizzo senza formato) con entrambi i lettori (Apple e VLC); la forma che funziona viene ricordata per gli altri canali della stessa lista. Un canale che resta bloccato sul caricamento viene riavviato da solo.
- **Indirizzi dei video**: oltre a quello costruito come fanno tutte le app Xtream, prova quello che il pannello dichiara (`server_info`) e l'indirizzo originale (`direct_source`) quando c'è.
- **Linee da una connessione**: i tentativi sono distanziati, così il fornitore non li conta come un secondo dispositivo.
- **Errori chiari**: la lista viene controllata prima di essere aggiunta; se non va, l'app dice perché (password, abbonamento scaduto, pagina web al posto della lista, server irraggiungibile…). In *Impostazioni › Registro tecnico* c'è il registro di cosa è stato chiesto ai server e cosa hanno risposto (utenti e password nascosti), da copiare e inviare.

Non sono supportati i portali **Stalker / MAG** (accesso con indirizzo MAC): servono liste M3U o account Xtream Codes.

Non c'è più nulla da configurare dopo aver aggiunto la lista: tutto il catalogo è subito visibile (i contenuti per adulti restano nascosti).

## Come ottenere il file `.ipa`

L'IPA non si può compilare su un Mac senza Xcode, e firmarlo richiede un Apple ID. Il percorso più semplice è **GitHub Actions**, che compila su un Mac in cloud.

1. Crea un repository **privato** su GitHub e caricaci il contenuto di questa cartella (`BGlass/`).
2. Vai su **Actions → Build IPA → Run workflow** (lascia `with_vlc` attivo).
3. Quando ha finito (qualche minuto) scarica l'artefatto **BGlass-ipa**: dentro c'è `BGlass.ipa`, **non firmato**.
   Le versioni con un tag (`v1.1.0`…) finiscono anche nelle **Releases** del repository, con il link diretto all'IPA.
   Se la build con VLC non riesce, il workflow rifà la build solo con AVPlayer e lo scrive nel riepilogo.
4. Installalo sull'iPhone con **[Sideloadly](https://sideloadly.io)** o **[AltStore](https://altstore.io)** usando il tuo Apple ID: firmano l'app per te.
   Con un Apple ID gratuito l'app dura **7 giorni** e poi va reinstallata/rinnovata (AltStore lo fa da solo); con l'Apple Developer Program (99 €/anno) dura un anno
   e puoi usare TestFlight.

### Alternativa: da un Mac con Xcode

```bash
brew install xcodegen cocoapods     # una volta sola
scripts/build_ipa.sh                # con VLC
scripts/build_ipa.sh --no-vlc       # solo AVPlayer
```

Oppure `xcodegen generate` e apri `BGlass.xcodeproj` in Xcode: scegli il tuo team in *Signing & Capabilities* e premi Run.

## Cosa è stato verificato (e cosa no)

**Verificato su questo Mac**
- Il *core* (`BGlassCore`: parser M3U e Xtream, JSON a flusso, gzip, XMLTV, guida, libreria su disco, profili, pacchetti, qualità, generi, righe, ricerca, speed test) con
  **1.384 controlli** (`scripts/check.sh`): i test JUnit dell'app Android su parser, libreria, generi, pacchetti di canali e qualità portati in Swift (compreso il riconoscimento dei canali in 8 stili di nomi internazionali: 286/286)
  più un **server HTTP finto** che si comporta da pannello Xtream (account, cataloghi, EPG gzip, M3U e M3U.gz, errori di credenziali, 404, riavvio dell'app)
  e una prova di **scala** con 106.000 titoli (2.000 canali, 98.000 film, 6.000 serie), anche in build non ottimizzata: canali pronti in ~20 ms, caricamento completo ~1,2 s,
  prime righe dei film ~0,7 s, ricerca ~0,3 s.
- L'intero codice dell'interfaccia e del player passa il **type-check contro le API di iOS** (target Mac Catalyst dell'SDK) e contro macOS (`scripts/typecheck.sh`).
- Le schermate sono state **disegnate e controllate a occhio** con dati finti (`scripts/preview.sh`): home, TV, guida, On Demand, dettagli, cerca, impostazioni, PIN, player in verticale e in orizzontale.

**NON verificato**
- Qui non c'è Xcode: la compilazione vera avviene su GitHub Actions; l'app non è mai stata eseguita sul simulatore.
- Non provato con un fornitore reale: il comportamento di Picture in Picture, AirPlay, audio in background e VLC è scritto secondo la documentazione ma va provato sul dispositivo.
- `project.yml` (XcodeGen) è stato solo validato come YAML.

## Limiti rispetto alla versione Android

- **AVPlayer non legge MKV, AVI e MPEG-TS grezzo** (molti film Xtream sono `.mkv`, molti canali `.ts`): servono VLC (consigliato, incluso di default) oppure un pannello con uscita HLS/MP4.
- Con certificati HTTPS non validi il caricamento delle liste funziona (opzione *Ignora errori del certificato*), ma AVPlayer non può ignorarli: i flussi su quei server potrebbero non partire.
- **DNS personalizzato (DoH/UDP)** non portato: su iOS le app non possono cambiare il DNS di sistema per il player. Usa un profilo DNS di sistema o una VPN.
- Telecomando, tasti colorati e *Registro tasti*: non servono sul telefono.
- I livelli interni di un flusso HLS non sono selezionabili a mano (AVPlayer non li espone); le **qualità del canale** (voci diverse della lista) sì.
- Nessuna registrazione, catch-up o timeshift (come su Android).

## Grafica e licenze

Colori e identità "glass" vengono da B-Glass; **non** sono stati usati i font né le immagini degli skin Enigma2 *Sky.NEW* / *Slyk Q* (senza licenza dichiarata) né marchi Sky:
l'app usa il carattere di sistema e un'icona nuova. Lo "stile Sky" è solo nell'impostazione (sfondo scuro, vetrina, righe, player con elenco canali), non nei marchi. B-Glass è **solo un lettore**: non fornisce né include contenuti.

## Struttura

```
Package.swift            pacchetto Swift: BGlassCore, BGlassUI (e BGlassChecks)
Sources/BGlassCore/      logica senza interfaccia (Foundation): liste, Xtream, guida, libreria, profili, pacchetti, qualità, ricerca, speed test
Sources/BGlassUI/        schermate SwiftUI, player (AVPlayer), caricamento immagini, modello dell'app
Sources/BGlassChecks/    i controlli automatici (eseguibile, non serve XCTest)
Sources/BGlassPreview/   strumento che disegna le schermate in PNG (solo macOS)
App/                     guscio iOS: @main, icona, motore VLC (compilato solo se la libreria c'è)
project.yml, Podfile     progetto Xcode (XcodeGen) e VLC (CocoaPods)
scripts/                 check.sh, typecheck.sh, preview.sh, build_ipa.sh, make_icon.swift
.github/workflows/       build-ipa.yml
```

### Strumenti di sviluppo (bastano le Command Line Tools)

```bash
scripts/check.sh                       # compila il core ed esegue i 1.384 controlli
scripts/typecheck.sh                   # type-check di core + UI contro iOS (Catalyst) e macOS
scripts/preview.sh /tmp/shots home live guide detail_movie   # PNG delle schermate con dati finti
```
