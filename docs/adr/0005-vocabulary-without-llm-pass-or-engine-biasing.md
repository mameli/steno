# The Vocabulary corrects with variants and the Summary prompt, not with an LLM pass or engine biasing

The **Vocabulary** fixes names and technical terms that speech recognition gets wrong in two places only: a deterministic substitution of known variants when the Transcript is built, and the Summary prompt, which gets the terms, variants and descriptions and is told to correct only what it is sure about. The Transcript in the Vault is not rewritten by a model, and the recognition engines get no vocabulary.

An extra LLM pass over the Transcript was rejected: it sends the whole Transcript to a Provider a second time, generates as many tokens as it reads (slow on a local server, and chunked for long Meetings), and a model that rewrites text can change what was said, with the audio gone after seven days. Biasing the engines was tried and does not work for the engine in use. Whisper accepts a prompt of about 224 tokens (`promptTokens`) but is not the engine the user runs. For Parakeet v3, FluidAudio's CTC vocabulary boosting loads a separate English-only 110M model; on 4 Italian sentences and about 75 seconds of real Italian speech with none of the terms it fixed "Scale Uai" and "Dimistral" but also turned correct words into terms ("sono", "meno" into "Steno", a whole sentence into "Parakeet Steno Mameli"), and even with its guards on it kept replacing correct words. FluidAudio's decode-time biasing exists only for Nemotron and Canary, not for the TDT v3 model Steno uses.

## Consequences

- Errors that are not in the variants list stay in the Transcript file; only the Summary repairs them. With *Transcript* chosen instead of a Profile only the variants apply.
- The Whisper prompt is out of v1 until Whisper is the engine in use and it has been tried on real audio. If Transcripts stay poor, an LLM pass with strict rules (words only, structure unchanged, raw text kept when the answer is rejected) can be added on top of this decision.
