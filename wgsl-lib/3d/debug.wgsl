// ---------------------------------------------------------------------------
// 3D Debug helpers — standard axes and grid for scene shaders.
// Usage: #import <bpm/3d/debug.wgsl>
// ---------------------------------------------------------------------------

/// Procedural geometry for the 3D local axes arrow. Returns local vertex position.
fn get_axis_vertex(local_id: u32) -> vec3<f32> {
  let tri = local_id / 3u;
  let vert = local_id % 3u;

  let l0 = 0.0;
  let l1 = 1.6;
  let l2 = 2.0;
  let w_line = 0.02;
  let w_cone = 0.08;

  var pos = vec3<f32>(0.0);
  let quad_u = array<f32, 6>(0.0, 1.0, 1.0, 0.0, 1.0, 0.0);
  let quad_v = array<f32, 6>(-1.0, -1.0, 1.0, -1.0, 1.0, 1.0);

  if tri == 0u || tri == 1u {
    let v_idx = tri * 3u + vert;
    pos = vec3<f32>(mix(l0, l1, quad_u[v_idx]), quad_v[v_idx] * w_line, 0.0);
  } else if tri == 2u || tri == 3u {
    let v_idx = (tri - 2u) * 3u + vert;
    pos = vec3<f32>(mix(l0, l1, quad_u[v_idx]), 0.0, quad_v[v_idx] * w_line);
  } else if tri >= 4u && tri <= 7u {
    let side = tri - 4u;
    let angles = array<f32, 5>(0.0, 1.5708, 3.14159, 4.71239, 6.28318);
    let a1 = angles[side];
    let a2 = angles[side + 1u];
    if vert == 0u {
      pos = vec3<f32>(l2, 0.0, 0.0);
    } else if vert == 1u {
      pos = vec3<f32>(l1, cos(a1) * w_cone, sin(a1) * w_cone);
    } else {
      pos = vec3<f32>(l1, cos(a2) * w_cone, sin(a2) * w_cone);
    }
  } else if tri == 8u || tri == 9u {
    let v_idx = (tri - 8u) * 3u + vert;
    let u = quad_u[v_idx] * 2.0 - 1.0;
    let v = quad_v[v_idx];
    pos = vec3<f32>(l1, u * w_cone, v * w_cone);
  }
  return pos;
}

