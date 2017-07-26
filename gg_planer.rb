# GG PLaner

# Author:	Gabriel Young, gabeplaysdrums@live.com

# Usage
#	Menu: Tools
#		Planer: Generate a plane fitting vertices near a point

#Load the normal support files
require 'sketchup.rb'
require 'extensions.rb'

module GG_Planer

    PLUGIN_ROOT = File.dirname(__FILE__) unless defined?(self::PLUGIN_ROOT)

    ex = SketchupExtension.new "GG Planer", File.join(PLUGIN_ROOT, "gg_planer/main.rb")
    ex.description = "Find a plane from vertices around a point"
    ex.version = "1.0.0"
    ex.copyright = "Gabriel Young (gabeplaysdrums@live.com) 2017"
    ex.creator = "Gabriel Young (gabeplaysdrums@live.com)"
    Sketchup.register_extension ex, true

end #module