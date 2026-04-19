#import <engine::bpm_kernel_bindings>
@group(0) @binding(0) var input_tex: texture_2d<f32>;

@group(0) @binding(1) var input_sampler: sampler;





@group(0) @binding(3) var prev_tex: texture_2d<f32>;

@group(0) @binding(4) var prev_sampler: sampler;

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

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let persistence = #gui_param "persistence".x;
  let spread = #gui_param "chromatic_spread".x;

  let current = textureSample(input_tex, input_sampler, in.uv);

  // Chromatic temporal sampling
  // We sample the previous frame with slightly offset UVs for each color channel.
  let prev_r =
    textureSample(prev_tex, prev_sampler, in.uv + vec2<f32>(spread, 0.0)).r;
  let prev_g = textureSample(prev_tex, prev_sampler, in.uv).g;
  let prev_b =
    textureSample(prev_tex, prev_sampler, in.uv - vec2<f32>(spread, 0.0)).b;

  let previous = vec4<f32>(prev_r, prev_g, prev_b, current.a);

  // Mix current frame with chromatic history
  return mix(current, previous, persistence);
}

