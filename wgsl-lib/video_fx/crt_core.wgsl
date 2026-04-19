fn crt_distort(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
  let centered = uv * 2.0 - 1.0;
  let dist = dot(centered, centered);
  let distorted = centered * (1.0 + dist * curvature * 0.1);
  return (distorted + 1.0) * 0.5;
}

fn apply_crt(
  input_tex: texture_2d<f32>,
  input_sampler: sampler,
  uv: vec2<f32>,
  intensity: f32,
  curvature: f32,
  mask_strength: f32,
  vignette: f32,
) -> vec4<f32> {
  let distorted_uv = crt_distort(uv, curvature * intensity);

  // Border check
  if
    (distorted_uv.x < 0.0
      || distorted_uv.x > 1.0
      || distorted_uv.y < 0.0
      || distorted_uv.y > 1.0)
  {
    return vec4<f32>(0.0, 0.0, 0.0, 0.0);
  }

  let raw_sample = textureSample(input_tex, input_sampler, distorted_uv);
  var color = raw_sample.rgb;

  // Phosphor Mask (RGB Aperture Grille)
  let mask_uv = distorted_uv * vec2<f32>(320.0, 240.0) * 3.0; // Simulated subpixels
  let mask_val = 1.0 - (sin(mask_uv.x) * 0.5 + 0.5) * mask_strength * intensity;
  color *= mask_val;

  // Corner Vignette
  let centered = distorted_uv * 2.0 - 1.0;
  let edge_dist = length(centered * centered * centered);
  let vig = smoothstep(1.2 - 0.4 * vignette * intensity, 0.5, edge_dist);
  color *= vig;

  return vec4<f32>(color, raw_sample.a);
}
