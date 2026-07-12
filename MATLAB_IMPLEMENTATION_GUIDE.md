# MATLAB SIMULATION & DESIGN ARCHITECTURE GUIDE
## Hybrid-Electric UAV Propulsion & Turbojet Digital Twin
### IIT Indore × HAL Challenge

---

## EXECUTIVE SUMMARY

This guide provides complete MATLAB implementation architectures for:
- **Challenge 1**: Hybrid-Electric Propulsion Optimization (system-level design)
- **Challenge 2**: Physics-Informed Digital Twin (real-time health monitoring)

Both frameworks emphasize **modularity**, **physics fidelity**, and **computational efficiency** for real-time applications.

---

## PART I: CHALLENGE 1 – HYBRID-ELECTRIC PROPULSION OPTIMIZATION

### 1.1 Architecture Overview

**Core Philosophy**: Component-based, separable design allowing parallel development and testing.

```
┌─────────────────────────────────────────────────────────────┐
│                   MISSION OPTIMIZER                          │
│  (PSO / GA / Gradient-based)                                │
└──────────────────────────┬──────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
    ┌─────────┐    ┌─────────────┐   ┌──────────────┐
    │ AERO    │    │ PROPULSION  │   │ BATTERY/ELEC │
    │ MODULE  │    │ MODULE      │   │ MODULE       │
    └────┬────┘    └──────┬──────┘   └──────┬───────┘
         │                │                 │
         │  drag_force()  │  engine_sfc()   │ battery_soc()
         │  power_req()   │  fuel_flow()    │ motor_eff()
         │                │                 │
         └────────────────┬─────────────────┘
                          │
                   ┌──────▼──────┐
                   │  SIMULATOR  │
                   │  (ODE time  │
                   │   step loop)│
                   └──────┬──────┘
                          │
        ┌─────────────────┼────────────────┐
        │                 │                │
        ▼                 ▼                ▼
    Endurance        Fuel Burn       Battery SoC
    (maximize)       (minimize)      (constraints)
```

### 1.2 Aerodynamic Module (`AerodynamicModel`)

**Purpose**: Compute power required for level flight across mission envelope.

**Key Methods**:
- `power_required(alt, V, W)` → Power in Watts
- `drag_force(alt, V, W)` → Drag in Newtons
- `generate_power_curve(alt, W)` → P(V) lookup table

**Physics**:
```
Drag: D = 0.5 * ρ * V² * S * Cd
  where Cd = Cd0 + CL² / (π * e * AR)
  
Power: P = D * V
```

**Key Tuning Parameters**:
- `Cd0_cruise` (0.020–0.035): Parasitic drag coefficient
- `aspect_ratio` (8–12): Wing aspect ratio
- `oswald_efficiency` (0.85–0.95): Span efficiency

**Typical Output**: P_cruise ~ 15–25 kW for 1000 kg UAV at 250 km/h, 5 km altitude.

**Testing Strategy**:
```matlab
% Validate against published aircraft data
% Example: Compare to Regional Air Taxi studies
aero = AerodynamicModel(12, 8.5, 0.025);

% Power curve @ 5 km altitude
V_range = 40:5:80;  % m/s
P_range = arrayfun(@(V) aero.power_required(5000, V, 10000*9.81, 'cruise'), V_range);

plot(V_range, P_range);  % Should show characteristic U-curve (minimum at best L/D)
```

### 1.3 Turboshaft Engine Module (`TurboshaftEngine`)

**Purpose**: Model engine power output, fuel consumption, efficiency across throttle & altitude.

**Key Methods**:
- `query_performance(throttle_pct, alt)` → (Power_kW, SFC_kg/kWh, eta_thermal)
- `fuel_flow(throttle_pct, alt, dt_sec)` → fuel mass consumed (kg)

