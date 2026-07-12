%% ============================================================================
%  MISSION DEFINITION: 7-HOUR LONG-ENDURANCE MISSION
%  ============================================================================

function mission = Mission_7hr()
    mission.phases = struct('name', {}, 'altitude', {}, 'speed', {}, 'duration', {});
    
    mission.phases(1).name = 'takeoff';
    mission.phases(1).altitude = 100;
    mission.phases(1).speed = 30;
    mission.phases(1).duration = 60;
    
    mission.phases(2).name = 'climb';
    mission.phases(2).altitude = 5000;
    mission.phases(2).speed = 40;
    mission.phases(2).duration = 600;
    
    mission.phases(3).name = 'cruise';
    mission.phases(3).altitude = 5000;
    mission.phases(3).speed = 60;
    mission.phases(3).duration = 18000;
    
    mission.phases(4).name = 'loiter';
    mission.phases(4).altitude = 5000;
    mission.phases(4).speed = 45;
    mission.phases(4).duration = 3600;
    
    mission.phases(5).name = 'descent';
    mission.phases(5).altitude = 500;
    mission.phases(5).speed = 35;
    mission.phases(5).duration = 300;
    
    total_time = sum([mission.phases.duration]);
    mission.total_time = total_time;
    mission.total_hours = total_time / 3600;
    
    fprintf('    Total mission time: %.2f hours\n', mission.total_hours);
end
