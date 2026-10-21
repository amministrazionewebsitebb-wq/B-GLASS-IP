# B-Glass per iPhone

Lettore IPTV nativo per iPhone (e iPad), scritto in SwiftUI. È il porting di **B-Glass 1.6.0** (l'app Android che avevi costruito): stessa idea e stessa logica,
ripensate per il tocco. Legge **liste M3U/M3U8** e **account Xtream Codes**; ogni persona ha un **profilo** e vede solo i canali, i film e le serie che ha scelto.

> **Nota onesta.** Un APK non si può "convertire" in un IPA: contiene codice Android (Java/Kotlin) e usa API che su iOS non esistono. Questa è una **riscrittura per iOS**
> che parte dai sorgenti di B-Glass: la logica (parser, Xtream, pacchetti di canali, riconoscimento delle qualità, righe per genere, guida TV, profili) è stata
> portata riga per riga e verificata con gli stessi test dell'originale; l'interfaccia e il player sono nuovi e nativi.

## Cosa c'è dentro

| | |
|---|---|
| **Home** | banner in evidenza, *Continua a guardare*, *Canali in onda ora* (con programma e avanzamento), *Film del momento*, *Serie TV del momento*, *Più votati*, avviso di scadenza dell'abbonamento |
| **TV** | elenco canali con ora/prossimo programma, filtri (Tutti, Preferiti, per pacchetto/categoria), ricerca, preferiti, **guida TV a griglia** (8 ore) con dettaglio del programma |
| **Film / Serie TV** | righe in stile Netflix (di tendenza, aggiunti di recente, più votati, *Perché hai guardato…*, una riga per genere anche con categorie dei fornitori diverse, poi le altre categorie); *Vedi tutto* a griglia con paginazione; pagina del titolo con trama, cast, stagioni ed episodi, *Riprendi / Dall'inizio* |
| **Cerca** | dalla terza lettera, tra i tuoi contenuti o in tutta la lista; film e serie senza doppioni, canali con "aggiungi al profilo" |
| **Profili** | "Chi guarda?", colori, PIN, profilo bambini (nasconde i contenuti per adulti), contenuti, preferiti, cronologia e punti di ripresa separati |
| **Scelta contenuti** | **pacchetti consigliati** (Intrattenimento, Sport, Cinema, Documentari, News, Bambini, Musica, Radio…) che trovano i canali per nome nella lista; oppure categoria per categoria con ricerca e selezione in blocco; riordino dei canali |
| **Player** | AVPlayer (HLS, MP4) con **Picture in Picture**, **AirPlay**, comandi in blocco schermo, audio in background; zapping con scorrimento su/giù, lista canali, **qualità del canale** (SD/HD/Full HD/4K, riconosciute dalla lista), audio e sottotitoli, adatta/riempi, velocità, timer di spegnimento, doppio tocco ±10 s, riconnessione automatica (e formato HLS/TS alternativo), prossimo episodio automatico, ripresa dal punto in cui eri |
| **VLC (opzionale)** | secondo motore per ciò che Apple non riproduce: **MKV, AVI, MPEG-TS grezzo**. Entra nella build se `with_vlc` è attivo |
| **Impostazioni** | liste (aggiorna, modifica, elimina, avanzamento), abbonamento (scadenza e connessioni), guida TV, motore/buffer/lingue/PiP, **speed test** con giudizio e formati sostenibili, rete e dispositivo, modalità esperto con PIN |
| **Avvio rapido** | a tappe come su Android: prima le liste, poi i canali, per ultimi film e serie (anche 100.000 titoli) |

## Come ottenere il file `.ipa`

L'IPA non si può compilare su un Mac senza Xcode, e firmarlo richiede un Apple ID. Il percorso più semplice è **GitHub Actions**, che compila su un Mac in cloud.

1. Crea un repository **privato** su GitHub e caricaci il contenuto di questa cartella (`BGlass/`).
2. Vai su **Actions → Build IPA → Run workflow** (lascia `with_vlc` attivo).
3. Quando ha finito (qualche minuto) scarica l'artefatto **BGlass-ipa**: dentro c'è `BGlass.ipa`, **non firmato**.
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
  **1.306 controlli** (`scripts/check.sh`): i test JUnit dell'app Android su parser, libreria, generi, pacchetti di canali e qualità portati in Swift (compreso il riconoscimento dei canali in 8 stili di nomi internazionali: 286/286)
  più un **server HTTP finto** che si comporta da pannello Xtream (account, cataloghi, EPG gzip, M3U e M3U.gz, errori di credenziali, 404, riavvio dell'app)
  e una prova di **scala** con 106.000 titoli (2.000 canali, 98.000 film, 6.000 serie), anche in build non ottimizzata: canali pronti in ~20 ms, caricamento completo ~1,2 s,
  prime righe dei film ~0,7 s, ricerca ~0,3 s.
- L'intero codice dell'interfaccia e del player passa il **type-check contro le API di iOS** (target Mac Catalyst dell'SDK) e contro macOS (`scripts/typecheck.sh`).
- Le schermate sono state **disegnate e controllate a occhio** con dati finti (`scripts/preview.sh`): home, TV, guida, film, serie, dettagli, profili, impostazioni, scelta dei contenuti, pacchetti, PIN, player.

**NON verificato**
- Mai compilato con Xcode e mai eseguito su un iPhone o sul simulatore (qui non c'è Xcode). Il **primo build in cloud potrebbe quindi richiedere una piccola correzione**:
  se fallisce, apri il log del workflow e mandamelo.
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
l'app usa il carattere di sistema e un'icona nuova. B-Glass è **solo un lettore**: non fornisce né include contenuti.

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
scripts/check.sh                       # compila il core ed esegue i 1.306 controlli
scripts/typecheck.sh                   # type-check di core + UI contro iOS (Catalyst) e macOS
scripts/preview.sh /tmp/shots home live guide detail_movie   # PNG delle schermate con dati finti
```
