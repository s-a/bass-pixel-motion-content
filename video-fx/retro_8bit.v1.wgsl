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
  let pixel_size = #gui_param "pixel_size".x;
  let color_depth = #gui_param "color_depth".x;

  var uv = in.uv;

  // 1. Pixelation (Resolution Downsampling)
  if (pixel_size > 1.0) {
    // texel_size is typically 1.0 / resolution
    // We want the grid size in UV space per "retro pixel"
    let aspect_ratio = params.texel_size.x / params.texel_size.y;
    // Assuming params.texel_size is the size of one physical pixel in UV space.
    // E.g. texel_size = vec2(1/1920, 1/1080)
    let block_size =
      vec2<f32>(
        pixel_size * params.texel_size.x,
        pixel_size * params.texel_size.y,
      );
    uv = floor(uv / block_size) * block_size + (block_size * 0.5);
  }

  // Sample the color at the quantized UV
  var color = textureSample(input_tex, input_sampler, uv);

  // 2. Color Quantization (Posterization)
  if (color_depth > 0.0) {
    // E.g. if color_depth is 8.0, we crush the 1.0 float range into 8 steps
    let quantized_rgb =
      floor(color.rgb * color_depth + vec3<f32>(0.5)) / color_depth;
    color = vec4<f32>(quantized_rgb, color.a);
  }

  return color;
}

