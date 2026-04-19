fn grain_hash(p: vec2<f32>) -> f32 {
  let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  let p3_2 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3_2.x + p3_2.y) * p3_2.z);
}

fn apply_film_grain(
  input_tex: texture_2d<f32>,
  input_sampler: sampler,
  uv: vec2<f32>,
  time: f32,
  intensity: f32,
  size: f32,
  color_amount: f32,
) -> vec4<f32> {
  let color = textureSample(input_tex, input_sampler, uv);

  // 1. Compute luminance (standard Rec. 709)
  let luma = dot(color.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

  // 2. Grain intensity curve (parabolic)
  // Film grain is most visible in mid-tones (around 0.5 luma)
  let grain_weight = pow(luma * (1.0 - luma), 0.5) * 4.0;

  // 3. Procedural noise generation
  // Animate at high speed but step-wise to simulate frame rates
  let t_seed = floor(time * 24.0) * 0.1337;
  let noise_uv = uv * (1000.0 / max(size, 0.1));

  let noise_r = grain_hash(noise_uv + t_seed);
  let noise_g = grain_hash(noise_uv + t_seed + 0.123);
  let noise_b = grain_hash(noise_uv + t_seed + 0.456);

  // 4. Combine monochrome and colored grain
  let mono_grain = noise_r;
  let color_grain = vec3<f32>(noise_r, noise_g, noise_b);
  let mixed_grain = mix(vec3<f32>(mono_grain), color_grain, color_amount);

  // 5. Final composition
  let grain_signal = (mixed_grain - 0.5) * intensity * grain_weight;

  // Additive blending for realistic film grain
  return vec4<f32>(max(color.rgb + grain_signal, vec3<f32>(0.0)), color.a);
}
