
clear
close all force
addpath '..\'

% No. of reweighting iterations (Optional).
rwt = 5;       
pow = 5;
sz = 2^pow;

N = sz^2; 

% No. of measurements
% M = round(N);
M = round((90*N)/100); 

xs = linspace(-1, 1, sz);
ys = xs;

[xx, yy] = meshgrid(xs, ys);

w = 0.4;
sig_rad = 0.4;
Amp = 5; % [mW / cm^2].
t = 1;

% Refferenced signal.
signal_type = 1;

switch signal_type
    case 1
        % Gaussian signal with incertainty of sqrt(w).
        r = Amp*exp(-((xx.^2) + (yy.^2)) ./ w).*exp(-1i.*pi*t); % [sqrt(mW / cm^2)].
        
    case 2
        % Circular signal radius sig_rad.
        r = Amp*circle_draw(sz, sig_rad); % [sqrt(mW / cm^2)].
end

Ir = abs(r).^2; % [mW / cm^2].

% Refferenced signal (has no usge now).
s = r;
Is = abs(s).^2; 

% Laser wavelenght.
lambda = 532e-9; % [m].

% velocity_scale = (1e-6/2) / 2. Dividing by 2 according to Hz definition and
% another 2 since we want the center of the range: [-0.5*(1e-6)/2, 0.5*(1e-6)/2]         
% to be as close to zero as possible. 
% This simulation's goal is to check how the reconstruction accuracy effected as we go
% close to zero, meaning that we are measuring smaller doppler shifts and
% the differences between I0 and I1 decreases.

velocity_scale = 1e-7 / 4; % membrane_scale [m / s].

% Piazo engeen doppler frequencies membren.
membrane_type = 2;
membrane_scale = 1e-9; % [m / s].

velocity_scale = membrane_scale;
switch membrane_type
    case 0 
        % Gaussian membrane.
        vD = exp(-(xx.^2 + yy.^2)./0.4) * velocity_scale;
        vD(xx.^2 + yy.^2 > 0.65^2)= 0;

    case 1
        % Half circle membrane.
        R = 0.7;
        vD = half_circle_draw(sz, R) * velocity_scale;
        
    case 2
        % Membrane shape.
        vD = membren(sz).* velocity_scale;
        
    case 3
        % Advanced membrane (similar to real one).
        vD = advanced_membrane(sz) * velocity_scale;

    case 4
        % Advanced membrane (Different version).
        vD = advanced_membrane2(sz) * velocity_scale;

    case 5 
        % Advanced membrane with control of:
        angs = 5; % N. of angels.
        rads = 4; % N. of radiuses.
        
        vD = advanced_membrane_set(sz, angs, rads) * velocity_scale;
        
    case 6
        % Parabul membrane.
         vD = (xx.^2 + yy.^2) * velocity_scale;
         vD(xx.^2 + yy.^2 > 0.65^2)= 0;

   otherwise
        disp('Invalid option for "membrane" variable');
        
end

% Doppler frequencies.
fD = 2.*vD./lambda; 

% PHYSICAL PARAMETERS (Raman-Nath Scattering approx (lamda*L / d^2 << 1): 

% Beams wave lenghts, in [m].
lambda = 532e-9; 

% Magnitude of the laser wavevector.
k0 = 2*pi / lambda; % in [1/m]

% Kerr like Refractive index.
n2 = -1.8*10^-4; % [m^2 / mW].

% Fringe spacing.
d = 50*10^-6; % [m].

% Interaction region thickness.
L = 9*10^-6; % [m]. 

ld = 12*10^-6; % [m].

% Grating index wavevector.
kg = 2*pi/(110*10^-6); % [1 / m].

% Liquid crystal relaxation time.
tau = 72*10^-3; %[s].

rho = (2*k0*n2.*d ./ (((1 + ld^2*kg^2)^2 + (fD.*tau)^2).^0.5)).*(Is.*Ir).^0.5;
psi = atan(fD.*tau ./ (1 + ld^2*kg^2)^2);

% After liquid crystal 
I1 = (abs(besselj(0, rho) + 1i.*besselj(1, rho).*exp(-1i.*psi)).^2).*Ir; %/Ir
I0 = (abs(besselj(-1, rho) + 1i.*besselj(0, rho).*exp(-1i.*psi)).^2).*Ir;% /Ir

photons_after_liquid = sum(I1, 'all') + sum(I0, 'all');

balance = I1 - I0;
% figure, image(balance,'CDatamapping','scaled'),set(gca,'FontSize',20);
% title('Original balanced signal');
% colorbar('eastoutside')

% We start with one white balance measurement.
white_bal_measre = sum(balance, 'all');

permutation1 = randperm(N, M);
permutation0 = randperm(N, M);

% Two different masks wavelets:

% Positive Dragon.
masks1 = double(dragon_masks(N, ...
       M, permutation1)');

% Positive Hadamard.
masks0 = double(hadamard_masks(N, ...
       M, permutation0)');

      
b1 = masks1 * reshape(I1.',1,[])';
b0 = masks0 * reshape(I0.',1,[])';

% First balanced projection.
b = b1 - b0; 

y1 = masks0 * reshape(I1.',1,[])';
y0 = masks1 * reshape(I0.',1,[])';

% Second balanced projection.
y = y1 - y0; 

% Subtracting the White Balanced measurment.
total_projection = y + b - white_bal_measre;

add_noise = 1;

    switch add_noise
        
        case 1
              noise = std(total_projection) * (rand(M,1) - 0.5).* 1e-3;
              sigma = std(noise);
              delta = sqrt(M + 2*sqrt(2*M)) * sigma;
              total_projection = total_projection + noise;  
            
        case 0
            delta = 0;

    end
    
% Final measurement matrix.
A = masks1 + masks0 - 1;
At = A';

% Final measurement matrix pointer function.
A_f = @(x)A * x;
At_f = @(x)At * x;

% Initial gues.
x0 = At * total_projection; 

tvI = sum(sum(sqrt([diff(balance,1,2) zeros(sz,1)].^2 + [diff(balance,1,1); zeros(1,sz)].^2 )));
fprintf('Original TV = %.3f\n', tvI);

% OPTIMIZATION PARAMETERS:

% Duality gap barrier - Algorithm terminates when the duality gap <= lbtol.
lbtol = 1e-4; % has been changed frm 1e-3
% Tolerance for SYMMLQ.
slqtol = 1e-8;
% Factor by which to increase the barrier constant at each iteration.
mu = 10;
% slqmaxiter - Maximum number of iterations for SYMMLQ;
slqmaxiter = 200;

time0 = clock;
xp =  tveq_logbarrier(x0, A_f, At_f, total_projection, lbtol, mu, slqtol, slqmaxiter); 

time1 = clock;
d = etime(time1, time0);

rec_balance = reshape(xp, sz, sz)';

fprintf('Total elapsed time = %f secs\n\n', etime(clock,time0));
plots = 1;
[err, centerized_rec, centerized_orig] = recover_piezo(Ir, balance, rec_balance, fD, sz, plots);

