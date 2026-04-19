#import <engine::bpm_kernel_bindings>
#import <bpm/video_fx/light_rays_core.wgsl>

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
  let threshold = #gui_param "threshold".x;
  let decay = #gui_param "decay".x;
  let density = #gui_param "density".x;
  let weight = #gui_param "weight".x;

  return apply_light_rays(
    input_tex,
    input_sampler,
    in.uv,
    intensity,
    threshold,
    decay,
    density,
    weight
  );
}

