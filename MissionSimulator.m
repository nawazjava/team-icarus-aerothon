%% ============================================================================
%  MISSION SIMULATOR CLASS
%  ============================================================================

classdef MissionSimulator
    properties
        aero_model
        engine
        battery
        motor
        phases
        dt
    end
    
    methods
        function obj = MissionSimulator(aero, engine, battery, motor, dt)
            obj.aero_model = aero;
            obj.engine = engine;
            obj.battery = battery;
            obj.motor = motor;
            obj.dt = dt;
        end
        
        function obj = setup_mission(obj, mission_struct)
            obj.phases = mission_struct.phases;
        end
        
        function [results] = run_simulation(obj, design)
            % Initialize state
            MTOW = 1000;
            payload = 200;
            empty_weight = MTOW - payload;
            fuel_mass = 150;
            % FIXED: battery_mass was hardcoded to 50 kg regardless of the
            % optimized capacity, so PSO could grow the battery "for free".
            % Now derived from obj.battery.energy_Wh using an assumed
            % specific energy for LiPo packs (~150 Wh/kg is a reasonable
            % pack-level figure incl. casing/BMS - cite/adjust per your
            % chosen cell datasheet in the report).
            battery_specific_energy_Wh_per_kg = 150;
            battery_mass = obj.battery.energy_Wh / battery_specific_energy_Wh_per_kg;
            weight = (empty_weight + fuel_mass + battery_mass) * 9.81;
            
            % Battery initial state
            soc_battery = 0.9;
            
            % Preallocate
            max_steps = sum([obj.phases.duration]) / obj.dt;
            t_array = zeros(max_steps, 1);
            alt_array = zeros(max_steps, 1);
            speed_array = zeros(max_steps, 1);
            weight_array = zeros(max_steps, 1);
            P_aero_array = zeros(max_steps, 1);
            P_engine_array = zeros(max_steps, 1);
            P_elec_array = zeros(max_steps, 1);
            soc_array = zeros(max_steps, 1);
            fuel_array = zeros(max_steps, 1);
            
            % Mission loop
            t = 0;
            step = 0;
            phase_idx = 1;
            phase_time = 0;
            
            while phase_idx <= length(obj.phases) && step < max_steps
                step = step + 1;
                phase = obj.phases(phase_idx);
                t = t + obj.dt;
                phase_time = phase_time + obj.dt;
                
                if phase_time >= phase.duration
                    phase_idx = phase_idx + 1;
                    phase_time = 0;
                    if phase_idx > length(obj.phases)
                        break;
                    end
                    phase = obj.phases(phase_idx);
                end
                
                alt = phase.altitude;
                speed = phase.speed;
                
                % Aerodynamic power requirement
                P_aero = obj.aero_model.power_required(alt, speed, weight, 'cruise');
                
                % Power distribution
                if strcmp(design.power_split_strategy, 'thermal_dominant')
                    throttle_thermal = min(100, 100 * P_aero / (design.engine_power_kw * 1000 + 1e-6));
                    P_engine = (throttle_thermal / 100) * design.engine_power_kw * 1000;
                    P_elec = max(0, P_aero - P_engine);
                elseif strcmp(design.power_split_strategy, 'hybrid_blending')
                    if strcmp(phase.name, 'takeoff') || strcmp(phase.name, 'climb')
                        P_engine = P_aero * 0.6;
                        P_elec = P_aero * 0.4;
                    else
                        P_engine = P_aero * 0.95;
                        P_elec = 0;
                    end
                else  % electric_boosting
                    P_engine = P_aero * 0.5;
                    P_elec = P_aero * 0.5;
                end
                
                % Engine fuel consumption
                [P_eng, SFC, ~] = obj.engine.query_performance(...
                    100 * P_engine / (design.engine_power_kw * 1000 + 1e-6), alt);
                fuel_consumed = obj.engine.fuel_flow(...
                    100 * P_engine / (design.engine_power_kw * 1000 + 1e-6), alt, obj.dt);
                
                % FIXED: P_elec above is mechanical power required at the
                % prop. Previously this was fed straight into the battery
                % as if the motor were 100% efficient, and num_motors had
                % no effect anywhere in the simulation. Now: split load
                % across num_motors (affects each motor's loading point on
                % the efficiency map), look up motor efficiency, and draw
                % the corresponding higher electrical power from the pack.
                num_motors = max(1, design.num_motors);
                P_elec_per_motor_kw = (P_elec / 1000) / num_motors;
                motor_rpm_assumed = 0.6 * obj.motor.max_rpm; % nominal cruise operating point
                eta_motor = obj.motor.motor_efficiency(P_elec_per_motor_kw, motor_rpm_assumed);
                P_elec_electrical = P_elec / eta_motor; % electrical draw from battery, incl. motor losses

                % Battery update
                soc_battery = obj.battery.discharge_step(soc_battery, P_elec_electrical, 48, obj.dt);
                
                % Weight update
                fuel_mass = fuel_mass - fuel_consumed;
                weight = (empty_weight + fuel_mass + battery_mass) * 9.81;
                
                % Store results
                t_array(step) = t;
                alt_array(step) = alt;
                speed_array(step) = speed;
                weight_array(step) = weight / 9.81;
                P_aero_array(step) = P_aero / 1000;
                P_engine_array(step) = P_engine / 1000;
                P_elec_array(step) = P_elec / 1000;
                soc_array(step) = soc_battery * 100;
                fuel_array(step) = fuel_mass;
            end
            
            % Trim arrays
            t_array = t_array(1:step);
            alt_array = alt_array(1:step);
            speed_array = speed_array(1:step);
            weight_array = weight_array(1:step);
            P_aero_array = P_aero_array(1:step);
            P_engine_array = P_engine_array(1:step);
            P_elec_array = P_elec_array(1:step);
            soc_array = soc_array(1:step);
            fuel_array = fuel_array(1:step);
            
            % Calculate metrics
            endurance_hours = t / 3600;
            fuel_burned = 150 - fuel_array(end);
            avg_power = mean(P_engine_array + P_elec_array);
            avg_efficiency = mean(P_engine_array) / (mean(P_engine_array) + mean(P_elec_array) + 1e-6);
            
            % Feasibility
            mission_feasible = (fuel_array(end) > 10) && (soc_array(end) > 20) && (weight_array(end) > 0);
            
            % Return results structure
            results.time = t_array;
            results.altitude = alt_array;
            results.speed = speed_array;
            results.mass = weight_array;
            results.P_aero = P_aero_array;
            results.P_engine = P_engine_array;
            results.P_electric = P_elec_array;
            results.soc = soc_array;
            results.fuel_mass = fuel_array;
            results.endurance_hours = endurance_hours;
            results.fuel_burned = fuel_burned;
            results.mission_feasible = mission_feasible;
            results.avg_efficiency = avg_efficiency;
        end
    end
end
