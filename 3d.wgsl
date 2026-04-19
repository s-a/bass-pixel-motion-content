// ------------------------------------------------------------------
// 3D Cube — EVE Visor Eyes Edition
// Loads a cube via #obj, rotates it, bobs up/down to music.
// Glowing EVE-style visor eyes teleport to the camera-facing side
// and express musical emotions (angry, happy, surprised, dreamy).
// ------------------------------------------------------------------

#import <engine::bpm_kernel_bindings>
#import <bpm/3d/transform.wgsl>
#import <bpm/3d/lighting.wgsl>
#obj "assets/obj/cube.obj" CUBE_ CENTER_PIVOT=true NORMALIZE_SIZE=true CALC_NORMALS=flat

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) world_normal: vec3<f32>,
    @location(1) cull_flag: f32,
    @location(2) local_pos: vec3<f32>,
}

// ---- audio helpers ----

fn audio_kick_peak() -> f32 {
    let _a = #audio "audio.stem.kicks.peak";
    return _a.value;
}

fn audio_sway_phase() -> f32 {
    let _a = #audio "audio.rhythm.kick_phase";
    return _a.clamped_safe;
}

fn audio_bass() -> f32 {
    let _a = #audio "audio.band.low";
    return _a.clamped_safe;
}

fn audio_energy() -> f32 {
    let _a = #audio "audio.rms";
    return _a.clamped_safe;
}

fn audio_brightness() -> f32 {
    let _a = #audio "audio.perceptual.brightness";
    return _a.clamped_safe;
}

fn audio_impact() -> f32 {
    let _a = #audio "audio.rhythm.impact_hit";
    return _a.value;
}

// ---- param helpers ----

fn cube_color() -> BpmColor {
    let c = #color "scene.cube_color";
    return c;
}

fn cube_size() -> f32 {
    return #gui_param "scene.cube_size".x;
}

fn eye_color_val() -> BpmColor {
    let c = #color "scene.eye_color";
    return c;
}

fn eye_glow_param() -> f32 {
    return #gui_param "scene.eye_glow".x;
}

fn eye_glow_color() -> BpmColor {
    let c = #color "scene.eye_glow_color";
    return c;
}

// ---- EVE eye SDF helpers ----

/// EVE eye SDF with emotional deformation.
/// side: 1.0 for left eye, -1.0 for right eye (controls angry brow slope direction)
fn eve_eye_sdf(
    p: vec2<f32>,
    center: vec2<f32>,
    w: f32,
    h: f32,
    tilt: f32,
    angry: f32,
    happy: f32,
    side: f32,
) -> f32 {
    var uv = p - center;

    // Apply tilt rotation (characteristic EVE inward tilt)
    let ct = cos(tilt);
    let st = sin(tilt);
    uv = vec2<f32>(uv.x * ct - uv.y * st, uv.x * st + uv.y * ct);

    // Base rounded rectangle SDF (very rounded corners ≈ capsule)
    let half = vec2<f32>(w * 0.5, h * 0.5);
    let cr = min(half.x, half.y) * 0.98; // nearly full capsule shape
    let rd = abs(uv) - half + cr;
    var d = length(max(rd, vec2<f32>(0.0))) + min(max(rd.x, rd.y), 0.0) - cr;

    // Angry: brow furrow — clip top edge, angled lower on inner side (∨ shape)
    if angry > 0.001 {
        let clip_y = half.y * (1.0 - angry * 0.4);
        let slope = angry * side * 2.2;
        d = max(d, uv.y - (clip_y - slope * uv.x));
    }

    // Happy: smile — clip bottom with upward parabolic curve (◠ shape)
    if happy > 0.001 {
        let lift_max = half.y * 0.8;
        let hw = max(half.x, 0.001);
        let k = lift_max / (hw * hw);
        let lift = max(lift_max - k * uv.x * uv.x, 0.0);
        d = max(d, -(uv.y - (-half.y + happy * lift)));
    }

    return d;
}