**Physics**:
```
Power available: P = P_rated * (throttle/100) * (ρ/ρ_sl)^0.5

SFC (Specific Fuel Consumption):
  SFC = 0.2 + 0.3 * (100 - throttle) / 100  (kg/kWh)
  Better SFC at higher throttle (higher efficiency)
  
Fuel flow rate: ṁ_fuel (kg/hr) = P_out (kW) * SFC (kg/kWh)
```

**Implementation Details**:
- **2D LUT (Look-Up Table)**: throttle % vs. altitude
  - Grid: 11 throttle points (0–100%), 11 altitude points (0–10 km)
  - Stored as `obj.power_map`, `obj.sfc_map`, `obj.efficiency_map`
  - Interpolation: `interp2()` for smooth queries
  
**Typical Performance**:
- Rated power: 60 kW @ sea level, full throttle
- Power reduction: ~15% at 10 km altitude (density effect)
- SFC: 0.20–0.35 kg/kWh (better at full throttle)
- Thermal efficiency: 30–35%

**Testing**:
```matlab
engine = TurboshaftEngine(60, 30000);

% Query @ cruise: 80% throttle, 5 km altitude
[P, SFC, eta] = engine.query_performance(80, 5000);
% Expected: P ≈ 48 kW, SFC ≈ 0.24 kg/kWh, eta ≈ 33%
```

### 1.4 Battery & Motor Module (`BatteryPack`, `ElectricMotor`)

**BatteryPack** methods:
- `discharge_step(soc, power_W, voltage_V, dt_sec)` → new SoC
- `check_feasibility(mission_energy_Wh)` → (feasible, remaining_SoC)

**Key Features**:
- **Peukert Effect**: Higher discharge rates reduce effective capacity
  - `Peukert_k` ≈ 0.95–1.05 (exponent in capacity-rate relationship)
  - Implementation: `C_eff = C_nominal * (I/I_rated)^(1-k)`
  
- **Safe Operating Region**:
  - LiPo: 20–100% SoC (below 20% causes damage)
  - LiFePO4: 10–100% SoC (more robust)

**ElectricMotor** methods:
- `motor_efficiency(power_kw, speed_rpm)` → efficiency (0–1)
- `electrical_input(power_mech_W, speed_rpm)` → electrical power (W)

**Efficiency Map** (typical BLDC):
- Peak: ~95% at 80–100% rated power
- Part-load: ~70–85% at 20–50% power
- Low-speed penalty: ~5–10% efficiency drop

**Typical Sizing**:
- Battery capacity: 80–150 Ah (48V nominal) → 4–7 kWh energy
- Motor rating: 30–50 kW (boosting during takeoff/climb)
- Max discharge C-rate: 2–3C (for brief peaks)

### 1.5 Mission Simulator (`MissionSimulator`) – CORE ENGINE

**Purpose**: Time-step propagation of aircraft state through mission phases.

**State Vector**:
```
x(t) = [
  weight (kg),
  fuel_mass (kg),
  battery_soc (0–1),
  altitude (m),
  speed (m/s)
]
```

**Mission Phases** (example):
1. **Takeoff** (0 m, 30 m/s, 60 s): Max power, shallow climb
2. **Climb** (0 → 5000 m, 40 m/s, 600 s): Hybrid power (60% thermal + 40% electric)
3. **Cruise** (5000 m, 60 m/s, 7200 s): Mostly thermal, battery charges
4. **Loiter** (5000 m, 45 m/s, 1800 s): Endurance pattern
5. **Descent** (5000 → 0 m, 35 m/s, 300 s): Glide with idle engine

**Time-Step Algorithm** (Δt = 10 s typical):

