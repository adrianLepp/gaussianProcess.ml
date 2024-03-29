% Gaussian Process Particle Filter
% with explizit basis functions g() and residual GP f()
%Author Adrian Lepp
% Last change: 24.03.2022

% new Version with new and correct sovleThreeTank function

% To Do: Varianz berechnen
%           schlechte Parameter einbauen
%% clear
close all
clear 
clc

addpath('helpfunctions','gpml-matlab-master');

%% load parameters
    load 'threeTankData.mat'
    load 'dreiTank.mat'
    dt = parameter.dt;
    n = length(xTrain);

%% init
S = 10;
T = 200; % Simulationsdauer (Sekunden)

t = T/dt;

% initial state
x0 = zeros(3,1);
dx0 = zeros (3,1);
u0 = uTrain(1);

% noise
sigmaX_default = diag([1e-09 1e-09 1e-09]);    % Systemrauschen
s2 = zeros(3,S);
s2Post = zeros(3,S);
sigmaY = diag([5e-07 5e-07 5e-07]);    % Messrauschen
sigmaY_default = 5e-07;
V_mf = 1e-12;                       % Varianz des Fehlermittelwerts


xPost = x0 .*ones(3,S) + sqrt(parameter.sigmaX)* randn(3,S);
dx = zeros(3,S);
dxPost = zeros(3,S);
yEst = zeros(3,1);
xPrio = zeros(3,S);
wPost = zeros(1,S);

%output values
xOut = zeros(3,t);
yOut = zeros(3,t);
xEst = zeros(3,t);
dxEst = zeros(3,t);
sigmaXout = zeros(3,t);

%% GP init
    
    theta = zeros(3,2); % no of hyperparameters, dimension of x, number of GP's
    %sigmaF
    theta(1,1) = 100;
    theta(1,2) = 0.1;
    %l
    theta(2,1) = 2;
    theta(2,2) = 5;
    %sigmaN
    theta(3,1) = 0.35;
    
    %GP 1: Prediction
        K_ux = CovMatrix([uTrain,xTrain],theta(1,1),theta(2,1));
        K_dx = (K_ux + theta(3,1)*eye(n))^-1;
        logLikelihood_V1(dxTrain(:,1),K_ux,theta(3,1))
    
    %GP 2: Observation
        K_x = CovMatrix(xTrain,theta(1,2),theta(2,2));
        K_y = (K_x + theta(3,2)*eye(n))^-1;
        logLikelihood_V1(yTrain(:,1),K_x,theta(3,2))
    u = parameter.u;
    c13 = parameter.c13;
    c32 = parameter.c32;
    cA2 = parameter.cA2;
    A = parameter.A;
    g = parameter.g;
    
    H = zeros(4,n,3);
    for i = 1 : n
        H(:,i,:) = threeTankHVector(xTrain(i,:),parameter);
    end 
    b = [1; c13*0.9; c32; cA2];
    B = 1e-1*eye(4) + 1e-2*zeros(4);
    betaEst = zeros(4,3);
    for i = 1 : 3
        betaEst(:,i) = (B^-1 + H(:,:,i) * K_dx * H(:,:,i).')^-1 * (H(:,:,i) * K_dx * dxTrain(:,i) + B^-1 * b);
    end
    
%% PF

for k = 1 : t
    %Simulation reales System
    if k == 1
        [xOut(:,k),y] = solveThreeTank(x0,parameter);
    else
        [xOut(:,k),y] = solveThreeTank(xOut(:,k-1),parameter);
    end
    %% Partikelfilter loesen
    
    for l = 1 : S
        %% a priori Partikel
        
        %GP für Systemgleichung / prediction model
        dx(:,l) = GPpredictBasisFct(K_dx,[uTrain,xTrain],dxTrain,[u0,xPost(:,l).'],xPost(:,l),theta(1,1),theta(2,1),betaEst,H,@threeTankHVector,parameter);
        
        % Der Gp bestimmt nur dx, daher Addition mit x_post_k-1
        xPrio(:,l) = xPost(:,l) + dx(:,l) + sqrt(parameter.sigmaX) * [randn; randn; randn];
        
        %% Gewichte bestimmen
        % GP Für Ausgangsgleichung  / observation model
        for i = 1 :3
            [yEst(i),sigmaY(i,i)] = GPpredict_V1(K_y,xTrain,yTrain(:,i),xPrio(:,l).',theta(1,2),theta(2,2));   
        end

        wPost(l) = 1/((det(2*pi*parameter.sigmaY))^(0.5)) * exp(-0.5*(yOut(:,k) - yEst).' * inv(parameter.sigmaY) * (yOut(:,k) - yEst));
        
        if wPost(l) < 1e-30
            wPost(l) = 1e-30;
        end
        summe = sum(wPost);
        wPost = wPost./summe;
    end
    %% a posteriori Partikel ziehen 
    xPost = lowVarianceSampling(xPrio,wPost);
    dxPost = lowVarianceSampling(dx,wPost);
    s2Post = lowVarianceSampling(s2,wPost);
    
    xEst(:,k) = [mean(xPost(1,:)); mean(xPost(2,:)); mean(xPost(3,:))];
    dxEst(:,k) = [mean(dxPost(1,:)); mean(dxPost(2,:)); mean(dxPost(3,:))];
    sigmaXout(:,k) = [mean(s2Post(1,:)); mean(s2Post(2,:)); mean(s2Post(3,:))];
    
end
 time = linspace(dt,T,t);
 
 figure(1)
 plot(time, xOut(1,:),time, xOut(2,:),time, xOut(3,:), time, xEst(1,:), time, xEst(2,:), time, xEst(3,:));
 legend('x_1','x_2','x_3','x_1 est','x_2 est','x_3 est');
 
figure(2)
f1 = [xOut(1,:)+2*sqrt(sigmaXout(1,:)), flip(xOut(1,:)-2*sqrt(sigmaXout(1,:)),2)];
f2 = [xOut(2,:)+2*sqrt(sigmaXout(2,:)), flip(xOut(2,:)-2*sqrt(sigmaXout(2,:)),2)];
f3 = [xOut(3,:)+2*sqrt(sigmaXout(3,:)), flip(xOut(3,:)-2*sqrt(sigmaXout(3,:)),2)];
fill([time, flip(time,2)], f1, [7 7 7]/8)
hold on; 
fill([time, flip(time,2)], f2, [7 7 7]/8)
fill([time, flip(time,2)], f3, [7 7 7]/8)

plot(time, dxEst(1,:), 'k', time, dxEst(2,:), 'b', time, dxEst(3,:), 'r');
legend('Varianz Fuellstand Tank 1','Varianz Fuellstand Tank 3','Varianz Fuellstand Tank 3', 'realer Fuellstand Tank 1', 'Outputschaetzung Tank 1', 'realer Fuellstand Tank 2', 'Outputschaetzung Tank 2', 'realer Fuellstand Tank 3', 'Outputschaetzung Tank 3');
xlabel('Zeit t /s')
ylabel('Fuellstand /m')
hold off;

 
 