fn glow_luma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn apply_glow(
  input_tex: texture_2d<f32>,
  input_sampler: sampler,
  uv: vec2<f32>,
  texel_size: vec2<f32>,
  intensity: f32,
  radius: f32,
  softness: f32,
  tint: vec3<f32>,
) -> vec4<f32> {
  let offsets =
    array<vec2<f32>, 8>(
      vec2<f32>(1.0, 0.0),
      vec2<f32>(-1.0, 0.0),
      vec2<f32>(0.0, 1.0),
      vec2<f32>(0.0, -1.0),
      vec2<f32>(0.7, 0.7),
      vec2<f32>(-0.7, 0.7),
      vec2<f32>(0.7, -0.7),
      vec2<f32>(-0.7, -0.7),
    );

  let center_color = textureSample(input_tex, input_sampler, uv);
  var glow_acc = vec3<f32>(0.0);

  let step = texel_size * radius;

  for (var i = 0; i < 8; i = i + 1) {
    let sample_uv = uv + offsets[i] * step;
    let sample_color = textureSample(input_tex, input_sampler, sample_uv).rgb;

    // Glow logic: weight by luma and apply softness curve
    let luma = glow_luma(sample_color);
    let weight = pow(luma, max(1.0 - softness, 0.1));
    glow_acc += sample_color * weight;
  }

  let glow_signal = (glow_acc / 8.0) * tint * intensity;

  // Combine using additive screen-like blending to prevent over-saturation
  return vec4<f32>(center_color.rgb + glow_signal, center_color.a);
}
