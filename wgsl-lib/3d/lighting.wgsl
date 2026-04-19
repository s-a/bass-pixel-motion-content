// ---------------------------------------------------------------------------
// 3D Lighting helpers — 3-point lighting rig for scene shaders.
// Usage: #import <bpm/3d/lighting.wgsl>
// ---------------------------------------------------------------------------

/// Classic 3-point lighting: key (front-left), fill (right), rim (behind).
/// Returns a scalar intensity suitable for: color * intensity.
fn lighting_3point(normal: vec3<f32>) -> f32 {
  // Key light: strong, from front-left-above
  let key_dir = normalize(vec3<f32>(-0.6, 0.8, -0.9));
  let key_diff = max(dot(normal, key_dir), 0.0);

  // Specular highlight (Blinn-Phong, camera looks -Z)
  let view_dir = vec3<f32>(0.0, 0.0, -1.0);
  let key_half = normalize(key_dir - view_dir);
  let key_spec = pow(max(dot(normal, key_half), 0.0), 32.0);

  // Fill light: softer, from the right side
  let fill_dir = normalize(vec3<f32>(0.7, 0.3, -0.5));
  let fill_diff = max(dot(normal, fill_dir), 0.0);

  // Rim light: from behind, highlights edges
  let rim_dir = normalize(vec3<f32>(0.0, 0.2, 0.9));
  let rim = pow(max(dot(normal, rim_dir), 0.0), 2.0);

  let ambient = 0.08;
  let diffuse = key_diff * 0.7 + fill_diff * 0.25;
  let specular = key_spec * 0.3;
  let rim_glow = rim * 0.35;

  return ambient + diffuse + specular + rim_glow;
}

/// Simple single-light diffuse for lightweight shaders.
fn lighting_simple(normal: vec3<f32>, light_dir: vec3<f32>) -> f32 {
  let diffuse = max(dot(normal, normalize(light_dir)), 0.0);
  return 0.15 + diffuse * 0.85;
}

/// Standard GLTF Point Light calculation derived from Blender Watts
fn apply_gltf_point_light(
  world_pos: vec3<f32>,
  normal: vec3<f32>,
  vertex_color: vec3<f32>,
  light_pos: vec3<f32>,
  light_intensity: f32,
  light_color: vec3<f32>,
) -> vec3<f32> {
  let to_light = light_pos - world_pos;
  let dist = length(to_light);
  let light_dir = to_light / max(dist, 0.001);

  let diffuse_term = max(dot(normal, light_dir), 0.0);
  let attenuation = light_intensity / (4.0 * 3.14159 * dist * dist);
  let light_contribution = light_color * min(attenuation, 5.0);
  let ambient = 0.12;

  return
    vertex_color
      * light_contribution
      * (ambient + diffuse_term * (1.0 - ambient));
}

/// Fallback directional light for missing GLTF lights
fn apply_fallback_light(normal: vec3<f32>, vertex_color: vec3<f32>) -> vec3<
  f32,
> {
  let light_dir = normalize(vec3<f32>(0.5, 1.0, -0.3));
  let diffuse_term = max(dot(normal, light_dir), 0.0);
  let ambient = 0.12;
  return vertex_color * (ambient + diffuse_term * (1.0 - ambient));
}