```
FOR each phase:
  FOR each time step:
    1. Calculate power required: P_aero = power_required(alt, V, W)
    
    2. Power distribution (control strategy):
       IF "thermal_dominant":
         P_thermal = min(P_aero, P_engine_max)
         P_electric = max(0, P_aero - P_thermal)
       IF "hybrid_blending":
         P_thermal = 0.6 * P_aero
         P_electric = 0.4 * P_aero
    
    3. Update engine state:
       fuel_consumed = engine.fuel_flow(throttle, alt, Δt)
       SFC, efficiency = engine.query_performance(throttle, alt)
    
    4. Update battery state:
       SoC_new = battery.discharge_step(SoC, P_electric, V_nominal, Δt)
       IF SoC_new < SoC_min: INFEASIBLE
    
    5. Update mass:
       W_new = (m_empty + m_fuel - fuel_consumed + m_battery) * g
    
    6. Store telemetry:
       log(t, alt, speed, weight, P_aero, P_thermal, P_electric, SoC)
END
```

**Feasibility Checks**:
- Fuel remaining: > 10% reserve for landing
- Battery SoC: > 20% minimum safe threshold
- Weight: Must remain within MTOW
- All mission phases completed

**Output Metrics**:
- **Endurance** (hours): Total mission time
- **Specific Range** (km/kg fuel): Distance per unit fuel
- **Average Efficiency**: (P_thermal + P_electric) / Total available
- **Mission Feasible**: Boolean

**Example Output**:
```
Endurance: 5.2 hours
Fuel Burned: 145.3 kg (96% of capacity)
Specific Range: 1.8 km/kg
Average Power: 18.2 kW (thermal), 4.1 kW (electric)
Mission Feasible: 1 (YES)
```

### 1.6 Optimization Framework (`ParticleSwarmOptimizer`)

**Design Variables** (D-dimensional):
```
x = [
  engine_power_kw,              (40–80 kW)
  battery_capacity_Ah,          (50–200 Ah)
  num_motors,                   (1–4)
  power_split_strategy,         (enum: thermal_dominant, hybrid, electric)
  generator_power_kw            (10–50 kW)
]
```

**Objective Functions** (weighted):
```
J = w1 * endurance_penalty + w2 * weight_penalty + w3 * feasibility_penalty

endurance_penalty = MAX(0, 5 - endurance_hours) / 5
weight_penalty = MAX(0, MTOW - mtow_available) / 500
feasibility_penalty = ∞ if mission_infeasible
```

**PSO Algorithm**:
```
Initialize swarm: X (N_particles × D)
Initialize velocities: V

FOR iter = 1:N_iterations:
  FOR each particle i:
    Evaluate fitness: f_i = objective(X_i)
    Update pbest (personal best) if f_i better
    Update gbest (global best) if f_i better
    
    Update velocity:
      V_i = w*V_i + c1*r1*(pbest_i - X_i) + c2*r2*(gbest - X_i)
    
    Update position:
      X_i = X_i + V_i
    
    Enforce bounds: X_i = max(lb, min(ub, X_i))
END
```

**PSO Parameters**:
- Swarm size: 30–50 particles
- Iterations: 50–100 (typically converges in ~50)
- Inertia weight: w = 0.7
- Cognitive: c1 = 1.5, Social: c2 = 1.5

**Expected Optimization Results**:
- Initial (baseline): Endurance 4.2 hrs, Weight 1000 kg
- Optimized: Endurance 5.5 hrs, Weight 995 kg
- Improvement: +31% endurance, same MTOW constraint

---

## PART II: CHALLENGE 2 – PHYSICS-INFORMED DIGITAL TWIN

### 2.1 Architecture Overview

**Core Concept**: Real-time estimation of engine state & health from limited measurements using physics-informed Kalman filtering + surrogate modeling.

