# COMPLETE TESTING & DEPLOYMENT GUIDE
## Hybrid-Electric Propulsion & Digital Twin Challenges

---

## PART 1: CHALLENGE 1 - TESTING & VALIDATION

### 1.1 Unit Testing Framework

#### Test: Aerodynamic Module

```matlab
% Run: test_aerodynamic_model.m

function test_aerodynamic_model()
    % Test aerodynamic power curves against known aircraft data
    
    aero = AerodynamicModel(12, 8.5, 0.025);
    
    % Test 1: Power curve shape (should have minimum at best L/D speed)
    V_range = 30:5:80;  % m/s
    P_range = arrayfun(@(V) aero.power_required(5000, V, 10000*9.81, 'cruise'), V_range);
    
    [P_min, idx_min] = min(P_range);
    V_optimal = V_range(idx_min);
    
    assert(V_optimal >= 50 && V_optimal <= 70, 'Optimal cruise speed out of range');
    assert(P_min > 10 && P_min < 40, 'Minimum power out of range');
    fprintf('✓ Power curve: V_opt=%.0f m/s, P_min=%.1f kW\n', V_optimal, P_min/1000);
    
    % Test 2: Altitude effect (power increases at lower altitude due to higher drag coefficient)
    P_sea = aero.power_required(0, 60, 10000*9.81, 'cruise');
    P_alt = aero.power_required(5000, 60, 10000*9.81, 'cruise');
    
    ratio = P_alt / P_sea;
    assert(ratio < 1.1 && ratio > 0.9, 'Altitude effect unrealistic');
    fprintf('✓ Altitude effect: P(5km)/P(SL) = %.3f\n', ratio);
    
    % Test 3: Weight effect (quadratic relationship through CL)
    W_light = 8000 * 9.81;
    W_heavy = 10000 * 9.81;
    
    P_light = aero.power_required(5000, 60, W_light, 'cruise');
    P_heavy = aero.power_required(5000, 60, W_heavy, 'cruise');
    
    ratio = P_heavy / P_light;
    assert(ratio > 1.1 && ratio < 1.5, 'Weight effect not quadratic');
    fprintf('✓ Weight effect: P(10t)/P(8t) = %.3f (expected ~1.25)\n', ratio);
end
```

#### Test: Engine Module

```matlab
function test_turboshaft_engine()
    % Test engine performance maps
    
    engine = TurboshaftEngine(60, 30000);
    
    % Test 1: Maximum power at sea level, full throttle
    [P_max, ~, ~] = engine.query_performance(100, 0);
    assert(P_max >= 59 && P_max <= 61, 'Max power not 60 kW');
    fprintf('✓ Max power at SL: %.1f kW\n', P_max);
    
    % Test 2: Power decreases with altitude (density effect)
    [P_sl, ~, ~] = engine.query_performance(100, 0);
    [P_alt, ~, ~] = engine.query_performance(100, 5000);
    
    reduction = (P_sl - P_alt) / P_sl;
    assert(reduction > 0.1 && reduction < 0.25, 'Altitude effect unrealistic');
    fprintf('✓ Altitude power loss: %.1f%%\n', reduction*100);
    
    % Test 3: SFC improves at higher throttle
    [~, SFC_low, ~] = engine.query_performance(20, 5000);
    [~, SFC_high, ~] = engine.query_performance(100, 5000);
    
    assert(SFC_high < SFC_low, 'SFC should improve at higher throttle');
    fprintf('✓ SFC trend: %.3f (20%%) → %.3f (100%%) kg/kWh\n', SFC_low, SFC_high);
end
```

#### Test: Battery Module

