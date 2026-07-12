%% ============================================================================
%  RECTIFIER CLASS  (NEW)
%  Generator AC output -> DC bus voltage
%  ============================================================================
%
%  Standard 3-phase bridge rectifier relations:
%    V_dc = 1.35 * V_ac_line - 2*V_drop     (diode/switch forward drop)
%    eta_rect = eta0 - k_sw * load_frac      (switching loss grows with load)
%    P_dc = P_ac * eta_rect
%
%  Data source: standard power-electronics 3-phase bridge topology
%  (Mohan, Undeland & Robbins, "Power Electronics", 3rd ed.). Values are
%  representative, not tied to a specific part number.

classdef Rectifier
    properties
        V_drop
        eta0
        k_sw
        I_max
    end

    methods
        function obj = Rectifier(I_max)
            obj.V_drop = 1.5;
            obj.eta0   = 0.99;
            obj.k_sw   = 0.03;
            if nargin < 1
                I_max = 500;
            end
            obj.I_max = I_max;
        end

        function [P_dc_kw, V_dc, I_dc, eta] = convert(obj, P_ac_kw, V_ac_line, rated_power_kw)
            load_frac = max(0, min(1.2, P_ac_kw / max(rated_power_kw,1e-6)));
            eta = max(0.90, obj.eta0 - obj.k_sw * load_frac);

            V_dc = max(1e-3, 1.35 * V_ac_line - 2*obj.V_drop);
            P_dc_kw = P_ac_kw * eta;
            I_dc = (P_dc_kw*1000) / V_dc;

            if I_dc > obj.I_max
                I_dc = obj.I_max;
                P_dc_kw = (I_dc * V_dc) / 1000;
            end
        end

        function P_ac_required_kw = required_ac_power(obj, P_dc_required_kw, rated_power_kw)
            load_frac = max(0, min(1.2, P_dc_required_kw / max(rated_power_kw,1e-6)));
            eta = max(0.90, obj.eta0 - obj.k_sw * load_frac);
            P_ac_required_kw = P_dc_required_kw / eta;
        end
    end
end
