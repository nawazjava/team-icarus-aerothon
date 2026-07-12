%% ============================================================================
%  MISSION SIMULATOR CLASS  (MAJOR REWRITE)
%  Full series-hybrid-electric propulsion chain
%  ============================================================================
%
%  Chain modeled at every timestep:
%
%    Aerodynamics -> Required Thrust
%         -> Propeller -> Required Shaft Power (per motor)
%         -> Gearbox (fixed ratio + efficiency)
%         -> Motor (mech->elec, torque-speed envelope checked)
%         -> Inverter (required AC power for the motor(s))
%         -> Energy Management Controller decides Battery vs Generator split
%         -> Battery step (SoC, terminal voltage)
%         -> Rectifier (reverse: AC power required from generator)
%         -> Generator (reverse: shaft power required from engine)
%         -> Engine (throttle %, fuel flow, capped at rated power)
%
%  Then a FORWARD pass re-derives what the generator/rectifier/DC bus
%  actually deliver (using the capped engine shaft power), so bus losses
%  and any supply shortfall are logged honestly rather than assumed away.
%
%  Simplification documented: required power is solved backward through
%  the chain (aircraft -> engine) each timestep rather than iterating to
%  a fully self-consistent simultaneous electrical solution. This is a
%  standard simplification at conceptual/preliminary design level -
%  component efficiencies are evaluated at their local operating point,
%  not solved jointly. It is flagged here rather than hidden, and the
%  forward cross-check (P_bus_loss_kw, max_power_deficit_kw) exists
%  specifically so any inconsistency shows up in the results instead of
%  being silently absorbed.

