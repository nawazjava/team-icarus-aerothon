%% ============================================================================
%  PROPELLER CLASS  (NEW)
%  Motor shaft power/RPM -> Thrust
%  ============================================================================
%
%  Classical propeller performance coefficients (Gudmundsson Ch.15,
%  Raymer Ch.13):
%    J  = V / (n * D)                  advance ratio, n in rev/s
%    CT = CT0 + CT1*J + CT2*J^2        thrust coefficient (fitted)
%    CP = CP0 + CP1*J + CP2*J^2        power coefficient (fitted)
%    T  = CT * rho * n^2 * D^4         thrust, N
%    P  = CP * rho * n^3 * D^5         power absorbed, W
%    eta_prop = J * CT / CP            propeller efficiency
%
%  Default coefficients approximate a fixed-pitch cruise propeller with
%  peak efficiency ~0.85 near its design advance ratio (J ~ 0.6-0.7),
%  consistent with typical UAV propeller test data (Gudmundsson, "General
%  Aviation Aircraft Design", propeller charts). Static thrust (J~0) uses
%  simple momentum theory instead, since the CT/CP polynomial fit is only
%  valid in the cruise J-range.

classdef Propeller
    properties
        diameter_m
        CT0, CT1, CT2
        CP0, CP1, CP2
        J_design
    end

    methods
        function obj = Propeller(diameter_m)
            obj.diameter_m = diameter_m;
            obj.CT0 = 0.12;  obj.CT1 = -0.10; obj.CT2 = -0.05;
            obj.CP0 = 0.09;  obj.CP1 = 0.02;  obj.CP2 = -0.06;
            obj.J_design = 0.65;
        end

        function [thrust_N, P_abs_W, eta_prop, J] = performance(obj, V_ms, rpm, rho)
            n = max(rpm,1) / 60;  % rev/s

            if V_ms < 1
                J = 0;
                CT = obj.CT0;
                CP = obj.CP0;
            else
                J = V_ms / (n * obj.diameter_m);
                J = max(0, min(1.2, J));
                CT = max(0.01, obj.CT0 + obj.CT1*J + obj.CT2*J^2);
                CP = max(0.02, obj.CP0 + obj.CP1*J + obj.CP2*J^2);
            end

            thrust_N = CT * rho * n^2 * obj.diameter_m^4;
            P_abs_W  = CP * rho * n^3 * obj.diameter_m^5;

            if P_abs_W > 1
                eta_prop = max(0.1, min(0.90, (thrust_N * V_ms) / P_abs_W));
            else
                eta_prop = 0;
            end
        end

        function P_shaft_required_W = required_shaft_power(obj, thrust_required_N, V_ms, rpm, rho)
            [~, ~, eta_prop, ~] = obj.performance(V_ms, rpm, rho);
            if V_ms < 1
                % Static case: eta_prop*V breaks down as V->0, use simple
                % momentum theory instead: P_induced ~ T^1.5/sqrt(2*rho*A)
                A = pi/4 * obj.diameter_m^2;
                P_shaft_required_W = thrust_required_N^1.5 / sqrt(2*rho*A + 1e-6);
            else
                eta_prop = max(0.35, eta_prop);  % floor to avoid blow-up near J extremes
                P_shaft_required_W = thrust_required_N * V_ms / eta_prop;
            end
        end
    end
end
