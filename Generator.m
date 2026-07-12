%% ============================================================================
%  GENERATOR CLASS  (NEW)
%  Engine mechanical shaft power -> 3-phase AC electrical power
%  ============================================================================
%
%  Equations / assumptions:
%    P_ac = P_shaft * eta_gen(load_frac, speed_frac)
%    eta_gen peaks ~0.96 near rated load/speed, falls off at part load
%    (iron/windage losses are a larger fraction of a smaller output).
%    Loss split (informational, for thermal bookkeeping only):
%      copper_loss ~ grows with load^2   (I^2R, dominates at high load)
%      iron_loss   ~ roughly constant with speed (dominates at part load)
%      mech_loss   ~ small, bearing/windage
%    AC side assumed regulated to a fixed line-line RMS voltage (handled
%    by the generator's own excitation/voltage regulator):
%      I_ac = P_ac / (sqrt(3) * V_ac * pf),  pf ~ 0.95 assumed
%
%  Data source: representative aerospace PMSG efficiency-curve shape
%  (Gudmundsson, "General Aviation Aircraft Design", Ch.15 electric
%  propulsion supplement; typical peak efficiency class 90-96%).
%  Replace defaults with a specific datasheet once a generator is chosen.

classdef Generator
    properties
        rated_power_kw
        rated_speed_rpm
        V_ac_line
        power_factor
        eta_peak
    end

    methods
        function obj = Generator(rated_power_kw, rated_speed_rpm, V_ac_line)
            obj.rated_power_kw  = rated_power_kw;
            obj.rated_speed_rpm = rated_speed_rpm;
            obj.V_ac_line       = V_ac_line;
            obj.power_factor    = 0.95;
            obj.eta_peak        = 0.96;
        end

        function eta = efficiency(obj, P_shaft_kw, speed_rpm)
            load_frac  = max(0, min(1.2, P_shaft_kw / max(obj.rated_power_kw,1e-6)));
            speed_frac = max(0.1, min(1.2, speed_rpm / max(obj.rated_speed_rpm,1e-6)));

            eta_load  = obj.eta_peak * (1 - exp(-4*load_frac)) / (1 - exp(-4));
            eta_speed = 1 - 0.05 * (1 - speed_frac)^2;
            eta = max(0.5, min(obj.eta_peak, eta_load * eta_speed));
        end

        function [P_ac_kw, I_ac, losses] = convert(obj, P_shaft_kw, speed_rpm)
            eta = obj.efficiency(P_shaft_kw, speed_rpm);
            P_ac_kw = P_shaft_kw * eta;
            I_ac = (P_ac_kw*1000) / (sqrt(3) * obj.V_ac_line * obj.power_factor + 1e-6);

            P_loss_kw = max(0, P_shaft_kw - P_ac_kw);
            load_frac = max(0, min(1.2, P_shaft_kw / max(obj.rated_power_kw,1e-6)));
            losses.copper_kw = P_loss_kw * 0.55 * load_frac;
            losses.iron_kw   = P_loss_kw * 0.30 * (1 - 0.3*load_frac);
            losses.mech_kw   = max(0, P_loss_kw - losses.copper_kw - losses.iron_kw);
        end

        function P_shaft_kw = required_shaft_power(obj, P_ac_required_kw, speed_rpm)
            % Inverse problem: given required AC output, find required
            % shaft input. One re-evaluation of eta at the resulting
            % operating point is enough for this level of fidelity.
            eta_guess = obj.eta_peak * 0.9;
            P_shaft_kw = P_ac_required_kw / eta_guess;
            eta = obj.efficiency(P_shaft_kw, speed_rpm);
            P_shaft_kw = P_ac_required_kw / max(0.5, eta);
        end
    end
end
