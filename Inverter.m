%% ============================================================================
%  INVERTER CLASS  (NEW)
%  DC bus -> 3-phase AC for the motor(s)
%  ============================================================================
%
%  Standard PWM voltage-source inverter. Switching + conduction losses are
%  lumped into a single load-dependent efficiency curve, consistent with
%  typical aerospace SiC/IGBT inverter datasheets (peak ~97%, dropping at
%  light load because fixed switching losses become a larger fraction of
%  a smaller output).
%
%    eta_inv(load_frac) = eta_peak, penalized at light load and above-rated
%    P_ac_motor = P_dc_in * eta_inv

classdef Inverter
    properties
        rated_power_kw
        eta_peak
        I_max
    end

    methods
        function obj = Inverter(rated_power_kw, I_max)
            obj.rated_power_kw = rated_power_kw;
            obj.eta_peak = 0.97;
            if nargin < 2, I_max = 600; end
            obj.I_max = I_max;
        end

        function eta = efficiency(obj, P_dc_kw)
            load_frac = max(0.02, min(1.2, P_dc_kw / max(obj.rated_power_kw,1e-6)));
            light_load_penalty = 0.03 * (1/load_frac - 1) * (load_frac < 0.3);
            eta = obj.eta_peak - light_load_penalty - 0.03*max(0, load_frac - 1);
            eta = max(0.85, min(obj.eta_peak, eta));
        end

        function [P_ac_kw, eta] = convert(obj, P_dc_kw)
            eta = obj.efficiency(P_dc_kw);
            P_ac_kw = P_dc_kw * eta;
        end

        function P_dc_required_kw = required_dc_power(obj, P_ac_required_kw)
            eta = obj.efficiency(P_ac_required_kw); % approx: load ~ output level
            P_dc_required_kw = P_ac_required_kw / max(0.85, eta);
        end
    end
end
