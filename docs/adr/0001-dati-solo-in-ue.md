# I dati delle Riunioni non escono dall'UE

La policy aziendale vieta che audio e testo delle riunioni vengano trattati fuori dall'UE: è il motivo per cui Granola non è utilizzabile e per cui Steno esiste. Ogni Provider è quindi configurabile dall'utente e deve essere locale o ospitato in UE; sono ammessi anche hyperscaler non europei purché il trattamento avvenga in una region UE. Steno non include alcun Provider predefinito che invii dati fuori dall'UE e non può verificare la region da solo: la responsabilità della scelta resta dell'utente.

Per lo stesso motivo non esiste un ripiego automatico su un altro Provider quando quello scelto fallisce: l'Elaborazione si ferma e l'utente decide se riprovare o rigenerare con un altro Profilo. Un fallback automatico potrebbe inviare i dati a un Provider non scelto per quella Riunione.

**Eccezione per lo sviluppo (4 ottobre 2026).** Durante lo sviluppo l'utente usa anche un Profilo fuori UE (OpenRouter con un modello OpenAI) esclusivamente con registrazioni di prova (la propria voce, video pubblici), mai con riunioni di lavoro. Steno non lo impedisce né lo segnala: la scelta del Profilo resta dell'utente. Per evitare che una Riunione finisca a un Provider scelto per un'altra, il Profilo viene fissato all'avvio della Riunione.
