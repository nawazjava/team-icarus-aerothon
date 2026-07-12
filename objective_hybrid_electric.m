%% ============================================================================
%  OBJECTIVE FUNCTION FOR OPTIMIZATION
%  ============================================================================

function fitness = objective_hybrid_electric(design, simulator, baseline_design, aircraft)
    % Multi-objective fitness function
    % Minimize: -(endurance) + weight_penalty + infeasibility_penalty
    %
    % Input: design = [engine_power_kw, battery_capacity_Ah, num_motors]
    % Output: fitness (scalar, to minimize)
    
    % Update design with new parameters
    design_opt = baseline_design;
    design_opt.engine_power_kw = design(1);
    design_opt.battery_capacity_Ah = design(2);
    design_opt.num_motors = design(3);
    
    % Update battery
    simulator.battery = BatteryPack('LiPo', 48, design(2), 0.95);
    
    % Run simulation
    try
        results = simulator.run_simulation(design_opt);
    catch
        % If simulation fails, penalize heavily
        fitness = 1e6;
        return;
    end
    
    % Extract metrics
    endurance = results.endurance_hours;
    feasible = results.mission_feasible;
    
    % Objective 1: Maximize endurance (negate for minimization)
    endurance_penalty = max(0, 5 - endurance) / 5;  % Penalty if < 5 hours
    
    % Objective 2: Minimize MTOW impact (prefer lighter designs)
    mtow_est = 500 + design(2) * 0.5 + design(1) * 0.1;  % Rough MTOW estimate
    mtow_penalty = max(0, mtow_est - aircraft.MTOW) / 500;
    
    % Objective 3: Feasibility (hard constraint)
    feasibility_penalty = 1e6 * (~feasible);  % Massive penalty if infeasible
    
    % Weighted combination
    fitness = -endurance + 0.5 * endurance_penalty + 0.3 * mtow_penalty + feasibility_penalty;
    
    % NOTE: previously clamped to max(0, fitness). That clamp made every
    % feasible design (endurance ~4-7 hrs, so -endurance already < 0)
    % collapse to fitness = 0, giving PSO no gradient to distinguish
    % between designs. PSO only needs relative ordering to minimize, so
    % the signed value is kept as-is - do NOT clamp here.
end
