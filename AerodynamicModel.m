%% ============================================================================
%  AERODYNAMIC MODEL CLASS  (UPGRADED)
%  ============================================================================
%
%  Adds an explicit required_thrust() method. Previously power_required()
%  jumped straight from Drag to Power (P = D*V), silently assuming a
%  propeller efficiency of 1. Now the chain is:
%     Lift/Drag -> Required Thrust -> [Propeller] -> Required Shaft Power
%  so propeller efficiency is modeled explicitly rather than folded in.
%  power_required() is kept for backward compatibility / sanity checks
%  (it now represents "aerodynamic power" at the airframe, not shaft power).

classdef AerodynamicModel
    properties
        wing_area
        fuselage_length
        fuselage_diameter
        aspect_ratio
        Cd0_cruise
        Cd0_takeoff
        oswald_efficiency
        altitude_min
        altitude_max
        speed_cruise
        speed_min
    end

    methods
        function obj = AerodynamicModel(wing_area, ar, cd0_cruise)
            obj.wing_area = wing_area;
            obj.aspect_ratio = ar;
            obj.Cd0_cruise = cd0_cruise;
            obj.Cd0_takeoff = cd0_cruise * 1.3;
            obj.oswald_efficiency = 0.95;
            obj.altitude_min = 0;
            obj.altitude_max = 10000;
            obj.speed_cruise = 60;  % m/s
            obj.speed_min = 20;     % m/s (stall + margin)
        end

        function Cd = drag_coefficient(obj, CL, config)
            if strcmp(config, 'cruise')
                cd0 = obj.Cd0_cruise;
            else
                cd0 = obj.Cd0_takeoff;
            end
            pi_e_AR = pi * obj.oswald_efficiency * obj.aspect_ratio;
            Cd = cd0 + (CL^2) / pi_e_AR;
        end

        function D = drag_force(obj, alt, V, W, config)
            [~, ~, rho] = atmosphere_model(alt);
            q = 0.5 * rho * V^2;
            CL = W / (q * obj.wing_area + 1e-6);
            Cd = obj.drag_coefficient(CL, config);
            D = q * obj.wing_area * Cd;
        end

        function T_req = required_thrust(obj, alt, V, W, config)
            % Steady, level-flight assumption: required thrust = drag.
            % (Climb phases in this model use a constant climb speed
            % rather than a flight-path angle, so no explicit W*sin(gamma)
            % term is added - documented simplification.)
            T_req = obj.drag_force(alt, V, W, config);
        end

        function P_req = power_required(obj, alt, V, W, config)
            % Airframe aerodynamic power (NOT shaft power - propeller
            % efficiency is applied separately by the Propeller class)
            D = obj.drag_force(alt, V, W, config);
            P_req = D * V;
        end
    end
end
