# Propulsion Chain v2 — Equations, Assumptions, Data Sources

Architecture (series-hybrid / turbo-electric):

```
Aerodynamics → Required Thrust
    → Propeller → Required Shaft Power (per motor)
    → Gearbox (fixed ratio, fixed efficiency)
    → Motor (torque-speed envelope + efficiency map)
    → Inverter
    → DC Bus ←→ Battery
    ← Rectifier ← Generator ← Engine
```

An Energy Management Controller decides the Battery/Generator split at
every timestep based on mission phase and SoC.

## Why "required" flows backward, then a forward check
Each timestep, required power is solved backward from the aircraft to
the engine (aero → propeller → motor → inverter → EMC split → rectifier
→ generator → engine), then a **forward pass** recomputes what the
generator/rectifier/DC bus actually deliver using the engine's *capped*
shaft power. Any shortfall shows up as `deficit_kw` (logged every step,
`max_power_deficit_kw` in the results, penalized in the objective
function) rather than being silently absorbed. This is a standard
conceptual/preliminary-design simplification — components are evaluated
at their local operating point rather than solved as one simultaneous
system of equations — and it's flagged here rather than hidden.

## Generator (`Generator.m`)
- `P_ac = P_shaft * eta_gen(load_frac, speed_frac)`, peak ~96% near
  rated load/speed, falling at part load (iron/windage losses become a
  larger share of a smaller output).
- `I_ac = P_ac / (sqrt(3) * V_ac * pf)`, pf ≈ 0.95.
- Loss split (informational): copper loss grows with load², iron loss
  roughly constant with speed, mechanical loss small and constant.
- Source: representative aerospace PMSG efficiency-curve shape
  (Gudmundsson, *General Aviation Aircraft Design*, Ch.15 electric
  propulsion supplement). Replace with a specific datasheet once a
  generator is selected.

## Rectifier (`Rectifier.m`)
- `V_dc = 1.35*V_ac_line − 2*V_drop` (standard 3-phase bridge ratio).
- `eta_rect = eta0 − k_sw*load_frac` (switching loss grows with load).
- Source: standard 3-phase bridge topology (Mohan, Undeland & Robbins,
  *Power Electronics*, 3rd ed.).

## DC Bus (`DCBus.m`)
- Power balance: `P_in + P_batt_discharge = P_out + P_batt_charge + P_bus_loss`.
- `P_bus_loss = I_bus² * R_bus` (lumped busbar/connector resistance).
- Voltage treated as approximately regulated (set by the battery,
  clamped to bus limits) — standard lumped-bus simplification at this
  design level.

## Inverter (`Inverter.m`)
- `P_ac_motor = P_dc_in * eta_inv(load_frac)`, peak ~97%, penalized at
  light load (fixed switching losses dominate a small output) and
  slightly above rated.
- Source: typical aerospace SiC/IGBT inverter datasheet shape.

## Propeller (`Propeller.m`)
- `J = V/(n*D)` (advance ratio, n in rev/s), `CT(J)`, `CP(J)` quadratic
  fits, `T = CT*ρ*n²*D⁴`, `P = CP*ρ*n³*D⁵`, `eta_prop = J*CT/CP`.
- Default coefficients approximate a fixed-pitch cruise prop peaking
  ~85% efficiency near J≈0.65. Static thrust (V<1 m/s) uses simple
  momentum theory instead (`P ≈ T^1.5/√(2ρA)`) since the CT/CP fit is
  only valid in the cruise J-range.
- Source: Gudmundsson Ch.15, Raymer Ch.13 propeller charts.

## Battery (`BatteryPack.m`, upgraded)
- `OCV(SoC)`: piecewise-linear, steep near empty/full, flat plateau in
  the middle (typical Li-ion/LiPo rest-voltage shape).
- `V_terminal = OCV ∓ I*R_int` (sag on discharge, rise on charge).
- Retains the original Peukert correction and adds separate
  charge/discharge coulombic efficiencies (97%/98% LiPo).
- `R_int` scaled ~0.5 mΩ per Ah at a 100 Ah reference (pack-level,
  includes busbars/BMS).
- Source: Plett, *Battery Management Systems*, Vol. 1.

## Motor (`ElectricMotor.m`, upgraded)
- Torque-speed envelope: constant max torque below base speed
  (current-limited), constant max power above base speed
  (field-weakening): `T_max(rpm) = P_rated/ω` above base speed.
- Base speed assumed at 50% of max speed (typical aerospace PMSM).
- Power-based efficiency map retained (already captures the right
  qualitative peak-near-rated shape; a torque-based map would need
  motor-specific test data we don't have).
- Source: Gudmundsson Ch.15 electric-propulsion supplement.

## Aerodynamics (`AerodynamicModel.m`, upgraded)
- Now exposes `required_thrust()` (= drag at steady level flight)
  separately from `power_required()` (aerodynamic power at the
  airframe). Propeller efficiency is applied explicitly by
  `Propeller.m` rather than implicitly assumed to be 1.
- Steady, level-flight assumption: climb phases use a constant climb
  speed rather than an explicit flight-path angle, so no `W*sin(γ)`
  climb term is added — documented simplification, not hidden.

## Engine (`TurboshaftEngine.m`, unchanged from the bug-fixed version)
- Output is mechanical **shaft power** feeding the Generator (matches
  the series-hybrid architecture) — this was already correct in the
  existing model, just re-labeled conceptually.

## Energy Management Controller (`EnergyManagementController.m`)
- Takeoff/Climb: battery assists above generator's rated continuous
  power, capped at the battery's max discharge C-rate.
- Cruise: generator supplies demand; spare capacity trickle-charges the
  battery toward an 80% SoC target.
- Loiter: battery preferentially supplies power down to a 30% SoC
  floor.
- Descent/Landing: battery covers the small remaining demand.
- Safety floor: below 20% SoC, generator is forced to cover ~100% of
  demand regardless of phase.

## What's simplified / left for future work
- Gearbox is a fixed ratio (3:1) + fixed efficiency (97%), not a full
  class — reasonable given the "(optional)" label on this node in the
  original architecture request.
- No battery thermal derating beyond the ESR itself; no explicit motor
  thermal model.
- Backward/forward split (see top) rather than one simultaneous
  electrical solve per timestep.
- Optimizer varies 5 variables (engine, battery, motor count,
  generator, motor size); DC bus voltage and propeller diameter are
  fixed design parameters rather than optimized, to keep the PSO search
  space tractable in the time available. Worth expanding if time
  allows.
