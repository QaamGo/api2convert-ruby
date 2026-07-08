# frozen_string_literal: true

# Audio Operations — re-encode a WAV to AAC with explicit codec settings.
#
#   API2CONVERT_API_KEY=<your key> ruby -Ilib examples/audio_operations.rb

require "api2convert"

WAV = "https://example-files.online-convert.com/audio/wav/example.wav"

client = Api2Convert::Client.new # reads API2CONVERT_API_KEY

result = client.convert(
  WAV,
  "aac",
  { "audio_codec" => "aac", "audio_bitrate" => 192, "channels" => "stereo", "frequency" => 44_100 },
  category: "audio"
)

path = result.save("output/")
puts "saved #{path} (#{File.size(path)} bytes)"
