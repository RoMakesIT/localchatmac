# Lantern

Lantern is a native SwiftUI chat application for running local language models through
[Ollama](https://ollama.com) on macOS.

It combines local chat, project organization, optional RAG memory, document and image
attachments, official-documentation-aware web research, response verification, and
personal finance tools in a single desktop app.

## Highlights

- Local Ollama model discovery and chat
- Chat, Code, Finance, and Tax agent profiles with saved settings and task-specific guidance
- Animated thinking dots with memory, research, tools, and verification status
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
open build/Lantern.app
```

The script builds for the current Mac architecture and ad-hoc signs the local app
bundle. Ad-hoc signing is intended for development; public distribution would require
an Apple Developer ID signature and notarization.

## Run Ollama

Install Ollama, start its local service, and pull at least one chat model:

```bash
ollama serve
ollama pull qwen3.8:27b-mlx
```

Lantern starts with `qwen3.8:27b-mlx` and discovers other installed models automatically.
It defaults to `http://127.0.0.1:11434` and can also target another configured
Ollama endpoint.

## Agent profiles and activity

In the message composer, **Enter** sends and **Shift+Enter** inserts a new line.
**Command+Enter** also sends.

Switch **Chat**, **Code**, **Finance**, or **Tax** in the composer to load that agent's saved
model, prompt, memory, web search, local tools, and verification settings. Customize
those settings once; Lantern restores them when you return to the agent. Conversations
remember their selected agent, and new project conversations use the project default.

- **Chat:** balanced everyday help, writing, explanations, and deterministic daily
  planning; an extra verification pass is off by default.
- **Code:** precise debugging, implementation, and review guidance, lower generation
  randomness, calculator/document tools, and answer verification.
- **Finance:** precise financial analysis, the current project's saved ledger,
  calculator/ledger/document tools, lowest generation randomness, and verification.

Each agent also uses the current conversation, attachments, project instructions,
and relevant project-scoped memories when memory is enabled. Finance ledger context
and its analysis tool are supplied only to Finance; Tax uses separate actual entity/year records. Mode guidance adapts the response
to tasks such as drafting, debugging, reviewing, budgeting, or reconciling. These are
local assistant profiles; Code provides guidance and code, without a shell or repository
editing tool.

**Settings → Agent profile** shows the active knowledge and tools and offers
**Restore defaults** for the current agent. Appearance, endpoint, and search credentials
remain app-wide. Web search starts off in new profiles and requires a configured search
API key when enabled. Existing installations retain their active settings as a
customized profile during migration.

Lantern checks native tool and vision capabilities using Ollama's
[model details endpoint](https://docs.ollama.com/api-reference/show-model-details).
Models without native tool support use a constrained JSON action format for every
enabled local tool, with the same argument validation as native calls. Lantern shows
the final answer rather than the action envelope. Export tools are offered only for
an explicit document/workbook request; descriptive questions do not enable exports.

The harness keeps supplied records, documents, search excerpts and recalled text out
of the system instructions. Finance starts with a deterministic ledger baseline;
Tax starts with its selected saved-record analysis. Verification retains the draft's
tool evidence and can use only read-only tools. Identical calls reuse their result;
successful exports cannot be repeated or replaced during verification.

**Settings → Model → Context size** is saved per agent, starting at 16K. Requests
explicitly send this limit to Ollama. A conservative input estimate reserves output
space, counts tool schemas, images and reasoning history, and removes older dialogue
first. The current request, selected records and new tool observations are retained.
If those do not fit, Lantern asks for a smaller task or larger context; it does not
silently clip those figures. Larger contexts use more memory, and estimates cannot
exactly predict every model's tokenizer. Document extraction marks its own page,
sheet, row and character limits. Partial model outputs are rejected, and completed
export paths remain visible if later generation fails.

While a reply is pending, animated dots appear inside the conversation with the current
phase and elapsed time. The indicator clears on completion, cancellation, or failure.
Reduced Motion uses static dots. Navigation and agent settings are disabled during a
reply so the answer remains attached to the conversation and configuration that sent it.

Run the isolated profile and request lifecycle checks with:

```bash
./Scripts/test_agent_profiles.sh
```

The tests use temporary storage and mock HTTP responses; they do not contact Ollama,
the memory service, or external search providers.

The reliability checks also exercise calculation evidence through verification,
native/structured argument repair, source instruction isolation, thinking/history
budgets, six-call final synthesis, truncation, and duplicate physical exports.
Test exports use the temporary test directory. Memory scope regressions run with:

```bash
python3 -m unittest discover -s MemoryService -p 'test_*.py' -v
```

For a repeatable live check using an installed model and synthetic data:

```bash
./Scripts/evaluate_harness.sh --model qwen3.8:27b-mlx --repeat 2
```

The five fixtures cover exact arithmetic, a schedule, constrained writing,
instructions hidden in a document, and tax actual/confirmed/proposed figures.
Reports in `build/evaluations` record model digest, settings, responses, tool evidence,
latency and available Ollama token metrics. These are narrow task checks, not proof
of GPT-4o parity; a comparison would require the same cases on both models. The
runner never reads your saved records and disables web research and memory.

## Business tax planning

Select **Tax** beside the composer, then use the **Tax Records** menu to choose
**Business entity / year** or **Personal / household year** (also available in Settings).
Add one record per entity and tax year within the current project. Save previous filed
years and update the current year's checkpoint as you move from filing preparation to
midyear and year-end planning. Records persist locally alongside your conversations.
The editor saves explicit user-entered accounting totals, not monthly budget estimates.
Attach source returns, P&Ls, receipts and supporting documents to project conversations;
chatting about an adjustment does not save or confirm it in Tax Records.

Record the legal form and tax classification/election, jurisdiction, currency, accounting
method and exact period dates. Unknown amounts stay blank; a recorded zero is different.
Actual income minus expenses gives book profit/loss; cash inflows minus outflows gives
net cash. The deterministic planning bridge adds confirmed add-backs and subtracts
confirmed reductions. Proposed adjustments appear only in a separate hypothetical
scenario. An adjustment whose tax effect is already in the starting profit is excluded.
Do not propose a second reduction for an expense already deducted in the books; an
add-back can reverse an expense included in book profit. User-confirmed adjustments
require supporting references, applicable rule/year references and eligibility review.
Confirmation is a user attestation, not legal validation by Lantern.

The **Audit / filing risk indicator** reports **Needs information**, **High attention**,
**Review needed**, or **No recorded issues**, with specific reasons. Unreviewed income,
documentation, reconciliation, owner activity, payroll and carryforward checks keep the
record incomplete. An explicitly unresolved check raises high attention. No recorded
issues means only that the entered checks are clear; it is not an audit probability or
certification that a return is correct. The IRS explains that audit selection can occur
without suggesting a problem: [IRS audits](https://www.irs.gov/businesses/small-businesses-self-employed/irs-audits).
Keep evidence for income and deductions: [IRS recordkeeping](https://www.irs.gov/businesses/small-businesses-self-employed/recordkeeping).

Review buttons prepare (but do not send) a filing, midyear or year-end chat prompt. The
agent receives the selected record's calculated analysis and other saved years for the
same entity/currency. It does not combine entities or treat partial-year figures as
annual totals. This context works even when the model lacks native tools; a model with
native tools can also call the read-only `analyze_tax_records` function.

**Export Excel** saves all records in the current project, their P&L/scenario numbers,
adjustment references, readiness checks and source details in Documents/Lantern Exports.
Tax mode does not calculate statutory tax liability, personal taxable income, a refund,
or whether losses are deductible, and it does not file or synchronize with tax software.
Use the analysis and records to prepare for your filing solution.

Tax web research remains off until configured. When enabled, Tax uses a generic business
rule query for the selected tax year instead of transmitting your chat, entity name or
financial amounts to the search provider. For US records it restricts results to IRS
sources; state rules and question-specific issues may need supplied official documents
or additional research. The agent must flag rules that are not supported by applicable
year/jurisdiction evidence. Other modes retain their existing search behavior. As with
all Lantern modes, a configured remote Ollama endpoint receives the model's chat context.

### Personal / household tax overview

Create a personal project and choose **Tax → Tax Records → Personal / household year**.
Add one personal/household record per tax year, using the same name across years. Record
country, residence state/region, filing status, currency and the through date. This
workspace saves separately from business records and restores the selected overview.

Add one wage entry per employer/person. Use **Annual W-2** with a December 31 through
date for filed years, or **Year-to-date paystub** for midyear figures. Record box 1 wages
and box 2 federal income tax withheld (or YTD equivalents); enter state rows separately
for boxes 15–17. Do not use take-home pay or add Social Security/Medicare taxes to federal
income tax withholding. State wages may overlap between states and are never added to
federal wage income. Spouse entries require a joint overview. Replace an existing source
for a corrected W-2 or updated YTD paystub instead of counting it twice. Statutory employee
sources block ordinary wage/combined income totals until their separate treatment is
resolved. These field meanings follow the [IRS W-2 instructions](https://www.irs.gov/instructions/iw2w3).

**Link a business-year record** can explicitly select a record from another project,
provided its year and currency match. Unlinked businesses are not included in the chat
context. Each link begins **Reference only**, contributing no income to the total.
For a 100%-owned sole proprietor/disregarded business, select its planning treatment,
review the owner-level applicability and add a source reference. The business's dates
must match the personal calendar-year period and its classification must identify a
sole proprietor or disregarded business. Confirmed business profit and hypothetical
proposals then flow into separate personal planning subtotals.

Other entity types use **Reviewed owner-level amount** from Schedule C, K-1 or other
appropriate records. The user supplies the includable amount and any hypothetical owner
scenario; Lantern never assumes total company profit, an ownership percentage or a cash
distribution is personal taxable income. Negative owner amounts require loss/basis review.
An unreviewed hypothetical loss does not erase a known positive baseline, but its scenario
stays incomplete. Sources and reviews remain user attestations, not eligibility certification.

Keep federal withholding, federal estimated payments and residence-state estimated
payments separate. Other income excludes wages and linked business figures; use 0 only
if none after review. Missing amounts stay unknown, and no-wage income requires an explicit
confirmation. Withholding plus estimates is shown as recorded federal payments, not an
expense or an income reduction. This distinction follows the [IRS withholding estimator
explanation](https://www.irs.gov/individuals/tax-withholding-estimator-faqs).

The combined recorded-income and hypothetical-income subtotals are **not AGI, taxable
income, tax liability or refund estimates**. Personal deductions, credits, statutory tax,
SE tax, other-form withholding and multi-state estimated-payment allocation are not
calculated; preserve those inputs in notes/source documents for filing-software review.
**Export Excel** includes personal summaries, wage/state sources, explicit owner mappings
and readiness actions. Review buttons prepare the personal chat with its saved history
and linked business context, including for models without native tools. No record is
changed by chatting.

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
~/Library/Application Support/Lantern/memory/
```

Lantern uses its own storage directory for this clean installation.
Chroma's anonymized product telemetry is disabled.

## Privacy and local data

- Conversations, projects, settings, and finance entries stay in
  `~/Library/Application Support/Lantern/state.json`.
- Tavily and SerpAPI credentials are stored in macOS Keychain, not in `state.json`.
- Attachments are copied into the Lantern Application Support directory.
- Semantic memory stays in the local Chroma directory shown above.
- Ollama prompts remain local unless web research is enabled. When enabled, the search
  query is sent to the selected search provider.
- Lantern does not upload chat history to this GitHub repository.

The first Keychain-enabled launch migrates any search credentials previously stored in
`state.json` into macOS Keychain and removes them from subsequent state writes.

## Web research

Web research is optional. For recognized vendor and developer questions, Lantern
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

Lantern is available under the [MIT License](LICENSE).
