%% ============================================================================
%  ELECTRIC MOTOR CLASS
%  ============================================================================

classdef ElectricMotor
    properties
        max_power
        max_rpm
        efficiency_map
    end
    
    methods
        function obj = ElectricMotor(max_power_kw, max_rpm)
            obj.max_power = max_power_kw;
            obj.max_rpm = max_rpm;
            
            power_pct = linspace(10, 100, 10);
            speed_pct = linspace(10, 100, 10);
            [P_grid, S_grid] = meshgrid(power_pct, speed_pct);
            obj.efficiency_map = 0.70 + 0.25 * (P_grid/100) + 0.05 * (S_grid/100);
        end
        
        function eta = motor_efficiency(obj, power_kw, speed_rpm)
            power_pct = 100 * power_kw / obj.max_power;
            speed_pct = 100 * speed_rpm / obj.max_rpm;
            % FIXED: clamp query points into the [10,100] grid range before
            % interpolating. Without this, interp2 returns NaN outside the
            % grid, and MATLAB's max/min silently ignore NaN - which meant
            % very light loads (power_pct < 10) were snapping to the BEST
            % case (0.98) instead of degrading like a real motor at part-load.
            power_pct_q = max(10, min(100, power_pct));
            speed_pct_q = max(10, min(100, speed_pct));
            eta = interp2(linspace(10, 100, 10), linspace(10, 100, 10), ...
                obj.efficiency_map, power_pct_q, speed_pct_q, 'linear');
            eta = max(0.5, min(0.98, eta));
        end
        
        function power_in = electrical_input(obj, power_mech_W, speed_rpm)
            eta = obj.motor_efficiency(power_mech_W/1000, speed_rpm);
            power_in = power_mech_W / eta;
        end
    end
end
