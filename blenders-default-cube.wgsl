// ------------------------------------------------------------------
// GLTF Cube — #gltf preprocessor demo
// Uses the embedded Blender camera + light for correct orientation.
// ------------------------------------------------------------------


#import <engine::bpm_kernel_bindings>
#import <bpm/3d/transform.wgsl>
#import <bpm/3d/lighting.wgsl>
#import <bpm/3d/debug.wgsl>
#gltf "assets/glb/default cube.glb" SCENE_

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) world_pos: vec3<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) cull_flag: f32,
    @location(3) color: vec3<f32>,
    @location(4) flags: f32, // 1.0 = floor, 2.0 = obj_axis
    @location(5) axis_idx: f32,
}





// ---- helpers ----

fn audio_kick_rms() -> f32 {
    let a = #audio "audio.stem.kicks.rms";
    return a.value;
}

fn audio_sway_phase() -> f32 {
    let a = #audio "audio.rhythm.kick_phase";
    return a.clamped_safe;
}

fn cube_color() -> BpmColor {
    let c = #color "scene.cube_color";
    return c;
}

fn cube_size() -> f32 {
    return #gui_param "scene.cube_size".x;
}

fn show_coordinates() -> bool {
    return #gui_param "scene.show_coordinates".x > 0.5;
}

fn xray_axes() -> bool {
    return #gui_param "scene.xray_axes".x > 0.5;
}

// ---- vertex shader ----

@vertex
fn vs_main(@builtin(vertex_index) id: u32) -> VertexOut {
    var out: VertexOut;
    out.flags = 0.0;

    let is_bg = id < 6u;
    let is_floor = id >= 6u && id < 12u;
    let cube_verts = SCENE_M0_TRIANGLE_COUNT * 3u; // 36
    let is_cube = id >= 12u && id < 12u + cube_verts;
    let is_obj_axis = id >= 12u + cube_verts && id < 12u + cube_verts * 4u;
    let is_world_axis = id >= 12u + cube_verts * 4u && id < 12u + cube_verts * 6u;

    if is_bg {
        var positions = array<vec2<f32>, 6>(
            vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(-1.0, 1.0),
            vec2<f32>(-1.0, 1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0)
        );
        out.clip_position = vec4<f32>(positions[id], 0.0, 1.0);
        out.world_normal = vec3<f32>(0.0, 0.0, 1.0);
        out.flags = 3.0; // flag for background
        out.cull_flag = 2.0;
        return out;
    }

    if !is_cube && !is_obj_axis && !is_world_axis && !is_floor {
        out.clip_position = vec4<f32>(0.0);
        out.cull_flag = 1.0;
        return out;
    }

    if (is_obj_axis || is_world_axis || is_floor) && !show_coordinates() {
        out.clip_position = vec4<f32>(0.0);
        out.cull_flag = 1.0;
        return out;
    }

    let t = scene.time;
    // At t=0 this is identity — no rotation, matching Blender's initial state
    let phase = audio_sway_phase();
    let rhythmic_spin = sin(phase * 3.14159) * 0.45;
    var obj_rotate = euler_rotation_matrix(vec3<f32>(
        t * 0.4, 
        t * 0.7 + rhythmic_spin, 
        0.0
    ));
    let scale = cube_size();

    // Audio bob offset with a baseline shift down (-0.8 world units)
    // Wir nutzen hier den rohen Wert, um mehr Dynamik zuzulassen.
    let audio = audio_kick_rms();
    let y_offset = (audio * 1.5) - 0.8;

    // ---- Camera: Use GLTF embedded camera ----
    let cam_pos = SCENE_CAMERA_0_POS;
    let cam_dir = SCENE_CAMERA_0_DIR;
    let cam_target = cam_pos + cam_dir;
    let view_mat3 = build_view_matrix(cam_pos, cam_target, vec3<f32>(0.0, 1.0, 0.0));
    
    // Create full 4x4 view matrix to use for depth sorting
    let view_mat4 = mat4x4<f32>(
        vec4<f32>(view_mat3[0], 0.0),
        vec4<f32>(view_mat3[1], 0.0),
        vec4<f32>(view_mat3[2], 0.0),
        vec4<f32>(-(view_mat3 * cam_pos), 1.0)
    );

    // glTF preprocessor bakes world transforms. Vertices are in glTF Y-up space.
    var pos: vec3<f32>;
    var normal_raw: vec3<f32>;
    var world_normal: vec3<f32>;
    var vertex_color = vec3<f32>(0.0);

    if is_cube {
        // ---- Painter's Algorithm for dynamic depth sorting ----
        let local_cube_id = id - 12u;
        var mesh_transform = obj_rotate;
        mesh_transform[0] *= scale;
        mesh_transform[1] *= scale;
        mesh_transform[2] *= scale;

        // Local to world matrix
        var local_world4 = mesh_transform;
        local_world4[3].y += y_offset;

        // Matrix for Painter's algorithm
        var sort_mat = view_mat4 * local_world4;
        // View space Z is negative forward, but get_sorted_triangle sorts descending (highest Z first).
        // By negating Z, deeper (more negative) points become more positive, making them draw first.
        sort_mat[0].z = -sort_mat[0].z;
        sort_mat[1].z = -sort_mat[1].z;
        sort_mat[2].z = -sort_mat[2].z;
        sort_mat[3].z = -sort_mat[3].z;

        let tri_id = local_cube_id / 3u;
        let sorted_tri = SCENE_M0_get_sorted_triangle(tri_id, sort_mat);
        let corner = local_cube_id % 3u;
        let idx = SCENE_M0_get_index(sorted_tri * 3u + corner);

        pos = SCENE_M0_VERTICES[idx];
        normal_raw = SCENE_M0_NORMALS[idx];

        pos = (local_world4 * vec4<f32>(pos, 1.0)).xyz;
        world_normal = (mesh_transform * vec4<f32>(normal_raw, 0.0)).xyz;
        
        vertex_color = cube_color().rgb;
    } else if is_obj_axis {
        let local_id = id - 12u - cube_verts;
        let cube_center = vec3<f32>(0.0, y_offset, 0.0);
        let vol = get_axis_volume(local_id, obj_rotate, cube_center);
        
        pos = vol.pos;
        vertex_color = vol.color;
        world_normal = (obj_rotate * vec4<f32>(normal_raw, 0.0)).xyz;
        out.flags = 2.0;
        out.axis_idx = vol.axis_idx;
    } else if is_world_axis {
        // We hide the rotated world axes to avoid clashes with the perfect grid floor
        out.cull_flag = 1.0;
        return out;
    } else if is_floor {
        let vol = get_floor_volume(id - 6u);
        pos = vol.pos;
        world_normal = vol.normal;
        vertex_color = vol.color;
        out.flags = 1.0;
    }

    // ---- Camera: Use GLTF embedded camera ----
    // (View matrix is pre-calculated above)

    // Transform to view space
    let view_pos = view_mat3 * (pos - cam_pos);
    let view_normal = view_mat3 * world_normal;

    // Backface culling: in view space (looking down -Z), faces pointing toward the camera have +Z normals.
    if view_normal.z < 0.0 && !is_floor && !is_obj_axis {
        out.cull_flag = 1.0;
    } else {
        out.cull_flag = 0.0;
    }

    // Perspective projection using extracted FOV
    let aspect = scene.resolution.x / max(scene.resolution.y, 1.0);
    out.clip_position = project_perspective(view_pos, SCENE_CAMERA_0_FOV, aspect, 0.1, 200.0);
    out.world_pos = pos;
    out.world_normal = world_normal;
    out.color = vertex_color;
    return out;
}
// ... (rest of vs_main)