```
┌────────────────────────────────────────────────────┐
│            MEASUREMENTS (Real-time)                 │
│  RPM, Fuel flow, P2, P3, P4, T3, T4                │
└──────────────────┬─────────────────────────────────┘
                   │
        ┌──────────▼──────────┐
        │ EXTENDED KALMAN     │
        │ FILTER (EKF)        │
        │                     │
        │ Predicts engine     │
        │ state x(t)          │
        └──────────┬──────────┘
                   │
        ┌──────────▼──────────────────┐
        │  STATE VECTOR               │
        │  [P2, T2, P3, T3, P4, T4, N]│
        │  Hidden: Efficiency drops   │
        └──────────┬──────────────────┘
                   │
        ┌──────────┴──────────┬──────────┐
        │                     │          │
        ▼                     ▼          ▼
    ┌─────────┐         ┌──────────┐  ┌──────────┐
    │ PHYSICS │         │SURROGATE │  │ HEALTH   │
    │ MODEL   │         │MODEL(GPR)│  │INDICATORS│
    │ (ODE)   │         │ (fast)   │  │ (HI)     │
    └─────────┘         └──────────┘  └────┬─────┘
                                            │
                        ┌───────────────────┘
                        │
                        ▼
            ┌──────────────────────┐
            │  HEALTH OUTPUTS      │
            │ ┌──────────────────┐ │
            │ │HI_compressor     │ │
            │ │HI_turbine        │ │
            │ │HI_combustor      │ │
            │ │HI_overall        │ │
            │ │Confidence bands  │ │
            │ │Degradation trend │ │
            │ └──────────────────┘ │
            └──────────────────────┘
```

### 2.2 Thermodynamic Model (`TurbojetsThermodynamicModel`)

**State-Space Formulation** (7 states):
```
States: x = [P2, T2, P3, T3, P4, T4, N]ᵀ

Measurements: z = [P2, P3, P4, T3, T4, mfr]ᵀ
```

**Governing Equations** (physics-based ODEs):

**Stage 1: Compressor (P2, T2)**
```
Isentropic compression:
  T2_ideal = T0 * (P2/P0)^((γ-1)/γ)
  
Actual temperature (efficiency loss):
  T2_actual = T0 + (T2_ideal - T0) / η_comp
  
Dynamics:
  dP2/dt = K_comp * (ṁ/ṁ_design) * N - 10000 * (P2 - P0*πc*N)
  dT2/dt = 100 * (T2_actual - T2)
```

**Stage 2: Combustor (P3, T3)**
```
Fuel heat release:
  Q_fuel = ṁ_fuel * q_fuel (Joules/s)
  
Temperature rise:
  dT3/dt = (η_comb * Q_fuel) / (ṁ * cp) - 50 * (T3 - T2_actual)
  
Pressure drop (friction):
  dP3/dt = -5000 * (P3 - P2 * 0.97)
```

**Stage 3: Turbine (P4, T4)**
```
Isentropic expansion:
  T4_ideal = T3 * (P4/P3)^((γ-1)/γ)
  
Actual (efficiency loss from erosion/fouling):
  T4_actual = T3 - (T3 - T4_ideal) * η_turb
  
Dynamics:
  dP4/dt = K_turb * (ṁ/ṁ_design) * N - 10000 * (P4 - P2*0.5)
  dT4/dt = 80 * (T4_actual - T4)
```

**Shaft Speed (N)**:
```
Power balance:
  Power_turbine = ṁ * cp * (T3 - T4_actual)
  Power_compressor = ṁ * cp * (T2_actual - T0)
  
Speed dynamics:
  dN/dt = 2.0 * (P_turb - P_comp) / (P_comp + ε) - 0.5 * N
```

**Health Degradation Integration**:
- Compressor fouling: `η_comp → η_comp * health_comp`
- Turbine erosion: `η_turb → η_turb * health_turb`
- Combustor efficiency: Independent degradation

### 2.3 Extended Kalman Filter (`ExtendedKalmanFilter`)

**Purpose**: Estimate hidden engine state (efficiency losses, degradation) from available measurements.

**EKF Cycle**:

**1. PREDICT** (time update):
```
x_hat_minus = x_hat + f(x_hat, u) * Δt      [RK4 integration]
P_minus = F*P*F' + Q                         [Covariance propagation]

where F = ∂f/∂x (Jacobian, computed numerically)
```

