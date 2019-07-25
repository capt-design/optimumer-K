classdef ActionGroup < handle
    properties
        action_plane;
        colors = ['r', 'g', 'b', 'k', 'm', 'c'];
        plot_on = false;
        
        toelink_length;
        
        curr_rocker;
        curr_shock;
        curr_pushrod;
        curr_aca;
        curr_pca;
        curr_rack;
        curr_knuckle;
        wheelbase = 61;
        cgh = 9;
        
        suspension_type;
        
        % Static Characteristics (scalars)
        static_char = struct('RCH', NaN,...
                             'spindle_length', NaN,...
                             'kingpin_angle', NaN,...
                             'scrub_radius', NaN,...
                             'anti_percentage', NaN,...
                             'FVSA', NaN,...
                             'SVSA', NaN,...
                             'mechanical_trail', NaN);
        
        % Dynamic Characteristics (vectors/matrices)
        dyn_char = struct('wheel_centers', NaN,...
                          'wheel_orientations', NaN);
        
        front_view_plane;
        side_view_plane;
        front_brake_percentage = 0.4;
        node_list = zeros([1, 13]);
        loc_list = cell(1, 13);
    end
   
    methods
        function self = ActionGroup(rocker, shock, pushrod, aca, pca, knuckle, rack, suspension_type)
            % Action group meant for sweeping the range of the suspension.
            assert(strcmp(suspension_type, 'front') || strcmp(suspension_type, 'rear'), 'Valid suspension types are "front" and "rear"');
            self.suspension_type = suspension_type;
            
            self.toelink_length = norm(knuckle.toe_node.location - rack.endpoint_location);
            
            self.curr_rocker = rocker;
            self.curr_shock = shock;
            self.curr_pushrod = pushrod;
            self.curr_aca = aca;
            self.curr_pca = pca;
            self.curr_knuckle = knuckle;
            self.curr_rack = rack; 
            self.action_plane = rocker.plane;
            
            self.node_list = [rocker.pivot_node];
            self.node_list(2) = rocker.shock_node;
            self.node_list(3) = rocker.control_arm_node;
            self.node_list(4) = shock.inboard_node;
            self.node_list(5) = pushrod.outboard_node;
            self.node_list(6:7) = aca.endpoints;
            self.node_list(8:9) = pca.endpoints;
            self.node_list(10) = knuckle.aca_node;
            self.node_list(11) = knuckle.pca_node;
            self.node_list(12) = knuckle.toe_node;
            self.node_list(13) = rack.location_node;
            
