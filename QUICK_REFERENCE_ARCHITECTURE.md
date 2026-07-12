# QUICK REFERENCE: MATLAB ARCHITECTURE COMPARISON
## Challenge 1 vs Challenge 2

---

## ARCHITECTURE AT A GLANCE

### Challenge 1: Hybrid-Electric Propulsion (System Design)
**Goal**: Optimize component sizing for maximum endurance  
**Time Scale**: Mission-level (hours)  
**Computational Speed**: Fast (50 ms per full mission sim)  
**Key Physics**: Aerodynamics, thermochemistry, power balance

```
DESIGN VARIABLES (5 dimensions)
  ├─ Engine power: 40–80 kW
  ├─ Battery capacity: 50–200 Ah
  ├─ Motor count: 1–4
  ├─ Power strategy: enum
  └─ Generator power: 10–50 kW
         ↓
    PSO OPTIMIZER (40 particles, 100 iterations)
         ↓
  MISSION SIMULATOR (time-step ODE integrator)
    ├─ Aerodynamic power requirement
    ├─ Engine fuel consumption
    ├─ Battery state tracking
    └─ Weight evolution
         ↓
   METRICS (fitness evaluation)
    ├─ Endurance (maximize)
    ├─ MTOW compliance (constraint)
    └─ Fuel reserve (constraint)
         ↓
   NEXT DESIGN CANDIDATE
```

**Key Modules**:
| Module | Method | Time | Dependency |
|--------|--------|------|------------|
| AerodynamicModel | power_required() | ~1 µs | alt, speed, weight |
| TurboshaftEngine | query_performance() | ~100 µs | throttle, alt |
| BatteryPack | discharge_step() | ~10 µs | power, voltage, dt |
| MissionSimulator | run_simulation() | ~50 ms | all above |
| PSO Optimizer | optimize() | ~200 s | objective_func |

---

### Challenge 2: Digital Twin (Health Monitoring)
**Goal**: Estimate engine health from measurements in real-time  
**Time Scale**: Component-level (milliseconds)  
**Computational Speed**: <10 ms per cycle (suitable for embedded)  
**Key Physics**: Thermodynamics, compressor/turbine aero, combustion

```
SENSOR MEASUREMENTS (6 channels, 1 kHz)
  ├─ Pressures: P2, P3, P4
  ├─ Temperatures: T3, T4
  └─ Mass flow rate (inferred from RPM)
         ↓
  EXTENDED KALMAN FILTER (state estimator)
    ├─ Predict: ODE integration (RK4)
    ├─ Update: Innovation from measurements
    └─ Estimate: 7-state vector + covariances
         ↓
   ENGINE STATE VECTOR
    ├─ P2, T2 (compressor discharge)
    ├─ P3, T3 (combustor outlet)
    ├─ P4, T4 (turbine outlet)
    └─ N (shaft speed)
         ↓
   HEALTH INDEX CALCULATION
    ├─ Compressor: efficiency ratio → HI_comp
    ├─ Turbine: pressure ratio → HI_turb
    ├─ Combustor: temp rise → HI_comb
    └─ Overall: weighted combination → HI_overall
         ↓
   SURROGATE PREDICTION (GPR for fast evaluation)
    ├─ Train: 500 samples offline
    ├─ Predict: <1 ms per sample
    └─ Uncertainty: 95% confidence intervals
         ↓
   HEALTH OUTPUTS
    ├─ Current health index
    ├─ Confidence bounds
    ├─ Degradation trend
    └─ Time-to-maintenance
```

**Key Modules**:
| Module | Method | Time | Dependency |
|--------|--------|------|------------|
| TurbojetsThermodynamicModel | state_equations() | ~10 µs | states, inputs |
| ExtendedKalmanFilter | predict() | ~100 µs | ODE integrator |
| ExtendedKalmanFilter | update() | ~50 µs | measurements |
| HealthIndicatorCalculator | compressor_health() | ~1 µs | states |
| GaussianProcessRegressor | predict() | ~1 ms | training data |

---

## DESIGN SPACE COMPARISON

| Aspect | Challenge 1 | Challenge 2 |
|--------|------------|------------|
| **Search Approach** | PSO (global optimization) | Kalman filter (state tracking) |
| **Degrees of Freedom** | 5 design variables | 7 state variables (fixed) |
| **Uncertainty Handling** | Sensitivity analysis | Bayesian: covariance matrices |
| **Real-time Capable?** | No (optimization ~3 mins) | Yes (<10 ms cycle) |
| **Physics Integration** | Simplified (LUT-based) | Deep (ODE systems) |
| **Data Requirements** | None (analytical) | 500+ training samples |
| **Validation** | Endurance comparison | RMSE, generalization test |

---

## PHYSICS FIDELITY LEVELS

### Challenge 1: AERODYNAMICS
**Fidelity**: Medium (Engineering correlations)
```
Level 0 (Rough):     P_cruise = MTOW * 10  [Watts]
Level 1 (Raymer):    P = D*V = [Cd0 + CL²/(πeAR)] * 0.5*ρ*V²*S * V
Level 2 (Detailed):  CFD-corrected Cd0, variable e(CL)
Level 3 (High):      Full CFD simulation (hours per point)
         ↑
      OUR LEVEL
```

