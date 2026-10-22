## B·Glass 1.2 — funziona con i fornitori più diversi

**Liste che prima non si caricavano**
- Se il server rifiuta l'app, B·Glass prova da sola a presentarsi come gli altri lettori IPTV più diffusi e ricorda quello accettato.
- Se il pannello non risponde all'indirizzo scritto, prova l'altro protocollo (http/https) e le porte più usate dai pannelli Xtream.
- Accetta i certificati HTTPS non validi quando sono l'unico problema.
- Legge le risposte "sporche": avvisi PHP prima dei dati, nomi con accenti scritti alla vecchia maniera (Latin-1), cataloghi vuoti, categorie mancanti.
- Liste M3U con intestazioni in stile Kodi (`|User-Agent=…&Referer=…`), opzioni `#EXTVLCOPT`, attributi tra apici, righe estranee; un link a un solo canale HLS diventa un canale.

**Canali che prima non partivano**
- Ogni canale viene provato in tutte le sue forme (HLS, MPEG-TS, indirizzo senza formato) con entrambi i lettori, Apple e VLC; la forma che funziona viene ricordata per gli altri canali della stessa lista.
- I canali che chiedono un Referer o un User-Agent particolare ora li ricevono.
- Un canale fermo sul caricamento si riavvia da solo invece di restare sulla rotellina.
- Con VLC i canali partono molto prima (il buffer iniziale era di 10 secondi).

**Quando qualcosa non va**
- La lista viene controllata prima di essere aggiunta, e l'errore si vede subito con la spiegazione (password sbagliata, abbonamento scaduto, pagina web al posto della lista…). C'è comunque «Aggiungi comunque».
- Nuovo *Impostazioni › Registro tecnico*: cosa è stato chiesto ai server e cosa hanno risposto, con utenti e password nascosti, da copiare e inviare.

**Installazione**: scarica `BGlass.ipa` qui sotto e installalo con Sideloadly o AltStore (non è firmato).