%             assert(rocker.plane.is_in_plane(shock.inboard_node.location));
            
            c = self.curr_knuckle.wheel.center;
            self.front_view_plane = Plane([0; 0; c(3)], [0; 0; 1]);
            self.side_view_plane = Plane([c(1); 0; 0], [1; 0; 0]);
            
            self.calc_static_char();
        end
        
        function [static_char, dyn_char] = perform_sweep(self, num_steps, plot_on)
            self.plot_on = plot_on;
            static_lateral_pos = self.curr_aca.tip.location(1);
            shock_step_size = self.curr_shock.total_travel / (num_steps - 1);
            shock_start_step = self.curr_shock.total_travel / -2;
            rack_step_size = self.curr_rack.max_travel / (num_steps - 1);
            rack_start_step = self.curr_rack.max_travel / -2;
            shock_steps = linspace(shock_start_step, -shock_start_step, num_steps);
            rack_steps = linspace(rack_start_step, -rack_start_step, num_steps);
            
            self.take_shock_step(shock_start_step);
           
            cambers = zeros(num_steps);
            toes = zeros(num_steps);
            
            if plot_on
                plot_system_3d('c', self.curr_rocker, self.curr_shock, self.curr_aca, self.curr_pushrod, self.curr_pca, self.curr_knuckle);
            end

            [camber, toe] = self.perform_rack_sweep(rack_start_step, rack_step_size, num_steps);
            cambers(1, :) = camber;
            toes(1, :) = toe;
            
            for shock_index = 2:num_steps
                self.take_shock_step(shock_step_size);
                if plot_on
                    plot_system_3d('k', self.curr_rocker, self.curr_shock, self.curr_aca, self.curr_pushrod, self.curr_pca, self.curr_knuckle);
                    drawnow()
                end
                [camber, toe] = self.perform_rack_sweep(rack_start_step, rack_step_size, num_steps);
                toes(shock_index, :) = toe;
                cambers(shock_index, :) = camber;
            end

            if plot_on
                figure
                hold on
                
                imagesc(rack_steps, shock_steps, cambers)
                c = colorbar;
                ylabel(c, 'Camber (Degrees)')
                xlabel('Rack Displacement From Static (in)')
                ylabel('Shock Displacement From Static (in)')
                
                figure
                imagesc(rack_steps, shock_steps, toes)
                c = colorbar;
                ylabel(c, 'Toe (Degrees)')
                xlabel('Rack Displacement From Static (in)')
                ylabel('Shock Displacement From Static (in)')
                
            end
            self.take_shock_step(-shock_step_size * (num_steps - 1) - shock_start_step);
            self.reset_rack();
            self.curr_knuckle.update_action_plane();
            self.curr_knuckle.update_toe_plane();
            self.calc_static_char();
            static_char = self.static_char;
            dyn_char = [];
        end
        
        function take_shock_step(self, step)
            self.calc_rocker_movement(step);
            self.curr_aca = self.calc_xca_movement(self.curr_aca, self.curr_pushrod.inboard_node.location, self.curr_pushrod.length);
            self.curr_knuckle.aca_node = self.curr_aca.tip;
            
            self.curr_pushrod.outboard_node.location = self.curr_aca.pushrod_mount.location;
            self.curr_pca = self.calc_xca_movement(self.curr_pca, self.curr_knuckle.aca_node.location, self.curr_knuckle.a_arm_dist);
            self.curr_knuckle.pca_node = self.curr_pca.tip;
        end
        
        function take_rack_step(self, step)
            self.curr_rack.calc_new_endpoint(step);
            self.calc_knuckle_rotation();
        end
        
        function calc_rocker_movement(self, step)
            prev_location = self.curr_shock.outboard_node.location;
            shock_radius = self.curr_shock.curr_length + step;
            shock_center = self.curr_shock.inboard_node.location;
            shock_center = self.action_plane.convert_to_planar_coor(shock_center);
            
            rocker_radius = self.curr_rocker.shock_lever;
            rocker_center = self.curr_rocker.pivot_node.location;
            rocker_center = self.action_plane.convert_to_planar_coor(rocker_center);
            
            [x, y] = circcirc(rocker_center(1), rocker_center(2), rocker_radius,...
                              shock_center(1), shock_center(2), shock_radius);
            p1 = [x(1); y(1)];
            p1 = self.action_plane.convert_to_global_coor(p1);
            p2 = [x(2); y(2)];
            p2 = self.action_plane.convert_to_global_coor(p2);
            new_location = find_closer_point(prev_location, p1, p2);
            
            new_rocker_pos = unit(new_location - self.curr_rocker.pivot_node.location);
            old_rocker_pos = unit(prev_location - self.curr_rocker.pivot_node.location);
            theta = -acosd(dot(old_rocker_pos, new_rocker_pos));

            self.curr_rocker.rotate(theta, new_location);
            self.curr_shock = self.curr_shock.new_outboard_point(new_location);
            self.curr_pushrod.inboard_node.location = self.curr_rocker.control_arm_node.location;
        end
        
        function new_xca = calc_xca_movement(self, xca, ref_point, ref_dist)
            if xca.active
                prev_location = xca.pushrod_mount.location;
                [int1, int2] = calc_sphere_circle_int(ref_point, ref_dist,...
                                              xca.pushrod_center, xca.pushrod_radius, xca.pushrod_plane);
                new_location = find_closer_point(prev_location, int1, int2);
                
                new_xca_pos = unit(new_location - xca.pushrod_center);
                old_xca_pos = unit(prev_location - xca.pushrod_center);
                
                assert(xca.pushrod_plane.is_in_plane(new_xca_pos + xca.pushrod_center));
                assert(xca.pushrod_plane.is_in_plane(old_xca_pos + xca.pushrod_center));
            else
                prev_location = xca.tip.location;
                [int1, int2] = calc_sphere_circle_int(ref_point, ref_dist,...
                                              xca.effective_center, xca.effective_radius, xca.action_plane);
                new_location = find_closer_point(prev_location, int1, int2);
                new_xca_pos = unit(new_location - xca.effective_center);
                old_xca_pos = unit(prev_location - xca.effective_center);
            end
            theta = -acosd(dot(old_xca_pos, new_xca_pos));
            new_xca = xca.rotate(theta, new_location);

            assert(abs(norm(new_location - ref_point) - ref_dist) < 1e-8);
        end
        
        function [cambers, toes] = perform_rack_sweep(self, rack_start_step, rack_step_size, num_steps)
            self.reset_rack();
            self.take_rack_step(rack_start_step);
            self.interference_detection(1);
            toes = zeros(1,num_steps);
            cambers = zeros(1,num_steps);
            self.curr_knuckle.update_action_plane();
            [cambers(1), toes(1)] = self.curr_knuckle.calc_camber_and_toe();
            
            for index = 2:num_steps
                self.take_rack_step(rack_step_size);
                self.interference_detection(1);
                    
                self.curr_knuckle.update_action_plane();
                [camber, toe] = self.curr_knuckle.calc_camber_and_toe();

                toes(index) = toe;
                cambers(index) = camber;
                if self.plot_on
                    plot_system_3d('g', self.curr_knuckle)
                end
            end
        end
        
        function calc_knuckle_rotation(self)
            % Rotates the knuckle
            
            previous_location = self.curr_knuckle.toe_node.location;
            self.curr_knuckle.update_toe_plane();
            
            % Reassign variables to shorten code 
            toe_center = self.curr_knuckle.toe_center;
            toe_radius = self.curr_knuckle.toe_radius;
            toe_plane = self.curr_knuckle.toe_plane;
            
            [p1, p2] = calc_sphere_circle_int(self.curr_rack.endpoint_location, self.toelink_length,...
                                              toe_center, toe_radius, toe_plane);
            
            new_location = find_closer_point(previous_location, p1, p2);
            
            % update toe point of knuckle
            self.curr_knuckle.toe_node.location = new_location;
        end
        
        function reset_rack(self)
            self.curr_rack.endpoint_location = self.curr_rack.static_endpoint_location;
            self.calc_knuckle_rotation();
        end
        
        function res = interference_detection(self, debug)
            res = true;
            r = 0.3;
            % Check for toe-link aca interference
            if line_line_interference(self.curr_rack.endpoint_location, self.curr_knuckle.toe_node.location, r,...
                                      self.curr_aca.endpoints(1).location, self.curr_aca.tip.location, r)
                return;
            end
            % Check for toe-link aca interference (second arm)
            if line_line_interference(self.curr_rack.endpoint_location, self.curr_knuckle.toe_node.location, r,...
                                      self.curr_aca.endpoints(2).location, self.curr_aca.tip.location, r)
                return;
            end
            % Check for pushrod toelink interference
            if line_line_interference(self.curr_rack.endpoint_location, self.curr_knuckle.toe_node.location, r,...
                                      self.curr_pushrod.inboard_node.location, self.curr_pushrod.outboard_node.location, r)
                return;
            end