/// Natural blink with slightly irregular timing (two overlapping cycles)
fn blink_factor(t: f32) -> f32 {
    // Primary blink: ~5.5s cycle with sine-jittered timing
    let p1 = fract(t * 0.18 + sin(t * 0.07) * 0.12);
    let c1 = smoothstep(0.0, 0.015, p1);
    let o1 = smoothstep(0.025, 0.048, p1);
    let b1 = clamp(1.0 - c1 + o1, 0.0, 1.0);

    // Secondary blink: ~12.5s cycle (occasional extra blink)
    let p2 = fract(t * 0.08 + 0.37);
    let c2 = smoothstep(0.0, 0.013, p2);
    let o2 = smoothstep(0.02, 0.042, p2);
    let b2 = clamp(1.0 - c2 + o2, 0.0, 1.0);

    return min(b1, b2);
}

/// Determine which cube face faces the camera most (returns 0-5)
/// 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z
fn camera_facing_face(xf: mat4x4<f32>) -> u32 {
    // The column with the largest |z| determines the dominant axis.
    // The sign determines which face of that axis faces the camera.
    // Camera looks in +Z; a face normal with most negative Z faces the camera.
    let az = abs(xf[0].z);
    let bz = abs(xf[1].z);
    let cz = abs(xf[2].z);

    if az >= bz && az >= cz {
        if xf[0].z < 0.0 { return 0u; } else { return 1u; }
    } else if bz >= az && bz >= cz {
        if xf[1].z < 0.0 { return 2u; } else { return 3u; }
    } else {
        if xf[2].z < 0.0 { return 4u; } else { return 5u; }
    }
}

// get_face_id is inlined at the call site in fs_main to reduce function count

// ---- vertex shader ----

@vertex
fn vs_main(@builtin(vertex_index) id: u32) -> VertexOut {
    var out: VertexOut;

    // Background quad (first 6 vertices)
    if id < 6u {
        var positions = array<vec2<f32>, 6>(
            vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(-1.0, 1.0),
            vec2<f32>(-1.0, 1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0)
        );
        out.clip_position = vec4<f32>(positions[id], 0.0, 1.0);
        out.world_normal = vec3<f32>(0.0, 0.0, 1.0);
        out.cull_flag = 2.0;
        out.local_pos = vec3<f32>(0.0);
        return out;
    }

    let tri_id = (id - 6u) / 3u;
    if tri_id >= CUBE_TRIANGLE_COUNT {
        out.clip_position = vec4<f32>(0.0, 0.0, 0.0, 0.0);
        out.cull_flag = 1.0;
        out.local_pos = vec3<f32>(0.0);
        return out;
    }

    let t = scene.time;

    // Build rotation with rhythmic spin impulse on kicks
    let phase = audio_sway_phase();
    let rhythmic_spin = sin(phase * 3.14159) * 0.45;
    var transform = euler_rotation_matrix(vec3<f32>(
        t * 0.3,
        t * 0.4 + rhythmic_spin,
        0.0
    ));
    let scale = cube_size();
    transform[0] *= scale;
    transform[1] *= scale;
    transform[2] *= scale;

    // Depth-sorted triangle via auto-generated sorter
    let sorted_tri = CUBE_get_sorted_triangle(tri_id, transform);
    let corner = id % 3u;
    let idx = CUBE_get_index(sorted_tri * 3u + corner);

    var pos = CUBE_VERTICES[idx];
    let normal_raw = CUBE_NORMALS[idx];

    // Store local position BEFORE rotation (for face UV in fragment shader)
    out.local_pos = pos;

    // Apply rotation & scale
    pos = (transform * vec4<f32>(pos, 1.0)).xyz;
    let world_normal = (transform * vec4<f32>(normal_raw, 0.0)).xyz;

    // Audio: bob up/down with kick peaks
    let audio = audio_kick_peak();
    pos.y += audio * 1.5 - 0.75;

    // Backface culling (camera looks in +Z from -cam_dist)
    if world_normal.z > 0.0 {
        out.cull_flag = 1.0;
    } else {
        out.cull_flag = 0.0;
    }

    // Perspective projection
    let cam_dist = 6.0;
    let z_view = max(pos.z + cam_dist, 0.1);
    let persp = 3.0 / z_view;
    let aspect = scene.resolution.x / max(scene.resolution.y, 1.0);

    out.clip_position = vec4<f32>(
        (pos.x * persp) / aspect,
        -(pos.y * persp),
        1.0 - persp * 0.5,
        1.0,
    );
    out.world_normal = world_normal;
    return out;
}

