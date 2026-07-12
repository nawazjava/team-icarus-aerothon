%% ============================================================================
%  ENERGY MANAGEMENT CONTROLLER CLASS  (NEW)
%  Decides battery vs engine-generator power split at every timestep
%  ============================================================================
%
%  Replaces the previous fixed "if takeoff: 60/40" rule with a strategy
%  keyed on mission phase, battery SoC, and instantaneous power demand.
%
%  Inputs:  mission phase, battery SoC, DC-bus power demand, generator
%           rated power, battery capacity, bus voltage
%  Outputs: P_battery_dc_kw            (+ = discharging into bus, - = charging)
%           P_generator_dc_required_kw (power the generator path must supply)
%
%  Strategy (documented assumptions):
%    Takeoff/Climb : battery assists (discharges) whenever demand exceeds
%                    the generator's rated continuous power, up to the
%                    battery's max discharge C-rate.
%    Cruise        : generator preferentially supplies full demand; any
%                    spare generator capacity trickle-charges the battery
%                    toward a cruise SoC target (default 80%).
%    Loiter        : battery preferentially supplies power (fuel economy)
%                    down to a minimum reserve SoC (default 30%).
%    Descent/Land  : minimal propulsion; battery covers the small demand.
%    Safety floor  : if SoC <= absolute floor (default 20%), generator is
%                    forced to cover ~100% of demand regardless of phase.

classdef EnergyManagementController
    properties
        soc_min_reserve
        soc_loiter_floor
        soc_cruise_target
        battery_max_c_rate
    end

    methods
        function obj = EnergyManagementController(soc_min_reserve, soc_loiter_floor, soc_cruise_target, battery_max_c_rate)
            if nargin < 1, soc_min_reserve = 0.20; end
            if nargin < 2, soc_loiter_floor = 0.30; end
            if nargin < 3, soc_cruise_target = 0.80; end
            if nargin < 4, battery_max_c_rate = 2.5; end
            obj.soc_min_reserve    = soc_min_reserve;
            obj.soc_loiter_floor   = soc_loiter_floor;
            obj.soc_cruise_target  = soc_cruise_target;
            obj.battery_max_c_rate = battery_max_c_rate;
        end

        function [P_battery_dc_kw, P_generator_dc_required_kw] = decide(obj, ...
                phase_name, soc, P_bus_demand_kw, generator_rated_kw, battery_capacity_Ah, V_bus)

            max_batt_power_kw = (obj.battery_max_c_rate * battery_capacity_Ah * V_bus) / 1000;

            if soc <= obj.soc_min_reserve
                % Safety override: generator covers everything (small
                % trickle charge only if it has genuine spare capacity)
                P_battery_dc_kw = -min(0.05*generator_rated_kw, max(0, generator_rated_kw - P_bus_demand_kw));
                P_generator_dc_required_kw = P_bus_demand_kw - P_battery_dc_kw;
                return;
            end

            switch phase_name
                case {'takeoff','climb'}
                    if P_bus_demand_kw > generator_rated_kw
                        P_battery_dc_kw = min(max_batt_power_kw, P_bus_demand_kw - generator_rated_kw);
                    else
                        P_battery_dc_kw = 0;
                    end

                case 'cruise'
                    if P_bus_demand_kw <= generator_rated_kw && soc < obj.soc_cruise_target
                        surplus_kw = min(generator_rated_kw - P_bus_demand_kw, 0.15*generator_rated_kw);
                        P_battery_dc_kw = -surplus_kw;   % negative = charging
                    elseif P_bus_demand_kw > generator_rated_kw
                        P_battery_dc_kw = min(max_batt_power_kw, P_bus_demand_kw - generator_rated_kw);
                    else
                        P_battery_dc_kw = 0;
                    end

                case 'loiter'
                    if soc > obj.soc_loiter_floor
                        P_battery_dc_kw = min(max_batt_power_kw, P_bus_demand_kw);
                    else
                        P_battery_dc_kw = 0;
                    end

                otherwise  % descent / landing
                    P_battery_dc_kw = min(max_batt_power_kw, P_bus_demand_kw);
            end

            P_generator_dc_required_kw = max(0, P_bus_demand_kw - P_battery_dc_kw);
        end
    end
end
