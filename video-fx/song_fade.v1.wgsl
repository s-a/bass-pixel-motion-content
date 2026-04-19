#import <engine::bpm_kernel_bindings>
@group(0) @binding(0) var input_tex: texture_2d<f32>;

@group(0) @binding(1) var input_sampler: sampler;





struct VsOut {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VsOut {
  var positions =
    array<vec2<f32>, 3>(
      vec2<f32>(-1.0, -3.0),
      vec2<f32>(-1.0, 1.0),
      vec2<f32>(3.0, 1.0),
    );
  var uvs =
    array<vec2<f32>, 3>(
      vec2<f32>(0.0, 2.0),
      vec2<f32>(0.0, 0.0),
      vec2<f32>(2.0, 0.0),
    );
  var out: VsOut;
  out.position = vec4<f32>(positions[vertex_index], 0.0, 1.0);
  out.uv = uvs[vertex_index];
  return out;
}

fn fade_in_factor(current_seconds: f32, fade_seconds: f32) -> f32 {
  if fade_seconds <= 0.0 {
    return 1.0;
  }
  return clamp(current_seconds / fade_seconds, 0.0, 1.0);
}

fn fade_out_factor(
  current_seconds: f32,
  total_seconds: f32,
  fade_seconds: f32,
) -> f32 {
  if total_seconds <= 0.0 || fade_seconds <= 0.0 {
    return 1.0;
  }
  return clamp((total_seconds - current_seconds) / fade_seconds, 0.0, 1.0);
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let color = textureSample(input_tex, input_sampler, in.uv);
  let current_seconds = max(params.timeline.x, 0.0);
  let total_seconds = max(params.timeline.y, 0.0);
  let fade =
    min(
      fade_in_factor(current_seconds, #gui_param "fade_in_seconds".x),
      fade_out_factor(current_seconds, total_seconds, #gui_param "fade_out_seconds".x),
    );
  return vec4<f32>(color.rgb * fade, color.a);
}

