fn film_hash(p: vec2<f32>) -> f32 {
  let p2 = fract(p * vec2<f32>(0.1031, 0.1030));
  let d = p2 + dot(p2, p2.yx + 33.33);
  return fract((d.x + d.y) * d.y);
}

fn apply_vintage_film(
  input_tex: texture_2d<f32>,
  input_sampler: sampler,
  uv: vec2<f32>,
  time: f32,
  intensity: f32,
  dust_amount: f32,
  scratches: f32,
  flicker: f32,
) -> vec4<f32> {
  let raw_sample = textureSample(input_tex, input_sampler, uv);
  var color = raw_sample.rgb;

  // 1. Exposure Flicker
  let flick_val = film_hash(vec2<f32>(time * 10.0, 0.0));
  color *= 1.0 + (flick_val - 0.5) * 0.2 * flicker * intensity;

  // 2. Dust & Specks
  let t_frame = floor(time * 12.0); // Animate dust at 12fps
  let dust_seed = uv + t_frame;
  if (film_hash(dust_seed) > 1.0 - 0.005 * dust_amount * intensity) {
    color = mix(color, vec3<f32>(0.0), 0.8);
  }

  // 3. Vertical Scratches
  let scratch_x = film_hash(vec2<f32>(t_frame, 0.0));
  let scratch_dist = abs(uv.x - scratch_x);
  if (scratch_dist < 0.001 * scratches * intensity) {
    let scratch_noise = film_hash(uv * 10.0 + time);
    if (scratch_noise > 0.2) {
      color = mix(color, vec3<f32>(0.1), 0.5);
    }
  }

  // 4. Sepia / Faded Color
  let gray = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let sepia = vec3<f32>(gray * 1.2, gray * 0.9, gray * 0.7);
  color = mix(color, sepia, 0.5 * intensity);

  return vec4<f32>(color, raw_sample.a);
}
