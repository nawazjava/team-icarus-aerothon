%% ============================================================================
%  OBJECTIVE FUNCTION FOR OPTIMIZATION  (LIFECYCLE-ROBUST VERSION)
%  ============================================================================
%
%  design = [engine_power_kw, battery_capacity_Ah, num_motors, ...
%            generator_power_kw, motor_power_kw_per_motor]
%
%  THE INTEGRATION POINT BETWEEN CHALLENGE 1 AND CHALLENGE 2:
%  Instead of sizing the propulsion system against a pristine (100%
%  health) engine, this samples endurance across the same health
%  thresholds Challenge 2's digital twin defines - healthy (1.00),
%  monitor (0.95), service (0.90), critical (0.85) - and optimizes a
%  blend of time-weighted expected endurance and worst-case (critical-
%  health) endurance. A design that only looks good on day one but
%  collapses as the engine ages scores worse here than one that stays
%  strong across the engine's whole service life, even if its brand-new
%  endurance number is slightly lower.
%
%  Health degradation is applied by rebuilding the TurboshaftEngine at a
%  derated rated_power (init_performance_maps() scales power_map
%  proportionally to rated_power, so reconstructing correctly derates
%  the whole performance map rather than just clipping one number).

function fitness = objective_hybrid_electric(design, simulator, baseline_design, aircraft)

    design_opt = baseline_design;
    design_opt.engine_power_kw = design(1);
    design_opt.battery_capacity_Ah = design(2);
    design_opt.num_motors = max(1, round(design(3)));
    design_opt.generator_power_kw = design(4);
    design_opt.motor_power_kw = design(5);

    % Rebuild the components whose sizing this particle controls
    simulator.battery   = BatteryPack('LiPo', 48, design(2), 0.95);
    simulator.generator = Generator(design(4), simulator.engine.rated_rpm, simulator.generator.V_ac_line);
    simulator.rectifier = Rectifier(800);
    simulator.motor     = ElectricMotor(design(5), simulator.motor.max_rpm);
    simulator.inverter  = Inverter(design(5) * design_opt.num_motors, 800);

    % ---- Lifecycle-robust health sampling ----
    % Matches Challenge 2's health-index thresholds exactly, so the two
    % challenges are optimizing against the same definition of "healthy"
    % vs "critical", not two independently-invented scales.
    health_states  = [1.00, 0.95, 0.90, 0.85];              % healthy / monitor / service / critical
    health_weights = [0.40, 0.30, 0.20, 0.10];               % time-weighted: most service life spent healthy
    rated_rpm = simulator.engine.rated_rpm;

    endurance_samples = zeros(size(health_states));
    deficit_samples   = zeros(size(health_states));
    feasible_all = true;
    avg_eff_healthy = 0;

    for h = 1:numel(health_states)
        try
            simulator.engine = TurboshaftEngine(design(1) * health_states(h), rated_rpm);
            results_h = simulator.run_simulation(design_opt);
        catch
            endurance_samples(h) = 0;
            deficit_samples(h) = 1e3;
            feasible_all = false;
            continue;
        end
        endurance_samples(h) = results_h.endurance_hours;
        deficit_samples(h)   = results_h.max_power_deficit_kw;
        feasible_all = feasible_all && results_h.mission_feasible;
        if h == 1
            avg_eff_healthy = results_h.avg_total_efficiency;
        end
    end

    expected_endurance   = sum(endurance_samples .* health_weights);
    worst_case_endurance = min(endurance_samples);   % pessimistic guarantee (weakest health state)

    % ---- Objective terms ----
    endurance_penalty = max(0, 5 - expected_endurance) / 5;

    mtow_est = 500 + design(2)*0.5 + design(1)*0.1 + design(4)*0.3 + design(5)*design_opt.num_motors*0.2;
    mtow_penalty = max(0, mtow_est - aircraft.MTOW) / 500;

    feasibility_penalty = 1e6 * (~feasible_all);
    deficit_penalty = 10 * max(deficit_samples);
    efficiency_bonus = -2 * avg_eff_healthy;

    % Blend: 70% time-weighted expected endurance, 30% worst-case
    % guarantee - rewards designs that stay strong as the engine ages,
    % not just ones optimized for a brand-new engine.
    fitness = -(0.7*expected_endurance + 0.3*worst_case_endurance) ...
              + 0.5*endurance_penalty + 0.3*mtow_penalty ...
              + feasibility_penalty + deficit_penalty + efficiency_bonus;
end
