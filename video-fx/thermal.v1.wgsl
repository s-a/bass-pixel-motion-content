#import <engine::bpm_kernel_bindings>
@group(0) @binding(0) var input_tex: texture_2d<f32>;
@group(0) @binding(1) var input_sampler: sampler;





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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Map a scalar [0..1] range into a thermal false-color palette
fn get_thermal_color(t: f32) -> vec3<f32> {
  // Thermal colors: deep blue -> violet -> red -> yellow -> white
  let c0 = vec3<f32>(0.0, 0.0, 0.15); // Deep cool background
  let c1 = vec3<f32>(0.4, 0.0, 0.6);  // Purple
  let c2 = vec3<f32>(0.9, 0.1, 0.2);  // Red/Orange
  let c3 = vec3<f32>(1.0, 0.6, 0.0);  // Yellow/Orange
  let c4 = vec3<f32>(1.0, 1.0, 0.4);  // Yellow/White
  let c5 = vec3<f32>(1.0, 1.0, 1.0);  // Core heat (White)

  var c = c0;
  if (t < 0.2) {
    c = mix(c0, c1, t * 5.0);
  } else if (t < 0.4) {
    c = mix(c1, c2, (t - 0.2) * 5.0);
  } else if (t < 0.6) {
    c = mix(c2, c3, (t - 0.4) * 5.0);
  } else if (t < 0.8) {
    c = mix(c3, c4, (t - 0.6) * 5.0);
  } else {
    c = mix(c4, c5, (t - 0.8) * 5.0);
  }
  return c;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let intensity = #gui_param "intensity".x;
  let posterize = #gui_param "posterize".x;
  let edge_enh = #gui_param "edge_enhancement".x;
  let synthetic_look = #gui_param "synthetic_look".x;
  let time = params.timeline.x;

  let uv = in.uv;
  var base_color = textureSample(input_tex, input_sampler, uv);

  // 1. Calculate base luminance from actual color (giving dark/light spots)
  let luma = dot(base_color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // 2. Edge Detection (Sobel-like cross sampling to amplify silhouettes)
  var edge_mag = 0.0;
  if (edge_enh > 0.0) {
    let ts = params.texel_size;
    let c_l = textureSample(input_tex, input_sampler, uv + vec2<f32>(-ts.x, 0.0)).rgb;
    let c_r = textureSample(input_tex, input_sampler, uv + vec2<f32>(ts.x, 0.0)).rgb;
    let c_u = textureSample(input_tex, input_sampler, uv + vec2<f32>(0.0, -ts.y)).rgb;
    let c_d = textureSample(input_tex, input_sampler, uv + vec2<f32>(0.0, ts.y)).rgb;

    // Simple robust gradient magnitude
    let diff_x = abs(c_l - c_r);
    let diff_y = abs(c_u - c_d);
    let diff_luma = dot(diff_x + diff_y, vec3<f32>(0.33333));
    edge_mag = diff_luma;
  }

  // 3. Composite Signal
  // Combine luma (general heat mass) with edge mapping (hot contours)
  var thermal_signal = luma + (edge_mag * edge_enh);
  thermal_signal = thermal_signal * intensity;
  
  // Clamp before quantization
  thermal_signal = clamp(thermal_signal, 0.0, 1.0);

  // 4. Posterization (Quantize scalar signal into distinct temperature zones)
  if (posterize > 0.0 && posterize < 64.0) {
    thermal_signal = floor(thermal_signal * posterize + 0.5) / posterize;
  }

  // 5. False color mapping (Render the actual heat gradient)
  var final_color = get_thermal_color(thermal_signal);

  // 6. Synthetic Video Distortions (Simulate surveillance feed)
  if (synthetic_look > 0.0) {
    // Scanlines based on physical pixel size
    let scanline_freq = 0.5;
    let pos_y = uv.y / params.texel_size.y;
    let scanline_mask = 0.85 + 0.15 * sin(pos_y * 3.14159 * scanline_freq);
    
    // Dynamic noise
    let time_offset = fract(time * vec2<f32>(1.234, 4.567));
    let noise_val = hash12(uv + time_offset);
    let noise_mult = mix(1.0, 0.8 + 0.2 * noise_val, synthetic_look);

    final_color = final_color * mix(1.0, scanline_mask, synthetic_look) * noise_mult;
  }

  return vec4<f32>(final_color, base_color.a);
}

