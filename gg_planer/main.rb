module GG_Planer

require 'set'

KC_CTRL = 262144
KC_ALT = 524288
KC_GUI = 1048576
KC_ENTER = 13
KC_ESC = 27

STATE_INIT = 0
STATE_TAGGING = 1
STATE_ORIENTING = 2

class PlanerTool

    @@instances = Hash.new

    def self.get_for_model(model)
        if not @@instances.include?(model.guid)
            @@instances[model.guid] = PlanerTool.new
        end

        return @@instances[model.guid]
    end

    def self.plane_point(origin, x_axis, y_axis, x, y)
        # Reference: https://math.stackexchange.com/questions/525829/how-to-find-the-3d-coordinate-of-a-2d-point-on-a-known-plane
        return Geom::Point3d.new(
            origin.x + x * x_axis.x + y * y_axis.x,
            origin.y + x * x_axis.y + y * y_axis.y,
            origin.z + x * x_axis.z + y * y_axis.z
        )
    end

    def initialize
        @normal_length = '10'.to_l
        @brush_radius = '0'.to_l
        @brush_hops = 5
        @component_definition = nil

        self.reset_plane
    end

    def activate
        puts 'Planer activated'

        @ph = Sketchup.active_model.active_view.pick_helper

        @vertexInput = Sketchup::InputPoint.new
        @orientInput = Sketchup::InputPoint.new

        Sketchup.active_model.active_view.invalidate

        self.set_state STATE_INIT
    end

    def deactivate(view)
        puts 'Planer deactivated'
        self.remove_plane_preview
        view.invalidate if view
    end

    def show_settings
        prompts = ['Brush radius', 'Brush hops', 'Normal length']
        defaults = [@brush_radius, @brush_hops, @normal_length]
        input = UI.inputbox(prompts, defaults, 'Planer Options')

        if input
            @brush_radius = input[0].to_l
            @brush_hops = input[1].to_i
            @normal_length = input[2].to_l
        end
    end

    def reset_plane
        @points = []
        @vertices = Set.new
        @centroid = nil
        @projected_centroid = nil
        @normal = nil
        @plane = nil
        @oriented_bounds_polyline = nil
        @x_axis_proj = nil
        @y_axis_proj = nil
        @plane_group = nil
        @center = nil
    end

    def set_state(state)
        @state = state

        if @state == STATE_INIT
            Sketchup::set_status_text('Click a vertex to start tagging vertices, <Esc> to start over.', SB_PROMPT)
        elsif @state == STATE_TAGGING
            Sketchup::set_status_text('Move mouse to tag vertices.  Click a vertex to stop tagging.  Press <Enter> to proceed to next step, <Esc> to start over.', SB_PROMPT)
        elsif @state == STATE_ORIENTING
            Sketchup::set_status_text('Move mouse to choose orientation.  Press <Enter> to commit the plane, <Esc> to tag more vertices.', SB_PROMPT)
        else
            set_state STATE_INIT
        end
    end

    def remove_plane_preview
        if @plane_preview_group
            puts 'hide plane preview'
            Sketchup.active_model.active_entities.erase_entities @plane_preview_group
            @plane_preview_group = nil
        end
    end

    def onLButtonDown(flags, x, y, view)
        if @state == STATE_ORIENTING
            self.commit_plane
            set_state STATE_INIT
            view.invalidate
            return
        end

        @vertexInput.pick view, x, y
        return unless (@vertexInput.valid? and @vertexInput.degrees_of_freedom == 0 and @vertexInput.vertex)
        view.invalidate

        first_point = @points.empty?
        self.add_to_plane(@vertexInput.vertex, @vertexInput.transformation, view)

        if @state == STATE_INIT
            set_state STATE_TAGGING
        elsif @state == STATE_TAGGING
            set_state STATE_INIT
        end
    end

    def onLButtonUp(flags, x, y, view)
    end

    def onMouseMove(flags, x, y, view)
        if @state != STATE_ORIENTING
            @vertexInput.pick view, x, y
            return unless (@vertexInput.valid? and @vertexInput.degrees_of_freedom == 0 and @vertexInput.vertex)
            view.invalidate
            self.add_to_plane(@vertexInput.vertex, @vertexInput.transformation, view) if @state == STATE_TAGGING
        elsif @state == STATE_ORIENTING and @plane
            @orientInput.pick view, x, y
            return unless @orientInput.valid?

            # Reference: https://stackoverflow.com/questions/23472048/projecting-3d-points-to-2d-plane
            @x_axis_proj = (@projected_centroid.vector_to (@orientInput.position.project_to_plane @plane)).normalize
            @y_axis_proj = (@normal.cross @x_axis_proj).normalize

            bounds_x = nil
            bounds_y = nil

            @points.each { |p|
                p_proj = p.project_to_plane @plane
                #t_1 = Dot(e_1, r_P-r_O)
                x_proj = @x_axis_proj.dot(p_proj - @projected_centroid)
                #t_2 = Dot(e_2, r_P-r_O)
                y_proj = @y_axis_proj.dot(p_proj - @projected_centroid)

                if not bounds_x
                    bounds_x = [x_proj, x_proj]
                else
                    bounds_x = (bounds_x + [x_proj]).minmax
                end

                if not bounds_y
                    bounds_y = [y_proj, y_proj]
                else
                    bounds_y = (bounds_y + [y_proj]).minmax
                end
            }

            @oriented_bounds_polyline = [
                PlanerTool.plane_point(@projected_centroid, @x_axis_proj, @y_axis_proj, bounds_x[0], bounds_y[0]),
                PlanerTool.plane_point(@projected_centroid, @x_axis_proj, @y_axis_proj, bounds_x[0], bounds_y[1]),
                PlanerTool.plane_point(@projected_centroid, @x_axis_proj, @y_axis_proj, bounds_x[1], bounds_y[1]),
                PlanerTool.plane_point(@projected_centroid, @x_axis_proj, @y_axis_proj, bounds_x[1], bounds_y[0]),
                PlanerTool.plane_point(@projected_centroid, @x_axis_proj, @y_axis_proj, bounds_x[0], bounds_y[0]),
            ]

            @center = PlanerTool.plane_point(@projected_centroid, @x_axis_proj, @y_axis_proj, (bounds_x[0] + bounds_x[1]) / 2, (bounds_y[0] + bounds_y[1]) / 2)

            @x_axis_proj.length = @normal_length
            @y_axis_proj.length = @normal_length

            view.invalidate
        end
    end

    def commit_plane
        puts 'commit plane'
        if @component_definition
            transformation = Geom::Transformation.axes(@center, @x_axis_proj, @y_axis_proj, @normal.normalize)
            Sketchup.active_model.entities.add_instance(@component_definition, transformation)
        else
            @plane_group = Sketchup.active_model.entities.add_group
            @plane_group.entities.add_face @oriented_bounds_polyline
            @plane_group.entities.add_line(@center, @center.offset(@normal))
            @plane_group.entities.add_line(@center, @center.offset(@x_axis_proj))
            @plane_group.entities.add_line(@center, @center.offset(@y_axis_proj))
        end
        self.remove_plane_preview
        self.reset_plane
        self.set_state STATE_INIT
    end

    def pick_component
        selection = Sketchup.active_model.selection
        if not selection.empty?
            if selection.first.is_a? Sketchup::ComponentInstance
                @component_definition = selection.first.definition
                return true
            end
        end

        Sketchup::set_status_text('No component selected.  Please select a component instance first.', SB_PROMPT)
        return false
    end

    def clear_component
        @component_definition = nil
    end

    def onKeyDown(key, repeat, flags, view)
        puts 'down: key=%d' % [key]

        if key == KC_ALT
            if @plane
                puts 'show plane preview'
                @plane_preview_group = Sketchup.active_model.entities.add_group
                if @state == STATE_ORIENTING
                    face = @plane_preview_group.entities.add_face @oriented_bounds_polyline
                else
                    circle = @plane_preview_group.entities.add_circle(@projected_centroid, @normal, 2 * @normal_length)
                    face = @plane_preview_group.entities.add_face circle
                end
                material = 'gold'
                face.material = material
                face.back_material = material
            end
        elsif key == KC_ENTER
            if @state == STATE_ORIENTING
                self.commit_plane
                view.invalidate
            elsif @plane
                self.set_state STATE_ORIENTING
            end
        elsif key == KC_ESC
            if @state != STATE_ORIENTING
                puts 'discard plane'
                self.reset_plane
                view.invalidate
            end

            self.set_state STATE_INIT
        end
    end

    def onKeyUp(key, repeat, flags, view)
        #puts 'up: key=%d' % [key]

        if key == KC_ALT
            self.remove_plane_preview
        end
    end

    def add_to_plane(vertex, transformation, view)
        found_vertices = self.find_vertices_near(vertex, @brush_hops)
        puts 'found %d vertices nearby' % [found_vertices.length]

        points_added = false
        found_vertices.entries.each { |v|
            if not @vertices.include?(v)
                @vertices.add(v)
                @points.push(transformation * v.position)
                points_added = true
            end
        }

        return unless points_added

        view.invalidate

        return if @points.length < 3

        # Compute the new centroid
        @centroid = Geom::Point3d.new 0, 0, 0
        @points.each { |p| @centroid = @centroid + [p.x, p.y, p.z] }
        @centroid = Geom::Point3d.new(@centroid.x / @points.length, @centroid.y / @points.length, @centroid.z / @points.length)

        # Compute new plane
        @plane = Geom.fit_plane_to_points(@points)
        @projected_centroid = @centroid.project_to_plane @plane
        p, @normal = normalize_plane @plane
        @normal.length = @normal_length

        if @normal.z < 0
            @normal = @normal.reverse
        end
    end

    def pick_and_add_vertex_point(view, x, y)
        @vertexInput.pick view, x, y
        return unless (@vertexInput.valid? and @vertexInput.degrees_of_freedom == 0 and @vertexInput.vertex)
        view.invalidate

        self.add_to_plane(@vertexInput.vertex, @vertexInput.transformation, view)
    end

    def draw(view)
        if @state == STATE_ORIENTING and @plane and @orientInput.valid?
            view.line_stipple = '_'
            view.draw_line(@projected_centroid, (@orientInput.position.project_to_plane @plane))
            view.draw_polyline @oriented_bounds_polyline if @oriented_bounds_polyline and @oriented_bounds_polyline.length >= 2
        elsif @state != STATE_ORIENTING
            @vertexInput.draw view
        end

        return if @points.empty?
        view.draw_points(@points, 10, 5, 'gold')

        if @state == STATE_ORIENTING
            if @center and @normal
                view.draw_points([ @center ], 10, 1, 'gold')
                view.drawing_color = 'gold'
                view.line_stipple = '_'
                view.draw_line(@center, @center.offset(@normal))
            end
        else
            if @projected_centroid and @normal
                view.draw_points([ @projected_centroid ], 10, 1, 'blue')
                view.drawing_color = 'blue'
                view.line_stipple = '_'
                view.draw_line(@projected_centroid, @projected_centroid.offset(@normal))
            end
        end
    end

    def find_vertices_near(origin_vertex, max_hops, from_vertex = nil, known_vertices = Set.new)
        from_vertex = origin_vertex if not from_vertex
        return Set.new if (max_hops == 0 or known_vertices.include?(from_vertex))

        known_vertices.add(from_vertex)
        found_vertices = Set.new

        if from_vertex.position.distance(origin_vertex.position) <= @brush_radius
            found_vertices.add(from_vertex)
        end

        if @brush_radius > 0
            from_vertex.edges.each { |e|
                e.vertices.each { |v|
                    found_vertices += self.find_vertices_near(origin_vertex, max_hops - 1, v, known_vertices)
                }
            }
        end

        return found_vertices
    end

    def normalize_plane(plane)
        a, b, c, d = plane
        v = Geom::Vector3d.new(a,b,c)
        p = ORIGIN.offset(v.reverse, d)
        return [p, v]
    end

end#class

menu = UI.menu("Tools").add_submenu("Planer")

menu.add_item("Define Plane") {
    tool = PlanerTool.get_for_model(Sketchup.active_model)
    tool.clear_component
    Sketchup.active_model.select_tool(tool)
}
menu.add_item("Duplicate Component onto Plane") {
    tool = PlanerTool.get_for_model(Sketchup.active_model)
    if tool.pick_component
        Sketchup.active_model.select_tool(tool)
    end
}
menu.add_item("Settings") { PlanerTool.get_for_model(Sketchup.active_model).show_settings }

end#module