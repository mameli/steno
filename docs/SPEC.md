# Steno: specifica v1

Termini in **grassetto** come definiti in [CONTEXT.md](../CONTEXT.md). Decisioni architetturali in [docs/adr](adr/).

## Obiettivo

Registrare una **Riunione** dal Mac, produrne **Trascrizione** e **Riepilogo** con **Provider** scelti dall'utente (locali o in UE) e scrivere tutto nel **Vault** Obsidian, senza che i dati escano dall'UE ([ADR 0001](adr/0001-dati-solo-in-ue.md)).

Uso personale, una macchina (M3 Pro, 18 GB, macOS 26). Riunioni in italiano o in inglese, una lingua per Riunione.

## Perimetro

**Dentro la v1**
- App nella barra dei menu: avvio/stop, scorciatoia globale, scelta del **Template**
- Cattura in Modalità Call: **Tracce** Io (microfono, con cancellazione d'eco) e Altri (audio di sistema)
- Trascrizione locale WhisperKit a blocchi durante la call
- Lingua rilevata in automatico o forzata
- **Profili** per il Riepilogo, adattatore compatibile OpenAI, chiavi nel Keychain, finestra Impostazioni essenziale
- **Nota della Riunione** creata all'avvio e aperta in Obsidian; **Zona gestita**; Trascrizione in un file separato
- Template letti dal Vault, **Rigenerazione**, "Riprova"
- Registrazione conservata 7 giorni, coda di **Elaborazione**

**Fuori dalla v1** (in ordine di probabilità)
1. Calendario (titolo e partecipanti da EventKit)
2. Trascrizione remota (la locale basta: 12 minuti in 50 secondi su M3 Pro); i Profili avranno allora anche il Ruolo trascrizione
3. Modalità Sala (solo microfono, per riunioni in presenza)
4. Notifica "sembra una call" quando un'app prende il microfono
5. Diarizzazione vera (Persona 1, 2…)
6. Preset dei Provider già pronti
7. Distribuzione ad altri (firma Developer ID, notarizzazione)
8. Stop automatico per silenzio a fine call (era la fase 6)

## Flusso principale

1. **Avvio** (clic o scorciatoia). Steno:
   - crea l'identificativo della Riunione e la cartella della Registrazione;
   - crea la Nota della Riunione `<Vault>/Meetings/2026-10-04 1430 - Riunione.md` (vedi [struttura](#nota-della-riunione));
   - la apre in Obsidian con `obsidian://open?path=<percorso assoluto>`;
   - avvia la cattura delle due Tracce.
2. **Durante la call**: l'utente scrive le **Note personali** nella nota. I segmenti audio già chiusi vengono trascritti in background. Il Template si può cambiare dalla barra dei menu; il Profilo per il Riepilogo è quello attivo all'avvio.
3. **Stop** (clic o scorciatoia). La Riunione entra nella coda di Elaborazione e si può subito avviare un'altra Riunione.
4. **Elaborazione** (una alla volta, in ordine di arrivo):
   1. completa la Trascrizione (gli ultimi segmenti);
   2. scrive il file della Trascrizione;
   3. rilegge la Nota della Riunione ed estrae le Note personali;
   4. genera Riepilogo e titolo con il Profilo di riepilogo;
   5. riscrive la Zona gestita e le chiavi di Steno nel frontmatter;
   6. rinomina la nota e la Trascrizione con il titolo, se l'utente non l'ha già rinominata (dalla fase 4, quando il titolo esiste);
   7. notifica "Riepilogo pronto" (clic → apre la nota in Obsidian).
5. Se un passo fallisce: la Zona gestita mostra `⚠️ Riepilogo non generato: <motivo>`. La Riunione resta in "Riunioni recenti" con **Riprova**. Nessun ripiego su un altro Provider.

## Cattura audio

- **Altri**: Core Audio process tap globale (`CATapDescription`, tutti i processi: Steno non riproduce audio, quindi non serve escluderlo) + aggregate device che contiene **solo il tap**. Un aggregato con gli altoparlanti come dispositivo principale smette di ricevere audio quando il voice processing del microfono è attivo. Si avvia prima del microfono. Richiede `NSAudioCaptureUsageDescription`: la prima volta macOS mostra il popup "Registrazione solo audio di sistema" e l'avvio resta in attesa della risposta.
- **Io**: `AVAudioEngine` sul microfono di default con `setVoiceProcessingEnabled(true)` per la cancellazione d'eco. Con il voice processing il microfono arriva a 9 canali: si tiene solo il canale 0, già ripulito. Il ramo d'uscita del motore non va collegato, altrimenti l'avvio fallisce (-10875). Disattivabile con `defaults write dev.mameli.steno echoCancellation -bool false` finché non ci sono le impostazioni. Richiede `NSMicrophoneUsageDescription`.
- Ogni Traccia viene scritta in **segmenti di 5 minuti** (`io-000.m4a`, `altri-000.m4a`, …), AAC mono 16 kHz. Motivi: un crash perde al massimo un segmento; i segmenti chiusi si trascrivono durante la call; i file restano sotto i limiti di upload dei Provider remoti.
- Le due Tracce condividono l'orologio d'avvio: ogni segmento registra il proprio offset dall'inizio della Riunione. L'elenco dei segmenti di ogni Traccia (`io-segmenti.json`, `altri-segmenti.json`) si aggiorna a ogni apertura, così gli offset sopravvivono a un crash; allo stop confluisce in `riunione.json`, che viene scritto anche se una Traccia si è interrotta.

**Stop per silenzio**: fuori dalla v1 per scelta dell'utente (la Riunione si ferma sempre a mano, dal menu o con ⌃⌥⌘R).

## Trascrizione

- Ogni Traccia si trascrive separatamente. Le Battute delle due Tracce si ordinano per tempo d'inizio e si fondono in paragrafi (regole sotto).
- Un segmento che non si riesce a trascrivere non blocca gli altri: la Trascrizione viene scritta con un buco e l'errore viene segnalato.
- A Whisper arrivano solo i **tratti con parlato** di ogni segmento: finestre da mezzo secondo con RMS sopra 0,004, pause sotto i 2 secondi assorbite, un quarto di secondo di margine per lato. Sul silenzio, sull'eco residuo e sulle voci lontane Whisper inventa frasi ("Grazie.", decine di volte nella prova della fase 1). Le annotazioni come `[BLANK_AUDIO]` o le frasi tra parentesi vengono comunque scartate.
- Un paragrafo della Trascrizione riunisce le Battute consecutive della stessa Traccia, ma si spezza dopo una pausa di oltre 30 secondi o quando una Battuta inizia più di 60 secondi dopo l'inizio del paragrafo: c'è un nuovo timestamp circa ogni minuto (una Battuta di Whisper dura al massimo 30 secondi).
- Il risultato di ogni segmento (lingua e Battute) viene salvato accanto all'audio (`io-000.m4a.json`), così una nuova Elaborazione non ritrascrive quello che è già fatto.
- **Locale**: WhisperKit, modello `openai_whisper-large-v3-v20240930_turbo_632MB` (646 MB), scaricato al primo uso in `~/Library/Application Support/Steno/Modelli` e preparato mentre la prima Riunione è in corso. Lingua `auto` oppure forzata `it`/`en`. La lingua si rileva una sola volta, su 30 secondi di solo parlato (i tratti con voce, senza silenzi) del primo segmento che ne contiene, di qualsiasi Traccia, scegliendo solo tra italiano e inglese, e vale per tutta la Riunione. Non si preferisce più Altri (era la difesa contro lo "svedese" della fase 1, nato dal silenzio): rilevando solo sul parlato il problema sparisce, e nella call reale l'eco residuo in Io resta sotto la soglia del parlato. La lingua usata viene salvata nella cache di ogni segmento; se poi si forza una lingua diversa, il segmento viene ritrascritto. Si può forzare con `defaults write dev.mameli.steno language it` (o `en`, `auto`) finché non ci sono le impostazioni. Rilevarla sui primi 30 secondi non basta: nella prova reale della fase 1 la Traccia Io iniziava con 80 secondi di quasi silenzio e Whisper l'ha classificata come svedese.
- **Remota** (dopo la v1): `POST {baseURL}/audio/transcriptions` (multipart, un segmento per richiesta) tramite l'adattatore compatibile OpenAI. Verrà usata solo allo stop: durante la call l'audio non lascia mai il Mac.

File `<Vault>/Meetings/Trascrizioni/2026-10-04 1430 - <Titolo> (trascrizione).md` (una copia senza frontmatter resta in `trascrizione.md` nella cartella della Registrazione, finché c'è l'audio). Una nuova Elaborazione della stessa Riunione sovrascrive il file esistente, ritrovato tramite `steno_id`:

```markdown
---
steno_id: 6F1C…
riunione: "[[2026-10-04 1430 - Titolo]]"
lingua: it
---
**[00:00] Altri:** Buongiorno a tutti, partiamo dal…

**[00:42] Io:** Sì, sul primo punto…
```

## Nota della Riunione

```markdown
---
steno_id: 6F1C…
data: 2026-10-04T14:30
durata: 47m
template: 1:1 settimanale
lingua: it
provider_trascrizione: Locale
provider_riepilogo: Mistral EU
trascrizione: "[[2026-10-04 1430 - Titolo (trascrizione)]]"
tags: [riunione]
---
%% steno:inizio %%
⏺ Registrazione in corso: il Riepilogo comparirà qui dopo lo stop.   ← poi il Riepilogo
%% steno:fine %%

## Note personali

```

Regole:
- Steno riscrive **solo** il testo tra `%% steno:inizio %%` e `%% steno:fine %%` e le **proprie** chiavi del frontmatter (`durata`, `lingua`, `provider_trascrizione`, `provider_riepilogo`, `template`, `trascrizione`). Le chiavi aggiunte dall'utente restano. `data` e `tags` si scrivono solo alla creazione: da quel momento appartengono all'utente. `steno_id` viene ripristinato a ogni aggiornamento se l'utente l'ha cancellato, altrimenti la nota non si ritroverebbe più.
- Lo `steno_id` conta solo nel frontmatter (un testo uguale nel corpo non identifica la nota). I marcatori della Zona gestita dentro i blocchi di codice non contano. Le note con a capo Windows o BOM vengono lette correttamente e riscritte con a capo `\n`.
- Steno aggiorna la nota sul file stesso (non lo sostituisce), controllando che non sia cambiata tra lettura e scrittura: se Obsidian l'ha salvata nel frattempo, la rilegge e riapplica la modifica.
- Se l'Elaborazione fallisce, la Zona gestita mostra `⚠️ <motivo>` invece di restare su "Registrazione in corso".
- Tra la creazione e la fine dell'Elaborazione Steno non scrive nella nota (niente stato intermedio "Elaborazione in corso"): il progresso si vede nella barra dei menu.
- Se all'avvio il Vault non è raggiungibile (volume non montato, cartella spostata) la Riunione si registra lo stesso e la nota viene creata a fine Elaborazione. Lo stesso succede se l'utente cancella la nota durante la Riunione.
- **Note personali** = tutto il corpo fuori dalla Zona gestita, senza l'intestazione `## Note personali`. Se è vuoto, il Riepilogo si basa solo sulla Trascrizione.
- Se i marcatori sono stati cancellati, Steno li ricrea in testa al corpo, senza cancellare niente.
- La nota si ritrova tramite `steno_id`: prima al percorso noto, altrimenti cercando nella cartella Meetings. Se l'utente l'ha rinominata o spostata, Steno non la rinomina.
- In caso di nome già esistente si aggiunge un suffisso ` (2)`.
- Senza calendario, `partecipanti` non viene scritto nella v1.
- Steno scrive solo a Elaborazione finita, quindi minuti dopo lo stop, per evitare conflitti con le modifiche ancora aperte in Obsidian.

## Template

- Cartella `<Vault>/Meetings/_Template/`. Il Template predefinito è `Appunti.md`, in stile Granola: argomenti nell'ordine in cui sono stati discussi, ciascuno con un'intestazione `###` e punti con sotto-punti (motivi, persone, cifre, link), poi `### Prossimi passi` con `- [ ] Cosa fare (Chi)` e il contesto sotto. Niente sintesi iniziale né sezioni fisse. Steno lo crea all'avvio dell'app e quando si sceglie il Vault, se la cartella è vuota o se il Template di default non esiste più (e allora il default torna Appunti).
- Formato: frontmatter con `nome` e `lingua_riepilogo` (`auto` | `it` | `en`, default `auto` = lingua della Riunione). Il corpo, cioè le istruzioni libere e la struttura di intestazioni, si passa al modello così com'è.
- Il Template si sceglie all'avvio (default dalle impostazioni) e si può cambiare fino allo stop.
- Nelle Impostazioni, sezione Template: elenco, Template di default, "Nuovo Template" (nome → file creato da Appunti e aperto in Obsidian), "Apri in Obsidian", "Elimina" (sposta il file nel Cestino; se era il default si torna ad Appunti). Il testo si scrive in Obsidian: Steno non ha un editor.

## Riepilogo

- `POST {baseURL}/chat/completions` con:
  - **prompt di sistema fisso**: non inventare, attribuisci a Io/Altri, azioni come checklist nel formato del Template (in mancanza `- [ ] chi: cosa (quando)`), rispondi nella lingua indicata, segui struttura e istruzioni del Template, dai priorità ai temi presenti nelle Note personali;
  - **messaggio utente**: Template, Note personali, Trascrizione.
- **Titolo**: seconda chiamata breve sul Riepilogo ("massimo 6 parole, niente data"), ripulito da intestazioni, prefissi "Titolo:", virgolette, grassetto e punteggiatura finale. Se il titolo non arriva la nota resta con il nome provvisorio: non è un errore.
- **Zona gestita**: il Riepilogo seguito da `Trascrizione completa: [[…]]`. Se il Riepilogo fallisce (nessun Profilo attivo, errore del Provider, Riunione senza parlato) mostra `⚠️ Riepilogo non generato: <motivo>` e il link alla Trascrizione, che resta utilizzabile. Eventuali marcatori della Zona gestita nella risposta del modello vengono tolti.
- **Stima dei token**: circa 3 caratteri per token, con 4.096 token riservati alla risposta; un blocco non spezza mai un paragrafo della Trascrizione.
- **Riunioni lunghe**: ogni Profilo di riepilogo ha un campo *contesto massimo*. Se Trascrizione + Note + Template lo superano, la Trascrizione si divide in blocchi, si riassume ogni blocco e i riassunti parziali si uniscono con il Template.
- **Rigenerazione**: da "Riunioni recenti" → *Rigenera con* ▸ Template / Profilo. Rilegge Trascrizione e Note personali correnti e riscrive solo la Zona gestita. È disponibile anche dopo i 7 giorni, perché la Trascrizione è nel Vault.

## Profili e impostazioni

**Profilo** (v1: solo per il Riepilogo): nome, base URL, chiave API (nel Keychain, facoltativa per i server locali), modello, contesto massimo. Esempi: "llama.cpp locale" (`http://localhost:8080/v1`), "Mistral EU" (`https://api.mistral.ai/v1`). La trascrizione è sempre locale (WhisperKit). Un Profilo fuori UE (es. OpenRouter) è ammesso solo per lo sviluppo con registrazioni di prova: Steno non lo impedisce, la scelta resta dell'utente (eccezione registrata nell'ADR 0001). Il Profilo si fissa all'avvio della Riunione. L'URL deve essere `https://`; `http://` è ammesso solo per server su questo Mac (`localhost`, `127.0.0.1`, `*.local`).

**Impostazioni** (UserDefaults; i segreti nel Keychain). Nella finestra Impostazioni della v1:
- percorso del Vault
- Template di default
- Profili per il Riepilogo e Profilo attivo (con "Prova connessione")

Per ora solo da terminale (`defaults write dev.mameli.steno …`), da portare nella finestra quando serviranno:
- lingua (`auto` | `it` | `en`)
- cancellazione d'eco on/off
- giorni di conservazione dell'audio (`retentionDays`, default 7)

La scorciatoia globale è fissa: ⌃⌥⌘R. Se un'altra app la usa già, il menu lo segnala.

Le cartelle sono fisse: `Meetings/`, `Meetings/Trascrizioni/`, `Meetings/_Template/`.

## Barra dei menu

- **Inattiva**: Avvia riunione (scorciatoia) · Template ▸ · Profilo Riepilogo ▸ · Riunioni recenti ▸ (Apri nota · Rigenera con ▸ · Riprova) · Impostazioni… · Esci
- **In registrazione**: nella barra solo un pallino rosso; nel menu "In registrazione · durata" · Ferma · Template ▸ · Impostazioni…
- **In Elaborazione**: clessidra nella barra; nel menu "Elaborazione in corso… (altre N in coda)"

## Stato e conservazione

- `~/Library/Application Support/Steno/Riunioni/<steno_id>/`: segmenti audio, cache della trascrizione per segmento, `riunione.json` (inizio, fine, segmenti) ed `elaborazione.json` (stato: in registrazione, in coda, in corso, completata, fallita con motivo; Template; Profilo fissato all'avvio; percorso della nota).
- Coda di Elaborazione persistente, una Riunione alla volta: al riavvio dell'app le Elaborazioni in coda o in corso ripartono, dalla più vecchia. Una Registrazione interrotta da un crash viene ricostruita dagli elenchi dei segmenti e messa in coda: si perde solo il segmento aperto al momento del crash (un file AAC non chiuso è illeggibile).
- Un segmento illeggibile è un avviso ("Trascrizione incompleta"), non un fallimento: il Riepilogo si genera con quello che c'è.
- All'avvio dell'app e ogni giorno: cancellazione dell'audio (e delle cache della trascrizione) delle Riunioni più vecchie di 7 giorni già elaborate o fallite, mai di quelle in registrazione, in coda o in corso. `riunione.json` ed `elaborazione.json` restano: la Riunione resta tra le recenti e si può Rigenerare.
- **Notifiche**: "Riepilogo pronto" (clic → nota in Obsidian) o "Elaborazione non riuscita" con il motivo.
- **Scorciatoia globale** ⌃⌥⌘R: avvia o ferma la Riunione da qualsiasi app.
- **Riunioni recenti** (le ultime 5): Apri nota · Riprova (finché c'è l'audio: rifà tutta l'Elaborazione, i segmenti già trascritti vengono dalla cache) · Rigenera con Template ▸ / con Profilo ▸ (solo il Riepilogo, dalla Trascrizione nel Vault; non rinomina la nota e non cambia Template e Profilo salvati della Riunione, che Riprova continua a usare). Riprova e Rigenera compaiono solo per Riunioni concluse (completate o fallite), mai per una in registrazione o in coda. Una Rigenerazione interrotta da un riavvio non si ripete: la Riunione torna completata con il Riepilogo precedente.
- Senza Vault configurato l'Elaborazione si ferma alla Trascrizione e la notifica dice "Trascrizione pronta", non "Riepilogo pronto".

## Struttura del progetto

- **App Xcode** `Steno` (SwiftUI, `MenuBarExtra`, target macOS 15, firma Personal Team): cattura audio, WhisperKit, notifiche, scorciatoia, Keychain, UI.
- **Pacchetto Swift locale** `StenoCore`, testabile con `swift test` e senza dipendenze da AppKit o AVFoundation: fusione dei segmenti → Trascrizione, lettura e scrittura della Nota della Riunione (Zona gestita, frontmatter, ricerca per `steno_id`), parsing dei Template, costruzione dei prompt e suddivisione in blocchi, client compatibile OpenAI, macchina a stati Riunione/coda, regole di conservazione.

Test: Swift Testing su `StenoCore`, in TDD. Cattura e trascrizione si verificano a mano con Registrazioni di prova salvate come fixture.

## Piano a fasi

Ogni fase si chiude con una verifica concreta.

| # | Fase | Fatto quando |
|---|---|---|
| 0 | Progetto Xcode + `StenoCore`, firma, Info.plist, `MenuBarExtra` con Avvia/Ferma | L'app parte nella barra dei menu e chiede i permessi una volta sola |
| 1 | **Cattura** delle due Tracce a segmenti, cancellazione d'eco | Una call Meet/Teams di 12 minuti produce 3+3 segmenti udibili, con Io senza eco degli altri |
| 2 | **Trascrizione locale** a blocchi + fusione Io/Altri | Il file Trascrizione della call di prova è leggibile, ordinato e attribuito |
| 3 | **Vault**: Nota della Riunione, Zona gestita, frontmatter, `steno_id` (la rinomina passa alla fase 4, insieme al titolo) | Test verdi; la nota appare in Obsidian all'avvio e le Note personali restano intatte dopo l'Elaborazione |
| 4 | **Riepilogo**: finestra Impostazioni, Profili, Keychain, client compatibile OpenAI, Template, suddivisione in blocchi, titolo e rinomina | Riepilogo corretto della call di prova con un Provider remoto (in sviluppo OpenRouter, solo registrazioni di prova). Restano da provare, quando l'utente li configura: un server locale (llama.cpp) e un Provider UE |
| 5 | **Flusso completo**: coda persistente, Rigenerazione, Riprova, notifiche, scorciatoia, conservazione | Due Riunioni consecutive elaborate in coda; Riprova dopo aver spento il server locale |
| ~~6~~ | ~~Stop per silenzio~~ | Tolta: l'utente preferisce fermare sempre a mano |

## Rischi noti

- **Ducking**: con il voice processing attivo e `voiceProcessingOtherAudioDuckingConfiguration` al minimo, la Traccia Altri registra circa metà del volume. In una call Meet reale (fase 1) l'utente non ha percepito abbassamenti di ciò che sente, quindi riguarda solo il segnale registrato. Se un giorno desse fastidio: cancellazione d'eco disattivata e cuffie.
- **Contesto del server locale**: llama.cpp (`llama-server -c`), Ollama (`OLLAMA_CONTEXT_LENGTH`) e LM Studio hanno un contesto di default piccolo che tramite l'endpoint compatibile OpenAI non si cambia per richiesta: va impostato all'avvio del server, coerente con il *contesto massimo* del Profilo (minimo 8.192 token, Steno non scende sotto).
- **Risposte troncate**: se il modello si ferma per limite di lunghezza (`finish_reason: length`) il Riepilogo è considerato fallito, non salvato a metà. Le Riunioni molto lunghe uniscono i riassunti parziali a gruppi finché l'unione finale entra nel contesto.
- **Buchi nell'audio**: l'offset di un segmento si calcola dai frame scritti dall'inizio della Traccia. Se una sorgente perde buffer (cambio di dispositivo, reset del voice processing) gli offset successivi di quella Traccia slittano rispetto all'altra. Fase 2: nella call reale di 12 minuti le due Tracce finiscono a meno di 10 ms l'una dall'altra, nessuno slittamento visibile nella Trascrizione. Se comparisse (es. cuffie collegate a metà call), si riallinea ogni segmento con l'host time del suo primo buffer.
- **Parole tagliate tra i segmenti**: il confine dei 5 minuti può spezzare una parola. Fase 2: con segmenti da 5 secondi una frase a cavallo di due segmenti si ricompone correttamente; nella call reale nessuna parola persa ai confini. Se dovesse pesare, si aggiunge una breve sovrapposizione tra segmenti.
- **Whisper non deterministico sull'audio degradato**: con il fallback di temperatura, lo stesso tratto può dare testi diversi tra due Elaborazioni. Nella prova della fase 2 (voce ripresa da un telefono in un'altra stanza, passata per Meet e riprodotta dagli altoparlanti) la prima frase si è persa in un giro su tre. Disattivare il fallback rende il risultato stabile ma peggiore; la soglia "nessun parlato" di Whisper è disattivata perché scartava proprio questi tratti. Da rivalutare se succede con l'audio di call normali.
- **Rinomina con la nota aperta in Obsidian**: Obsidian di solito segue il cambio di nome, ma va verificato nella fase 3. Il ripiego è non rinominare (titolo solo nell'intestazione).
- **Download del modello Whisper**: WhisperKit scarica i pesi da Hugging Face. Non è un dato di Riunione e non tocca l'ADR 0001, ma richiede rete al primo avvio.