```matlab
function test_battery_pack()
    % Test battery discharge and Peukert effect
    
    battery = BatteryPack('LiPo', 48, 100, 0.95);
    
    % Test 1: Nominal capacity
    assert(battery.capacity_Ah == 100, 'Capacity mismatch');
    assert(battery.energy_Wh == 4800, 'Energy mismatch');
    fprintf('✓ Battery: 100 Ah, 4800 Wh\n');
    
    % Test 2: Peukert effect (higher discharge rate reduces effective capacity)
    soc = 1.0;
    
    % Low current discharge
    I_low = 10;  % 0.1C rate
    energy_consumed_low = I_low * (battery.capacity_Ah / I_low) * battery.nominal_voltage;
    
    % High current discharge (Peukert penalty)
    I_high = 100;  % 1C rate
    c_rate = I_high / battery.capacity_Ah;
    peukert_penalty = c_rate ^ (1 - battery.peukert_k);
    energy_consumed_high = I_high * (battery.capacity_Ah / I_high / peukert_penalty) * battery.nominal_voltage;
    
    assert(energy_consumed_high < energy_consumed_low, 'Peukert effect reversed');
    fprintf('✓ Peukert effect: High-rate discharge reduces capacity\n');
    
    % Test 3: Safe operating range
    soc_unsafe = battery.discharge_step(0.15, 1000, 48, 10);
    assert(soc_unsafe == battery.soc_min, 'Should clamp at minimum SoC');
    fprintf('✓ Safe SoC range: [%.0f%%, 100%%]\n', battery.soc_min*100);
end
```

#### Test: Motor Module

```matlab
function test_electric_motor()
    % Test motor efficiency map
    
    motor = ElectricMotor(50, 5000);
    
    % Test 1: Peak efficiency at rated power
    eta_rated = motor.motor_efficiency(50, 5000);
    assert(eta_rated > 0.90 && eta_rated < 0.97, 'Rated efficiency unrealistic');
    fprintf('✓ Motor efficiency at rated: %.1f%%\n', eta_rated*100);
    
    % Test 2: Efficiency drops at part-load
    eta_part = motor.motor_efficiency(10, 2500);
    assert(eta_part < eta_rated, 'Efficiency should drop at part-load');
    fprintf('✓ Part-load efficiency: %.1f%% (rated: %.1f%%)\n', ...
        eta_part*100, eta_rated*100);
end
```

### 1.2 Integration Testing

#### Mission Simulator Validation

```matlab
function test_mission_simulator()
    % Run baseline mission and check energy balance
    
    % Setup
    aero = AerodynamicModel(12, 8.5, 0.025);
    engine = TurboshaftEngine(60, 30000);
    battery = BatteryPack('LiPo', 48, 100, 0.95);
    motor = ElectricMotor(50, 5000);
    simulator = MissionSimulator(aero, engine, battery, motor, 10);
    
    % Simple test mission: 1 hour cruise
    mission.phases(1).name = 'cruise';
    mission.phases(1).altitude = 5000;
    mission.phases(1).speed = 60;
    mission.phases(1).duration = 3600;
    
    simulator = simulator.setup_mission(mission);
    
    % Run simulation
    design.engine_power_kw = 60;
    design.battery_capacity_Ah = 100;
    design.num_motors = 2;
    design.power_split_strategy = 'thermal_dominant';
    
    results = simulator.run_simulation(design);
    
    % Validation checks
    fprintf('Mission Simulator Test:\n');
    fprintf('  Total time: %.2f hours\n', results.endurance_hours);
    fprintf('  Fuel burned: %.1f kg\n', results.fuel_burned);
    fprintf('  Final SoC: %.1f%%\n', results.soc(end));
    
    % Energy conservation check
    energy_aero = sum(results.P_aero) * simulator.dt / 3600;  % kWh
    energy_thermal = sum(results.P_engine) * simulator.dt / 3600;
    energy_electric = sum(results.P_electric) * simulator.dt / 3600;
    energy_total = energy_thermal + energy_electric;
    
    ratio = energy_aero / energy_total;
    assert(ratio > 0.95 && ratio < 1.05, 'Energy balance error > 5%');
    fprintf('  Energy balance: P_aero / (P_thermal + P_elec) = %.3f\n', ratio);
    fprintf('✓ Mission simulator validated\n\n');
end
```

### 1.3 Sensitivity Analysis

