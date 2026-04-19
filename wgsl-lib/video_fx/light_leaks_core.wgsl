fn leaks_hash(p: vec2<f32>) -> f32 {
  let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  let p3_2 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3_2.x + p3_2.y) * p3_2.z);
}

fn leaks_noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);

  // Quintic interpolation for maximum smoothness (no more square fragments)
  let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

  let a = leaks_hash(i);
  let b = leaks_hash(i + vec2<f32>(1.0, 0.0));
  let c = leaks_hash(i + vec2<f32>(0.0, 1.0));
  let d = leaks_hash(i + vec2<f32>(1.0, 1.0));

  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn apply_light_leaks(
  input_tex: texture_2d<f32>,
  input_sampler: sampler,
  uv: vec2<f32>,
  time: f32,
  intensity: f32,
  speed: f32,
  scale: f32,
  tint: vec3<f32>,
) -> vec4<f32> {
  let base_color = textureSample(input_tex, input_sampler, uv);

  let t = time * speed * 0.1;
  let n_uv = uv * scale;

  // Layered smooth noise
  let noise1 = leaks_noise(n_uv + vec2<f32>(t, t * 0.3));
  let noise2 = leaks_noise(n_uv * 0.7 - vec2<f32>(t * 0.2, t * 0.5));

  var combined_noise = pow(noise1 * noise2, 3.0) * 15.0;

  // Edge mask to keep it organic
  let edge_mask = 1.0 - smoothstep(0.2, 0.8, length(uv - vec2<f32>(0.5)) * 1.5);
  combined_noise *= (1.0 - edge_mask) * intensity;

  // Apply the user-defined tint
  let leak_color = tint * combined_noise;

  // Soft Screen Blending
  let final_rgb = base_color.rgb + leak_color * (1.0 - base_color.rgb);

  return vec4<f32>(final_rgb, base_color.a);
}