/// Generic raycaster for drawing perfect arrows within the procedural bounding boxes.
/// Returns the shaded color mapped to the axis, or returns alpha < 0.0 to signal a discard.
fn raycast_axis(
  axis_idx: f32,
  world_pos: vec3<f32>,
  vertex_color: vec3<f32>,
  camera_pos: vec3<f32>,
  obj_center: vec3<f32>,
  obj_rotate: mat4x4<f32>,
  obj_scale: f32,
  xray_active: bool,
) -> vec4<f32> {
  let inv_rotate =
    transpose(
      mat3x3<f32>(obj_rotate[0].xyz, obj_rotate[1].xyz, obj_rotate[2].xyz),
    );

  let ro_world = camera_pos;
  let rd_world = normalize(world_pos - camera_pos);
  let ro_local = inv_rotate * (ro_world - obj_center);
  let rd_local = inv_rotate * rd_world;

  var ro = ro_local;
  var rd = rd_local;
  if axis_idx > 0.5 && axis_idx < 1.5 {
    // Y
    ro = vec3<f32>(ro_local.y, ro_local.x, ro_local.z);
    rd = vec3<f32>(rd_local.y, rd_local.x, rd_local.z);
  } else if axis_idx > 1.5 {
    // Z
    ro = vec3<f32>(ro_local.z, ro_local.x, ro_local.y);
    rd = vec3<f32>(rd_local.z, rd_local.x, rd_local.y);
  }

  let R1 = 0.03;
  let a1 = rd.y * rd.y + rd.z * rd.z;
  let b1 = ro.y * rd.y + ro.z * rd.z;
  let c1 = ro.y * ro.y + ro.z * ro.z - R1 * R1;
  let h1 = b1 * b1 - a1 * c1;
  var t_cyl = -1.0;
  if a1 > 0.0001 && h1 >= 0.0 {
    let tc = (-b1 - sqrt(h1)) / a1;
    let x = ro.x + tc * rd.x;
    if tc > 0.0 && x > 0.0 && x < 1.6 {
      t_cyl = tc;
    }
  }

  let R2 = 0.10; // cone base radius
  let xmin = 1.6;
  let xmax = 2.0;
  let k = R2 / (xmax - xmin);
  let dx = xmax - ro.x;
  let a2 = rd.y * rd.y + rd.z * rd.z - k * k * rd.x * rd.x;
  let b2 = ro.y * rd.y + ro.z * rd.z + k * k * dx * rd.x;
  let c2 = ro.y * ro.y + ro.z * ro.z - k * k * dx * dx;
  let h2 = b2 * b2 - a2 * c2;
  var t_cone = -1.0;
  if h2 >= 0.0 && abs(a2) > 0.0001 {
    var tA = (-b2 - sqrt(h2)) / a2;
    var tB = (-b2 + sqrt(h2)) / a2;
    if tA > tB {
      let temp = tA;
      tA = tB;
      tB = temp;
    }
    if tA > 0.0 && (ro.x + tA * rd.x) > xmin && (ro.x + tA * rd.x) < xmax {
      t_cone = tA;
    } else if
      tB > 0.0 && (ro.x + tB * rd.x) > xmin && (ro.x + tB * rd.x) < xmax
    {
      t_cone = tB;
    }
  }

  // Base of cone
  var t_disk = -1.0;
  if abs(rd.x) > 0.0001 {
    let tc = (xmin - ro.x) / rd.x;
    if tc > 0.0 {
      let y = ro.y + tc * rd.y;
      let z = ro.z + tc * rd.z;
      if (y * y + z * z) <= R2 * R2 {
        t_disk = tc;
      }
    }
  }

  var t_hit = -1.0;
  if t_cyl > 0.0 {
    t_hit = t_cyl;
  }
  if t_cone > 0.0 && (t_hit < 0.0 || t_cone < t_hit) {
    t_hit = t_cone;
  }
  if t_disk > 0.0 && (t_hit < 0.0 || t_disk < t_hit) {
    t_hit = t_disk;
  }

  if t_hit < 0.0 {
    return vec4<f32>(0.0, 0.0, 0.0, -1.0); // Discard signal
  }

  // Compute normal
  var n_local = vec3<f32>(0.0);
  let hit_x = ro.x + t_hit * rd.x;
  let hit_y = ro.y + t_hit * rd.y;
  let hit_z = ro.z + t_hit * rd.z;
  if t_hit == t_cone {
    n_local =
      normalize(
        vec3<f32>(k * sqrt(hit_y * hit_y + hit_z * hit_z), hit_y, hit_z),
      );
  } else if t_hit == t_disk {
    n_local = vec3<f32>(-1.0, 0.0, 0.0);
  } else {
    n_local = normalize(vec3<f32>(0.0, hit_y, hit_z));
  }

  if axis_idx > 0.5 && axis_idx < 1.5 {
    // Y
    n_local = vec3<f32>(n_local.y, n_local.x, n_local.z);
  } else if axis_idx > 1.5 {
    // Z
    n_local = vec3<f32>(n_local.y, n_local.z, n_local.x);
  }

  let world_n = normalize((obj_rotate * vec4<f32>(n_local, 0.0)).xyz);
  let light_dir = normalize(vec3<f32>(0.5, 1.0, -0.3));
  let diffuse = max(dot(world_n, light_dir), 0.0) * 0.6 + 0.4;
  let shaded_color = vertex_color * diffuse;

  if !xray_active {
    let ray_m = 1.0 / rd_local;
    let ray_n = ray_m * ro_local;
    let ray_k = abs(ray_m) * obj_scale;
    let t1 = -ray_n - ray_k;
    let t2 = -ray_n + ray_k;
    let tN = max(max(t1.x, t1.y), t1.z);
    let tF = min(min(t2.x, t2.y), t2.z);
    if tN < tF && tN > 0.0 && tN < t_hit {
      return vec4<f32>(0.0, 0.0, 0.0, -1.0); // Discard signal
    }
  }

  return vec4<f32>(clamp(shaded_color, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0);
}

/// Floor grid rendering (Authentic Blender Viewport Style)
/// Returns color with alpha. If alpha < 0.1, the caller should discard.
fn render_floor_grid(world_pos: vec3<f32>, camera_pos: vec3<f32>) -> vec4<f32> {
  let coord = world_pos.xz;
  let dw = fwidth(coord);
  // Base line weights
  let grid = abs(fract(coord + 0.5) - 0.5) / dw;
  let line_w = min(grid.x, grid.y);
  let axis_w_x = abs(coord.y) / dw.y;
  let axis_w_z = abs(coord.x) / dw.x;

  let alpha_grid = max(0.0, 1.0 - line_w);
  let alpha_axis_x = max(0.0, 1.0 - axis_w_x / 1.5);
  let alpha_axis_z = max(0.0, 1.0 - axis_w_z / 1.5);

  let max_alpha = max(max(alpha_grid, alpha_axis_x), alpha_axis_z);
  if max_alpha < 0.1 {
    return vec4<f32>(0.0, 0.0, 0.0, -1.0); // Discard signal
  }

  var color = vec3<f32>(0.2); // grid color
  if alpha_axis_x > alpha_axis_z && alpha_axis_x > alpha_grid {
    color = vec3<f32>(0.7, 0.15, 0.25);
  } else if alpha_axis_z > alpha_grid {
    color = vec3<f32>(0.15, 0.7, 0.15);
  }

  // Smoothly fade out based on true distance to camera
  let view_dist = length(world_pos - camera_pos);
  let fade = smoothstep(12.0, 48.0, view_dist);
  color = mix(color, vec3<f32>(0.0), fade);

  // Only discard at the absolute edge effectively transitioning into black skybox
  if fade > 0.99 {
    return vec4<f32>(0.0, 0.0, 0.0, -1.0); // Discard signal
  }

  return vec4<f32>(color, 1.0);
}

/// Helper struct for the vertex shader axis volume.
struct AxisVolumeOut {
  pos: vec3<f32>,
  color: vec3<f32>,
  axis_idx: f32,
}

/// Computes the vertex position and color for the axis bounding volume in the vertex shader.
fn get_axis_volume(
  local_id: u32,
  obj_rotate: mat4x4<f32>,
  obj_center: vec3<f32>,
) -> AxisVolumeOut {
  let axis_idx = local_id / 36u;
  let cube_id = local_id % 36u;
  let proc_pos = get_axis_vertex(cube_id);

  var axis_pos = vec3<f32>(0.0);
  var vertex_color = vec3<f32>(0.0);
  let fat_radius = 2.0;

  if axis_idx == 0u {
    axis_pos =
      vec3<f32>(proc_pos.x, proc_pos.y * fat_radius, proc_pos.z * fat_radius);
    vertex_color = vec3<f32>(1.0, 0.15, 0.25);
  } else if axis_idx == 1u {
    axis_pos =
      vec3<f32>(proc_pos.y * fat_radius, proc_pos.x, proc_pos.z * fat_radius);
    vertex_color = vec3<f32>(0.1, 0.45, 1.0);
  } else {
    axis_pos =
      vec3<f32>(proc_pos.y * fat_radius, proc_pos.z * fat_radius, proc_pos.x);
    vertex_color = vec3<f32>(0.15, 0.85, 0.15);
  }

  let pos = (obj_rotate * vec4<f32>(axis_pos, 1.0)).xyz + obj_center;

  var out: AxisVolumeOut;
  out.pos = pos;
  out.color = vertex_color;
  out.axis_idx = f32(axis_idx);
  return out;
}

/// Helper struct for the vertex shader floor quad.
struct FloorVolumeOut {
  pos: vec3<f32>,
  normal: vec3<f32>,
  color: vec3<f32>,
}

/// Computes the standard viewport floor grid vertex position.
fn get_floor_volume(quad_id: u32) -> FloorVolumeOut {
  let floor_size = 50.0;
  // quad triangles
  let uvs =
    array<vec2<f32>, 6>(
      vec2<f32>(-1.0, -1.0),
      vec2<f32>(1.0, -1.0),
      vec2<f32>(-1.0, 1.0),
      vec2<f32>(-1.0, 1.0),
      vec2<f32>(1.0, -1.0),
      vec2<f32>(1.0, 1.0),
    );
  let uv = uvs[quad_id];
  var out: FloorVolumeOut;
  out.pos = vec3<f32>(uv.x * floor_size, 0.0, uv.y * floor_size);
  out.normal = vec3<f32>(0.0, 1.0, 0.0);
  out.color = vec3<f32>(0.1, 0.1, 0.1);
  return out;
}