```matlab
function sensitivity_analysis()
    % Tornado chart: rank design variable importance
    
    % Baseline
    baseline.engine_power_kw = 60;
    baseline.battery_capacity_Ah = 100;
    baseline.num_motors = 2;
    baseline.power_split_strategy = 'thermal_dominant';
    
    % Setup
    aero = AerodynamicModel(12, 8.5, 0.025);
    engine = TurboshaftEngine(60, 30000);
    battery = BatteryPack('LiPo', 48, 100, 0.95);
    motor = ElectricMotor(50, 5000);
    simulator = MissionSimulator(aero, engine, battery, motor, 10);
    
    mission = Mission_7hr();
    simulator = simulator.setup_mission(mission);
    
    % Baseline result
    results_base = simulator.run_simulation(baseline);
    base_endurance = results_base.endurance_hours;
    
    % Sensitivity: vary each parameter ±20%
    perturbations = [-0.2, -0.1, 0.1, 0.2];
    
    sensitivity = struct('engine', [], 'battery', [], 'motors', []);
    
    for delta = perturbations
        % Engine power
        design = baseline;
        design.engine_power_kw = design.engine_power_kw * (1 + delta);
        results = simulator.run_simulation(design);
        sensitivity.engine = [sensitivity.engine, results.endurance_hours];
        
        % Battery capacity
        design = baseline;
        design.battery_capacity_Ah = design.battery_capacity_Ah * (1 + delta);
        simulator.battery = BatteryPack('LiPo', 48, design.battery_capacity_Ah, 0.95);
        results = simulator.run_simulation(design);
        sensitivity.battery = [sensitivity.battery, results.endurance_hours];
        
        % Motor count
        design = baseline;
        design.num_motors = round(design.num_motors * (1 + delta));
        design.num_motors = max(1, min(4, design.num_motors));
        results = simulator.run_simulation(design);
        sensitivity.motors = [sensitivity.motors, results.endurance_hours];
    end
    
    % Tornado chart
    figure;
    bar_width = 0.2;
    
    engine_range = max(sensitivity.engine) - min(sensitivity.engine);
    battery_range = max(sensitivity.battery) - min(sensitivity.battery);
    motors_range = max(sensitivity.motors) - min(sensitivity.motors);
    
    variables = {'Engine\nPower', 'Battery\nCapacity', 'Motor\nCount'};
    ranges = [engine_range, battery_range, motors_range];
    
    [~, idx_sort] = sort(ranges, 'descend');
    
    barh(ranges(idx_sort));
    set(gca, 'YTickLabel', variables(idx_sort));
    xlabel('Endurance Range (hours)');
    title('Sensitivity Tornado Chart');
    grid on;
    
    fprintf('Sensitivity Analysis:\n');
    fprintf('  Engine power: ±%.2f hours\n', engine_range);
    fprintf('  Battery capacity: ±%.2f hours\n', battery_range);
    fprintf('  Motor count: ±%.2f hours\n', motors_range);
    fprintf('✓ Most sensitive variable: %s\n\n', variables{idx_sort(1)});
end
```

---

## PART 2: CHALLENGE 2 - TESTING & VALIDATION

### 2.1 Unit Testing: Thermodynamic Model

