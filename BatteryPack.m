%% ============================================================================
%  BATTERY PACK CLASS  (UPGRADED)
%  ============================================================================
%
%  Adds to the original SoC/Peukert model:
%    - Open-circuit voltage vs SoC: piecewise-linear discharge curve
%      (steep near empty/full, flat plateau in the middle - typical
%      Li-ion/LiPo shape; see Plett, "Battery Management Systems", Vol 1)
%    - Lumped internal resistance (ESR)
%    - Terminal voltage = OCV -/+ I*R_int (sag under discharge, rise on charge)
%    - Separate charge/discharge coulombic efficiencies
%
%  Simplification documented: single lumped ESR (no separate
%  charge-transfer/diffusion RC branches), no explicit thermal model
%  beyond the ESR itself.

classdef BatteryPack
    properties
        chemistry
        nominal_voltage
        capacity_Ah
        energy_Wh
        peukert_k
        soc_min
        soc_max
        max_discharge_C
        R_int_ohm
        eta_charge
        eta_discharge
    end

    methods
        function obj = BatteryPack(chemistry, nominal_V, capacity_Ah, peukert_k)
            obj.chemistry = chemistry;
            obj.nominal_voltage = nominal_V;
            obj.capacity_Ah = capacity_Ah;
            obj.peukert_k = peukert_k;
            obj.energy_Wh = nominal_V * capacity_Ah;

            if strcmp(chemistry, 'LiPo')
                obj.soc_min = 0.2;
                obj.soc_max = 1.0;
                obj.max_discharge_C = 3;
                obj.eta_charge = 0.97;
                obj.eta_discharge = 0.98;
            else  % LiFePO4
                obj.soc_min = 0.1;
                obj.soc_max = 1.0;
                obj.max_discharge_C = 2;
                obj.eta_charge = 0.96;
                obj.eta_discharge = 0.97;
            end

            % Pack-level ESR (incl. busbars/connections), scaled inversely
            % with capacity: ~0.5 mOhm per Ah at 100 Ah reference, typical
            % of aerospace-grade Li-ion packs in the 48V class.
            obj.R_int_ohm = 0.0005 * (100 / max(capacity_Ah,1));
        end

        function ocv = open_circuit_voltage(obj, soc)
            % Piecewise-linear OCV(SoC), normalized so OCV = nominal_voltage
            % at soc = 0.5 (typical Li-ion/LiPo rest-voltage curve shape)
            soc = max(0, min(1, soc));
            if soc < 0.2
                frac = soc/0.2;
                ocv = obj.nominal_voltage * (0.88 + 0.06*frac);
            elseif soc > 0.8
                frac = (soc-0.8)/0.2;
                ocv = obj.nominal_voltage * (1.02 + 0.06*frac);
            else
                frac = (soc-0.2)/0.6;
                ocv = obj.nominal_voltage * (0.94 + 0.08*frac);
            end
        end

        function v_term = terminal_voltage(obj, soc, current_A, mode)
            ocv = obj.open_circuit_voltage(soc);
            if strcmp(mode, 'charge')
                v_term = ocv + current_A * obj.R_int_ohm;
            else
                v_term = ocv - current_A * obj.R_int_ohm;
            end
        end

        function [soc_new, v_term, current_A] = discharge_step(obj, soc, power_W, dt_sec)
            % Power-controlled discharge: fixed-point solve for current
            % since terminal voltage sags with current (converges in a
            % couple of iterations at this ESR scale)
            v_term = obj.open_circuit_voltage(soc);
            for k = 1:3
                current_A = power_W / max(v_term, 1e-3);
                v_term = obj.terminal_voltage(soc, current_A, 'discharge');
            end

            c_rate = current_A / obj.capacity_Ah;
            peukert_correction = max(c_rate,1e-6) ^ (1 - obj.peukert_k);
            ah_consumed = current_A * (dt_sec/3600) / peukert_correction / obj.eta_discharge;

            soc_new = soc - (ah_consumed / obj.capacity_Ah);
            soc_new = max(obj.soc_min, min(obj.soc_max, soc_new));
        end

        function [soc_new, v_term, current_A] = charge_step(obj, soc, power_W, dt_sec)
            v_term = obj.open_circuit_voltage(soc);
            for k = 1:3
                current_A = power_W / max(v_term, 1e-3);
                v_term = obj.terminal_voltage(soc, current_A, 'charge');
            end

            ah_added = current_A * (dt_sec/3600) * obj.eta_charge;
            soc_new = soc + (ah_added / obj.capacity_Ah);
            soc_new = max(obj.soc_min, min(obj.soc_max, soc_new));
        end

        function [feasible, soc_remaining] = check_feasibility(obj, mission_energy_Wh)
            available_energy = obj.energy_Wh * (obj.soc_max - obj.soc_min);
            feasible = mission_energy_Wh <= available_energy;
            soc_remaining = obj.soc_max - (mission_energy_Wh / obj.energy_Wh);
        end
    end
end
