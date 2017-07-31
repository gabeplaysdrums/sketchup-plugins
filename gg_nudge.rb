# GG Nudge

# Author:	Gabriel Young, gabeplaysdrums@live.com

# Usage
#	Menu: Tools
#		Nudge Move:	Move selected object in small increments using arrow key

#Load the normal support files
require 'sketchup.rb'
require 'extensions.rb'

module GG_Nudge

    PLUGIN_ROOT = File.dirname(__FILE__) unless defined?(self::PLUGIN_ROOT)

    ex = SketchupExtension.new "GG Nudge", File.join(PLUGIN_ROOT, "gg_nudge/main.rb")
    ex.description = "Nudge entities into place using the keyboard"
    ex.version = "1.0.0"
    ex.copyright = "Gabriel Young (gabeplaysdrums@live.com) 2017"
    ex.creator = "Gabriel Young (gabeplaysdrums@live.com)"
    Sketchup.register_extension ex, true

end #module