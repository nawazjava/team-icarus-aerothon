function [T, P, rho] = atmosphere_model(altitude)
    T0 = 288.15;
    P0 = 101325;
    rho0 = 1.225;
    L = 0.0065;
    
    if altitude <= 11000
        T = T0 - L * altitude;
        P = P0 * (T/T0)^(5.255);   % exponent must be positive (ISA troposphere)
        rho = rho0 * (T/T0)^(4.255); % exponent is 4.255, not 6.255, and must be positive
    else
        error('Altitude > 11 km not supported');
    end
end
