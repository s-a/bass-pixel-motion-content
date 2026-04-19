fn apply_matte(
  input_tex: texture_2d<f32>,
  input_sampler: sampler,
  uv: vec2<f32>,
  texel_size: vec2<f32>,
  intensity: f32,
  softness: f32,
  milkiness: f32,
  desaturation: f32,
) -> vec4<f32> {
  let base_sample = textureSample(input_tex, input_sampler, uv);
  var color = base_sample.rgb;

  // 1. Diffuse Softening (Box Blur Approximation)
  var diffuse = vec3<f32>(0.0);
  let step = texel_size * softness * 2.0;
  let offsets =
    array<vec2<f32>, 4>(
      vec2<f32>(-1.0, -1.0),
      vec2<f32>(1.0, -1.0),
      vec2<f32>(-1.0, 1.0),
      vec2<f32>(1.0, 1.0),
    );

  for (var i = 0; i < 4; i++) {
    diffuse +=
      textureSample(input_tex, input_sampler, uv + offsets[i] * step).rgb;
  }
  diffuse /= 4.0;

  // Mix base with diffuse layer
  color = mix(color, diffuse, 0.3 * intensity);

  // 2. Luma Compression (Matte Histogram)
  // Raise blacks (milkiness) and slightly lower highlights
  let lift = 0.15 * milkiness * intensity;
  color = color * (1.0 - lift) + lift;
  color = color * (1.0 - 0.05 * intensity); // Slight top-end compression

  // 3. Desaturation
  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  color = mix(color, vec3<f32>(luma), desaturation * 0.2 * intensity);

  // 4. Contrast adjustment for "Paper" feel
  color = (color - 0.5) * (1.0 - 0.1 * intensity) + 0.5;

  return vec4<f32>(max(color, vec3<f32>(0.0)), base_sample.a);
}
