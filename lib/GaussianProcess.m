classdef GaussianProcess < handle
    %UNTITLED3 Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        n
        m
        hyperParameter
        kernel
        meanFct
        meanD
        K
        KyInv
        xD
        yD
        xStd
        xMean
        yStd
        yMean
        L
        Lt
        alpha
    end
    
    methods
        function obj = GaussianProcess(xD,yD,hyperParameter,kernel, meanFct)
            %GaussianProcess Construct an instance of this class
            %   Detailed explanation goes here
            obj.n = size(xD,1);
            obj.m = size(xD,2);
            obj.hyperParameter = hyperParameter;
            obj.kernel = kernel;
            obj.meanFct = meanFct;
            
            %% GP with basis functions and Gp parameters beta

            
            %% Normalize 
            %Normalize in the C++ Way
            obj.xStd = zeros(1,obj.m);
            obj.xMean = zeros(1,obj.m);
            obj.xD = zeros(obj.n,obj.m);
            obj.yD = zeros(obj.n,1);
            
            for i = 1 : obj.m
                obj.xStd(1,i) = std(xD(:,i));
                obj.xMean(1,i) = mean(xD(:,i));
            end
            obj.yStd = std(yD);
            obj.yMean = mean(yD);
            
            for l = 1 : obj.n
                for i = 1: obj.m
                    obj.xD(l,i) = (xD(l,i) - obj.xMean(1,i)) / obj.xStd(1,i);
                end
                obj.yD(l,1) = (yD(l,1) - obj.yMean) / obj.yStd;
                %obj.meanD(l,1) = (meanD(l,1) - obj.yMean) / obj.yStd;
            end
            
%           Normalize in the Matlab way           
%             obj.xStd = std(xD);
%             obj.xMean = mean(xD);
%             obj.yStd = std(yD);
%             obj.yMean = mean(yD);
%             
%             
%             obj.xD = (xD - obj.xMean)./ obj.xStd;
%             obj.yD = (yD - obj.yMean)./ obj.yStd;
            
            %% standard GP stuff
            obj.K = CovMatrix(obj.xD, obj.hyperParameter,kernel);
            obj.KyInv = (obj.K + eye(obj.n) * hyperParameter.sigmaN )^-1 ;
            
            %% GP with basis functions and Gp parameters beta. TODO: bad style.
            obj.meanD = zeros(obj.n,1);
            
            H = zeros(2, obj.n);
            b = obj.hyperParameter.beta;
            noParam.beta = 1; % to calculate h without b, one can set b=1 and then transpose h again. Not best style though
            for i = 1 : obj.n
                H(:,i) = obj.meanFct(xD(i,:),noParam).';
                for j = 1 : 2
                    H(j,i) = (H(j,i) - obj.yMean) / obj.yStd;
                end
            end
            
            betaEst = (obj.hyperParameter.B^-1 + H * obj.KyInv * H.')^-1  * (H * obj.KyInv * obj.yD + obj.hyperParameter.B^-1 * b);
            obj.hyperParameter.beta = betaEst;
            
            meanD = zeros(obj.n,1);
            for i = 1 : obj.n
                meanD(i,1) = obj.meanFct(xD(i,:),obj.hyperParameter);
            end
            
            %normalize
            for l = 1 : obj.n
                obj.meanD(l,1) = (meanD(l,1) - obj.yMean) / obj.yStd;
            end
            
            %% cholesky
            obj.Lt = chol(obj.K + hyperParameter.sigmaN^2*eye(obj.n)); %upper triangular matrix
            obj.L = obj.Lt.';
            %obj.alpha = obj.L.'\(obj.L \ obj.yD);
            opsLt.LT = true;
            opsUt.UT = true;
            obj.alpha = linsolve(obj.Lt,(linsolve(obj.L,obj.yD,opsLt)),opsUt);
           
        end
        
        function [yS,std] = predict(obj,xSIn)
            %predict Summary of this method goes here
            %   Detailed explanation goes here
 
            %Normalize the Matlab way
            %xS = (xS - obj.xMean) ./ obj.xStd ;
            
            %Normalize the C++ way
            xS = zeros(1,obj.m);
            for i = 1 : obj.m
                xS(1,i) = (xSIn(1,i) - obj.xMean(1,i)) / obj.xStd(1,i);
            end
            
            ks = zeros(obj.n,1);
            for i = 1 : obj.n
                ks(i) = obj.kernel(obj.xD(i,:),xS,obj.hyperParameter); 
            end

            yS = (ks.' * obj.KyInv * (obj.yD - obj.meanD));
            std = (obj.kernel(xS,xS,obj.hyperParameter) - ks.'* obj.KyInv * ks);
            
            %yS = yS * obj.yStd + obj.yMean + obj.meanFct(xSIn, obj.hyperParameter);
            yS = yS * obj.yStd + obj.meanFct(xSIn, obj.hyperParameter);
            std = std * obj.yStd^2;
        end
        
        function [yS, std] = predictCholesky(obj, xS)
            %Normalize the Matlab way
            %xS = (xS - obj.xMean) ./ obj.xStd ;
            
            %Normalize the C++ way
            for i = 1 : obj.m
                xS(1,i) = (xS(1,i) - obj.xMean(1,i)) / obj.xStd(1,i);
            end
            
            ks = zeros(obj.n,1);
            for i = 1 : obj.n
                ks(i) = obj.kernel(obj.xD(i,:),xS,obj.hyperParameter); 
            end     

            opt.LT = true;
            
            v = linsolve(obj.L,ks,opt);
            %v = obj.L \ ks;

            y_mu = ks.' * obj.alpha;
            y_s2 = obj.kernel(xS,xS,obj.hyperParameter) - v.'*v;
            
            yS = y_mu * obj.yStd + obj.yMean;
            std = y_s2 * obj.yStd;
            
        end
    end
end