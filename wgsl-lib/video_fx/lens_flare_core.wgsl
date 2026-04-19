fn flare_extract(color: vec3<f32>, threshold: f32) -> vec3<f32> {
  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  return color * smoothstep(threshold, threshold + 0.5, luma);
}

fn apply_lens_flare(
  input_tex: texture_2d<f32>,
  input_sampler: sampler,
  uv: vec2<f32>,
  intensity: f32,
  threshold: f32,
  ghost_count: i32,
  ghost_dispersal: f32,
  halo_radius: f32,
  halo_thickness: f32,
) -> vec4<f32> {
  let base_color = textureSample(input_tex, input_sampler, uv);

  // Center-relative coordinates
  let ghost_vec = (vec2<f32>(0.5) - uv) * ghost_dispersal;
  let halo_vec = normalize(uv - vec2<f32>(0.5)) * halo_radius;

  var flare_acc = vec3<f32>(0.0);

  // 1. Generate Ghosts
  // Ghosts are light reflections mirrored across the center
  for (var i = 0; i < ghost_count; i++) {
    let offset = ghost_vec * f32(i);
    let ghost_uv = fract(uv + offset);

    // Falloff towards edges
    let weight = length(vec2<f32>(0.5) - ghost_uv) / length(vec2<f32>(0.5));
    let ghost_weight = pow(1.0 - weight, 10.0);

    // Chromatic aberration in ghosts
    let r =
      flare_extract(
        textureSample(
          input_tex,
          input_sampler,
          ghost_uv + ghost_vec * 0.02,
        ).rgb,
        threshold,
      ).r;
    let g =
      flare_extract(
        textureSample(input_tex, input_sampler, ghost_uv).rgb,
        threshold,
      ).g;
    let b =
      flare_extract(
        textureSample(
          input_tex,
          input_sampler,
          ghost_uv - ghost_vec * 0.02,
        ).rgb,
        threshold,
      ).b;

    flare_acc += vec3<f32>(r, g, b) * ghost_weight;
  }

  // 2. Generate Halo (Ring)
  let halo_uv = fract(uv + halo_vec);
  let halo_weight =
    smoothstep(
      halo_thickness,
      0.0,
      abs(length(uv - vec2<f32>(0.5)) - halo_radius),
    );
  flare_acc +=
    flare_extract(
      textureSample(input_tex, input_sampler, halo_uv).rgb,
      threshold,
    )
      * halo_weight
      * 0.5;

  // 3. Diffraction Star (Simple horizontal streak)
  let streak_uv = vec2<f32>(uv.x, 0.5 + (uv.y - 0.5) * 100.0);
  flare_acc +=
    flare_extract(
      textureSample(input_tex, input_sampler, streak_uv).rgb,
      threshold,
    ) * 0.1;

  return vec4<f32>(base_color.rgb + flare_acc * intensity, base_color.a);
}
