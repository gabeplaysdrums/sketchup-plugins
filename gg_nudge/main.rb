module GG_Nudge

KC_UP = 63232
KC_DOWN = 63233
KC_LEFT = 63234
KC_RIGHT = 63235
KC_HOME = 63273
KC_END = 63275

class NudgeTool

    @@instances = Hash.new

    def self.get_for_model(model)
        if not @@instances.include?(model.guid)
            @@instances[model.guid] = self.new
        end

        return @@instances[model.guid]
    end

    def initialize
        @translate_step = '0.25'.to_l
        @rotate_step = 0.25
    end

    def activate
        @ph = Sketchup.active_model.active_view.pick_helper
        puts 'Nudge activated'

        Sketchup::set_status_text('Choose an origin point', SB_PROMPT)
        @originInput = Sketchup::InputPoint.new
        @origin = nil

    end

    def show_settings
        prompts = ['Translate step', 'Rotate step']
        defaults = [@translate_step, @rotate_step]
        input = UI.inputbox(prompts, defaults, 'Nudge Options')

        if input
            @translate_step = input[0].to_l
            @rotate_step = input[1].to_f
        end
    end

    def start_move
        Sketchup::set_status_text('Press arrow keys to nudge', SB_PROMPT)
    end

    def deactivate(view)
        puts 'Nudge deactivated'

        view.invalidate if view
    end

    def onKeyDown(key, repeat, flags, view)
        translate = (flags & ALT_MODIFIER_MASK == 0)
        y_axis = (flags & COPY_MODIFIER_MASK == 0)

        if translate
            step = (flags & CONSTRAIN_MODIFIER_MASK == 0) ? @translate_step : 10*@translate_step

            if false
            elsif key == KC_RIGHT
                puts '+x'
                self.translate(step, 0, 0)
            elsif key == KC_LEFT
                puts '-x'
                self.translate(-step, 0, 0)
            elsif key == KC_UP and y_axis
                puts '+y'
                self.translate(0, step, 0)
            elsif key == KC_DOWN and y_axis
                puts '-y'
                self.translate(0, -step, 0)
            elsif ((key == KC_UP and not y_axis) or key == KC_HOME)
                puts '+z'
                self.translate(0, 0, step)
            elsif ((key == KC_DOWN and not y_axis) or key == KC_END)
                puts '-z'
                self.translate(0, 0, -step)
            end
        else
            step = (flags & CONSTRAIN_MODIFIER_MASK == 0) ? @rotate_step.degrees : 10*@rotate_step.degrees

            if false
            elsif key == KC_RIGHT
                puts '+x'
                self.rotate(step, 1, 0, 0)
            elsif key == KC_LEFT
                puts '-x'
                self.rotate(step, -1, 0, 0)
            elsif key == KC_UP and y_axis
                puts '+y'
                self.rotate(step, 0, 1, 0)
            elsif key == KC_DOWN and y_axis
                puts '-y'
                self.rotate(step, 0, -1, 0)
            elsif ((key == KC_UP and not y_axis) or key == KC_HOME)
                puts '+z'
                self.rotate(step, 0, 0, 1)
            elsif ((key == KC_DOWN and not y_axis) or key == KC_END)
                puts '-z'
                self.rotate(step, 0, 0, -1)
            end
        end

        view.invalidate
    end

    def onMouseMove(flags, x, y, view)
        if not @origin
            @originInput.pick view, x, y
            view.invalidate
        end
    end

    def draw(view)
        @originInput.draw view
        view.draw_points([ @origin ], 10, 1, 'gold') if @origin
    end

    def translate(x, y, z)
        return if not @origin

        t = Geom::Vector3d.new(x, y, z)

        Sketchup.active_model.selection.each { |entity|
            entity.transform!(Geom::Transformation.translation(t))
        }
    end

    def rotate(angle, x, y, z)
        return if not @origin
        Sketchup.active_model.selection.each { |entity|
            entity.transform!(Geom::Transformation.rotation(@origin, Geom::Vector3d.new(x, y, z), angle))
        }
    end

    def onLButtonDown(flags, x, y, view)
        if (Sketchup.active_model.selection.length == 0)
            #Clear selection
            Sketchup.active_model.selection.clear

            #Select what's hovered
            @ph.do_pick(x, y)
            picked = @ph.best_picked
            if (picked)
                Sketchup.active_model.selection.add picked
            end
        end

        #Do nothing with this click if nothing is selected
        return nil if Sketchup.active_model.selection.length == 0

        @originInput.pick view, x, y
        @origin = (@originInput.valid?) ? @originInput.position : nil

        if @origin
            Sketchup::set_status_text("Use keyboard to nudge selection", SB_PROMPT)
            view.invalidate
        end
    end

menu = UI.menu("Tools").add_submenu("Nudge")
menu.add_item("In model axes relative to point") {
    tool = NudgeTool.get_for_model Sketchup.active_model
    Sketchup.active_model.select_tool tool
}
menu.add_item("Settings") {
    tool = NudgeTool.get_for_model Sketchup.active_model
    tool.show_settings
}

end#class
end#module