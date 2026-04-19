fn bloom_luma(color: vec3<f32>) -> f32 {
  return max(max(color.r, color.g), color.b);
}

fn bloom_weight(luma: f32, threshold: f32, soft_knee: f32) -> f32 {
  let knee = max(soft_knee, 0.0001);
  return smoothstep(threshold - knee, threshold + knee, luma);
}

fn bloom_extract(
  sample_color: vec3<f32>,
  threshold: f32,
  soft_knee: f32,
) -> vec3<f32> {
  return
    sample_color * bloom_weight(bloom_luma(sample_color), threshold, soft_knee);
}

fn bloom_combine(
  base_color: vec3<f32>,
  bloom_signal: vec3<f32>,
  intensity: f32,
  tint: vec3<f32>,
) -> vec3<f32> {
  return base_color + bloom_signal * tint * intensity;
}

fn apply_bloom(
  input_tex: texture_2d<f32>,
  input_sampler: sampler,
  uv: vec2<f32>,
  texel_size: vec2<f32>,
  threshold: f32,
  intensity: f32,
  radius: f32,
  soft_knee: f32,
  tint: vec3<f32>,
) -> vec4<f32> {
  let offsets =
    array<vec2<f32>, 8>(
      vec2<f32>(1.0, 0.0),
      vec2<f32>(-1.0, 0.0),
      vec2<f32>(0.0, 1.0),
      vec2<f32>(0.0, -1.0),
      vec2<f32>(1.0, 1.0),
      vec2<f32>(-1.0, 1.0),
      vec2<f32>(1.0, -1.0),
      vec2<f32>(-1.0, -1.0),
    );
  let color = textureSample(input_tex, input_sampler, uv);
  let center_signal = bloom_extract(color.rgb, threshold, soft_knee);
  let center_weight = bloom_weight(bloom_luma(color.rgb), threshold, soft_knee);
  var blur = center_signal;
  var total_weight = center_weight;
  let sample_step = texel_size * max(radius, 0.0);
  for (var i = 0; i < 8; i = i + 1) {
    let sample_uv = uv + offsets[i] * sample_step;
    let sample_color = textureSample(input_tex, input_sampler, sample_uv);
    let weight =
      bloom_weight(bloom_luma(sample_color.rgb), threshold, soft_knee);
    blur = blur + bloom_extract(sample_color.rgb, threshold, soft_knee);
    total_weight = total_weight + weight;
  }
  let bloom_signal = blur / max(total_weight, 0.0001);
  return
    vec4<f32>(bloom_combine(color.rgb, bloom_signal, intensity, tint), color.a);
}
