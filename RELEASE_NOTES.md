## B·Glass 1.3 — quando un canale non parte, sai perché

Provata su oltre 11.000 canali pubblici di server diversi e su un pannello Xtream reale. Ecco cosa cambia per tutti i fornitori.

**Più modi per far partire un canale**
- Usa anche l'indirizzo dei video che il pannello dichiara (`server_info`) quando è diverso da quello del login.
- Usa anche l'indirizzo originale del canale quando il pannello lo fornisce (`direct_source`).
- Resta tutto quello della 1.2: HLS, MPEG-TS, indirizzo senza formato, lettore Apple e VLC, la forma vincente ricordata per lista.

**Rispetto per le linee da una connessione**
- Niente più tentativi a raffica: tra un tentativo e l'altro l'app lascia il tempo al server di chiudere la connessione precedente; se il fornitore segnala troppe connessioni aspetta prima di riprovare.

**Messaggi chiari**
- Al primo errore l'app chiede al server del video il motivo e lo spiega: video rifiutato dal fornitore (401/403), contenuto tolto (404), troppe connessioni, server in errore, server irraggiungibile dalla tua rete (anche per blocchi DNS dell'operatore), pagina web al posto del video.
- Se il rifiuto è del fornitore lo dice subito, invece di far girare la rotellina per mezzo minuto: in quel caso nessun lettore può fare meglio.

**Installazione**: scarica `BGlass.ipa` qui sotto e installalo con Sideloadly o AltStore (non è firmato).
