module GG_Planer

require 'set'

menu = UI.menu("Tools")
menu.add_item("Planer") { Sketchup.active_model.select_tool(PlanerTool.new) }
menu.add_item("Planer Settings") { PlanerTool.show_settings }

class PlanerTool
    @@max_distance = '5'.to_l
    @@normal_length = '10'.to_l
    @@max_vertex_hops = 5

    def self.show_settings
        prompts = ['Max distance', 'Normal length', 'Max hops']
        defaults = [@@max_distance, @@normal_length, @@max_vertex_hops]
        input = UI.inputbox(prompts, defaults, 'Planer Options')

        if input
            @@max_distance = input[0].to_l
            @@normal_length = input[1].to_l
            @@max_vertex_hops = input[2].to_i
        end
    end

    def activate
        puts 'Planer activated'

        @ph = Sketchup.active_model.active_view.pick_helper

        Sketchup::set_status_text('Select a point to generate plane', SB_PROMPT)
        @originInput = Sketchup::InputPoint.new

        @points = []
        @vertices = Set.new
        @centroid = nil
        @projected_centroid = nil
        @normal = nil
    end

    def deactivate(view)
        puts 'Planer deactivated'

        view.invalidate if view
    end

    def onLButtonDown(flags, x, y, view)
        puts "onLButtonDown: flags = #{flags}"
        puts "                   x = #{x}"
        puts "                   y = #{y}"
        puts "                view = #{view}"

        if (Sketchup.active_model.selection.length == 0)
            Sketchup.active_model.selection.clear
            @ph.do_pick(x, y)
            picked = @ph.best_picked
            Sketchup.active_model.selection.add(picked) if picked
        end

        #Do nothing with this click if nothing is selected
        return nil if Sketchup.active_model.selection.length == 0

        @originInput.pick view, x, y

        if @originInput.valid?
            origin = @originInput.position

            return if not @originInput.vertex
            points = find_vertex_points_max_hops_from_vertex(@originInput.vertex, @originInput.transformation, @@max_vertex_hops)

            #points = find_vertex_points_max_distance_from_point(Sketchup.active_model.selection, origin, @@max_distance)
            puts 'found %d points nearby' % [points.length]
            return if points.length == 0

            plane = Geom.fit_plane_to_points(points.entries)
            projected_origin = origin.project_to_plane plane
            p, v = normalize_plane plane
            puts 'plane normal: %s' % [v]
            v.length = @@normal_length

            if v.z < 0
                v = v.reverse
            end

            Sketchup.active_model.active_entities.add_line(projected_origin, projected_origin.offset(v))
        end
    end

    def onMouseMove(flags, x, y, view)
        @originInput.pick view, x, y
        if @originInput.degrees_of_freedom == 0 and @originInput.vertex
            view.invalidate

            if not @vertices.include?(@originInput.vertex)
                @vertices.add(@originInput.vertex)
                @points.push(@originInput.position)

                # Compute the new centroid
                @centroid = Geom::Point3d.new 0, 0, 0
                @points.each { |p| @centroid = @centroid + [p.x, p.y, p.z] }
                @centroid = Geom::Point3d.new(@centroid.x / @points.length, @centroid.y / @points.length, @centroid.z / @points.length)

                # Compute new plane
                plane = Geom.fit_plane_to_points(@points)
                @projected_centroid = @centroid.project_to_plane plane
                p, @normal = normalize_plane plane
                @normal.length = @@normal_length

                if @normal.z < 0
                    @normal = @normal.reverse
                end
            end
        end
    end

    def draw(view)
        @originInput.draw view
        view.draw_points(@points, 10, 5, 'green')

        if @projected_centroid and @normal
            view.draw_points([ @projected_centroid ], 10, 1, 'blue')
            view.drawing_color = 'blue'
            view.line_stipple = '_'
            view.draw_line(@projected_centroid, @projected_centroid.offset(@normal))
        end
    end

    def find_vertex_points_max_distance_from_point(entities, from_point, max_distance, transformation = Geom::Transformation.new)
        points = Set.new
        known_vertices = Set.new
        entities.each { |e|
            if e.public_methods.include?(:entities)
                points += self.find_vertex_points_max_distance_from_point(e.entities, from_point, max_distance, transformation * e.transformation)
            elsif e.is_a?(Sketchup::ComponentInstance)
                points += self.find_vertex_points_max_distance_from_point(e.definition.entities, from_point, max_distance, transformation * e.transformation)
            elsif e.is_a?(Sketchup::Edge)
                e.vertices.each { |v|
                    if not known_vertices.include?(v)
                        known_vertices.add(v)
                        point = transformation * v.position
                        points.add(point) if from_point.distance(point) < max_distance
                    end
                }
            end
        }
        return points
    end

    def find_vertex_points_max_hops_from_vertex(from_vertex, transformation, max_hops, known_vertices = Set.new)
        return Set.new if (max_hops == 0 or known_vertices.include?(from_vertex))

        known_vertices.add(from_vertex)
        points = Set.new([ transformation * from_vertex.position ])

        from_vertex.edges.each { |e|
            e.vertices.each { |v|
                points += self.find_vertex_points_max_hops_from_vertex(v, transformation, max_hops - 1, known_vertices)
            }
        }

        return points
    end

    def normalize_plane(plane)
        a, b, c, d = plane
        v = Geom::Vector3d.new(a,b,c)
        p = ORIGIN.offset(v.reverse, d)
        return [p, v]
    end

end#class
end#module