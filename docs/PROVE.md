# Prove di Steno v1

Lista delle prove da fare a mano prima di usare Steno per le riunioni vere. Ognuna dice cosa fare e cosa deve succedere.

Prima di iniziare: Steno avviato dal menu (icona a onda), vault e Profilo "OpenRouter (solo prove)" configurati. **Con OpenRouter usa solo registrazioni di prova**: la tua voce, video pubblici, mai riunioni di lavoro.

## 1. Registrazione

- [ ] **Avvio da menu**: *Avvia riunione* → nella barra compare il pallino rosso, in Obsidian si apre `Meetings/<data> <ora> - Riunione.md`.
- [ ] **Durata**: apri il menu durante la registrazione → prima riga "In registrazione · mm:ss".
- [ ] **Scorciatoia**: ⌃⌥⌘R da un'altra app avvia, ⌃⌥⌘R di nuovo ferma.
- [ ] **Template durante la call**: cambia *Template* dal menu mentre registri → il Riepilogo segue il Template scelto per ultimo.
- [ ] **Profilo durante la call**: il menu *Profilo Riepilogo* non c'è mentre registri (si fissa all'avvio).

## 2. Elaborazione

- [ ] **Template Appunti**: il Riepilogo ha gli argomenti nell'ordine della Riunione, con punti e sotto-punti, e in fondo *Prossimi passi* come checklist "Cosa fare (Chi)".
- [ ] **Note personali**: scrivi qualche riga sotto `## Note personali` durante la call → dopo lo stop restano intatte e il Riepilogo dà precedenza a quei temi.
- [ ] **Riepilogo**: dopo lo stop la clessidra nella barra, poi la notifica "Riepilogo pronto"; la nota ha Riepilogo, link alla Trascrizione e frontmatter (durata, lingua, template, provider).
- [ ] **Titolo e rinomina**: la nota non si chiama più "… - Riunione" ma "… - <titolo>"; la Trascrizione in `Trascrizioni/` ha lo stesso nome con "(trascrizione)".
- [ ] **Clic sulla notifica**: apre la nota in Obsidian.
- [ ] **Nota rinominata da te**: rinomina la nota durante la call → Steno la ritrova e non la rinomina.
- [ ] **Lingua inglese**: una prova con un video in inglese → Trascrizione e Riepilogo in inglese.

## 3. Coda e Riunioni recenti

- [ ] **Due Riunioni di fila**: ferma la prima e avvia subito la seconda → nel menu "Elaborazione in corso… (altre 1 in coda)", poi due notifiche.
- [ ] **Riunioni recenti → Apri nota**: apre la nota giusta, anche se l'hai rinominata o spostata.
- [ ] **Nuovo Template**: Impostazioni → *Template* → scrivi un nome → *Crea e apri* → si apre in Obsidian; cambia istruzioni e sezioni e salva.
- [ ] **Template di default**: scegli il nuovo Template come default → la prossima Riunione parte con quello.
- [ ] **Elimina Template**: *Elimina* → conferma → il file è nel Cestino del Mac; se era il default, torna Appunti.
- [ ] **Rigenera con Template**: *Riunioni recenti* → una Riunione → *Rigenera con Template* → il tuo Template → il Riepilogo cambia, durata e Trascrizione no.
- [ ] **Riprova**: togli la connessione a internet, fai una Riunione breve → "Elaborazione non riuscita" e ⚠️ nella nota e nel menu; ricollegati e *Riprova* → Riepilogo generato.

## 4. Casi limite

- [ ] **Senza Profilo**: *Profilo Riepilogo* → *Nessuno*, fai una Riunione → nella nota "⚠️ Riepilogo non generato: Nessun Profilo…", la Trascrizione c'è.
- [ ] **Chiusura durante l'Elaborazione**: ferma una Riunione ed esci subito da Steno → alla riapertura l'Elaborazione riparte da sola.
- [ ] **Chiave sbagliata**: in Impostazioni sostituisci la chiave con una a caso → *Prova connessione* mostra l'errore del provider; poi rimetti quella giusta.

## 5. Da fare quando li configuri

- [ ] **Provider UE** (es. Mistral): nuovo Profilo con chiave → *Prova connessione* → una Riunione di prova → *Rigenera con Profilo* su una Riunione vecchia per confrontare i Riepiloghi.
- [ ] **Server locale** (llama.cpp): nuovo Profilo senza chiave, `http://localhost:8080/v1`, contesto massimo uguale a quello del server (`llama-server -c 32768`).

Se qualcosa non va: il messaggio ⚠️ nel menu e nella nota dice il motivo; copialo così com'è.
