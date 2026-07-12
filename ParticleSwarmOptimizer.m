%% ============================================================================
%  PARTICLE SWARM OPTIMIZER CLASS
%  ============================================================================

classdef ParticleSwarmOptimizer
    properties
        num_particles
        num_iterations
        w
        c1
        c2
        lb
        ub
        obj_func
    end
    
    methods
        function obj = ParticleSwarmOptimizer(num_particles, num_iterations)
            obj.num_particles = num_particles;
            obj.num_iterations = num_iterations;
            obj.w = 0.7;
            obj.c1 = 1.5;
            obj.c2 = 1.5;
        end
        
        function [best_design, best_fitness, history] = optimize(obj, lb, ub, obj_func)
            obj.lb = lb;
            obj.ub = ub;
            obj.obj_func = obj_func;
            
            dim = length(lb);
            history.best_fitness = zeros(obj.num_iterations, 1);
            
            X = repmat(lb, obj.num_particles, 1) + ...
                rand(obj.num_particles, dim) .* repmat((ub - lb), obj.num_particles, 1);
            V = (ub - lb) .* 0.1 .* (rand(obj.num_particles, dim) - 0.5);
            
            fitness = zeros(obj.num_particles, 1);
            for i = 1:obj.num_particles
                fitness(i) = obj.obj_func(X(i, :));
            end
            
            [best_fitness, best_idx] = min(fitness);
            best_design = X(best_idx, :);
            pbest = X;
            pbest_fitness = fitness;
            gbest = best_design;
            
            for iter = 1:obj.num_iterations
                for i = 1:obj.num_particles
                    r1 = rand(1, dim);
                    r2 = rand(1, dim);
                    V(i, :) = obj.w * V(i, :) + ...
                             obj.c1 * r1 .* (pbest(i, :) - X(i, :)) + ...
                             obj.c2 * r2 .* (gbest - X(i, :));
                    
                    X(i, :) = X(i, :) + V(i, :);
                    X(i, :) = max(obj.lb, min(obj.ub, X(i, :)));
                end
                
                for i = 1:obj.num_particles
                    fitness(i) = obj.obj_func(X(i, :));
                    
                    if fitness(i) < pbest_fitness(i)
                        pbest(i, :) = X(i, :);
                        pbest_fitness(i) = fitness(i);
                    end
                    
                    if fitness(i) < best_fitness
                        best_fitness = fitness(i);
                        best_design = X(i, :);
                        gbest = best_design;
                    end
                end
                
                history.best_fitness(iter) = best_fitness;
                
                if mod(iter, 10) == 0
                    fprintf('    Iteration %3d / %d: Best fitness = %.6f\n', iter, obj.num_iterations, best_fitness);
                end
            end
            
            fprintf('    Iteration %3d / %d: Best fitness = %.6f\n', obj.num_iterations, obj.num_iterations, best_fitness);
        end
    end
end
