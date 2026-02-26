# Material Feel Applied to Transaction UX — Gemini Deep Research (2026-02-26)

> Source: Gemini Deep Research, Prompt 3 — "Material Feel Applied to Transaction UX"
> **Cross-construct**: This research bridges Protocol (verification) and Artisan (design physics).
> See also: `grimoires/artisan/research/material-feel-tx-ux.md` in loa-constructs.

## Core Framework

Three primary axes (from Artisan's design system):
- **Warmth** — cold/clinical ↔ warm/inviting
- **Weight** — lightweight/instant ↔ heavy/consequential
- **Rhythm** — staccato/rapid ↔ flowing/measured

## Material Personality Reference Table

| Dimension | Soft/Cozy (Family, Rainbow) | Sharp/Dense (Drift, Blur) | Premium/Minimal (Stripe, Uniswap) |
|-----------|---------------------------|--------------------------|----------------------------------|
| **Spacing** | Generous, `padding: 24px+` | Tight, `padding: 4-8px` | Balanced, `padding: 16px` |
| **Typography** | Editorial, rounded, varied weights | Technical, monospaced tabular nums | Refined, legible, clean sans-serif |
| **Corners** | `border-radius: 16px+` | `border-radius: 0-2px` | `border-radius: 4-8px` |
| **Motion Duration** | 300-600ms (leisurely) | 80-150ms (immediate) | 200-300ms (measured) |
| **Easing** | Spring / overshoot `cubic-bezier(0.34, 1.56, 0.64, 1)` | Fast response `cubic-bezier(0.4, 0, 0.2, 1)` | Smooth ease-out `cubic-bezier(0.2, 0, 0.38, 0.9)` |
| **Feedback** | Bouncy, morphing shapes | Color flashes, instant toggles | Subtle fades, precise icon transitions |
| **Color** | Warm, vibrant, avoid neon-on-black | Dark mode, high-contrast utilitarian | Restrained palette, confident accents |
| **Elevation** | Soft shadows, layered | Flat, minimal shadows | Subtle elevation, intentional depth |

## Weight of Consequence

| Action Category | Impact | UI State Mgmt | Timing | Vocabulary |
|----------------|--------|--------------|--------|-----------|
| **Lightweight** | Reversible, local | Optimistic | < 100ms | Toggle, View, Hide, Dismiss |
| **Medium** | Reversible, remote | Pessimistic (soft) | 200-300ms | Update, Save, Submit, Modify |
| **Heavy** | Irreversible, financial | Pessimistic (strict) | 800ms+ enforced delay | Burn, Revoke, Swap, Transfer |

Key insight: Stripe intentionally adds artificial delay to payment confirmation — communicates "this matters" through temporal weight, even when network auth is instantaneous.

Heavy vocabulary: Delete, Destroy, Revoke, Burn → terminal actions
Soft vocabulary: Archive, Dismiss, Snooze, Toggle → reversible state changes
"Disconnect" (local session) vs "Revoke Allowance" (on-chain permanent)

## Error States by Material

### Soft/Cozy Errors
- Avoid aggressive reds → softer oranges/warm yellows
- Gentle side-to-side shake (human "no" gesture)
- Abstract blockchain mechanics entirely: "Network is busy. Trying again with higher priority..."
- Immediate CTA: fiat on-ramp or auto-retry
- Tone: "let's fix this together"

### Sharp/Dense Errors
- Stark red borders, instant un-eased popups
- Exact telemetry: "Slippage Tolerance Exceeded. Deviation: 1.2%. Adjust > 1.5%."
- Assumes user understands AMMs and liquidity
- CTA: inline parameter adjustment, rapid retry
- Tone: unvarnished data, get out of the way

### Premium/Minimal Errors
- Clean error cards with precise iconography
- Actionable but not overwhelming: "Price moved. Review updated quote."
- One clear recovery action

## Progressive Disclosure

### Spacious Apps (Soft/Cozy)
- "One Big Button" principle — strip secondary elements
- Gas abstracted to fiat USD cost
- Advanced settings (slippage, RPC routing, gas) collapsed behind toggle
- Surface must feel calm

### Dense Apps (Sharp/Terminal)
- Parameters exposed inline by default — slippage, MEV status, margin ratios
- Hiding settings = operational friction for experts
- Challenge shifts from hiding info → organizing it (tabular, monospace, strict grids)

## Flow State Preservation

### The Cost of Interruption (Gloria Mark, UC Irvine)
- 23 min 15 sec to regain deep focus after interruption
- Compensatory speed-up → higher stress, more errors
- Meditative app: interruption cost is devastating
- Trading terminal: users expect staccato context switches

### Architectural Solutions
- **Paymasters** (ERC-4337): eliminate "5-minute drop-off" to acquire gas
- **Session keys**: pre-approve parameter set for defined period → single-click flow
- **Batch transactions**: collapse multi-step into atomic execution

### Waiting State by Material
- **Soft**: indeterminate pulsing (1000ms loop), "Working our magic (~2 min)"
- **Sharp**: determinate progress bar tied to block confirmations, "ETA: 12s"
- **Premium**: smooth phase transitions, progressive state reveals

## Perceived Performance

- Users overestimate wait times by up to 36%
- Progress indicators make waits feel ~15% faster
- 100ms = "direct manipulation" threshold (NNG)
- 200ms ease-out: right for trading, rushed for meditation app
- Choreograph micro-interactions to fill 12-second block times

## Protocol↔Artisan Composability Note

This research establishes that **material feel is not Protocol territory** — it's Artisan's domain.
Protocol's role is to **verify** that implementations match the declared taste:

- `dapp-lint`: Should check animation durations against `taste.md` Never Rules
- `dapp-test`: Should test that pending states render appropriate to material personality
- `dapp-e2e`: Should validate error messages match declared tone (cozy vs terminal)

The composability: **Artisan defines → Protocol verifies**.