### Challenge 1: PROPULSION
**Fidelity**: Medium-High (Component maps)
```
Level 0:   P_avail = P_rated * (throttle%)
Level 1:   P_avail = P_rated * (throttle%) * (ρ/ρ_SL)^0.5  + SFC map
Level 2:   Turbine map + compressor map + detailed combustor
         ↑
      OUR LEVEL
Level 3:   Transient thermodynamics, rotor dynamics, thermal analysis
```

### Challenge 2: THERMODYNAMICS
**Fidelity**: High (Physics-informed)
```
Level 0:   Linear model: T_out = T_in + ΔT
Level 1:   Isentropic relations: T_is = T_in * (P_out/P_in)^((γ-1)/γ)
Level 2:   + Efficiency factors (η_comp, η_turb)
Level 3:   + Detailed mass/energy balances, transient dynamics
         ↑
      OUR LEVEL
Level 4:   3D CFD + blade erosion modeling + heat transfer
```

---

## COMPUTATIONAL COMPLEXITY

### Challenge 1: Optimization Budget
```
Scenario: Optimize 1000 kg UAV, 7-hour mission, 5 design variables

Single simulation:
  Mission time: 25,200 seconds
  Time step: 10 seconds
  Iterations: 2,520 steps per mission
  Aero calc: 2,520 × 1 µs = 2.5 ms
  Engine calc: 2,520 × 100 µs = 252 ms
  Battery calc: 2,520 × 10 µs = 25 ms
  Total per mission: ~50 ms

Full optimization:
  Particles: 40
  Iterations: 100
  Simulations: 40 × 100 = 4,000
  Total time: 4,000 × 50 ms = 200 seconds ← ACCEPTABLE (3 min)
```

### Challenge 2: Real-Time Monitoring
```
Scenario: Turbojet health monitoring on flying engine, 1 kHz sensor rate

Per time step (1 ms available):
  EKF predict (RK4 ODE):      ~100 µs
  EKF update (matrix ops):    ~50 µs
  Health calc:                ~5 µs
  GPR prediction:             ~1 ms
  Total:                      ~1.15 ms ← EXCEEDS BUDGET by 15%

Solution: Run GPR every 10 steps, interpolate:
  Every 1 ms: EKF only        ~155 µs ✓
  Every 10 ms: + GPR          ~1.15 ms ✓
```

---

## VALIDATION STRATEGIES

### Challenge 1: Confidence Building
```
Phase 1: Unit Tests
  ├─ Aero: Compare power curve to published aircraft
  ├─ Engine: Cross-check SFC with manufacturer data
  ├─ Battery: Validate against datasheets
  └─ ✓ PASS if all within ±10%

Phase 2: Integration Tests
  ├─ Mission simulator: Trace through one phase manually
  ├─ PSO convergence: Test on 2D Rosenbrock (known solution)
  └─ ✓ PASS if PSO finds optimum in <100 iterations

Phase 3: Sensitivity Analysis
  ├─ Tornado: Rank design variable impact
  ├─ Monte Carlo: Propagate parameter uncertainties
  └─ ✓ PASS if results stable to ±5% perturbations

Phase 4: Comparison Studies
  ├─ Baseline vs. optimized: Endurance improvement?
  ├─ Pareto front: Multiple trade-offs visible?
  └─ ✓ PASS if improvements >10% without MTOW violation
```

### Challenge 2: Confidence Building
```
Phase 1: Unit Tests
  ├─ Thermodynamic model: Compare to textbook examples
  ├─ EKF observability: Can we estimate all states?
  └─ ✓ PASS if state error < 5% in 10 seconds

Phase 2: Integration Tests
  ├─ Synthetic data: Generate known degradation scenarios
  ├─ Health index: Does HI drop when efficiency drops?
  └─ ✓ PASS if HI responsive to degradation

Phase 3: Surrogate Validation
  ├─ Training: 400 samples → RMSE < 0.05
  ├─ Testing: 100 held-out samples → RMSE < 0.06
  ├─ Generalization: New engine? → RMSE < 0.10
  └─ ✓ PASS if uncertainty bands contain 95% of errors

Phase 4: Real-Data Testing
  ├─ Historical engine logs: Replay and check predictions
  ├─ Known failures: Does HI predict maintenance?
  └─ ✓ PASS if 90%+ agreement with actual failures
```

---

## HYPERPARAMETER TUNING CHECKLIST

### Challenge 1: PSO
- [ ] Swarm size: 30–50 (larger = more exploration, slower convergence)
- [ ] Iterations: 50–150 (stop when fitness plateau < 1% per 10 iterations)
- [ ] Inertia w: 0.7–0.9 (higher = more exploration, lower = exploitation)
- [ ] Cognitive c1: 1.0–2.0 (balance personal best vs. global trend)
- [ ] Social c2: 1.0–2.0 (typically equal to c1)
- [ ] Bounds: Iteratively narrow around optimum (divide space in half each generation)