%             
%             % Check for pushrod aca interference
%             if line_line_interference(self.curr_aca.endpoints(1).location, self.curr_aca.tip.location, r,...
%                                       self.curr_pushrod.inboard_node.location, self.curr_pushrod.outboard_node.location, r)
%                 return;
%             end
%             % Check for pushrod aca interference (second arm)
%             if line_line_interference(self.curr_aca.endpoints(2).location, self.curr_aca.tip.location, r,...
%                                       self.curr_pushrod.inboard_node.location, self.curr_pushrod.outboard_node.location, r)
%                 return;
%             end
            % Check for pushrod pca interference
            if line_line_interference(self.curr_pca.endpoints(1).location, self.curr_pca.tip.location, r,...
                                      self.curr_pushrod.inboard_node.location, self.curr_pushrod.outboard_node.location, r)
                return;
            end
            % Check for pushrod pca interference (second arm)
            if line_line_interference(self.curr_pca.endpoints(2).location, self.curr_pca.tip.location, r,...
                                      self.curr_pushrod.inboard_node.location, self.curr_pushrod.outboard_node.location, r)
                return;
            end
            
            for index = 1:length(self.curr_knuckle.wheel.radii)
                w = self.curr_knuckle.wheel;
                wr = w.radii(index);
                c = w.center + w.axial_dists(index) * w.axis;
                % Check for toe link interference
                if line_circle_interference(c, wr, self.curr_knuckle.wheel.plane,...
                                            self.curr_rack.endpoint_location, self.curr_knuckle.toe_node.location, r)
                    return;
                end
                if line_circle_interference(c, wr, self.curr_knuckle.wheel.plane,...
                                            self.curr_aca.endpoints(1).location, self.curr_aca.tip.location, r)
                    return;
                end
                if line_circle_interference(c, wr, self.curr_knuckle.wheel.plane,...
                                            self.curr_aca.endpoints(2).location, self.curr_aca.tip.location, r)
                    return;
                end
                if line_circle_interference(c, wr, self.curr_knuckle.wheel.plane,...
                                            self.curr_pca.endpoints(1).location, self.curr_pca.tip.location, r)
                    return;
                end
                if line_circle_interference(c, wr, self.curr_knuckle.wheel.plane,...
                                            self.curr_pca.endpoints(2).location, self.curr_pca.tip.location, r)
                    return;
                end
                if line_circle_interference(c, wr, self.curr_knuckle.wheel.plane,...
                                          self.curr_pushrod.inboard_node.location, self.curr_pushrod.outboard_node.location, r)
                    return;
                end
            end
            
            res = false;
            if debug && res
                disp('INTERFERENCE DETECTED')
            end
        end
        
        function IC = calc_instant_center(self)
            [pca_point, pca_line] = self.curr_pca.static_plane.calc_plane_plane_int(self.front_view_plane);
            [aca_point, aca_line] = self.curr_aca.static_plane.calc_plane_plane_int(self.front_view_plane);
            
            eqns = [pca_line, aca_line, (aca_point - pca_point)];
            sols = rref(eqns);
            n = sols(1, 3);
            IC = pca_point - n * pca_line;
        end
        
        function RCH = calc_roll_center_height(self, IC)
            cp = self.front_view_plane.project_into_plane(self.curr_knuckle.wheel.calc_contact_patch());
            v = unit(cp - IC);
            n = -IC(1) / v(1);
            RC = IC + n*v;
            RCH = RC(2)
        end
        
        function [angle, mechanical_trail, scrub_radius, spindle_length] = calc_kingpin(self, c, cp)
            % Find which a-arm is the upper vs lower
            if self.curr_pca.tip.location(2) > self.curr_aca.tip.location(2)
                upper_tip = self.curr_pca.tip.location;
                lower_tip = self.curr_aca.tip.location;
                
            else
                lower_tip = self.curr_pca.tip.location;
                upper_tip = self.curr_aca.tip.location;
            end
            angle_sign = sign(lower_tip(1) - upper_tip(1));
            axis = unit(upper_tip - lower_tip);
            front_axis = unit([axis(1); axis(2)]);
            angle = angle_sign * acosd(dot([0;1], front_axis));
            
            m = -lower_tip(2) / axis(2);
            axis_contact = lower_tip + m * axis;
            assert(abs(axis_contact(2)) < 1e-6);
            mechanical_trail = axis_contact(3) - cp(3);
            scrub_radius = axis_contact(1) - cp(1);
            scatter3(axis_contact(1), axis_contact(2), axis_contact(3), 'bo')
            hold on
            v = [axis_contact, upper_tip];
            plot3(v(1, :), v(2, :), v(3, :), 'g--');
            scatter3(c(1), c(2), c(3), 'r*');
            lower_tip_2d = [lower_tip(1); lower_tip(2)];
            c_2d = [c(1); c(2)];
            
            a = -dot(front_axis, (c_2d - lower_tip_2d)) / dot(front_axis, front_axis);
            
            spindle_length = norm(c_2d - lower_tip_2d + a * front_axis);
        end
        
        function [SVSA, anti] = calc_SVSA_and_anti(self, c, cp)
            [pca_point, pca_line] = self.curr_pca.static_plane.calc_plane_plane_int(self.side_view_plane);
            [aca_point, aca_line] = self.curr_aca.static_plane.calc_plane_plane_int(self.side_view_plane);
            eqns = [pca_line, aca_line, (aca_point - pca_point)];
            sols = rref(eqns);
            quiver3(pca_point(1), pca_point(2), pca_point(3), pca_line(1), pca_line(2), pca_line(3));
            hold on
            quiver3(aca_point(1), aca_point(2), aca_point(3), aca_line(1), aca_line(2), aca_line(3));
            
            % if it is unable to find a solution
            if ~isequal(sols(1:2, 1:2), eye(2))
                SVSA = inf;
                anti = 0;
                return
            end
            n = sols(1, 3);
            IC = pca_point - n * pca_line;
            SVSA = abs(cp(3) - IC(3));
            if strcmp(self.suspension_type, 'front')
                anti = self.front_brake_percentage * (IC(2) / SVSA) * self.wheelbase / self.cgh;
            else
                anti = (abs(IC(2) - c(2)) / SVSA) * self.wheelbase / self.cgh;
            end
        end
        
        function update_all(self)
            self.curr_rocker.update();
            self.curr_pushrod.update();
            self.curr_aca.update();
            self.curr_pca.update();
            self.curr_knuckle.update();
            self.curr_rack.reset_endpoint();
            
        end
        
        function calc_static_char(self)
            c = self.curr_knuckle.wheel.center;
            cp = self.curr_knuckle.wheel.contact_patch;
            
            IC = self.calc_instant_center();
            self.static_char.RCH = self.calc_roll_center_height(IC);
            self.static_char.FVSA = abs(IC(1)-cp(1));
            
           
            [angle, mechanical_trail, scrub_radius, spindle_length] = self.calc_kingpin(c, cp);
            self.static_char.kingpin_angle = angle;
            self.static_char.mechanical_trail = mechanical_trail;
            self.static_char.scrub_radius = scrub_radius;
            self.static_char.spindle_length = spindle_length;
            [SVSA, anti] = self.calc_SVSA_and_anti(c, cp);
            self.static_char.SVSA = SVSA;
            self.static_char.anti_percentage = anti;
        end
    end
end