```matlab
function test_thermodynamic_model()
    % Validate ODE system against known thermodynamic relations
    
    thermo = TurbojetsThermodynamicModel();
    
    % Test steady-state performance
    u.mfr = 50;
    u.T_ambient = 288.15;
    u.P_ambient = 101325;
    u.fuel_flow = 1.0;
    u.health_comp = 1.0;
    u.health_turb = 1.0;
    u.health_comb = 1.0;
    
    x0 = [101325*5; 400; 101325*15; 900; 101325*3; 450; 0.8];
    
    [t_sim, x_sim] = ode45(@(t, x) thermo.state_equations(t, x, u), ...
        linspace(0, 100, 1000), x0);
    
    x_ss = x_sim(end, :)';
    
    % Test 1: Steady-state (derivatives should be near zero)
    dxdt_ss = thermo.state_equations(0, x_ss, u);
    norm_dxdt = norm(dxdt_ss);
    
    assert(norm_dxdt < 100, 'Model did not converge to steady-state');
    fprintf('✓ Convergence: ||dxdt|| = %.2f (target: < 100)\n', norm_dxdt);
    
    % Test 2: Pressure ratio compressor
    P0 = u.P_ambient;
    P2 = x_ss(1);
    pr_comp = P2 / P0;
    
    assert(pr_comp > 4.5 && pr_comp < 5.5, 'Compressor pressure ratio out of range');
    fprintf('✓ Compressor PR: %.2f (target: 5.0)\n', pr_comp);
    
    % Test 3: Temperature rise through combustor
    T3 = x_ss(4);
    T2 = x_ss(2);
    dT_combustor = T3 - T2;
    
    assert(dT_combustor > 400 && dT_combustor < 700, 'Combustor temp rise out of range');
    fprintf('✓ Combustor ΔT: %.0f K\n', dT_combustor);
    
    % Test 4: Performance metrics
    [thrust, sfc, eta] = thermo.compute_performance(x_ss, u);
    
    assert(thrust > 1000 && thrust < 5000, 'Thrust out of range');
    assert(sfc > 0.15 && sfc < 0.5, 'SFC out of range');
    assert(eta > 20 && eta < 40, 'Thermal efficiency out of range');
    
    fprintf('✓ Performance: Thrust=%.0f N, SFC=%.3f kg/kWh, η=%.1f%%\n', ...
        thrust, sfc, eta);
end
```

### 2.2 EKF Convergence Testing

```matlab
function test_ekf_convergence()
    % Verify EKF converges to true state with noisy measurements
    
    thermo = TurbojetsThermodynamicModel();
    ekf = ExtendedKalmanFilter(thermo);
    
    % True input conditions
    u_true.mfr = 50;
    u_true.T_ambient = 288.15;
    u_true.P_ambient = 101325;
    u_true.fuel_flow = 1.0;
    u_true.health_comp = 0.95;
    u_true.health_turb = 0.92;
    u_true.health_comb = 0.98;
    
    % Generate true state trajectory
    x_true = [101325*5; 400; 101325*15; 900; 101325*3; 450; 0.8];
    x_true_trajectory = x_true';
    
    % Noisy measurements
    z_meas_trajectory = [];
    
    % Simulate
    dt = 1;  % 1 second
    for k = 1:100
        % True ODE
        dxdt_true = thermo.state_equations(0, x_true, u_true);
        x_true = x_true + dxdt_true * dt;
        x_true_trajectory = [x_true_trajectory; x_true'];
        
        % Measurement: [P2, P3, P4, T3, T4, mfr]
        z_true = [x_true(1); x_true(3); x_true(5); x_true(4); x_true(6); u_true.mfr];
        z_meas = z_true + randn(6, 1) .* [5e3; 5e3; 5e3; 10; 10; 0.5];
        z_meas_trajectory = [z_meas_trajectory, z_meas];
        
        % EKF step
        ekf = ekf.predict(u_true, dt);
        ekf = ekf.update(z_meas);
    end
    
    % Evaluate convergence
    P2_error = abs(ekf.x_hat(1) - x_true(1)) / x_true(1);
    T3_error = abs(ekf.x_hat(4) - x_true(4)) / x_true(4);
    
    fprintf('EKF Convergence Test:\n');
    fprintf('  P2 error: %.2f%%\n', P2_error*100);
    fprintf('  T3 error: %.2f%%\n', T3_error*100);
    fprintf('  Covariance trace: %.2e\n', trace(ekf.P));
    
    assert(P2_error < 0.05, 'P2 error > 5%');
    assert(T3_error < 0.05, 'T3 error > 5%');
    fprintf('✓ EKF converged\n\n');
end
```

### 2.3 Surrogate Model Validation