// ---- fragment shader ----

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    // Background quad
    if in.cull_flag > 1.5 {
        let bg = #color "scene.bg_color";
        return encode_output_alpha(bg.rgb, bg.a);
    }
    // Culled backfaces
    if in.cull_flag > 0.5 { discard; }

    // Base cube lighting
    let lit = lighting_3point(normalize(-in.world_normal));
    var color = cube_color();
    let c1 = #color "scene.cube_color";
    let cube_a = c1.a;

    if cube_a < 0.001 { discard; }
    color.rgb *= lit;

    // ---- EVE Eyes Rendering ----
    let t = scene.time;

    // Reconstruct rotation matrix (MUST match vs_main exactly)
    let ph = audio_sway_phase();
    let rspin = sin(ph * 3.14159) * 0.45;
    var xform = euler_rotation_matrix(vec3<f32>(t * 0.3, t * 0.4 + rspin, 0.0));
    let sc = cube_size();
    xform[0] *= sc;
    xform[1] *= sc;
    xform[2] *= sc;

    // Inverse rotation for local-space queries
    let rot3 = mat3x3<f32>(
        normalize(xform[0].xyz),
        normalize(xform[1].xyz),
        normalize(xform[2].xyz),
    );
    let inv_rot = transpose(rot3);

    // Face detection uses BASE rotation WITHOUT kick wobble = teleportation cooldown
    // The smooth rotation (0.3/0.4 rad/s) naturally spaces face changes 3-5s apart,
    // and removing the rhythmic_spin prevents rapid flipping on bass hits.
    var xform_stable = euler_rotation_matrix(vec3<f32>(t * 0.3, t * 0.4, 0.0));
    xform_stable[0] *= sc;
    xform_stable[1] *= sc;
    xform_stable[2] *= sc;
    let front_id = camera_facing_face(xform_stable);
    let local_n = inv_rot * normalize(in.world_normal);
    let aln = abs(local_n);
    var this_id = 4u;
    if aln.x >= aln.y && aln.x >= aln.z {
        if local_n.x > 0.0 { this_id = 0u; } else { this_id = 1u; }
    } else if aln.y >= aln.x && aln.y >= aln.z {
        if local_n.y > 0.0 { this_id = 2u; } else { this_id = 3u; }
    } else {
        if local_n.z > 0.0 { this_id = 4u; } else { this_id = 5u; }
    }

    // Only render eyes on the camera-facing face
    if this_id == front_id {
        // Screen-up direction in local space (for correct eye orientation)
        let su = inv_rot * vec3<f32>(0.0, -1.0, 0.0);

        // Face-local UV: pick two axes from geometry, then orient to screen-up
        var raw_h: f32; // raw "horizontal" component
        var raw_v: f32; // raw "vertical" component
        var su_h: f32;  // screen-up along horizontal axis
        var su_v: f32;  // screen-up along vertical axis
        if aln.x >= aln.y && aln.x >= aln.z {
            raw_h = in.local_pos.z; raw_v = in.local_pos.y;
            su_h = su.z; su_v = su.y;
        } else if aln.y >= aln.z {
            raw_h = in.local_pos.x; raw_v = in.local_pos.z;
            su_h = su.x; su_v = su.z;
        } else {
            raw_h = in.local_pos.x; raw_v = in.local_pos.y;
            su_h = su.x; su_v = su.y;
        }

        // Orient: pick the axis closest to screen-up as face_uv.y
        var face_uv: vec2<f32>;
        if abs(su_v) >= abs(su_h) {
            // Vertical axis is screen-up → keep, just fix sign
            face_uv = vec2<f32>(raw_h, raw_v * sign(su_v));
        } else {
            // Horizontal axis is screen-up → swap axes
            face_uv = vec2<f32>(raw_v, raw_h * sign(su_h));
        }

        // === EVE VISOR DISPLAY OVERLAY ===
        let scan_freq = 22.0;
        let scanline_h = 0.56 + 0.44 * sin(face_uv.y * scan_freq * 6.283185);
        let vert_freq = 30.0;
        let scanline_v = 0.88 + 0.12 * sin(face_uv.x * vert_freq * 6.283185);
        let scanline = scanline_h * scanline_v;

        let face_w = smoothstep(0.05, -0.45, normalize(in.world_normal).z);

        // Audio signals for emotions
        let bass = audio_bass();
        let energy = audio_energy();
        let bright = audio_brightness();
        let impact = audio_impact();
        let kick = audio_kick_peak();

        // --- Emotion weights ---
        let w_angry = smoothstep(0.12, 0.45, bass) * smoothstep(0.08, 0.3, energy);
        let w_happy = smoothstep(0.12, 0.4, bright) * (1.0 - w_angry) * smoothstep(0.05, 0.25, energy);
        let w_surprise = clamp(impact * 4.0, 0.0, 1.0);
        let w_dreamy = (1.0 - smoothstep(0.02, 0.15, energy)) * (1.0 - w_angry);
        let w_excited = smoothstep(0.25, 0.55, energy);

        // --- Eye dimensions ---
        let ew = 0.314;
        let eh_base = 0.101;
        let eye_tilt = 0.08;
        let spread = 0.232;

        let blink = blink_factor(t);
        let h_mod = blink * (1.0 - w_dreamy * 0.35 + w_surprise * 0.3);
        let eh = eh_base * max(h_mod, 0.01);
        let e_scale = 1.0 + w_surprise * 0.35 + w_excited * 0.12;

        // 25% from top edge (face UV = [-0.5, +0.5], top = +0.5)
        let eye_y = 0.25;

        let lc = vec2<f32>(-spread, eye_y);
        let rc = vec2<f32>(spread, eye_y);

        // Compute both eye SDFs
        let d_l = eve_eye_sdf(
            face_uv, lc,
            ew * e_scale, eh * e_scale,
            -eye_tilt, w_angry * 0.5, w_happy * 0.6, 1.0
        );
        let d_r = eve_eye_sdf(
            face_uv, rc,
            ew * e_scale, eh * e_scale,
            eye_tilt, w_angry * 0.5, w_happy * 0.6, -1.0
        );
        let d = min(d_l, d_r);

        // --- Refined glow (subtle, not overpowering) ---
        let glow = eye_glow_param();
        let ec = eye_color_val();
        let gc = eye_glow_color();

        // Gentle breathing pulse + kick reactivity
        let breath = 1.0 + sin(t * 2.5) * 0.04;
        let pulse = breath * (1.0 + kick * 0.3 + w_excited * 0.15);

        // Inner core fill — wide feathering for soft edges
        let core_fill = smoothstep(0.015, -0.006, d);
        // Medium inner glow (eye color) — slightly softer falloff
        let inner_glow = exp(-max(d, 0.0) * 22.0) * 0.55;
        // Soft outer halo (separate glow color)
        let outer_glow = exp(-max(d, 0.0) * 9.0) * 0.18;

        // Warmth shift on excitement/anger
        let warmth = w_excited * 0.12 + w_angry * 0.08;
        let eye_rgb = mix(ec.rgb, ec.rgb * vec3<f32>(1.15, 0.92, 0.82), warmth);

        // Composite emission — core=eye_color, inner=eye_color, outer=glow_color
        let emission =
            eye_rgb * core_fill * glow * scanline +
            eye_rgb * inner_glow * glow * pulse * 0.6 * scanline +
            gc.rgb * outer_glow * glow * pulse * 0.2;

        color.rgb += emission * face_w;
    }

    let c2 = #color "scene.bg_color";
    let base_a = max(cube_a, c2.a);
    return encode_output_alpha(color.rgb, base_a);
}
