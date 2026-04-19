// ---------------------------------------------------------------------------
// 3D Transform helpers — reusable rotation functions for scene shaders.
// Usage: #import <bpm/3d/transform.wgsl>
// ---------------------------------------------------------------------------

fn rotate_x(p: vec3<f32>, angle: f32) -> vec3<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return vec3<f32>(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

fn rotate_y(p: vec3<f32>, angle: f32) -> vec3<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return vec3<f32>(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

fn rotate_z(p: vec3<f32>, angle: f32) -> vec3<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return vec3<f32>(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

/// Builds a 3D rotation matrix (order: Y -> X -> Z)
fn euler_rotation_matrix(rot: vec3<f32>) -> mat4x4<f32> {
  let cx = cos(rot.x);
  let sx = sin(rot.x);
  let cy = cos(rot.y);
  let sy = sin(rot.y);
  let cz = cos(rot.z);
  let sz = sin(rot.z);

  let m00 = cy * cz + sy * sx * sz;
  let m01 = cz * sx * sy - cy * sz;
  let m02 = cx * sy;
  let m10 = cx * sz;
  let m11 = cx * cz;
  let m12 = -sx;
  let m20 = cy * sx * sz - cz * sy;
  let m21 = cy * cz * sx + sy * sz;
  let m22 = cx * cy;

  return
    mat4x4<f32>(
      vec4<f32>(m00, m10, m20, 0.0),
      vec4<f32>(m01, m11, m21, 0.0),
      vec4<f32>(m02, m12, m22, 0.0),
      vec4<f32>(0.0, 0.0, 0.0, 1.0),
    );
}

/// Builds a look-at view matrix that transforms world-space into view-space.
/// x=right, y=up, z=-forward (looking down -Z)
fn build_view_matrix(
  eye: vec3<f32>,
  look_at: vec3<f32>,
  up_hint: vec3<f32>,
) -> mat3x3<f32> {
  let forward = normalize(look_at - eye);
  let right = normalize(cross(forward, up_hint));
  let up = cross(right, forward);
  return
    mat3x3<f32>(
      vec3<f32>(right.x, up.x, -forward.x),
      vec3<f32>(right.y, up.y, -forward.y),
      vec3<f32>(right.z, up.z, -forward.z),
    );
}

/// Projects a view-space position into a 4D clip position using classic perspective mapping.
fn project_perspective(
  view_pos: vec3<f32>,
  fov: f32,
  aspect: f32,
  near: f32,
  far: f32,
) -> vec4<f32> {
  let f = 1.0 / tan(fov * 0.5);
  let depth = -view_pos.z;
  let ndc_depth = (depth - near) / (far - near);
  return
    vec4<f32>(
      (view_pos.x * f) / aspect,
      view_pos.y * f,
      ndc_depth * depth,
      depth,
    );
}
