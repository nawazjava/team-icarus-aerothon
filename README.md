

Interactive demo built for the **HAL × IIT Indore Hybrid-Electric Propulsion
& Digital Twin Challenge**. It shows the one thing that ties both challenge
tracks together: **the propulsion system is sized against the engine's whole
service life, not just its first day.**

Select an engine health state — Fresh / 500 Flight Hours / 850 Flight Hours —
and watch the Energy Management Controller shift more load onto the battery
as the compressor ages, while the guaranteed-endurance number holds.

## What this is

Most propulsion designs are optimized assuming a brand-new engine. This one
is optimized across the same four health thresholds the project's digital
twin uses (Healthy → Monitor → Service → Critical), so the sizing decision
accounts for degradation instead of being invalidated by it. This page is
the live, clickable version of that result — the number in the center is
what the aircraft is *guaranteed* to deliver even at the worst health state
in that range, not just on day one.

## How to read it

| Element | What it shows |
|---|---|
| Center gauge | Endurance guaranteed at the selected health state, and the engine/battery share of propulsive power |
| Stat panel | Engine health index, average engine load, battery assist share, remaining thrust margin |
| Mission timeline | Engine (teal) vs. battery (amber) power draw per mission phase; a lightning tag marks phases where the battery is net-charging |
| Punchline | The one-sentence version, with the live number inline |

## Updating the numbers

The three health states are driven by one `DATA` object near the top of the
`<script>` block in `index.html`. **These are placeholder values** —
representative of the expected behavior, not yet pulled from a real run.

Before presenting, replace them with actual output from
`run_optimization.m` (Step 6b prints the exact `lifecycle_endurance` value
per health state; per-phase engine/battery kW comes from
`results_optimized.P_eng_shaft_kw` / `P_battery_dc_kw`):

```js
const DATA = {
  fresh:    { guaranteedHours: ..., engineSharePct: ..., phases: [...] },
  mid:      { guaranteedHours: ..., engineSharePct: ..., phases: [...] },
  critical: { guaranteedHours: ..., engineSharePct: ..., phases: [...] }
};
```

Edit, save, commit, push — Pages redeploys automatically within ~30–60s.

## Tech notes

- Single self-contained `index.html` — no build step, no external fonts,
  no CDN dependencies. Works fully offline once loaded, which matters if
  the venue's wifi is unreliable during a live demo.
- Pure SVG + CSS + vanilla JS. No frameworks.
- Responsive down to mobile width.

## Related

This demo accompanies the full MATLAB propulsion-chain simulation
(Aerodynamics → Propeller → Motor → Inverter → DC Bus ↔ Battery →
Rectifier → Generator → Engine, coordinated by an Energy Management
Controller) built for the same challenge.
