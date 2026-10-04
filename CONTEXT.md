# Steno

App personale macOS che registra le riunioni, ne produce Trascrizione e Riepilogo con provider scelti dall'utente (locali o ospitati in UE) e scrive il risultato in un Vault Obsidian. Alternativa a Granola compatibile con la policy aziendale di residenza dei dati in UE.

## Linguaggio

### Riunione e cattura

**Riunione** (`Meeting`):
Una call registrata con Steno, dall'avvio allo stop. È l'unità attorno a cui ruota tutto il resto.
_Evita_: call, sessione, meeting (in italiano)

**Registrazione** (`Recording`):
L'audio di una Riunione, conservato fuori dal Vault per un periodo limitato.
_Evita_: audio, file audio

**Traccia** (`Track`):
Una delle due sorgenti audio di una Registrazione: **Io** (microfono) o **Altri** (audio di sistema).
_Evita_: canale, stream

**Segmento** (`Segment`):
Una porzione di una Traccia salvata in un file a sé, con il suo istante d'inizio rispetto all'inizio della Riunione.
_Evita_: pezzo, chunk, blocco

**Modalità** (`CaptureMode`):
Come viene catturata una Riunione: **Call** (Tracce Io e Altri separate) o **Sala** (solo microfono, per riunioni in presenza, senza attribuzione Io/Altri).

**Elaborazione** (`Processing`):
La fase dopo lo stop in cui Steno completa la Trascrizione e genera il Riepilogo. Può fallire ed essere ritentata.
_Evita_: post-processing, job

### Prodotti

**Trascrizione** (`Transcript`):
Il testo parlato di una Riunione, con timestamp e attribuzione a Io/Altri. Vive in un file separato nel Vault.
_Evita_: transcript, sbobinatura

**Battuta** (`Utterance`):
Un tratto di parlato riconosciuto in una Traccia, con inizio e fine rispetto all'inizio della Riunione. Le Battute consecutive della stessa Traccia formano un paragrafo della Trascrizione.
_Evita_: segmento (è un'altra cosa), frase, chunk

**Riepilogo** (`Summary`):
La sintesi strutturata di una Riunione, generata applicando un Template a Trascrizione e Note personali.
_Evita_: recap, summary (in italiano), verbale

**Note personali** (`PersonalNotes`):
Gli appunti scritti a mano dall'utente durante la Riunione. Guidano il Riepilogo e non vengono mai modificati da Steno.
_Evita_: appunti, note utente

**Nota della Riunione** (`MeetingNote`):
Il file nel Vault che contiene il Riepilogo, le Note personali e il link alla Trascrizione.
_Evita_: file riepilogo, documento

**Zona gestita** (`ManagedSection`):
La parte della Nota della Riunione che Steno può riscrivere. Tutto il resto appartiene all'utente.

**Template** (`Template`):
Un file nel Vault che definisce struttura e istruzioni del Riepilogo per un tipo di Riunione.
_Evita_: modello (ambiguo con il modello AI), prompt

**Rigenerazione** (`Regeneration`):
La produzione di un nuovo Riepilogo per una Riunione già elaborata, tipicamente con un altro Template o Profilo.

### Provider

**Ruolo** (`Role`):
Il compito per cui si usa un Provider: **trascrizione** o **riepilogo**. I due Ruoli si configurano in modo indipendente.

**Provider** (`Provider`):
Un servizio, locale o remoto, che svolge un Ruolo. Deve trattare i dati dentro l'UE.
_Evita_: backend, API, vendor

**Profilo** (`ProviderProfile`):
Una configurazione con nome di un Provider (endpoint, credenziali, modello) che l'utente seleziona per un Ruolo.
_Evita_: preset, account

**Vault** (`Vault`):
La cartella Obsidian in cui Steno scrive Note della Riunione, Trascrizioni e da cui legge i Template.
