module GG_Planer

require 'set'

KC_CTRL = 262144
KC_ALT = 524288
KC_GUI = 1048576
KC_ENTER = 13
KC_ESC = 27

STATE_INIT = 0
STATE_TAGGING = 1

menu = UI.menu("Tools")
menu.add_item("Planer") { Sketchup.active_model.select_tool(PlanerTool.new) }
menu.add_item("Planer Settings") { PlanerTool.show_settings }

class PlanerTool
    @@normal_length = '10'.to_l
    @@brush_radius = '0'.to_l
    @@brush_hops = 5

    def self.show_settings
        prompts = ['Normal length', 'Brush radius', 'Brush hops']
        defaults = [@@normal_length, @@brush_radius, @@brush_hops]
        input = UI.inputbox(prompts, defaults, 'Planer Options')

        if input
            @@normal_length = input[0].to_l
            @@brush_radius = input[1].to_l
            @@brush_hops = input[2].to_i
        end
    end

    def self.reset_plane
        @@points = []
        @@vertices = Set.new
        @@centroid = nil
        @@projected_centroid = nil
        @@normal = nil
        @@plane = nil
    end

    def set_state(state)
        @state = state

        if @state == STATE_INIT
            Sketchup::set_status_text('Click a vertex to start tagging vertices', SB_PROMPT)
        elsif @state == STATE_TAGGING
            Sketchup::set_status_text('Move mouse to tag vertices.  Click a vertex to stop tagging.  Press <Enter> to commit the plane, <Esc> to start over.', SB_PROMPT)
        end
    end

    def activate
        puts 'Planer activated'

        @ph = Sketchup.active_model.active_view.pick_helper

        @originInput = Sketchup::InputPoint.new

        Sketchup.active_model.active_view.invalidate

        set_state STATE_INIT
    end

    def deactivate(view)
        puts 'Planer deactivated'
        self.remove_plane_preview
        view.invalidate if view
    end

    def remove_plane_preview
        if @plane_preview_group
            puts 'hide plane preview'
            Sketchup.active_model.active_entities.erase_entities @plane_preview_group
            @plane_preview_group = nil
        end
    end

    def onLButtonDown(flags, x, y, view)
        @originInput.pick view, x, y
        return unless (@originInput.valid? and @originInput.degrees_of_freedom == 0 and @originInput.vertex)
        view.invalidate

        first_point = @@points.empty?
        self.add_to_plane(@originInput.vertex, @originInput.transformation, view)

        if @state == STATE_INIT
            set_state STATE_TAGGING
        elsif @state == STATE_TAGGING
            set_state STATE_INIT
        end

        # elsif @@points.length > 3
        #     # Commit plane
        #     Sketchup.active_model.active_entities.add_line(@@projected_centroid, @@projected_centroid.offset(@@normal))
        #     PlanerTool.reset_plane
        #     self.remove_plane_preview
    end

    def onLButtonUp(flags, x, y, view)
    end

    def onMouseMove(flags, x, y, view)
        @originInput.pick view, x, y
        return unless (@originInput.valid? and @originInput.degrees_of_freedom == 0 and @originInput.vertex)
        view.invalidate

        return if not @state == STATE_TAGGING
        self.add_to_plane(@originInput.vertex, @originInput.transformation, view)
    end

    def onKeyDown(key, repeat, flags, view)
        puts 'down: key=%d' % [key]

        if key == KC_ALT
            if @@plane
                puts 'show plane preview'
                @plane_preview_group = Sketchup.active_model.entities.add_group
                circle = @plane_preview_group.entities.add_circle(@@projected_centroid, @@normal, 2 * @@normal_length)
                face = @plane_preview_group.entities.add_face circle
                material = 'green'
                face.material = material
                face.back_material = material
            end
        elsif key == KC_ENTER
            if @@plane
                puts 'commit plane'
                Sketchup.active_model.active_entities.add_line(@@projected_centroid, @@projected_centroid.offset(@@normal))
                self.remove_plane_preview
                PlanerTool.reset_plane
                set_state STATE_INIT
            end
        elsif key == KC_ESC
            puts 'discard plane'
            PlanerTool.reset_plane
            set_state STATE_INIT
        end
    end

    def onKeyUp(key, repeat, flags, view)
        #puts 'up: key=%d' % [key]

        if key == KC_ALT
            self.remove_plane_preview
        end
    end

    def add_to_plane(vertex, transformation, view)
        found_vertices = self.find_vertices_near(vertex, @@brush_hops)
        puts 'found %d vertices nearby' % [found_vertices.length]

        points_added = false
        found_vertices.entries.each { |v|
            if not @@vertices.include?(v)
                @@vertices.add(v)
                @@points.push(transformation * v.position)
                points_added = true
            end
        }

        return unless points_added

        view.invalidate

        return if @@points.length < 3

        # Compute the new centroid
        @@centroid = Geom::Point3d.new 0, 0, 0
        @@points.each { |p| @@centroid = @@centroid + [p.x, p.y, p.z] }
        @@centroid = Geom::Point3d.new(@@centroid.x / @@points.length, @@centroid.y / @@points.length, @@centroid.z / @@points.length)

        # Compute new plane
        @@plane = Geom.fit_plane_to_points(@@points)
        @@projected_centroid = @@centroid.project_to_plane @@plane
        p, @@normal = normalize_plane @@plane
        @@normal.length = @@normal_length

        if @@normal.z < 0
            @@normal = @@normal.reverse
        end
    end

    def pick_and_add_vertex_point(view, x, y)
        @originInput.pick view, x, y
        return unless (@originInput.valid? and @originInput.degrees_of_freedom == 0 and @originInput.vertex)
        view.invalidate

        self.add_to_plane(@originInput.vertex, @originInput.transformation, view)
    end

    def draw(view)
        @originInput.draw view

        return if @@points.empty?
        view.draw_points(@@points, 10, 5, 'green')

        if @@projected_centroid and @@normal
            view.draw_points([ @@projected_centroid ], 10, 1, 'blue')
            view.drawing_color = 'blue'
            view.line_stipple = '_'
            view.draw_line(@@projected_centroid, @@projected_centroid.offset(@@normal))
        end
    end

    def find_vertices_near(origin_vertex, max_hops, from_vertex = nil, known_vertices = Set.new)
        from_vertex = origin_vertex if not from_vertex
        return Set.new if (max_hops == 0 or known_vertices.include?(from_vertex))

        known_vertices.add(from_vertex)
        found_vertices = Set.new

        if from_vertex.position.distance(origin_vertex.position) <= @@brush_radius
            found_vertices.add(from_vertex)
        end

        if @@brush_radius > 0
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

PlanerTool.reset_plane

end#module