```matlab
function test_surrogate_validation()
    % Cross-validation on surrogate model accuracy
    
    thermo = TurbojetsThermodynamicModel();
    
    % Generate synthetic data
    N = 400;
    X = [];
    y_comp = [];
    
    for i = 1:N
        mfr = 30 + (70-30)*rand();
        health_comp = 0.6 + (1.0-0.6)*rand();
        
        u.mfr = mfr;
        u.T_ambient = 288.15;
        u.P_ambient = 101325;
        u.fuel_flow = 1.0;
        u.health_comp = health_comp;
        u.health_turb = 0.95;
        u.health_comb = 0.98;
        
        x0 = [101325*5; 400; 101325*15; 900; 101325*3; 450; 0.8];
        [~, x_sim] = ode45(@(t, x) thermo.state_equations(t, x, u), ...
            linspace(0, 30, 100), x0);
        x_ss = x_sim(end, :)';
        
        X = [X; mfr, 1.0, x_ss(1), x_ss(3), x_ss(5), x_ss(4), x_ss(6)];
        y_comp = [y_comp; health_comp];
    end
    
    % Train GPR
    gpr = GaussianProcessRegressor();
    gpr = gpr.fit(X(1:300, :), y_comp(1:300));
    
    % Test on holdout set
    X_test = X(301:end, :);
    y_test = y_comp(301:end);
    
    [mu, sigma] = gpr.predict(X_test);
    
    % Metrics
    rmse = sqrt(mean((mu - y_test).^2));
    mae = mean(abs(mu - y_test));
    coverage = mean((y_test >= mu - 1.96*sigma) & (y_test <= mu + 1.96*sigma));
    
    fprintf('Surrogate Model Validation:\n');
    fprintf('  RMSE: %.4f\n', rmse);
    fprintf('  MAE: %.4f\n', mae);
    fprintf('  95%% CI coverage: %.1f%% (target: 95%%)\n', coverage*100);
    
    assert(rmse < 0.08, 'RMSE too high');
    assert(coverage > 0.90 && coverage < 0.98, 'Coverage miscalibrated');
    fprintf('✓ Surrogate model validated\n\n');
end
```

---

## PART 3: DEPLOYMENT CHECKLIST

### Challenge 1: Pre-Submission Verification

- [ ] **Physics Validation**
  - [ ] Aerodynamic drag within ±10% of published data
  - [ ] Engine SFC within ±15% of manufacturer specs
  - [ ] Battery capacity matches datasheet
  - [ ] Motor efficiency map realistic (peak > 0.90)

- [ ] **Simulation Accuracy**
  - [ ] Manual trace of one mission phase (spreadsheet validation)
  - [ ] Energy conservation check (P_aero / (P_thermal + P_elec) = 1.00 ± 0.05)
  - [ ] Weight evolution correct (decreases with fuel burn)
  - [ ] Battery SoC never goes below 20% (safe limit)

- [ ] **Optimization Quality**
  - [ ] PSO converges within 100 iterations
  - [ ] Pareto front shows clear trade-offs (endurance vs. weight)
  - [ ] Optimized design outperforms baseline by > 10%
  - [ ] All constraints satisfied (MTOW, fuel reserve, feasibility)

- [ ] **Code Quality**
  - [ ] No hard-coded magic numbers (use constants)
  - [ ] All classes documented with docstrings
  - [ ] Functions have error handling (try-catch)
  - [ ] Reasonable variable names (no single letters except i, j, k)

- [ ] **Documentation**
  - [ ] README with installation, usage, and example
  - [ ] Physics equations cited (Raymer, Walsh & Fletcher)
  - [ ] Design assumptions listed
  - [ ] Sensitivity analysis complete

- [ ] **Visualization**
  - [ ] Mission profile (altitude, speed vs. time)
  - [ ] Power budget (aero requirement, thermal, electric)
  - [ ] Battery SoC trajectory
  - [ ] Fuel consumption
  - [ ] Comparison: baseline vs. optimized

### Challenge 2: Pre-Submission Verification

- [ ] **Physics Validation**
  - [ ] Thermodynamic model converges to steady-state
  - [ ] Compressor PR = 5.0 ± 0.2 at nominal design
  - [ ] Combustor ΔT = 500 ± 100 K
  - [ ] Thermal efficiency = 30–35% at design

- [ ] **EKF Performance**
  - [ ] Converges within 10 seconds on noisy data
  - [ ] State estimation error < 5% on all states
  - [ ] Covariance matrix remains positive definite
  - [ ] Handles sensor dropouts gracefully