// ---- fragment shader ----

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    if in.cull_flag > 0.5 && in.cull_flag < 1.5 {
        discard; // Cull backfaces but NOT the background quad (cull_flag 2.0)
    }

    if in.flags > 2.5 {
        let bg = #color "scene.bg_color";
        return encode_output_alpha(bg.rgb, bg.a);
    }

    if in.flags > 1.5 {
        let t = scene.time;
        let audio = audio_kick_rms();
        let y_offset = (audio * 1.5) - 0.8;
        let phase = audio_sway_phase();
        let rhythmic_spin = sin(phase * 3.14159) * 0.45;
        let obj_rotate = euler_rotation_matrix(vec3<f32>(t * 0.4, t * 0.7 + rhythmic_spin, 0.0));
        let cube_center = vec3<f32>(0.0, y_offset, 0.0);
        
        let axis_res = raycast_axis(
            in.axis_idx,
            in.world_pos,
            in.color,
            SCENE_CAMERA_0_POS,
            cube_center,
            obj_rotate,
            cube_size(),
            xray_axes()
        );
        if axis_res.a < 0.0 { discard; }
        return vec4<f32>(axis_res.rgb, 1.0);
    } else if in.flags > 0.5 {
        let grid_res = render_floor_grid(in.world_pos, SCENE_CAMERA_0_POS);
        if grid_res.a < 0.0 { discard; }
        return vec4<f32>(grid_res.rgb, 1.0);
    }

    let n = normalize(in.world_normal);

    var final_color_bpm = cube_color();
    let c1 = #color "scene.cube_color";
    let cube_a = c1.a;
    
    // Discard fully transparent objects to prevent them from erasing background alpha
    if cube_a < 0.001 {
        discard;
    }

    if SCENE_LIGHT_COUNT > 0u {
        final_color_bpm.rgb = apply_gltf_point_light(
            in.world_pos, n, in.color, 
            SCENE_LIGHT_0_POS, SCENE_LIGHT_0_INTENSITY, SCENE_LIGHT_0_COLOR
        );
    } else {
        final_color_bpm.rgb = apply_fallback_light(n, in.color);
    }

    let c2 = #color "scene.bg_color";
    let base_a = max(cube_a, c2.a);
    return encode_output_alpha(final_color_bpm.rgb, base_a);
}

