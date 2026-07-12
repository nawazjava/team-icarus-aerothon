%% ============================================================================
%  CHALLENGE 1: HYBRID-ELECTRIC PROPULSION OPTIMIZATION
%  Complete Production Source Code
%  ============================================================================
%  
%  Directory structure:
%  ├── run_optimization.m          [MAIN ENTRY POINT]
%  ├── aerodynamics/
%  │   ├── AerodynamicModel.m
%  │   ├── power_curve.m
%  │   └── validate_aero.m
%  ├── propulsion/
%  │   ├── TurboshaftEngine.m
%  │   ├── engine_performance.m
%  │   └── validate_engine.m
%  ├── battery/
%  │   ├── BatteryPack.m
%  │   ├── ElectricMotor.m
%  │   └── validate_battery.m
%  ├── mission/
%  │   ├── MissionSimulator.m
%  │   ├── Mission_Example_7hr.m
%  │   └── simulate_baseline.m
%  ├── optimization/
%  │   ├── ParticleSwarmOptimizer.m
%  │   ├── objective_functions.m
%  │   └── run_pso.m
%  └── visualization/
%      ├── plot_mission.m
%      ├── plot_trades.m
%      └── plot_dashboard.m
%
%  ============================================================================
%  RUN_OPTIMIZATION.M - MAIN ENTRY POINT
%  ============================================================================