**2. MEASURE** (measurement available):
```
z_meas = [P2, P3, P4, T3, T4, mfr] (noisy measurements)
z_pred = H * x_hat_minus                    [Predicted measurement]
```

**3. UPDATE** (measurement correction):
```
y = z_meas - z_pred                         [Innovation]
S = H*P_minus*H' + R                        [Innovation covariance]
K = P_minus*H' / S                          [Kalman gain]

x_hat_plus = x_hat_minus + K*y              [State correction]
P_plus = (I - K*H)*P_minus                  [Covariance update]
```

**Noise Covariances**:
```
Q (process noise):     diag([1e6, 1e3, 1e6, 1e3, 1e6, 1e3, 1e-2])
                       → Pressures: ±1000 Pa, Temperatures: ±30 K, Speed: ±0.1

R (measurement noise): diag([5e4, 5e4, 5e4, 10, 10, 0.5])
                       → Pressures: ±500 Pa, Temps: ±10 K, MFR: ±0.5 kg/s
```

**Health Estimation** (post-state-estimate):
```matlab
health_comp = T2_actual / T2_nominal          (ratio of isentropic efficiency)
health_turb = (η_turb_actual) / η_turb_nominal
health_comb = dT_actual / dT_nominal
```

### 2.4 Surrogate Model: Gaussian Process Regression (GPR)

**Purpose**: Fast (O(N) after training) health index prediction with uncertainty quantification.

**Training Phase**:
```
Dataset: (X_train, y_train)
  X ∈ ℝ^(N×D): Features [ṁ, fuel_flow, P2, P3, P4, T3, T4]
  y ∈ ℝ^N: Target [health_comp, health_turb, health_comb]

Training: Learn kernel hyperparameters (length scales, signal variance)
  - Maximize marginal likelihood: log p(y | X, θ)
  - Compute K = K_prior + σ_n² * I
  - Factor: K = L*L' (Cholesky)
  - Store: α = L^{-T} * L^{-1} * y (for fast prediction)
```

**Kernel** (Squared Exponential / RBF):
```
k(x1, x2) = σ_f² * exp(-0.5 * Σ_d (x1_d - x2_d)² / l_d²)

where l_d = length scale per dimension (learned)
      σ_f² = signal variance (learned)
```

**Prediction** (O(N) dot products):
```
For test point x*:
  μ(x*) = Σ_i α_i * k(x_i, x*)           [Mean prediction]
  σ²(x*) = k(x*, x*) - k*ᵀ * K^{-1} * k* [Variance]
```

**Advantages**:
✓ Naturally provides uncertainty (confidence intervals)
✓ Small training set (200–500 samples) sufficient
✓ Transparent: Easy to interpret what features matter
✓ Bayesian: Principled handling of missing data

**Training Convergence**:
- 200 samples: ~50 iterations (minutes on CPU)
- Validation RMSE: ~0.02–0.05 on [0, 1] health scale
- Prediction latency: <1 ms per sample

### 2.5 Health Indicators (`HealthIndicatorCalculator`)

**Component Health Indices** (0 = failed, 1 = healthy):

**Compressor Health**:
```
HI_comp = η_actual / η_nominal
        = (T2_ideal - T0) / (T2_actual - T0)
        
Interpretation:
  1.0  → No degradation
  0.95 → 5% efficiency loss (minor fouling)
  0.85 → 15% efficiency loss (significant fouling)
  0.75 → 25% efficiency loss (major wear, maintenance needed)
```

**Turbine Health**:
```
HI_turb = η_actual / η_nominal
        = (T3 - T4) / (T3 - T4_ideal)
        
Triggers replacement when < 0.80 (20% efficiency loss from blade erosion)
```

**Combustor Health**:
```
HI_comb = ΔT_actual / ΔT_nominal
        = (T3 - T2) / ((T3 - T2)_design * η_comb)
        
Robust to small variations; mainly useful for combustor efficiency degradation
```

