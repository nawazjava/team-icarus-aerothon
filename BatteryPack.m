%% ============================================================================
%  BATTERY PACK CLASS
%  ============================================================================

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
            else  % LiFePO4
                obj.soc_min = 0.1;
                obj.soc_max = 1.0;
                obj.max_discharge_C = 2;
            end
        end
        
        function soc_new = discharge_step(obj, soc, power_W, voltage_V, dt_sec)
            I_discharge = power_W / voltage_V;
            I_nominal = obj.capacity_Ah;
            c_rate = I_discharge / I_nominal;
            peukert_correction = c_rate ^ (1 - obj.peukert_k);
            
            ah_consumed = I_discharge * (dt_sec / 3600) / peukert_correction;
            soc_new = soc - (ah_consumed / obj.capacity_Ah);
            soc_new = max(obj.soc_min, min(obj.soc_max, soc_new));
        end
        
        function [feasible, soc_remaining] = check_feasibility(obj, mission_energy_Wh)
            available_energy = obj.energy_Wh * (obj.soc_max - obj.soc_min);
            feasible = mission_energy_Wh <= available_energy;
            soc_remaining = obj.soc_max - (mission_energy_Wh / obj.energy_Wh);
        end
    end
end
