#!../../src/liquidsoap -i ../../libs/stdlib.liq ../../libs/deprecations.liq
%include "test.liq"

log.level.set(5)
audio.samplerate.set(48000)
video.frame.rate.set(45)
settings.decoder.decoders.set(["FFMPEG"])

fname = argv(default="files/video/@ffmpeg(format=mp4,@audio(codec=aac,channels=2),@video(codec=libx264)).mp4",1)
out = "files/test_videos_size.avi"

if file.exists(out) then
  file.remove(out)
end

s = (single(fname) : source(video=canvas(width=47, height=52)))
s = once(s)
s = mux_audio(audio=blank(), s)

clock.assign_new(sync='none',[s])

def on_done () =
  j = process.read("ffprobe -v quiet -print_format json -show_streams #{out}")

  let json.parse ( parsed: {
    streams: ({
      width: int,
      height: int
    } * _)
  }) = j

  let stream = fst(parsed.streams)

  print("Output video size is #{stream.width}x#{stream.height}.")

  if stream.width == 47 and stream.height == 52 then
    test.pass()
  else
    test.fail()
  end
end

output.file(fallible=true, on_stop=on_done, %avi(width=47, height=52), out, s)