**Overall Health Index** (weighted):
```
HI_overall = 0.40 * HI_comp + 0.35 * HI_turb + 0.25 * HI_comb

Maintenance thresholds:
  HI > 0.95     : Healthy, routine monitoring
  0.90 > HI > 0.95: Monitor closely, schedule maintenance window
  0.85 > HI > 0.90: Maintenance required within next 50 hours
  HI < 0.85     : URGENT, ground aircraft
```

### 2.6 Uncertainty Quantification

**Sources of Uncertainty**:
1. **Aleatoric** (irreducible): Sensor noise
2. **Epistemic** (reducible): Model uncertainty, limited training data

**Confidence Intervals** (from GPR):
```
95% CI: μ(x*) ± 1.96 * σ(x*)

Interpretation:
  Narrow band → High confidence in prediction
  Wide band   → High uncertainty, data collection needed
```

**Predictive Variance Decomposition**:
```matlab
var_epistemic = var_gpr;              % Model uncertainty
var_aleatoric = sigma_n^2;            % Sensor noise
var_total = var_epistemic + var_aleatoric;
```

**Degradation Projection**:
```
From health trends over time:
  HI(t) = HI_0 - λ * t  (linear degradation assumption)
  
Time-to-failure: T_fail = (HI_threshold - HI_0) / λ
  Example: HI drops from 1.0 to 0.85 in 1000 hours
           λ = 0.15 / 1000 = 1.5e-4 /hour
           Time to HI=0.8: (0.8 - 1.0) / (-1.5e-4) = 1333 hours
```

---

## IMPLEMENTATION CHECKLIST

### Challenge 1: Hybrid-Electric Propulsion
- [ ] Aerodynamic module: Validate power curve against published aircraft
- [ ] Engine SFC maps: Cross-check with turboshaft manufacturer data (e.g., Rolls-Royce M250)
- [ ] Battery model: Verify Peukert coefficients with Li-ion datasheets
- [ ] Mission simulator: Walk through one complete mission by hand (spreadsheet)
- [ ] PSO optimizer: Test on 2D toy problem first (e.g., Rosenbrock function)
- [ ] Dashboard: Real-time animation of mission profile
- [ ] Sensitivity analysis: Tornado chart of design variables vs. endurance

### Challenge 2: Digital Twin
- [ ] Thermodynamic model: Validate steady-state performance against engine model
- [ ] EKF convergence: Ensure filter stabilizes within 5–10 seconds on synthetic data
- [ ] GPR training: Plot convergence of training error vs. sample size
- [ ] Health indices: Verify against known degradation scenarios
- [ ] Uncertainty quantification: Confirm 95% CI captures ~95% of test points
- [ ] Generalization: Test on engines NOT in training set (interpolation capability)
- [ ] Real-time performance: Confirm <10 ms cycle time on target hardware

---

## EXECUTION WORKFLOW

### Challenge 1: Optimization Loop
```matlab
% 1. Setup
aero = AerodynamicModel(...);
engine = TurboshaftEngine(...);
battery = BatteryPack(...);
motor = ElectricMotor(...);
simulator = MissionSimulator(aero, engine, battery, motor, 10);

% 2. Baseline simulation
baseline = struct('engine_power_kw', 60, 'battery_capacity_Ah', 100, ...);
results_baseline = simulator.run_simulation(baseline);

% 3. Optimize
optimizer = ParticleSwarmOptimizer(40, 100);
[best_design, best_fitness] = optimizer.optimize(lb, ub, objective_func);

% 4. Visualize
plot_results(results_baseline);
plot_trades(pareto_front);
```

### Challenge 2: Health Monitoring Loop
```matlab
% 1. Load data & train
data = load_dataset('synthetic_turbojet_data.csv');
gpr_comp = train_gpr(data.X, data.health_comp);

% 2. Real-time loop (on vehicle)
for k = 1:N_measurements
    z_meas = read_sensors();
    ekf = ekf.predict(u_k, dt);
    ekf = ekf.update(z_meas);
    
    [hi_comp, hi_turb] = estimate_health(ekf.x_hat);
    [hi_pred, ci] = gpr_comp.predict(feature_vector);
    
    if hi_pred < 0.85
        alert("MAINTENANCE REQUIRED");
    end
end
```

