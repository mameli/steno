# Meeting data does not leave the EU

Company policy forbids processing meeting audio and text outside the EU: that is why Granola cannot be used and why Takku exists. Every Provider is therefore configurable by the user and must be local or hosted in the EU; non-European hyperscalers are also allowed as long as processing happens in an EU region. Takku ships no default Provider that sends data outside the EU and cannot check the region by itself: the choice is the user's responsibility.

For the same reason there is no automatic fallback to another Provider when the chosen one fails: Processing stops and the user decides whether to retry or regenerate with another Profile. An automatic fallback could send data to a Provider not chosen for that Meeting.

**Development exception (4 October 2026).** During development the user also uses a Profile outside the EU (OpenRouter with an OpenAI model) only with test recordings (their own voice, public videos), never with work meetings. Takku neither prevents nor flags it: choosing the Profile stays with the user. To keep a Meeting from going to a Provider chosen for another one, the Profile is fixed when the Meeting starts.