classdef MissionSimulator
    properties
        aero
        propeller
        motor
        inverter
        dcbus
        battery
        rectifier
        generator
        engine
        emc
        phases
        dt
        gearbox_ratio       % motor_rpm / propeller_rpm
        eta_gearbox         % fixed gearbox efficiency
        motor_rpm_nominal   % assumed constant motor operating speed, RPM
    end

    methods
        function obj = MissionSimulator(aero, propeller, motor, inverter, dcbus, ...
                battery, rectifier, generator, engine, emc, dt)
            obj.aero = aero;
            obj.propeller = propeller;
            obj.motor = motor;
            obj.inverter = inverter;
            obj.dcbus = dcbus;
            obj.battery = battery;
            obj.rectifier = rectifier;
            obj.generator = generator;
            obj.engine = engine;
            obj.emc = emc;
            obj.dt = dt;
            obj.gearbox_ratio = 3.0;      % typical direct-drive-avoidant reduction for a cruise prop
            obj.eta_gearbox = 0.97;
            obj.motor_rpm_nominal = 0.6 * motor.max_rpm;
        end

        function obj = setup_mission(obj, mission_struct)
            obj.phases = mission_struct.phases;
        end

        function results = run_simulation(obj, design)
            MTOW = 1000; payload = 200;
            empty_weight = MTOW - payload;
            fuel_mass = 150;

            battery_specific_energy_Wh_per_kg = 150; % pack-level, incl. casing/BMS
            battery_mass = obj.battery.energy_Wh / battery_specific_energy_Wh_per_kg;
            weight_N = (empty_weight + fuel_mass + battery_mass) * 9.81;

            soc = 0.9;
            num_motors = max(1, round(design.num_motors));
            prop_rpm = obj.motor_rpm_nominal / obj.gearbox_ratio;
            motor_rpm = prop_rpm * obj.gearbox_ratio;

            max_steps = ceil(sum([obj.phases.duration]) / obj.dt);

            field_names = {'t','alt','speed','mass_kg','T_req','P_prop_shaft_kw', ...
                'motor_torque_Nm','eta_motor','P_motor_elec_kw','eta_inverter', ...
                'P_dc_bus_req_kw','P_battery_dc_kw','soc','v_batt','eta_generator', ...
                'P_gen_ac_kw','eta_rect','P_rect_dc_kw','P_bus_loss_kw', ...
                'P_eng_shaft_kw','throttle_pct','SFC','eta_thermal','fuel_mass', ...
                'deficit_kw','total_efficiency'};
            L = struct();
            for i = 1:numel(field_names)
                L.(field_names{i}) = zeros(max_steps,1);
            end

            LHV_kJ_per_kg = 43150; % jet fuel lower heating value

            t = 0; step = 0; phase_idx = 1; phase_time = 0;
            max_deficit_kw = 0;

            while phase_idx <= length(obj.phases) && step < max_steps
                step = step + 1;
                phase = obj.phases(phase_idx);
                t = t + obj.dt;
                phase_time = phase_time + obj.dt;
                if phase_time >= phase.duration
                    phase_idx = phase_idx + 1;
                    phase_time = 0;
                    if phase_idx > length(obj.phases), break; end
                    phase = obj.phases(phase_idx);
                end

                alt = phase.altitude; V = phase.speed;
                [~, ~, rho] = atmosphere_model(alt);

                % ---- 1. Aerodynamics -> required thrust ----
                T_req_total = obj.aero.required_thrust(alt, V, weight_N, 'cruise');
                T_req_per_prop = T_req_total / num_motors;

                % ---- 2. Propeller -> required shaft power (per motor) ----
                P_prop_shaft_req_W = obj.propeller.required_shaft_power(T_req_per_prop, V, prop_rpm, rho);
                P_prop_shaft_req_kw = P_prop_shaft_req_W / 1000;

                % ---- Gearbox (motor -> propeller) ----
                P_motor_mech_req_kw = P_prop_shaft_req_kw / obj.eta_gearbox;

                % ---- 3. Motor: torque check + electrical demand ----
                [torque_Nm, ~] = obj.motor.torque_from_power(P_motor_mech_req_kw, motor_rpm);
                eta_motor = obj.motor.motor_efficiency(P_motor_mech_req_kw, motor_rpm);
                P_motor_elec_req_kw_per = P_motor_mech_req_kw / max(eta_motor,0.5);
                P_motor_elec_req_kw_total = P_motor_elec_req_kw_per * num_motors;

                % ---- 4. Inverter: required DC bus power ----
                P_dc_bus_req_kw = obj.inverter.required_dc_power(P_motor_elec_req_kw_total);
                eta_inv = obj.inverter.efficiency(P_dc_bus_req_kw);

                % ---- 5. Energy Management Controller: battery vs generator ----
                [P_battery_dc_kw, P_generator_dc_required_kw] = obj.emc.decide(...
                    phase.name, soc, P_dc_bus_req_kw, design.generator_power_kw, ...
                    design.battery_capacity_Ah, obj.dcbus.V_nominal);

                % ---- 6. Battery step ----
                if P_battery_dc_kw >= 0
                    [soc, v_batt, ~] = obj.battery.discharge_step(soc, P_battery_dc_kw*1000, obj.dt);
                else
                    [soc, v_batt, ~] = obj.battery.charge_step(soc, -P_battery_dc_kw*1000, obj.dt);
                end

                % ---- 7. Rectifier + Generator (reverse chain: required -> shaft power) ----
                P_gen_ac_req_kw = obj.rectifier.required_ac_power(P_generator_dc_required_kw, design.generator_power_kw);
                P_eng_shaft_req_kw = obj.generator.required_shaft_power(P_gen_ac_req_kw, obj.engine.rated_rpm);

                deficit_kw = max(0, P_eng_shaft_req_kw - design.engine_power_kw);
                P_eng_shaft_kw = min(P_eng_shaft_req_kw, design.engine_power_kw);
                max_deficit_kw = max(max_deficit_kw, deficit_kw);

                % ---- 8. Engine: throttle, fuel, SFC (at the capped shaft power) ----
                throttle_pct = 100 * P_eng_shaft_kw / max(design.engine_power_kw,1e-6);
                throttle_pct = max(0, min(100, throttle_pct));
                [~, SFC, eta_thermal] = obj.engine.query_performance(throttle_pct, alt);
                fuel_consumed = obj.engine.fuel_flow(throttle_pct, alt, obj.dt);

                % ---- FORWARD cross-check: what does the generator path actually deliver? ----
                [P_gen_ac_kw, ~, ~] = obj.generator.convert(P_eng_shaft_kw, obj.engine.rated_rpm);
                eta_gen = obj.generator.efficiency(P_eng_shaft_kw, obj.engine.rated_rpm);
                [P_rect_dc_kw, ~, ~, eta_rect] = obj.rectifier.convert(P_gen_ac_kw, obj.generator.V_ac_line, obj.generator.rated_power_kw);

                P_dc_supply_kw = P_rect_dc_kw + max(0,P_battery_dc_kw) - max(0,-P_battery_dc_kw);
                [P_bus_loss_kw, ~, ~] = obj.dcbus.balance(P_dc_supply_kw, P_dc_bus_req_kw, obj.dcbus.V_nominal);

                % ---- Weight update ----
                fuel_mass = max(0, fuel_mass - fuel_consumed);
                weight_N = (empty_weight + fuel_mass + battery_mass) * 9.81;

                % ---- Overall fuel-to-thrust chain efficiency (informational) ----
                P_useful_kw = T_req_total * V / 1000;
                if fuel_consumed > 0
                    fuel_flow_kg_per_hr = fuel_consumed / (obj.dt/3600);
                    fuel_power_kw = fuel_flow_kg_per_hr * LHV_kJ_per_kg / 3600;
                else
                    fuel_power_kw = 0;
                end
                if fuel_power_kw > 0.01
                    total_eff = min(1, P_useful_kw / fuel_power_kw);
                else
                    total_eff = eta_motor * eta_inv * eta_gen; % electric-only phases
                end

                % ---- Log ----
                L.t(step)=t; L.alt(step)=alt; L.speed(step)=V; L.mass_kg(step)=weight_N/9.81;
                L.T_req(step)=T_req_total; L.P_prop_shaft_kw(step)=P_prop_shaft_req_kw*num_motors;
                L.motor_torque_Nm(step)=torque_Nm; L.eta_motor(step)=eta_motor;
                L.P_motor_elec_kw(step)=P_motor_elec_req_kw_total; L.eta_inverter(step)=eta_inv;
                L.P_dc_bus_req_kw(step)=P_dc_bus_req_kw; L.P_battery_dc_kw(step)=P_battery_dc_kw;
                L.soc(step)=soc*100; L.v_batt(step)=v_batt; L.eta_generator(step)=eta_gen;
                L.P_gen_ac_kw(step)=P_gen_ac_kw; L.eta_rect(step)=eta_rect; L.P_rect_dc_kw(step)=P_rect_dc_kw;
                L.P_bus_loss_kw(step)=P_bus_loss_kw;
                L.P_eng_shaft_kw(step)=P_eng_shaft_kw; L.throttle_pct(step)=throttle_pct;
                L.SFC(step)=SFC; L.eta_thermal(step)=eta_thermal; L.fuel_mass(step)=fuel_mass;
                L.deficit_kw(step)=deficit_kw; L.total_efficiency(step)=total_eff;
            end

            for i = 1:numel(field_names)
                L.(field_names{i}) = L.(field_names{i})(1:step);
            end

            endurance_hours = t/3600;
            fuel_burned = 150 - L.fuel_mass(end);
            mission_feasible = (L.fuel_mass(end) > 10) && (L.soc(end) > 20) && (max_deficit_kw < 0.5);

            results = L;
            results.endurance_hours = endurance_hours;
            results.fuel_burned = fuel_burned;
            results.mission_feasible = mission_feasible;
            results.max_power_deficit_kw = max_deficit_kw;
            results.avg_total_efficiency = mean(L.total_efficiency);
        end
    end
end
