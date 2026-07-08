# frozen_string_literal: true

# Presets — list your saved conversion presets.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/presets.rb

require "api2convert"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

presets = client.presets.list(category: "video", target: "mp4")
puts "#{presets.length} preset(s)"

presets.each { |preset| puts "#{preset.id}: #{preset.name} -> #{preset.target}" }
