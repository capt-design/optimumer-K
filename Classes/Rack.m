classdef Rack < handle
    properties
        location_node;
        max_travel;
        static_length;
        endpoint_location;
        static_endpoint_location;
    end

    methods
        function self = Rack(location_node, max_travel, static_length)
            self.location_node = location_node;
            self.max_travel = max_travel;
            self.static_length = static_length;
            self.update();
            % Rack should be centered left right in the car
            %assert(location_node.region.max_x == location_node.region.min_x);
        end
        function calc_new_endpoint(self, displacement)
            % weak assertion. Needs to check against static length, not max
            % travel.
%             assert(abs(displacement) <= self.max_travel /2 )
            self.endpoint_location = self.endpoint_location + displacement * [1;0;0];
        end
        
        function reset_endpoint(self)
            self.endpoint_location = self.location_node.location + (self.static_length / 2) * [1;0;0];
        end
        
        function update(self)
            self.static_endpoint_location = self.location_node.location + (self.static_length / 2) * [1;0;0];
            self.reset_endpoint();
        end
    end
end