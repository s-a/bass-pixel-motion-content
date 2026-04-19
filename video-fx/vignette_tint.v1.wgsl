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

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let color = textureSample(input_tex, input_sampler, in.uv);
  let radius = clamp(#gui_param "radius".x, 0.05, 0.92);
  let softness = clamp(#gui_param "softness".x, 0.01, 1.0);
  let intensity = max(#gui_param "intensity".x, 0.0);
  let center = #gui_param "center".xy;
  let tint = #gui_param "tint".xyz;
  let delta = in.uv - center;
  let extent_x = max(select(center.x, 1.0 - center.x, delta.x >= 0.0), 0.0001);
  let extent_y = max(select(center.y, 1.0 - center.y, delta.y >= 0.0), 0.0001);
  let normalized = vec2<f32>(delta.x / extent_x, delta.y / extent_y);
  let radial = length(normalized) * 0.70710677;
  let edge_locked = max(abs(normalized.x), abs(normalized.y)) * 0.84;
  let distance_from_center = max(radial, edge_locked);
  let vignette =
    smoothstep(radius, min(radius + softness, 1.0), distance_from_center);
  let tinted = color.rgb * mix(vec3<f32>(1.0), tint, vignette * intensity);
  let darkened = tinted * (1.0 - vignette * intensity * 0.65);
  return vec4<f32>(darkened, color.a);
}

