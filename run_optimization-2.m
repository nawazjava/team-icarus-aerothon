%% ============================================================================
%  CHALLENGE 1: HYBRID-ELECTRIC PROPULSION OPTIMIZATION
%  Full Propulsion-Chain Version (Generator/Rectifier/DCBus/Inverter/
%  Propeller/Energy Management Controller added)
%  ============================================================================
%
%  Chain now modeled:
%    Aero -> Propeller -> Gearbox -> Motor -> Inverter -> DC Bus
%       <-> Battery
%       <- Rectifier <- Generator <- Engine
%    with an Energy Management Controller deciding the battery/generator
%    split at every timestep (see EnergyManagementController.m).
%
%  Files required in the same folder (add folder to MATLAB path, or cd
%  into it, then run this script - or just run RUN_ME.m):
%    atmosphere_model.m, AerodynamicModel.m, TurboshaftEngine.m,
%    Generator.m, Rectifier.m, DCBus.m, Inverter.m, BatteryPack.m,
%    ElectricMotor.m, Propeller.m, EnergyManagementController.m,
%    MissionSimulator.m, Mission_7hr.m, ParticleSwarmOptimizer.m,
%    objective_hybrid_electric.m

function run_optimization()
    clc; clear all; close all;
    fprintf('========== HYBRID-ELECTRIC UAV OPTIMIZATION (Full Propulsion Chain) ==========\n');
    fprintf('IIT Indore x HAL Challenge\n');
    fprintf('===============================================================================\n\n');

    % =====================================================================
    % STEP 1: AIRCRAFT + PROPULSION CHAIN COMPONENTS
    % =====================================================================
    fprintf('STEP 1: Building propulsion chain components...\n');

    aircraft.MTOW = 1000;
    aircraft.wing_area = 12;
    aircraft.aspect_ratio = 8.5;
    aircraft.cd0 = 0.025;

    aero      = AerodynamicModel(aircraft.wing_area, aircraft.aspect_ratio, aircraft.cd0);
    propeller = Propeller(1.8);                     % 1.8 m fixed-pitch cruise prop
    motor     = ElectricMotor(25, 5000);             % per-motor baseline: 25 kW, 5000 rpm max
    inverter  = Inverter(50, 800);                   % sized for 2 motors baseline (2x25kW)
    dcbus     = DCBus(400, 0.01, 800);               % 400 V DC bus baseline
    battery   = BatteryPack('LiPo', 48, 100, 0.95);
    rectifier = Rectifier(800);
    generator = Generator(60, 30000, 230);           % matched to baseline 60kW engine, direct-drive
    engine    = TurboshaftEngine(60, 30000);
    emc       = EnergyManagementController(0.20, 0.30, 0.80, 2.5);

    simulator = MissionSimulator(aero, propeller, motor, inverter, dcbus, ...
        battery, rectifier, generator, engine, emc, 10);
    fprintf('  9 propulsion-chain components initialized (Engine->Generator->Rectifier->\n');
    fprintf('  DCBus->Battery->Inverter->Motor->Gearbox->Propeller).\n');

    % =====================================================================
    % STEP 2: MISSION PROFILE
    % =====================================================================
    fprintf('\nSTEP 2: Defining mission profile...\n');
    mission = Mission_7hr();
    simulator = simulator.setup_mission(mission);

    % =====================================================================
    % STEP 3: BASELINE SIMULATION
    % =====================================================================
    fprintf('\nSTEP 3: Running baseline simulation...\n');
    baseline_design.engine_power_kw = 60;
    baseline_design.battery_capacity_Ah = 100;
    baseline_design.num_motors = 2;
    baseline_design.generator_power_kw = 60;
    baseline_design.motor_power_kw = 25;

    results_baseline = simulator.run_simulation(baseline_design);
    fprintf('  Endurance: %.2f h | Fuel burned: %.1f kg | Feasible: %d | Avg sys eff: %.1f%%\n', ...
        results_baseline.endurance_hours, results_baseline.fuel_burned, ...
        results_baseline.mission_feasible, results_baseline.avg_total_efficiency*100);
    if results_baseline.max_power_deficit_kw > 0.1
        fprintf('  NOTE: generator+battery path was short by up to %.1f kW during the mission\n', ...
            results_baseline.max_power_deficit_kw);
    end

    % =====================================================================
    % STEP 4: OPTIMIZATION SETUP (5 design variables)
    % =====================================================================
    fprintf('\nSTEP 4: Setting up optimization (5 design variables)...\n');
    % [engine_kw, battery_Ah, num_motors, generator_kw, motor_kw_per_motor]
    lb = [40,  50, 1, 40, 10];
    ub = [80, 200, 4, 80, 40];

    fprintf('  Engine power:    %.0f-%.0f kW\n', lb(1), ub(1));
    fprintf('  Battery capacity:%.0f-%.0f Ah\n', lb(2), ub(2));
    fprintf('  Motor count:     %.0f-%.0f\n', lb(3), ub(3));
    fprintf('  Generator power: %.0f-%.0f kW\n', lb(4), ub(4));
    fprintf('  Motor size:      %.0f-%.0f kW (per motor)\n', lb(5), ub(5));

    objective = @(x) objective_hybrid_electric(x, simulator, baseline_design, aircraft);

    % =====================================================================
    % STEP 5: RUN PSO
    % =====================================================================
    fprintf('\nSTEP 5: Running Particle Swarm Optimizer (30 particles x 50 iterations)...\n\n');
    optimizer = ParticleSwarmOptimizer(30, 50);
    [best_design, best_fitness, history] = optimizer.optimize(lb, ub, objective);

    fprintf('\n Optimization complete. Best fitness: %.6f\n', best_fitness);
    fprintf('  Engine: %.1f kW | Battery: %.1f Ah | Motors: %.0f | Generator: %.1f kW | Motor size: %.1f kW\n', ...
        best_design(1), best_design(2), round(best_design(3)), best_design(4), best_design(5));

    % =====================================================================
    % STEP 6: SIMULATE OPTIMIZED DESIGN
    % =====================================================================
    fprintf('\nSTEP 6: Simulating optimized design...\n');
    optimized_design = baseline_design;
    optimized_design.engine_power_kw = best_design(1);
    optimized_design.battery_capacity_Ah = best_design(2);
    optimized_design.num_motors = max(1, round(best_design(3)));
    optimized_design.generator_power_kw = best_design(4);
    optimized_design.motor_power_kw = best_design(5);

    simulator.battery   = BatteryPack('LiPo', 48, best_design(2), 0.95);
    simulator.generator = Generator(best_design(4), engine.rated_rpm, generator.V_ac_line);
    simulator.rectifier = Rectifier(800);
    simulator.motor     = ElectricMotor(best_design(5), motor.max_rpm);
    simulator.inverter  = Inverter(best_design(5)*optimized_design.num_motors, 800);

    results_optimized = simulator.run_simulation(optimized_design);
    fprintf('  Endurance: %.2f h (+%.1f%%) | Fuel: %.1f kg | Feasible: %d | Avg sys eff: %.1f%%\n', ...
        results_optimized.endurance_hours, ...
        100*(results_optimized.endurance_hours/results_baseline.endurance_hours - 1), ...
        results_optimized.fuel_burned, results_optimized.mission_feasible, ...
        results_optimized.avg_total_efficiency*100);

    % =====================================================================
    % STEP 6b: LIFECYCLE ROBUSTNESS CHECK  (the Challenge 1 <-> Challenge 2 link)
    % =====================================================================
    % Re-simulate the FINAL optimized design at each Challenge-2 health
    % threshold to report the number that actually goes on the slide:
    % "guaranteed endurance even at the critical (0.85) health state".
    fprintf('\nSTEP 6b: Lifecycle robustness check (same design, aging engine)...\n');
    health_labels = {'Healthy (1.00)','Monitor (0.95)','Service (0.90)','Critical (0.85)'};
    health_states_report = [1.00, 0.95, 0.90, 0.85];
    lifecycle_endurance = zeros(1,4);
    for h = 1:4
        simulator.engine = TurboshaftEngine(optimized_design.engine_power_kw * health_states_report(h), engine.rated_rpm);
        r_h = simulator.run_simulation(optimized_design);
        lifecycle_endurance(h) = r_h.endurance_hours;
        fprintf('  %-16s -> %.2f h endurance\n', health_labels{h}, lifecycle_endurance(h));
    end
    simulator.engine = TurboshaftEngine(optimized_design.engine_power_kw, engine.rated_rpm); % restore healthy engine
    fprintf('  >> GUARANTEED (worst-case, critical health): %.2f h <<\n', min(lifecycle_endurance));

    % =====================================================================
    % STEP 7: DASHBOARD
    % =====================================================================
    fprintf('\nSTEP 7: Generating full propulsion-chain dashboard...\n');
    figure('Position',[80 60 1500 950]);

    subplot(3,3,1);
    plot(results_baseline.t/60, results_baseline.alt,'b-','LineWidth',2); hold on;
    plot(results_optimized.t/60, results_optimized.alt,'r--','LineWidth',2);
    xlabel('Time (min)'); ylabel('Altitude (m)'); title('Mission Profile');
    legend('Baseline','Optimized'); grid on;

    subplot(3,3,2);
    plot(results_baseline.t/60, results_baseline.P_eng_shaft_kw,'b-','LineWidth',1.5); hold on;
    plot(results_baseline.t/60, results_baseline.P_battery_dc_kw,'g-','LineWidth',1.5);
    plot(results_baseline.t/60, results_baseline.P_dc_bus_req_kw,'k--','LineWidth',1);
    xlabel('Time (min)'); ylabel('Power (kW)'); title('Baseline: Engine vs Battery vs Bus Demand');
    legend('Engine shaft','Battery (+dis/-chg)','Bus demand'); grid on;

    subplot(3,3,3);
    plot(results_optimized.t/60, results_optimized.P_eng_shaft_kw,'b-','LineWidth',1.5); hold on;
    plot(results_optimized.t/60, results_optimized.P_battery_dc_kw,'g-','LineWidth',1.5);
    plot(results_optimized.t/60, results_optimized.P_dc_bus_req_kw,'k--','LineWidth',1);
    xlabel('Time (min)'); ylabel('Power (kW)'); title('Optimized: Engine vs Battery vs Bus Demand');
    legend('Engine shaft','Battery (+dis/-chg)','Bus demand'); grid on;

    subplot(3,3,4);
    plot(results_baseline.t/60, results_baseline.soc,'b-','LineWidth',2); hold on;
    plot(results_optimized.t/60, results_optimized.soc,'r--','LineWidth',2);
    yline(20,'k--'); xlabel('Time (min)'); ylabel('SoC (%)'); title('Battery SoC');
    legend('Baseline','Optimized'); grid on;

    subplot(3,3,5);
    plot(results_baseline.t/60, results_baseline.fuel_mass,'b-','LineWidth',2); hold on;
    plot(results_optimized.t/60, results_optimized.fuel_mass,'r--','LineWidth',2);
    xlabel('Time (min)'); ylabel('Fuel (kg)'); title('Fuel Remaining');
    legend('Baseline','Optimized'); grid on;

    subplot(3,3,6);
    plot(results_optimized.t/60, results_optimized.eta_generator*100,'m-'); hold on;
    plot(results_optimized.t/60, results_optimized.eta_inverter*100,'c-');
    plot(results_optimized.t/60, results_optimized.eta_motor*100,'g-');
    xlabel('Time (min)'); ylabel('Efficiency (%)'); title('Component Efficiencies (Optimized)');
    legend('Generator','Inverter','Motor'); grid on;

    subplot(3,3,7);
    plot(results_optimized.t/60, results_optimized.motor_torque_Nm,'b-');
    xlabel('Time (min)'); ylabel('Torque (Nm)'); title('Motor Torque (per motor)'); grid on;

    subplot(3,3,8);
    plot(results_optimized.t/60, results_optimized.total_efficiency*100,'k-','LineWidth',1.5);
    xlabel('Time (min)'); ylabel('Efficiency (%)'); title('Overall Fuel-to-Thrust Chain Efficiency'); grid on;

    subplot(3,3,9);
    categories = {'Endurance(h)','Fuel(kg)','SysEff(%)'};
    base_vals = [results_baseline.endurance_hours, results_baseline.fuel_burned, results_baseline.avg_total_efficiency*100];
    opt_vals  = [results_optimized.endurance_hours, results_optimized.fuel_burned, results_optimized.avg_total_efficiency*100];
    x = 1:3; bar(x-0.2, base_vals, 0.4,'b'); hold on; bar(x+0.2, opt_vals, 0.4,'r');
    set(gca,'XTickLabel',categories); legend('Baseline','Optimized'); title('Summary'); grid on;

    sgtitle('Series-Hybrid-Electric Propulsion Chain: Full-Depth Simulation');

    % ---- Power-flow snapshot (Sankey-style bar) ----
    figure('Position',[80 60 900 500]);
    mid = max(1, round(numel(results_optimized.t)*0.5));  % mid-mission (cruise) sample
    stage_power = [results_optimized.P_eng_shaft_kw(mid), ...
                   results_optimized.P_gen_ac_kw(mid), ...
                   results_optimized.P_rect_dc_kw(mid), ...
                   results_optimized.P_dc_bus_req_kw(mid)*results_optimized.eta_inverter(mid), ...
                   results_optimized.P_prop_shaft_kw(mid)];
    stage_names = {'Engine\nShaft','Generator\nAC','Rectifier\nDC','Inverter\nAC (motor)','Propeller\nShaft'};
    bar(stage_power,'FaceColor',[0.2 0.5 0.8]);
    set(gca,'XTickLabel',stage_names); ylabel('Power (kW)');
    title('Power Flow Through Propulsion Chain (mid-mission snapshot, optimized design)');
    grid on;

    fprintf('  Dashboard generated.\n');

    % ---- Lifecycle robustness chart (the "guaranteed" slide) ----
    figure('Position',[80 60 700 450]);
    bar(lifecycle_endurance, 'FaceColor',[0.85 0.35 0.25]);
    hold on;
    yline(min(lifecycle_endurance), 'k--', sprintf('Guaranteed: %.2fh', min(lifecycle_endurance)), 'LineWidth',1.5);
    set(gca,'XTickLabel', health_labels);
    ylabel('Endurance (hours)');
    title('Optimized Design: Endurance Across Engine Lifecycle');
    grid on;

    fprintf('  Lifecycle robustness chart generated.\n');

    % =====================================================================
    % SUMMARY
    % =====================================================================
    fprintf('\n=================================================================\n');
    fprintf('SUMMARY\n');
    fprintf('=================================================================\n');
    fprintf('Baseline : %.2fh endurance | %.1fkg fuel | %.1f%% system efficiency\n', ...
        results_baseline.endurance_hours, results_baseline.fuel_burned, results_baseline.avg_total_efficiency*100);
    fprintf('Optimized: %.2fh endurance | %.1fkg fuel | %.1f%% system efficiency\n', ...
        results_optimized.endurance_hours, results_optimized.fuel_burned, results_optimized.avg_total_efficiency*100);
    fprintf('Improvement: +%.1f%% endurance\n', ...
        100*(results_optimized.endurance_hours/results_baseline.endurance_hours - 1));
    fprintf('Guaranteed endurance (critical-health engine): %.2f h\n', min(lifecycle_endurance));
    fprintf('=================================================================\n\n');
end
