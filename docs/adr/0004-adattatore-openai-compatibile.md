# Un solo adattatore compatibile OpenAI; LLM locale esterno, Whisper integrato

Quasi tutti i Provider candidati (Mistral, Scaleway, OVHcloud, IONOS, Azure v1, Ollama, LM Studio) espongono API compatibili OpenAI per chat e trascrizione, quindi Steno ha un unico adattatore generico configurato da Profili con nome, invece di un client per ogni Provider. L'LLM locale gira fuori dall'app (Ollama/LM Studio) per non gestire download e memoria dei modelli; la trascrizione locale invece è integrata (WhisperKit) perché si usa a ogni Riunione e deve funzionare senza altri programmi aperti.
