# Nadir

Nadir is a native SwiftUI chat application for running local language models through
[Ollama](https://ollama.com) on macOS.

It combines local chat, project organization, optional RAG memory, document and image
attachments, official-documentation-aware web research, response verification, and
personal finance tools in a single desktop app.

## Highlights

- Local Ollama model discovery and chat
- Chat, Code, and Finance assistant modes
- Projects with scoped instructions, conversations, and memories
- Optional Chroma-based semantic memory service
- Image, PDF, Word, Excel, CSV, text, and source-code attachments
- Tavily or SerpAPI web research
- Official documentation routing for Apple, Google, Microsoft, GitHub, OpenAI,
  Llama/Ollama, and Anthropic questions
- A second consistency pass for technical and finance answers
- Markdown rendering, copy controls, and persistent helpful/unhelpful feedback
- Local Word and Excel export tools
- Draggable conversation and composer panes

## Requirements

- macOS 15 or later
- Xcode Command Line Tools
- [Ollama](https://ollama.com) running locally
- Python 3 with `venv` support for optional semantic memory
- A Tavily or SerpAPI key for optional web research

## Build the app

```bash
git clone https://github.com/RoMakesIT/localchatmac.git
cd localchatmac
./Scripts/build_app.sh
open build/Nadir.app
```

The script builds for the current Mac architecture and ad-hoc signs the local app
bundle. Ad-hoc signing is intended for development; public distribution would require
an Apple Developer ID signature and notarization.

## Run Ollama

Install Ollama, start its local service, and pull at least one chat model:

```bash
ollama serve
ollama pull llama3.1:8b
```

Nadir defaults to `http://127.0.0.1:11434` and can also target another configured
Ollama endpoint.

## Optional memory service

The memory service stores embeddings and conversation text locally with Chroma:

```bash
cd MemoryService
./start_memory.sh
```

The first start creates `MemoryService/.venv-memory`, installs the pinned Python
dependencies, downloads the embedding model, and listens only on
`http://127.0.0.1:8765`.

Memory data is stored outside the repository at:

```text
~/Library/Application Support/GemmaAssistant/memory/
```

The legacy directory name is retained to preserve existing installations.

## Privacy and local data

- Conversations, projects, settings, and finance entries stay in
  `~/Library/Application Support/LocalChatMac/state.json`.
- Tavily and SerpAPI credentials are stored in macOS Keychain, not in `state.json`.
- Attachments are copied into the LocalChatMac Application Support directory.
- Semantic memory stays in the local Chroma directory shown above.
- Ollama prompts remain local unless web research is enabled. When enabled, the search
  query is sent to the selected search provider.
- Nadir does not upload chat history to this GitHub repository.

The first Keychain-enabled launch migrates any search credentials previously stored in
`state.json` into macOS Keychain and removes them from subsequent state writes.

## Web research

Web research is optional. For recognized vendor and developer questions, Nadir
restricts search to official documentation domains and labels the active source route
in the interface. General questions retain normal web search.

## Repository layout

```text
Assets/          App icon source and generated icon sizes
MemoryService/   Optional local FastAPI + Chroma memory service
Resources/       macOS application metadata
Scripts/         Local build script
Sources/         SwiftUI application source
```

## Security

Please do not commit API keys, local state, attachments, model files, memory databases,
or generated app bundles. The included `.gitignore` excludes the common local paths.

For a security-sensitive issue, avoid posting credentials or private chat content in a
public issue.

## License

Nadir is available under the [MIT License](LICENSE).
