fn rays_extract(color: vec3<f32>, threshold: f32) -> vec3<f32> {
  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  return color * smoothstep(threshold, threshold + 0.3, luma);
}

fn apply_light_rays(
  input_tex: texture_2d<f32>,
  input_sampler: sampler,
  uv: vec2<f32>,
  intensity: f32,
  threshold: f32,
  decay: f32,
  density: f32,
  weight: f32,
) -> vec4<f32> {
  let base_color = textureSample(input_tex, input_sampler, uv);

  // Ray vector pointing from center
  let delta_uv = (uv - vec2<f32>(0.5)) * density / 32.0;
  var current_uv = uv;
  var illumination_decay = 1.0;
  var rays_acc = vec3<f32>(0.0);

  // Radial blur loop
  for (var i = 0; i < 32; i++) {
    current_uv -= delta_uv;
    var sample_color =
      rays_extract(
        textureSample(input_tex, input_sampler, current_uv).rgb,
        threshold,
      );

    // Add slight chromatic shift to rays
    let r =
      rays_extract(
        textureSample(
          input_tex,
          input_sampler,
          current_uv + delta_uv * 0.1,
        ).rgb,
        threshold,
      ).r;
    let b =
      rays_extract(
        textureSample(
          input_tex,
          input_sampler,
          current_uv - delta_uv * 0.1,
        ).rgb,
        threshold,
      ).b;
    sample_color = vec3<f32>(r, sample_color.g, b);

    sample_color *= illumination_decay * weight;
    rays_acc += sample_color;
    illumination_decay *= decay;
  }

  return vec4<f32>(base_color.rgb + rays_acc * intensity, base_color.a);
}