---

## TROUBLESHOOTING TIPS

### Challenge 1 Issues
| Issue | Cause | Fix |
|-------|-------|-----|
| Optimizer not converging | Bounds too large | Narrow design space (iterative refinement) |
| Negative weight in simulator | Fuel underestimated | Increase fuel capacity or reduce payload |
| Battery SoC never charges | Power split strategy wrong | Check if P_electric ever negative (charging phase) |
| Unrealistic endurance | Aero drag too low | Validate Cd0 with CFD/wind tunnel |

### Challenge 2 Issues
| Issue | Cause | Fix |
|-------|-------|-----|
| EKF diverges | Measurement noise too high | Increase R (sensor noise covariance) |
| GPR predictions negative | Training data range too limited | Augment dataset with boundary cases |
| Confidence intervals too wide | Too few training samples | Collect 500+ samples for robust UQ |
| Health indicators invert | Degradation trends crossed | Use ensemble of models, not single HI |

---

## KEY PERFORMANCE METRICS

### Challenge 1
- **Optimization Convergence**: <100 iterations for 5D design space
- **Simulation Speed**: 50 ms per full mission (7+ hours)
- **Parallelization**: N particles × M fitness evals = 40×100 = 4000 simulations (~200 s)

### Challenge 2
- **EKF Convergence**: <10 seconds to <5% state error
- **GPR Prediction Latency**: <1 ms per sample (suitable for real-time)
- **Health Index Accuracy**: RMSE < 0.05 on [0, 1] scale
- **Uncertainty Coverage**: 95% CI captures 92–98% of test errors

---

## REFERENCES & FURTHER READING

**Aerodynamics**:
- Raymer, D. P. (2012). *Aircraft Design: A Conceptual Approach*. AIAA Education Series.
- Loftin, L. K. (1985). *Quest for Performance: The Evolution of Modern Aircraft*. NASA SP-468.

**Propulsion**:
- Walsh, P. P., & Fletcher, P. (2004). *Gas Turbine Performance* (2nd ed.). Blackwell Science.
- Heywood, J. B. (1988). *Internal Combustion Engine Fundamentals*. McGraw-Hill.

**Control & Estimation**:
- Kalman, R. E. (1960). "A new approach to linear filtering and prediction problems." ASME J. Basic Eng., 82(1), 35–45.
- Rasmussen, C. E., & Williams, C. K. (2006). *Gaussian Processes for Machine Learning*. MIT Press.

**Hybrid-Electric Systems**:
- Strack, J. (2017). "Development of hybrid-electric aircraft." AIAA Paper 2017–1131.

**Digital Twins**:
- Tao, F., et al. (2018). "Digital twin in industry." *J. Ambient Intell. Humanized Comput.*, 10, 2405–2415.

---

## APPENDIX: MATLAB/PYTHON BRIDGING

For challenges requiring machine learning (PINN training):

**Option 1: TensorFlow/PyTorch via Python Engine**
```matlab
% In MATLAB:
py.importlib.import_module('train_pinn');
pinn_model = py.train_pinn.fit(X_train, y_train);

% Prediction:
predictions = py.train_pinn.predict(pinn_model, X_test);
```

**Option 2: ONNX Export** (recommended for deployment)
```python
# Train PINN in PyTorch, export to ONNX
torch.onnx.export(model, dummy_input, "pinn_model.onnx")
```

```matlab
% Load in MATLAB
net = importNetworkFromONNX("pinn_model.onnx");
predictions = predict(net, X_test);
```

---

**Last Updated**: July 2026  
**Version**: 1.0  
**Maintainer**: IIT Indore Aerospace Team
