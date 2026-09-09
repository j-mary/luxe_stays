# 12 — AI-assisted engineering

AI tooling was used throughout building this project. This document records
where it genuinely helped, where it actively misleads, and the guardrails that
make the difference — including where it was deliberately *not* used.

## Where it helped, concretely

| Task | What AI did well | What still needed a human |
|---|---|---|
| **Scaffolding integrations** | Generating a DTO + mapper pair from a sample JSON response in seconds, including defensive field reads | Deciding *which* fields are required vs optional — that is a contract judgement, not a text-transformation |
| **Test generation** | Enumerating edge cases from an implementation: null fields, wrong types, empty lists, boundary values | Choosing which behaviours are worth pinning. An LLM will happily write forty tests for a getter |
| **Error-envelope mapping** | Four vendors, four fault shapes, one mapper — mechanical and easy to get subtly wrong by hand | The taxonomy itself: that `RATE_CHANGED` deserves its own `Failure` type is a product decision |
| **Documentation** | Turning a design decision into readable prose, and keeping fourteen documents consistent with the code | Every claim about a vendor. See "the failure mode" below |
| **Debugging** | Pasting a stack trace plus the relevant file and asking "what invariant is violated here" is faster than bisecting | Reproducing it. AI cannot tell you it only happens on Android 13 with a slow network |
| **Code review** | "What can be null here that the code assumes is not" catches real bugs, fast | Architectural review. It optimises the code in front of it, not the shape of the system |

Two bugs in this repository were found by an AI review pass and are worth
naming, because they are the kind that survive human review:

* `CheckoutController.build()` originally used `ref.watch(sessionProvider)`. The
  loyalty refresh fired after a successful booking would rebuild the notifier
  and **discard the booking outcome the confirmation screen was displaying**.
  Changed to `ref.read`, with a comment explaining why.
* `PaymentWebViewScreen` had no double-pop guard. A PSP that both posts a bridge
  message *and* redirects would pop the route twice, tearing down the screen
  underneath. Fixed with a `_completed` flag.

## The failure mode, and the guardrail

**AI is confidently wrong about vendor APIs.** Ask any assistant for the SynXis
REST endpoint for availability and it will produce something plausible,
specific, and unverifiable — because the real contract is distributed to
certified partners, not published.

The guardrail, stated as a rule:

> Anything an AI asserts about an external system is treated as a **hypothesis
> until it is verified against a primary source or a live sandbox.**

In practice that meant:

* Vendor documentation URLs in [03](03-INTEGRATION-SYNXIS.md),
  [04](04-INTEGRATION-SALESFORCE.md), [05](05-INTEGRATION-LEONARDO.md) and
  [06](06-INTEGRATION-CMS.md) were **fetched and checked**, not recalled. That is
  how this repository knows that `sabrehospitality.com` now redirects to
  `avenhospitality.com`, and that "Leonardo" in a hospitality context is the
  LUCID/Vizlly media platform rather than the generative-image company with a
  similar name.
* Where a contract could not be verified, the documentation **says so** and the
  code isolates it behind a mapper. "Modelled on the platform's documented
  concepts, and here is the one file to change" is an honest engineering
  position. A fabricated endpoint presented as fact is not.
* `tool/contract_check.sh` exists precisely because assumptions about a vendor's
  response shape need to be executable, not remembered.

## Beyond code generation

Code generation is the least interesting use. What was more valuable:

* **Test-case enumeration.** Feeding `Money`, `LoyaltyProgramRules` and the
  bridge parser to a model and asking "what inputs break the stated invariants"
  produced the string-amount case, the floor-vs-round case and the
  newer-protocol-version case — all of which are now tests.
* **Adversarial review of the error taxonomy.** "For each failure, what does the
  guest see, and can they act on it?" is a prompt that surfaces the difference
  between an error message and a dead end.
* **Documentation consistency.** Fourteen documents and a README drift the
  moment code changes. Asking a model to diff prose against implementation
  catches the paragraph that still describes last week's design.
* **Threat modelling as a checklist.** "What can a compromised page inside this
  WebView do?" produced the message-time origin check in
  [02](02-WEBVIEW-BRIDGE.md), which is the control most hybrid apps are missing.

## AI features in the product itself

Distinct from AI in the workflow. This POC includes one, deliberately narrow:

**Leonardo.Ai destination imagery** — generative images on inspiration surfaces
only, never for a room or a property, always visibly labelled, never blocking a
screen, and with the API key held server-side. See
[05 — Leonardo](05-INTEGRATION-LEONARDO.md).

Candidates a travel app should consider next, roughly in order of value per unit
of risk:

1. **Natural-language search** — "somewhere quiet in Kyoto with a private
   bath in April" parsed into a `SearchQuery`. The domain model is already the
   right target; the parse happens server-side.
2. **Itinerary summarisation** from CMS destination content, cached per
   destination rather than generated per guest.
3. **Support triage** — classifying an in-app case before it reaches Service
   Cloud, using the correlation id to attach the real failure.
4. **Review summarisation**, with the source reviews always one tap away.

The rule for all four: **AI output that a guest could mistake for a fact about
their booking must be labelled, sourced, or not shipped.** A generated summary
of a hotel's cancellation policy is a liability; a generated mood image labelled
as such is not.

## What AI is bad at here, and where the human stayed in charge

* **Architecture.** The layering, the four-vendor composition rules and the
  "content is never load-bearing" decision came from thinking about who owns
  which change — not from a prompt.
* **Product judgement.** That a rate change must interrupt the guest rather than
  silently re-price is a trust decision.
* **Knowing what to leave out.** An assistant will always add the feature. The
  reasons this repository has no `go_router`, no code generation and no
  certificate pinning are all in [01](01-ARCHITECTURE.md) and
  [11](11-SECURITY.md), and all of them are judgements about cost.