function run_optimization()
    % Main optimization framework for hybrid-electric UAV propulsion
    % Runs complete pipeline: baseline simulation → PSO optimization → analysis
    
    clc; clear all; close all;
    fprintf('================== HYBRID-ELECTRIC UAV OPTIMIZATION ==================\n');
    fprintf('IIT Indore × HAL Challenge\n');
    fprintf('=====================================================================\n\n');
    
    % =====================================================================
    % STEP 1: SETUP AIRCRAFT CONFIGURATION
    % =====================================================================
    fprintf('STEP 1: Setting up aircraft configuration...\n');
    
    % Aircraft specs
    aircraft.MTOW = 1000;           % kg
    aircraft.empty_weight = 500;    % kg
    aircraft.payload = 200;         % kg
    aircraft.fuel_capacity = 150;   % kg
    aircraft.battery_capacity = 50; % kg (will optimize)
    
    % Initial mission fuel load
    aircraft.fuel_initial = 150;    % kg (full tank)
    
    % Aerodynamic properties
    aircraft.wing_area = 12;        % m^2
    aircraft.aspect_ratio = 8.5;
    aircraft.cd0 = 0.025;           % Parasite drag coefficient
    
    fprintf('  ✓ Aircraft MTOW: %.0f kg\n', aircraft.MTOW);
    fprintf('  ✓ Empty weight: %.0f kg\n', aircraft.empty_weight);
    fprintf('  ✓ Wing area: %.1f m²\n', aircraft.wing_area);
    
    % =====================================================================
    % STEP 2: CREATE SYSTEM OBJECTS
    % =====================================================================
    fprintf('\nSTEP 2: Initializing system components...\n');
    
    % Aerodynamic model
    aero = AerodynamicModel(aircraft.wing_area, aircraft.aspect_ratio, aircraft.cd0);
    fprintf('  ✓ Aerodynamic model created\n');
    
    % Turboshaft engine (baseline: 60 kW)
    engine = TurboshaftEngine(60, 30000);
    fprintf('  ✓ Turboshaft engine created (60 kW rated)\n');
    
    % Battery (baseline: 100 Ah, 48V)
    battery = BatteryPack('LiPo', 48, 100, 0.95);
    fprintf('  ✓ Battery pack created (100 Ah, 48V LiPo)\n');
    
    % Electric motor (50 kW)
    motor = ElectricMotor(50, 5000);
    fprintf('  ✓ Electric motor created (50 kW peak)\n');
    
    % Mission simulator
    simulator = MissionSimulator(aero, engine, battery, motor, 10);  % 10 s time step
    fprintf('  ✓ Mission simulator created (10 s time step)\n');
    
    % =====================================================================
    % STEP 3: DEFINE MISSION PROFILE
    % =====================================================================
    fprintf('\nSTEP 3: Defining mission profile...\n');
    
    mission = Mission_7hr();  % 7-hour long-endurance mission
    simulator = simulator.setup_mission(mission);
    
    fprintf('  ✓ Mission phases:\n');
    for i = 1:length(mission.phases)
        phase = mission.phases(i);
        fprintf('    - %s: alt=%.0f m, v=%.0f m/s, duration=%.0f s\n', ...
            phase.name, phase.altitude, phase.speed, phase.duration);
    end
    
    % =====================================================================
    % STEP 4: RUN BASELINE SIMULATION
    % =====================================================================
    fprintf('\nSTEP 4: Running baseline simulation...\n');
    fprintf('  Design: engine=60kW, battery=100Ah, motors=2, power=thermal_dominant\n');
    
    baseline_design.engine_power_kw = 60;
    baseline_design.battery_capacity_Ah = 100;
    baseline_design.num_motors = 2;
    baseline_design.power_split_strategy = 'thermal_dominant';
    
    results_baseline = simulator.run_simulation(baseline_design);
    
    fprintf('  ✓ Baseline simulation complete\n');
    fprintf('    - Endurance: %.2f hours\n', results_baseline.endurance_hours);
    fprintf('    - Fuel burned: %.1f kg\n', results_baseline.fuel_burned);
    fprintf('    - Mission feasible: %d\n', results_baseline.mission_feasible);
    fprintf('    - Avg efficiency: %.1f%%\n', results_baseline.avg_efficiency * 100);
    
    % =====================================================================
    % STEP 5: OPTIMIZATION SETUP
    % =====================================================================
    fprintf('\nSTEP 5: Setting up optimization problem...\n');
    
    % Design variable bounds
    % [engine_power, battery_capacity, num_motors]
    lb = [40,  50, 1];
    ub = [80, 200, 4];
    
    fprintf('  Design space:\n');
    fprintf('    - Engine power: %.0f–%.0f kW\n', lb(1), ub(1));
    fprintf('    - Battery capacity: %.0f–%.0f Ah\n', lb(2), ub(2));
    fprintf('    - Motor count: %.0f–%.0f\n', lb(3), ub(3));
    
    % Objective function (minimize)
    objective = @(x) objective_hybrid_electric(x, simulator, baseline_design, aircraft);
    
    % =====================================================================
    % STEP 6: RUN PARTICLE SWARM OPTIMIZATION
    % =====================================================================
    fprintf('\nSTEP 6: Running Particle Swarm Optimizer...\n');
    fprintf('  Swarm size: 30 particles\n');
    fprintf('  Iterations: 50\n');
    fprintf('  Expected time: ~3 minutes\n\n');
    
    optimizer = ParticleSwarmOptimizer(30, 50);
    [best_design, best_fitness, history] = optimizer.optimize(lb, ub, objective);
    
    fprintf('\n✓ Optimization complete!\n');
    fprintf('  Best fitness: %.6f\n', best_fitness);
    fprintf('  Engine power: %.1f kW\n', best_design(1));
    fprintf('  Battery capacity: %.1f Ah\n', best_design(2));
    fprintf('  Motor count: %.0f\n', best_design(3));
    
    % =====================================================================
    % STEP 7: ANALYZE OPTIMIZED DESIGN
    % =====================================================================
    fprintf('\nSTEP 7: Simulating optimized design...\n');
    
    optimized_design = baseline_design;
    optimized_design.engine_power_kw = best_design(1);
    optimized_design.battery_capacity_Ah = best_design(2);
    optimized_design.num_motors = best_design(3);
    
    % Update battery in simulator
    battery_opt = BatteryPack('LiPo', 48, optimized_design.battery_capacity_Ah, 0.95);
    simulator.battery = battery_opt;
    
    results_optimized = simulator.run_simulation(optimized_design);
    
    fprintf('  ✓ Optimized design simulation complete\n');
    fprintf('    - Endurance: %.2f hours (+%.1f%%)\n', ...
        results_optimized.endurance_hours, ...
        100 * (results_optimized.endurance_hours / results_baseline.endurance_hours - 1));
    fprintf('    - Fuel burned: %.1f kg\n', results_optimized.fuel_burned);
    fprintf('    - Mission feasible: %d\n', results_optimized.mission_feasible);
    
    % =====================================================================
    % STEP 8: VISUALIZATION
    % =====================================================================
    fprintf('\nSTEP 8: Generating visualizations...\n');
    
    figure('Position', [100 100 1400 900]);
    
    % Baseline mission profile
    subplot(2, 3, 1);
    plot(results_baseline.time/60, results_baseline.altitude, 'b-', 'LineWidth', 2);
    hold on;
    plot(results_optimized.time/60, results_optimized.altitude, 'r--', 'LineWidth', 2);
    xlabel('Time (min)'); ylabel('Altitude (m)'); title('Mission Profile');
    legend('Baseline', 'Optimized'); grid on;
    
    % Power budget
    subplot(2, 3, 2);
    plot(results_baseline.time/60, results_baseline.P_aero, 'b-', 'LineWidth', 1.5);
    hold on;
    plot(results_baseline.time/60, results_baseline.P_engine, 'r-', 'LineWidth', 1.5);
    plot(results_baseline.time/60, results_baseline.P_electric, 'g-', 'LineWidth', 1.5);
    xlabel('Time (min)'); ylabel('Power (kW)'); title('Baseline Power Budget');
    legend('Aero Req', 'Thermal', 'Electric'); grid on;
    
    % Optimized power budget
    subplot(2, 3, 3);
    plot(results_optimized.time/60, results_optimized.P_aero, 'b-', 'LineWidth', 1.5);
    hold on;
    plot(results_optimized.time/60, results_optimized.P_engine, 'r-', 'LineWidth', 1.5);
    plot(results_optimized.time/60, results_optimized.P_electric, 'g-', 'LineWidth', 1.5);
    xlabel('Time (min)'); ylabel('Power (kW)'); title('Optimized Power Budget');
    legend('Aero Req', 'Thermal', 'Electric'); grid on;
    
    % Battery SoC
    subplot(2, 3, 4);
    plot(results_baseline.time/60, results_baseline.soc, 'b-', 'LineWidth', 2);
    hold on;
    plot(results_optimized.time/60, results_optimized.soc, 'r--', 'LineWidth', 2);
    xlabel('Time (min)'); ylabel('SoC (%)'); title('Battery State of Charge');
    legend('Baseline', 'Optimized');
    yline(20, 'k--', 'LineWidth', 1); % Min safe
    grid on;
    
    % Fuel consumption
    subplot(2, 3, 5);
    plot(results_baseline.time/60, results_baseline.fuel_mass, 'b-', 'LineWidth', 2);
    hold on;
    plot(results_optimized.time/60, results_optimized.fuel_mass, 'r--', 'LineWidth', 2);
    xlabel('Time (min)'); ylabel('Fuel Mass (kg)'); title('Fuel Remaining');
    legend('Baseline', 'Optimized'); grid on;
    
    % Comparison metrics
    subplot(2, 3, 6);
    categories = {'Endurance\n(hrs)', 'Fuel Burn\n(kg)', 'Avg Power\n(kW)'};
    baseline_vals = [results_baseline.endurance_hours, results_baseline.fuel_burned, ...
                     mean(results_baseline.P_engine + results_baseline.P_electric)];
    optimized_vals = [results_optimized.endurance_hours, results_optimized.fuel_burned, ...
                      mean(results_optimized.P_engine + results_optimized.P_electric)];
    
    x = 1:3;
    bar(x - 0.2, baseline_vals, 0.4, 'b', 'DisplayName', 'Baseline');
    hold on;
    bar(x + 0.2, optimized_vals, 0.4, 'r', 'DisplayName', 'Optimized');
    set(gca, 'XTickLabel', categories);
    ylabel('Value'); title('Performance Comparison');
    legend(); grid on;
    
    sgtitle('Hybrid-Electric UAV Optimization Results');
    
    fprintf('  ✓ Visualization complete\n');
    
    % =====================================================================
    % STEP 9: SENSITIVITY ANALYSIS
    % =====================================================================
    fprintf('\nSTEP 9: Sensitivity analysis...\n');
    
    % Tornado chart: vary each parameter ±20%
    sensitivity_engine = [];
    sensitivity_battery = [];
    sensitivity_motors = [];
    
    for delta = -0.2:0.1:0.2
        design_test = optimized_design;
        design_test.engine_power_kw = design_test.engine_power_kw * (1 + delta);
        f_engine = objective(design_test);
        sensitivity_engine = [sensitivity_engine, f_engine];
        
        design_test = optimized_design;
        design_test.battery_capacity_Ah = design_test.battery_capacity_Ah * (1 + delta);
        f_battery = objective(design_test);
        sensitivity_battery = [sensitivity_battery, f_battery];
        
        design_test = optimized_design;
        design_test.num_motors = round(design_test.num_motors * (1 + delta));
        design_test.num_motors = max(1, min(4, design_test.num_motors));
        f_motors = objective(design_test);
        sensitivity_motors = [sensitivity_motors, f_motors];
    end
    
    fprintf('  Engine power sensitivity: %.4f (range)\n', max(sensitivity_engine) - min(sensitivity_engine));
    fprintf('  Battery capacity sensitivity: %.4f (range)\n', max(sensitivity_battery) - min(sensitivity_battery));
    fprintf('  Motor count sensitivity: %.4f (range)\n', max(sensitivity_motors) - min(sensitivity_motors));
    
    % =====================================================================
    % SUMMARY
    % =====================================================================
    fprintf('\n');
    fprintf('=====================================================================\n');
    fprintf('OPTIMIZATION SUMMARY\n');
    fprintf('=====================================================================\n');
    fprintf('Baseline Design:\n');
    fprintf('  Engine: %.0f kW | Battery: %.0f Ah | Motors: %.0f\n', 60, 100, 2);
    fprintf('  Endurance: %.2f hours | Fuel: %.1f kg | Efficiency: %.1f%%\n', ...
        results_baseline.endurance_hours, results_baseline.fuel_burned, ...
        results_baseline.avg_efficiency * 100);
    fprintf('\nOptimized Design:\n');
    fprintf('  Engine: %.1f kW | Battery: %.1f Ah | Motors: %.0f\n', ...
        optimized_design.engine_power_kw, optimized_design.battery_capacity_Ah, ...
        optimized_design.num_motors);
    fprintf('  Endurance: %.2f hours | Fuel: %.1f kg | Efficiency: %.1f%%\n', ...
        results_optimized.endurance_hours, results_optimized.fuel_burned, ...
        results_optimized.avg_efficiency * 100);
    fprintf('\nImprovement:\n');
    fprintf('  Endurance: +%.1f%%\n', 100 * (results_optimized.endurance_hours / results_baseline.endurance_hours - 1));
    fprintf('  Fuel efficiency: +%.1f%%\n', 100 * (results_optimized.fuel_burned / results_baseline.fuel_burned - 1));
    fprintf('=====================================================================\n\n');
end
