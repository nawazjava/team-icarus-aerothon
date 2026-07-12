%% ============================================================================
%  TURBOSHAFT ENGINE CLASS
%  ============================================================================

classdef TurboshaftEngine
    properties
        rated_power
        rated_rpm
        turbine_inlet_temp
        throttle_range
        altitude_range
        power_map
        sfc_map
        efficiency_map
    end
    
    methods
        function obj = TurboshaftEngine(rated_power_kw, rpm_rated)
            obj.rated_power = rated_power_kw;
            obj.rated_rpm = rpm_rated;
            obj.turbine_inlet_temp = 1100;
            obj = obj.init_performance_maps();
        end
        
        function obj = init_performance_maps(obj)
            throttle = linspace(0, 100, 11);
            altitude = linspace(0, 10000, 11);
            [Throttle_grid, Alt_grid] = meshgrid(throttle, altitude);
            
            rho_sl = 1.225;
            [~, ~, rho_alt] = atmosphere_model(Alt_grid);
            obj.power_map = obj.rated_power .* (Throttle_grid/100) .* sqrt(rho_alt/rho_sl);
            
            % SFC improves at higher throttle (better efficiency)
            obj.sfc_map = 0.2 + 0.3 * (100 - Throttle_grid) ./ 100;
            
            % Efficiency: eta = Work_out / Energy_in
            % 1 kWh of work = 3600 kJ. Fuel burned per kWh = SFC [kg/kWh].
            % Energy in fuel = SFC * LHV [kJ/kg]. LHV (jet fuel) = 43150 kJ/kg.
            % FIXED: previous formula (1/(SFC*3600*43.15)) was off by ~3-4
            % orders of magnitude and only "worked" because of the hard
            % clamp below - it wasn't actually derived from sfc_map.
            LHV_kJ_per_kg = 43150;
            obj.efficiency_map = 3600 ./ (obj.sfc_map * LHV_kJ_per_kg);
        end
        
        function [P, SFC, eta_thermal] = query_performance(obj, throttle_pct, altitude)
            throttle_vec = linspace(0, 100, size(obj.power_map, 2));
            altitude_vec = linspace(0, 10000, size(obj.power_map, 1));
            
            P = interp2(throttle_vec, altitude_vec, obj.power_map, throttle_pct, altitude, 'linear');
            SFC = interp2(throttle_vec, altitude_vec, obj.sfc_map, throttle_pct, altitude, 'linear');
            eta_thermal = interp2(throttle_vec, altitude_vec, obj.efficiency_map, throttle_pct, altitude, 'linear') * 100;
            
            % Handle extrapolation
            P = max(0, min(obj.rated_power, P));
            SFC = max(0.15, min(0.5, SFC));
            eta_thermal = max(25, min(40, eta_thermal));
        end
        
        function wf = fuel_flow(obj, throttle_pct, altitude, dt_sec)
            [P_out, SFC, ~] = obj.query_performance(throttle_pct, altitude);
            fuel_flow_rate = P_out * SFC;
            wf = fuel_flow_rate * (dt_sec / 3600);
        end
    end
end