- [ ] **Surrogate Model Quality**
  - [ ] Training RMSE < 0.05 on health scale [0, 1]
  - [ ] Test RMSE < 0.06 (slight generalization loss acceptable)
  - [ ] 95% CI coverage = 93–97% (properly calibrated)
  - [ ] Prediction latency < 1 ms (real-time capable)

- [ ] **Health Indicators**
  - [ ] HI_comp decreases when efficiency drops (validation)
  - [ ] HI_turb correlates with pressure ratio changes
  - [ ] Overall HI weighted correctly (40% comp, 35% turb, 25% comb)
  - [ ] Maintenance thresholds at 0.95, 0.90, 0.85 make sense

- [ ] **Uncertainty Quantification**
  - [ ] Confidence intervals narrow when data is good
  - [ ] Confidence intervals widen when data is sparse
  - [ ] Coverage probability ≈ nominal (95% CI → 95% coverage)
  - [ ] No overconfident predictions in unfamiliar region

- [ ] **Code Quality**
  - [ ] ODE solver uses RK4 (not Euler for accuracy)
  - [ ] Jacobian computed numerically (no hand-coded bugs)
  - [ ] GPR kernel properly normalized
  - [ ] All array dimensions correct

- [ ] **Documentation**
  - [ ] State equations written out (not just in code)
  - [ ] Health indicator formulas explained
  - [ ] Uncertainty quantification method (Bayesian vs. frequentist)
  - [ ] Known limitations and failure modes listed

- [ ] **Visualization**
  - [ ] Compressor health predictions vs. true values
  - [ ] 95% confidence intervals visualized
  - [ ] Error distribution histogram (should be ~normal)
  - [ ] Degradation trajectory over 1000 flight hours

---

## PART 4: RUN SCRIPTS

### Challenge 1: Quick Start

```matlab
% Step 1: Run baseline simulation only (5 minutes)
aero = AerodynamicModel(12, 8.5, 0.025);
engine = TurboshaftEngine(60, 30000);
battery = BatteryPack('LiPo', 48, 100, 0.95);
motor = ElectricMotor(50, 5000);
simulator = MissionSimulator(aero, engine, battery, motor, 10);

mission = Mission_7hr();
simulator = simulator.setup_mission(mission);

design.engine_power_kw = 60;
design.battery_capacity_Ah = 100;
design.num_motors = 2;
design.power_split_strategy = 'thermal_dominant';

results = simulator.run_simulation(design);
fprintf('Baseline: %.2f hours endurance\n', results.endurance_hours);

% Step 2: Run full optimization (3 minutes)
run_optimization();  % See Challenge_1_Complete_Source_Code.m
```

### Challenge 2: Quick Start

```matlab
% Run digital twin development pipeline
main_digital_twin();  % See Challenge_2_Complete_Source_Code.m

% Loads digital_twin_models.mat with trained surrogates
load('digital_twin_models.mat', 'gpr_comp', 'gpr_turb', 'gpr_comb', 'ekf');

% Use for real-time health monitoring:
% For each sensor measurement z = [P2, P3, P4, T3, T4, mfr]:
%   ekf = ekf.predict(u, dt);
%   ekf = ekf.update(z);
%   [mu_comp, sigma_comp] = gpr_comp.predict(features);
%   if mu_comp < 0.85, alert("MAINTENANCE REQUIRED"); end
```

---

## KEY PERFORMANCE TARGETS

### Challenge 1

| Metric | Target | Success Criterion |
|--------|--------|------------------|
| Baseline endurance | 4–5 hours | Complete 7-hour mission |
| Optimized endurance | >5.5 hours | +30% improvement |
| Optimization time | <300 s | PSO completes |
| Power budget error | <5% | Energy conservation |
| Design feasibility | 100% | All constraints met |

### Challenge 2

| Metric | Target | Success Criterion |
|--------|--------|------------------|
| EKF convergence | <10 s | <5% state error |
| Surrogate RMSE | <0.05 | High accuracy |
| Prediction latency | <1 ms | Real-time capable |
| UQ coverage | 95% | Properly calibrated |
| Health sensitivity | Clear | Degrades with time |

---

**Document Version**: 1.0  
**Last Updated**: July 2026  
**Status**: Ready for Competition
