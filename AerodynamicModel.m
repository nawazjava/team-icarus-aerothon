%% ============================================================================
%  AERODYNAMIC MODEL CLASS
%  ============================================================================

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
            P0 = 101325;  % Pa
            q = 0.5 * rho * V^2;
            CL = W / (q * obj.wing_area + 1e-6);
            Cd = obj.drag_coefficient(CL, config);
            D = q * obj.wing_area * Cd;
        end
        
        function P_req = power_required(obj, alt, V, W, config)
            D = obj.drag_force(alt, V, W, config);
            P_req = D * V;
        end
    end
end
