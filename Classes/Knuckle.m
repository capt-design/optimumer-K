classdef Knuckle
    properties
        uca_point;
        lca_point;
        toe_point;
        axis;
        static_camber;
        camber_offset;
        static_toe;
        toe_radius;
        toe_height;
        toe_center;
        toe_offset;
        control_arm_dist;
        lca_actuated;
        toe_plane;
        
    end
    
    methods
        function self = Knuckle(uca_point, lca_point, toe_point, static_camber, static_toe, lca_actuated)
            self.uca_point = uca_point;
            self.lca_point = lca_point;
            self.toe_point = toe_point;
            
            self.axis = unit(uca_point.location - lca_point.location);
            self.static_camber = static_camber;
            self.camber_offset = static_camber - atan2d(self.axis(1), self.axis(2));
            self.static_toe = static_toe;
            
            toe_to_lca = (toe_point - self.lca_point.location);
            self.toe_height = dot(toe_to_lca, self.axis);
            self.toe_center = self.toe_height * self.axis + self.lca_point.location;
            self.toe_radius = norm(toe_to_lca - (self.toe_height*self.axis));
            self.toe_plane = Plane(self.toe_center, self.axis);
            
            
            theta = self.calc_signed_steering_angle_raw();
            self.toe_offset = theta - self.static_toe;
            
            
            self.control_arm_dist = norm(uca_point.location - lca_point.location);
            self.lca_actuated = lca_actuated;
        end
        
        function res = valid_length(self)
            dist = norm(self.uca_point.location - self.lca_point.location);
            res = (abs(dist - self.control_arm_dist) < 1e-8);
        end
        
        function camber = calc_camber(self)
            self.axis = unit(self.uca_point.location - self.lca_point.location);
            camber = atan2d(self.axis(1), self.axis(2)) + self.camber_offset;
        end
        
        function self = update_toe_plane(self)
            self.axis = unit(self.uca_point.location - self.lca_point.location);
            self.toe_center = self.toe_height * self.axis + self.lca_point.location;
            self.toe_plane = Plane(self.toe_center, self.axis);
        end
        
        function theta = calc_signed_steering_angle_raw(self)
            toe_lever = unit(self.toe_point - self.toe_center);
            forward_v = unit(self.toe_plane.project_into_plane([0;0;1] + self.toe_center) - self.toe_center);
            unsigned_toe_offset = acosd(dot(toe_lever, forward_v));
            sign = -dot(unit(cross(self.toe_center+forward_v, self.toe_center+toe_lever)), self.axis);
            if sign > 0
                direction = 1;
            else
                direction = -1;
            end
            theta = unsigned_toe_offset * direction;
            quiver3(self.toe_center(1), self.toe_center(2), self.toe_center(3), forward_v(1), forward_v(2), forward_v(3), 'b')
            quiver3(self.toe_center(1), self.toe_center(2), self.toe_center(3), toe_lever(1), toe_lever(2), toe_lever(3), 'r');
        end
        
    end
end