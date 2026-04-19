fn vhs_hash(p: vec2<f32>) -> f32 {
  // Improved hash that avoids diagonal correlation
  let p2 = fract(p * vec2<f32>(0.1031, 0.1030));
  let d = p2 + dot(p2, p2.yx + 33.33);
  return fract((d.x + d.y) * d.y);
}

fn rgb2yuv(rgb: vec3<f32>) -> vec3<f32> {
  return
    vec3<f32>(
      dot(rgb, vec3<f32>(0.299, 0.587, 0.114)),
      dot(rgb, vec3<f32>(-0.14713, -0.28886, 0.436)),
      dot(rgb, vec3<f32>(0.615, -0.51499, -0.10001)),
    );
}

fn yuv2rgb(yuv: vec3<f32>) -> vec3<f32> {
  return
    vec3<f32>(
      yuv.x + 1.13983 * yuv.z,
      yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z,
      yuv.x + 2.03211 * yuv.y,
    );
}

fn apply_vhs(
  input_tex: texture_2d<f32>,
  input_sampler: sampler,
  uv: vec2<f32>,
  time: f32,
  intensity: f32,
  jitter: f32,
  chroma_drift: f32,
  noise_amount: f32,
  tracking_amount: f32,
) -> vec4<f32> {
  var lookup_uv = uv;

  // 1. STABLE JITTER (Horizontal only)
  let wave = sin(uv.y * 25.0 + time * 8.0) * 0.00012 * jitter * intensity;
  lookup_uv.x += wave;

  // 2. TRACKING BAR (Vertical only movement)
  let roll_pos = fract(time * 0.1);
  let roll_dist = abs(uv.y - roll_pos);
  let bar_strength = smoothstep(0.03 * intensity, 0.0, roll_dist);

  if (bar_strength > 0.0) {
    lookup_uv.x +=
      (vhs_hash(vec2<f32>(time * 0.5, uv.y)) - 0.5)
        * 0.006
        * bar_strength
        * tracking_amount;
  }

  // 3. FETCH
  let raw_sample = textureSample(input_tex, input_sampler, lookup_uv);
  var yuv = rgb2yuv(raw_sample.rgb);

  // 4. CLEAN ANALOG NOISE (No diagonal patterns)
  // We compute noise based on UV and a high-frequency time seed
  let t_seed = fract(time * 60.0); // Animate at 60Hz
  let grain = (vhs_hash(uv + t_seed) - 0.5) * 0.1 * noise_amount * intensity;

  // Horizontal tape streaks (stretched noise)
  let streak_uv = vec2<f32>(uv.x * 0.01, uv.y * 1000.0);
  let streaks =
    (vhs_hash(streak_uv + t_seed) - 0.5) * 0.06 * noise_amount * intensity;

  yuv.x += grain + streaks;

  // 5. CHROMA BANDWIDTH (Smearing)
  var chroma_acc = yuv.yz;
  let bleed_samples = 5;
  let bleed_width = 0.01 * chroma_drift * intensity;
  for (var i = 1; i < bleed_samples; i++) {
    let offset = vec2<f32>(f32(i) * bleed_width / f32(bleed_samples), 0.0);
    chroma_acc +=
      rgb2yuv(
        textureSample(input_tex, input_sampler, lookup_uv - offset).rgb,
      ).yz;
  }
  yuv.y = chroma_acc.x / f32(bleed_samples);
  yuv.z = chroma_acc.y / f32(bleed_samples);

  // 6. BAR INTERFERENCE
  if (bar_strength > 0.0) {
    yuv.x +=
      (vhs_hash(uv * 2.0 + t_seed) - 0.5)
        * 0.12
        * bar_strength
        * tracking_amount;
  }

  var color = yuv2rgb(yuv);

  // 7. FINISH
  color *= 1.02; // Compensation
  return vec4<f32>(color, raw_sample.a);
}
