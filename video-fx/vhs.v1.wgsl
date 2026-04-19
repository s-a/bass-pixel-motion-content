#import <engine::bpm_kernel_bindings>
#import <bpm/video_fx/vhs_core.wgsl>

@group(0) @binding(0)
var input_tex: texture_2d<f32>;

@group(0) @binding(1)
var input_sampler: sampler;





struct VsOut {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VsOut {
  var positions = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -3.0),
    vec2<f32>(-1.0, 1.0),
    vec2<f32>(3.0, 1.0),
  );
  var uvs = array<vec2<f32>, 3>(
    vec2<f32>(0.0, 2.0),
    vec2<f32>(0.0, 0.0),
    vec2<f32>(2.0, 0.0),
  );
  var out: VsOut;
  out.position = vec4<f32>(positions[vertex_index], 0.0, 1.0);
  out.uv = uvs[vertex_index];
  return out;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let intensity = #gui_param "intensity".x;
  let jitter = #gui_param "jitter".x;
  let chroma_drift = #gui_param "chroma_drift".x;
  let noise_amount = #gui_param "noise".x;
  let tracking_amount = #gui_param "tracking".x;
  let time = params.timeline.x;

  return apply_vhs(
    input_tex,
    input_sampler,
    in.uv,
    time,
    intensity,
    jitter,
    chroma_drift,
    noise_amount,
    tracking_amount
  );
}