### Challenge 2: EKF
- [ ] Process noise Q: Increase if filter underestimates uncertainty
- [ ] Measurement noise R: Decrease if filter doesn't trust measurements
- [ ] Initial covariance P0: Start conservative (large uncertainty)
- [ ] Time step dt: Must be << fastest system time constant (here: ~0.1 s)
- [ ] Integration method: RK4 for accuracy, Euler for speed (trade-off)

### Challenge 2: GPR
- [ ] Kernel: RBF works for most, try Matern if behavior non-smooth
- [ ] Length scales: Auto-initialize from feature ranges
- [ ] Signal variance σ_f²: Normalize output to [0, 1] first
- [ ] Noise variance σ_n²: Set to ~(measurement noise)², not zero
- [ ] Training data size: 200 = minimum, 500 = robust, 1000+ = diminishing returns

---

## DEBUGGING DECISION TREES

### Challenge 1: Optimizer Not Converging
```
Is fitness improving each iteration?
  ├─ NO → Objective function may be flat
  │       ├─ Check: Can you compute fitness by hand?
  │       ├─ Try: Broader bounds, coarser grid for faster evals
  │       └─ Last resort: Switch to Genetic Algorithm (more robust)
  │
  └─ YES but slowly → Bounds too large
            ├─ Check: Std dev of particle positions << range
            ├─ Try: Narrow bounds around best solution, re-run
            └─ Add: Local refinement phase with smaller bounds
```

### Challenge 2: EKF Diverges (Filter Ignores Measurements)
```
Does predicted state match sensor measurements?
  ├─ NO → Process model (ODE) wrong
  │       ├─ Check: Can states reach steady-state? (dxdt → 0)
  │       ├─ Try: Increase process noise Q by factor of 10
  │       └─ Debug: Trace ODE step-by-step with known input
  │
  └─ YES but filter still diverges → Measurement noise wrong
            ├─ Check: Is R too large? (filter thinks sensors bad)
            ├─ Try: Reduce R, re-test
            └─ Verify: Actual sensor noise matches assumed σ_n
```

### Challenge 2: GPR Predictions Always "Safe" (HI ≈ 1)
```
Is training data diverse enough?
  ├─ NO → Dataset only has healthy engines
  │       ├─ Solution: Synthetically degrade healthy data
  │       └─ Generate: scenarios from healthy (HI=1) to worn (HI=0.7)
  │
  └─ YES → Features not informative
            ├─ Check: Which features correlate with degradation?
            ├─ Add: Derived features (e.g., pressure ratios, temp drops)
            └─ Engineer: Thermodynamic residuals (actual vs. ideal)
```

---

## DEPLOYMENT CHECKLIST

### Challenge 1: Verification for Competition
- [ ] **Physics validation**: Aero drag ±10%, Engine SFC ±15%
- [ ] **Simulation accuracy**: Hand-trace one mission phase
- [ ] **Optimization convergence**: Pareto front shows clear trade-offs
- [ ] **Sensitivity**: Top 3 design variables identified
- [ ] **Presentation-ready plots**: Mission profile, power budget, Pareto curves
- [ ] **Code documentation**: Class docstrings, method signatures clear
- [ ] **Runtime**: Full optimization < 5 minutes on laptop
- [ ] **Robustness**: Handles edge cases (infeasible designs, extreme bounds)

### Challenge 2: Verification for Competition
- [ ] **Physics validation**: Steady-state performance matches engine model
- [ ] **EKF tuning**: Converges within 10 seconds on synthetic data
- [ ] **Health indices**: Respond correctly to known degradation
- [ ] **Surrogate accuracy**: RMSE < 0.05 on test set
- [ ] **Uncertainty**: 95% CI captures 92–98% of errors
- [ ] **Generalization**: Works on engine types not in training
- [ ] **Real-time**: <10 ms per cycle (suitable for embedded)
- [ ] **Dashboard**: Live health trends, degradation projection

---

## FINAL RECOMMENDATIONS

### For Challenge 1 Success:
1. **Start simple**: Baseline with 60 kW engine, 100 Ah battery (validate PSO first)
2. **Validate each module** independently before integration
3. **Sensitivity analysis** to understand lever arms (which variables matter most?)
4. **Narrow bounds iteratively**: Initial [-∞, +∞], then refine around optimum
5. **Visualize aggressively**: Plot every metric, spot check unrealistic values

### For Challenge 2 Success:
1. **Thermodynamic model first**: Get ODE system physically correct (RK4, transient response)
2. **Generate synthetic data**: Degrade each component independently, sweep conditions
3. **Train GPR on diverse scenarios**: Not just cruise, but takeoff, climb, descent, loiter
4. **Uncertainty quantification**: Confidence intervals are your credibility (show them!)
5. **Real-data validation**: Even synthetic data can have blind spots; plot residuals

---

**Generated**: July 2026  
**For**: IIT Indore × HAL Challenge Teams  
**Status**: Ready for competition submission
