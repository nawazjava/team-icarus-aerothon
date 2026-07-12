%% ============================================================================
%  OBJECTIVE FUNCTION FOR OPTIMIZATION  (UPDATED)
%  ============================================================================
%
%  design = [engine_power_kw, battery_capacity_Ah, num_motors, ...
%            generator_power_kw, motor_power_kw_per_motor]
%
%  Expanded from the original 3-variable version to also size the
%  generator and the per-motor rating, and to penalize any timestep
%  where the generator+battery genuinely can't meet bus demand
%  (max_power_deficit_kw > 0), rather than only checking endurance/SoC/
%  fuel-remaining feasibility.

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

    try
        results = simulator.run_simulation(design_opt);
    catch
        fitness = 1e6;
        return;
    end

    endurance = results.endurance_hours;
    feasible = results.mission_feasible;
    avg_eff = results.avg_total_efficiency;

    % Objective 1: maximize endurance (penalty below 5 hours)
    endurance_penalty = max(0, 5 - endurance) / 5;

    % Objective 2: minimize weight impact of oversized components
    mtow_est = 500 + design(2)*0.5 + design(1)*0.1 + design(4)*0.3 + design(5)*design_opt.num_motors*0.2;
    mtow_penalty = max(0, mtow_est - aircraft.MTOW) / 500;

    % Objective 3 (hard constraint): mission feasibility
    feasibility_penalty = 1e6 * (~feasible);

    % Objective 4: penalize any real power shortfall in the chain
    % (generator+battery genuinely couldn't meet bus demand at some point)
    deficit_penalty = 10 * results.max_power_deficit_kw;

    % Objective 5: reward higher overall fuel-to-thrust chain efficiency
    efficiency_bonus = -2 * avg_eff;

    fitness = -endurance + 0.5*endurance_penalty + 0.3*mtow_penalty ...
              + feasibility_penalty + deficit_penalty + efficiency_bonus;
end
