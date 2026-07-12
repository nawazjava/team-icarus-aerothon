%% ============================================================================
%  DC BUS CLASS  (NEW)
%  Central electrical node: rectifier(generator) + battery -> inverter
%  ============================================================================
%
%  Power balance enforced at every timestep:
%    P_in (from rectifier) + P_battery_discharge
%       = P_out (to inverter) + P_battery_charge + P_bus_loss
%
%  Bus loss modeled as a lumped resistive loss (busbar/connector
%  resistance) proportional to the square of net bus current:
%    P_bus_loss = I_bus^2 * R_bus
%
%  Bus voltage is treated as approximately regulated (set by the battery
%  pack, clamped to bus limits) - a standard simplification at conceptual
%  design level (Mohan et al.; similar lumped-bus assumptions appear in
%  NASA/Boeing hybrid-electric aircraft powertrain studies).

classdef DCBus
    properties
        V_nominal
        V_min
        V_max
        R_bus
        I_max
    end

    methods
        function obj = DCBus(V_nominal, R_bus, I_max)
            obj.V_nominal = V_nominal;
            obj.V_min = V_nominal * 0.85;
            obj.V_max = V_nominal * 1.15;
            if nargin < 2, R_bus = 0.01; end
            if nargin < 3, I_max = 800; end
            obj.R_bus = R_bus;
            obj.I_max = I_max;
        end

        function [P_bus_loss_kw, I_bus, feasible] = balance(obj, P_in_kw, P_out_kw, V_bus)
            P_net_kw = abs(P_in_kw - P_out_kw);
            I_bus = (P_net_kw*1000) / max(V_bus, 1e-3);
            P_bus_loss_kw = (I_bus^2 * obj.R_bus) / 1000;
            feasible = (V_bus >= obj.V_min) && (V_bus <= obj.V_max) && (I_bus <= obj.I_max);
        end
    end
end
