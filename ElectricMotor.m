%% ============================================================================
%  ELECTRIC MOTOR CLASS  (UPGRADED)
%  ============================================================================
%
%  Adds a torque-speed operating envelope on top of the existing
%  power-based efficiency map:
%    - Below base speed: constant max torque (current-limited region)
%    - Above base speed: constant max power, falling max torque
%      (field-weakening region): T_max(rpm) = P_rated / omega
%
%  The efficiency map is kept as a function of (power%, speed%) since it
%  already captures the right qualitative shape (peak near rated
%  load/speed); reworking it torque-based would need motor-specific test
%  data this project doesn't have.
%
%  Data source: generic BLDC/PMSM torque-speed envelope shape
%  (Gudmundsson Ch.15 electric-propulsion supplement; base speed
%  typically ~40-60% of max speed on aerospace PMSM datasheets).

classdef ElectricMotor
    properties
        max_power
        max_rpm
        base_rpm
        max_torque_Nm
        efficiency_map
    end

    methods
        function obj = ElectricMotor(max_power_kw, max_rpm)
            obj.max_power = max_power_kw;
            obj.max_rpm = max_rpm;
            obj.base_rpm = 0.5 * max_rpm;   % field-weakening starts at 50% max speed

            omega_base = obj.base_rpm * 2*pi/60;
            obj.max_torque_Nm = (max_power_kw*1000) / max(omega_base,1e-6);

            power_pct = linspace(10, 100, 10);
            speed_pct = linspace(10, 100, 10);
            [P_grid, S_grid] = meshgrid(power_pct, speed_pct);
            obj.efficiency_map = 0.70 + 0.25 * (P_grid/100) + 0.05 * (S_grid/100);
        end

        function T_max = max_torque_at_speed(obj, rpm)
            if rpm <= obj.base_rpm
                T_max = obj.max_torque_Nm;                 % constant-torque region
            else
                omega = max(rpm,1) * 2*pi/60;
                T_max = (obj.max_power*1000) / omega;       % constant-power (field-weakening) region
            end
        end

        function eta = motor_efficiency(obj, power_kw, speed_rpm)
            power_pct = 100 * power_kw / obj.max_power;
            speed_pct = 100 * speed_rpm / obj.max_rpm;
            % Clamp query points into the [10,100] grid range before
            % interpolating - interp2 returns NaN outside the grid, which
            % previously let very light loads snap to the best-case value
            % instead of degrading like a real motor at part-load.
            power_pct_q = max(10, min(100, power_pct));
            speed_pct_q = max(10, min(100, speed_pct));
            eta = interp2(linspace(10, 100, 10), linspace(10, 100, 10), ...
                obj.efficiency_map, power_pct_q, speed_pct_q, 'linear');
            eta = max(0.5, min(0.98, eta));
        end

        function [torque_Nm, feasible] = torque_from_power(obj, power_kw, speed_rpm)
            omega = max(speed_rpm,1) * 2*pi/60;
            torque_Nm = (power_kw*1000) / omega;
            T_max = obj.max_torque_at_speed(speed_rpm);
            feasible = torque_Nm <= T_max;
            torque_Nm = min(torque_Nm, T_max);
        end

        function power_in = electrical_input(obj, power_mech_kw, speed_rpm)
            eta = obj.motor_efficiency(power_mech_kw, speed_rpm);
            power_in = power_mech_kw / eta;
        end
    end
end
