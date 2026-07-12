%% ============================================================================
%  MISSION DEFINITION: 7-HOUR LONG-ENDURANCE MISSION
%  ============================================================================

function mission = Mission_7hr()
    % Define a realistic 7-hour long-endurance mission profile
    %
    % Phase 1: Takeoff (0 m → ground level, 30 m/s)
    % Phase 2: Climb (ground → 5000 m, 40 m/s)
    % Phase 3: Cruise (5000 m, 60 m/s) — MAIN PHASE
    % Phase 4: Loiter (5000 m, 45 m/s) — LOITERING FOR OBSERVATIONS
    % Phase 5: Descent (5000 m → 0 m, 35 m/s)
    
    mission.phases = struct('name', {}, 'altitude', {}, 'speed', {}, 'duration', {});
    
    % Phase 1: Takeoff
    mission.phases(1).name = 'takeoff';
    mission.phases(1).altitude = 100;   % Quick climb to clear ground
    mission.phases(1).speed = 30;       % m/s
    mission.phases(1).duration = 60;    % 60 seconds
    
    % Phase 2: Climb to cruise altitude
    mission.phases(2).name = 'climb';
    mission.phases(2).altitude = 5000;  % Cruise altitude
    mission.phases(2).speed = 40;       % Climb speed
    mission.phases(2).duration = 600;   % 10 minutes
    
    % Phase 3: Main cruise (bulk of mission time)
    mission.phases(3).name = 'cruise';
    mission.phases(3).altitude = 5000;
    mission.phases(3).speed = 60;       % Optimal cruise
    mission.phases(3).duration = 18000; % 5 hours (main endurance)
    
    % Phase 4: Loiter (observation/surveillance)
    mission.phases(4).name = 'loiter';
    mission.phases(4).altitude = 5000;
    mission.phases(4).speed = 45;       % Slower, more efficient
    mission.phases(4).duration = 3600;  % 1 hour
    
    % Phase 5: Descent and landing
    mission.phases(5).name = 'descent';
    mission.phases(5).altitude = 500;   % Low altitude descent
    mission.phases(5).speed = 35;
    mission.phases(5).duration = 300;   % 5 minutes
    
    % Total mission time
    total_time = sum([mission.phases.duration]);
    mission.total_time = total_time;
    mission.total_hours = total_time / 3600;
    
    fprintf('    Total mission time: %.2f hours\n', mission.total_hours);
end
