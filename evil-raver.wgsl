
#import <engine::bpm_kernel_bindings>
#import <bpm/sprite_utils.wgsl>

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}




@group(1) @binding(0) var eyes_tex: texture_2d<f32>;
@group(1) @binding(1) var eyes_sam: sampler;
@group(1) @binding(2) var mouth_tex: texture_2d<f32>;
@group(1) @binding(3) var mouth_sam: sampler;

const PI: f32 = 3.14159265;
const TAU: f32 = 6.28318530;

fn hash11(p: f32) -> f32 { return fract(sin(p * 12.9898) * 43758.5453); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453); }

fn rotX(a: f32) -> mat3x3<f32> { let s = sin(a); let c = cos(a); return mat3x3<f32>(1.,0.,0., 0.,c,-s, 0.,s,c); }
fn rotY(a: f32) -> mat3x3<f32> { let s = sin(a); let c = cos(a); return mat3x3<f32>(c,0.,s, 0.,1.,0., -s,0.,c); }
fn rotZ(a: f32) -> mat3x3<f32> { let s = sin(a); let c = cos(a); return mat3x3<f32>(c,-s,0., s,c,0., 0.,0.,1.); }
fn smin(a: f32, b: f32, k: f32) -> f32 { let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
fn sdf_sphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }

fn hue_shift(color: vec3<f32>, a: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735); let ca = cos(a);
    return color * ca + cross(k, color) * sin(a) + k * dot(k, color) * (1.0 - ca);
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOut {
    var p = array<vec2<f32>, 3>(vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));
    var out: VertexOut;
    out.clip_position = vec4<f32>(p[vi], 0.0, 1.0);
    out.uv = p[vi] * 0.5 + 0.5;
    return out;
}

// ═══════════════════════════════════════════════════════════════════════
// TUNNEL PATH – Organic winding 3-octave centerline
// ═══════════════════════════════════════════════════════════════════════

fn tunnel_path(z: f32) -> vec2<f32> {
    return vec2<f32>(
        sin(z * 0.08) * 3.0 + cos(z * 0.035) * 2.0 + sin(z * 0.15) * 1.0,
        cos(z * 0.06) * 2.5 + sin(z * 0.04) * 1.8 + cos(z * 0.12) * 0.8
    );
}

// ═══════════════════════════════════════════════════════════════════════
// FLIGHT Z – Monotonic asymmetric S-curve position
// ═══════════════════════════════════════════════════════════════════════

fn get_flight_z() -> f32 {
    let progress = clamp(scene.timeline.z, 0.0, 1.0);
    let speed_mult = max(#gui_param "scene.tunnel_speed_mult".x, 0.1);

    if (progress < 0.001) {
        return scene.time * 13.2 * speed_mult;
    }

    // Asymmetric S-curve: fast ramp (~20%), slow decel (~50%)
    // pow(p,0.7) skews so acceleration is compressed into early progress
    let sp = pow(progress, 0.7);
    let eased = sp * sp * (3.0 - 2.0 * sp);
    let duration = scene.time / max(progress, 0.001);
    return eased * duration * 148.5 * speed_mult;
}

fn get_tunnel_radius_at(z: f32) -> f32 {
    let progress = clamp(scene.timeline.z, 0.0, 1.0);
    let base_radius = mix(8.0, 12.0, smoothstep(0.0, 0.6, progress));
    let width_var = sin(z * 0.07) * 1.2 + cos(z * 0.13) * 0.6 + sin(z * 0.21) * 0.3;
    let breathing = 0.4 * sin(scene.time * 0.25) + 0.2 * cos(scene.time * 0.17);
    return max(base_radius + width_var + breathing, 8.0);
}

// ═══════════════════════════════════════════════════════════════════════
// CAMERA & HEAD – Physical flight through winding tunnel
// ═══════════════════════════════════════════════════════════════════════

fn get_cam_pos(t: f32) -> vec3<f32> {
    let cam_z = get_flight_z();
    let path = tunnel_path(cam_z);
    let turb_x = sin(t * 0.8) * 0.5 + sin(t * 1.7) * 0.2 + cos(t * 2.3) * 0.1;
    let turb_y = cos(t * 0.6) * 0.4 + sin(t * 1.3) * 0.2 + cos(t * 2.7) * 0.1;
    return vec3<f32>(path.x + turb_x, path.y + turb_y, cam_z);
}

fn get_head_center(t: f32) -> vec3<f32> {
    let cam_z = get_flight_z();

    // Organic Z-curve (irrational frequencies = never repeats)
    let z_curve = sin(t * 0.37) * cos(t * 0.61) - 0.5 * sin(t * 1.13) + 0.3 * cos(t * 1.91);
    var rel_z = z_curve * 2.0;

    // Asymmetric forward/backward behavior
    if (rel_z > 0.0) {
        // RARE dramatic close-up lunge (skull rushes at camera!)
        let lunge1 = pow(max(sin(t * 0.17 + 2.0), 0.0), 20.0);
        let lunge2 = pow(max(cos(t * 0.11 + 0.7), 0.0), 24.0);
        let lunge = max(lunge1, lunge2);
        // Normal: forward_scale ~0.3, Lunge: forward_scale up to 3.5 (closes to ~1.5 units!)
        let forward_scale = 0.3 + lunge * 3.2;
        rel_z *= forward_scale;
    } else {
        // Sometimes drops deep behind; rare extreme retreats
        let rare_spike = pow(max(sin(t * 0.13), 0.0), 16.0);
        let deep_random = 1.0 + 0.4 * (sin(t * 0.23) * cos(t * 0.51)) + rare_spike * 3.0;
        rel_z *= (1.55 * deep_random);
    }

    // Head behind camera with organic distance variation
    let head_z = cam_z - 6.0 + rel_z;

    // ── ORIGINAL's organic Y drift ──
    let y_curve = cos(t * 0.43) + 0.5 * sin(t * 0.89);
    let head_y_drift = y_curve * 0.35;

    let path = tunnel_path(head_z);
    let tun_r = get_tunnel_radius_at(head_z);

    // Clamp drift so head + horns never touch walls (horns extend ~5 units)
    let max_offset = max(tun_r - 6.0, 0.0);
    var drift = vec2<f32>(sin(t * 0.31) * 0.8, head_y_drift);
    let drift_len = length(drift);
    drift = drift * min(1.0, max_offset / max(drift_len, 0.001));

    return vec3<f32>(path.x + drift.x, path.y + drift.y, head_z);
}

// ── ORIGINAL's head yaw (verbatim) ──
fn get_head_rot_y(t: f32) -> f32 {
    let sway_base = sin(t * 0.3) + 0.4 * sin(t * 0.7);
    let sway_micro = 0.1 * sin(t * 1.1) * cos(t * 0.9);
    return (sway_base + sway_micro) * 0.15;
}

// ── HEADBANG NOD ──
// Uses isolated stem kick_phase for perfect, noise-free zero-crossing kick-sync.
// Phase ramps 0.0 (kick transient) to 1.0 (next kick). We map this to a smooth recovery curve.
fn get_nod_angle(t: f32) -> f32 {
    let _a0 = #audio "audio.stem.kicks.rhythm.kick_phase";
    let phase = clamp(_a0.value, 0.0, 1.0);
    
    // Smooth cosine decay: 1.0 at transient, smooth S-curve recovery to 0.0.
    // Multiplying phase by a small factor keeps the head down slightly longer for heavy kicks.
    let clean = min(phase * 1.2, 1.0); 
    let nod_weight = (1.0 + cos(clean * PI)) * 0.5;
    
    // Apply heavy amplitude (1.4 rad = ~80 degrees max)
    let nod = nod_weight * 1.4; 

    let float_nod = sin(t * 0.45) * 0.05;
    return nod + float_nod - 0.1;
}

// ═══════════════════════════════════════════════════════════════════════
// HEAD TRANSFORM – Look-at camera + nod + yaw + roll
// ═══════════════════════════════════════════════════════════════════════

fn get_head_transform(p: vec3<f32>, t: f32, nod: f32) -> vec3<f32> {
    let center = get_head_center(t);
    let cam_pos = get_cam_pos(t);

    // Look-at: head faces the camera
    let hw = normalize(center - cam_pos);
    let hu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), hw));
    let hv = cross(hw, hu);

    let offset_p = p - center;
    let aligned_p = vec3<f32>(dot(offset_p, hu), dot(offset_p, hv), dot(offset_p, hw));

    // G-force lean from tunnel curvature
    let cam_z = get_flight_z();
    let path_here = tunnel_path(cam_z);
    let path_ahead = tunnel_path(cam_z + 5.0);
    let curve_x = path_ahead.x - path_here.x;
    let skull_intensity = #gui_param "scene.skull_intensity".x;
    let roll_angle = curve_x * 0.06 * skull_intensity;

    let head_rot_y = get_head_rot_y(t);

    // Apply: roll → yaw → nod (pitch)
    return rotZ(roll_angle) * rotY(head_rot_y) * rotX(-nod) * aligned_p;
}

// ═══════════════════════════════════════════════════════════════════════
// SDF – Horns (remaster version – cleaner)
// ═══════════════════════════════════════════════════════════════════════

fn sdf_horns(p: vec3<f32>) -> f32 {
    // Bilateral symmetry
    var q = vec3<f32>(abs(p.x), p.y, p.z);
    
    // Skull connection point
    q = q - vec3<f32>(1.25, 0.5, -0.3);
    
    // Angle horns outwards and back organically
    q = rotX(-0.35) * q;
    q = rotZ(0.12) * q;
    
    // Smooth forward curve: bends the entire spiraling spine "nach vorn" towards the tip
    // We warp the z-axis (forward/back) gently based on its outward growth (q.x)
    let forward_bend = 0.15 * q.x * q.x; 
    q.z += forward_bend; // '+' brings it forward/backward organically
    
    // ── THE EXACT POLAR SPIRAL (TIGHTENING AT TIP) ──
    let pitch = 0.3; // Distance between coils along X
    let ap = atan2(q.z, q.y);
    let k = round((q.x / pitch - ap) / TAU);
    let angle = ap + k * TAU;
    let r = length(q.yz);
    let horn_l = angle; 
    
    let h_horn = max(#gui_param "scene.horn_length_ui".x, 0.5); 
    let max_angle = h_horn * 6.0; 
    let nl = clamp(horn_l / max_angle, 0.0, 1.0);
    
    // The magical tightening: The spiral starts wide (1.1) and wraps tighter and tighter
    // into the center (down to 0.05) as it reaches the tip.
    let loop_radius = mix(1.1, 0.05, pow(nl, 0.7));
    
    // Exact mathematical tube (no raymarching artifacts)
    let axis_dist = length(vec2<f32>(q.x - angle * pitch, r - loop_radius));
    
    // Natural bone tapering
    let r_base = 0.3 + clamp(h_horn * 0.05, 0.0, 0.4);
    let thickness = r_base * (1.0 - pow(nl, 1.4));
    
    // Organic, realistic goat/ram ridges
    let f1 = 15.0 + h_horn * 3.0; 
    let ridge_wave = smoothstep(-0.2, 0.8, sin(horn_l * f1));
    let ridge_env = 1.0 - pow(nl, 0.5);
    let ridges = 0.07 * ridge_wave * ridge_env;
    
    let d = axis_dist - (thickness + ridges);
    let d_ends = max(-(horn_l + 0.8), horn_l - max_angle);
    
    return max(d, d_ends) * 0.9;
}

// ═══════════════════════════════════════════════════════════════════════
// SCENE MAP – Smooth winding tunnel + head
// ═══════════════════════════════════════════════════════════════════════

fn map(p: vec3<f32>, nod: f32) -> vec2<f32> {
    // Tunnel: subtract winding centerline, smooth walls
    let path = tunnel_path(p.z);
    var tun_p = vec2<f32>(p.x - path.x, p.y - path.y);
    let shape = length(tun_p);
    let tun_r = get_tunnel_radius_at(p.z);
    let d_tunnel = tun_r - shape;

    // Head
    let head_p = get_head_transform(p, scene.time, nod);
    let d_sphere = sdf_sphere(head_p, 1.8);
    let d_horns = sdf_horns(head_p);
    let d_head = smin(d_sphere, d_horns, 0.4);

    if (d_head < d_tunnel) { return vec2<f32>(d_head, 1.0); }
    return vec2<f32>(d_tunnel, 2.0);
}

fn get_normal(p: vec3<f32>, nod: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, nod).x;
    return normalize(vec3<f32>(
        map(p + e.xyy, nod).x - d,
        map(p + e.yxy, nod).x - d,
        map(p + e.yyx, nod).x - d
    ));
}

// ═══════════════════════════════════════════════════════════════════════
// FRAGMENT SHADER
// ═══════════════════════════════════════════════════════════════════════

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let uv = in.uv;
    let aspect = scene.resolution.x / max(scene.resolution.y, 1.0);
    let p = vec2<f32>((uv.x * 2.0 - 1.0) * aspect, uv.y * 2.0 - 1.0);

    let _a_rms = #audio "audio.rms";
    let rms = _a_rms.value;
    let _a_beat = #audio "audio.rhythm.beat";
    let beat = _a_beat.value;
    let _a_kick = #audio "audio.rhythm.kick_count";
    let kick_counter = _a_kick.value;
    let progress = clamp(scene.timeline.z, 0.0, 1.0);

    // ── Headbang nod (impact_hit is the driver!) ──
    let nod_angle = get_nod_angle(scene.time);

    // Camera flies backward through winding tunnel, looking back at skull
    let ro = get_cam_pos(scene.time);
    let head_pos = get_head_center(scene.time);
    let cw = normalize(head_pos - ro);

    // Banking: camera leans into tunnel curves
    let cam_z = get_flight_z();
    let path_here = tunnel_path(cam_z);
    let path_ahead = tunnel_path(cam_z + 5.0);
    let bank_angle = (path_ahead.x - path_here.x) * 0.05 * #gui_param "scene.tunnel_speed_mult".x;
    let up_vec = vec3<f32>(-sin(bank_angle), cos(bank_angle), 0.0);
    let cu = normalize(cross(cw, up_vec));
    let cv = cross(cu, cw);
    var rd = normalize(mat3x3<f32>(cu, cv, cw) * vec3<f32>(p.x, p.y, 1.3));

    // Raymarch
    var t = 0.0; var d = 0.0; var m = 0.0;
    for (var i = 0u; i < 72u; i = i + 1u) {
        let res = map(ro + rd * t, nod_angle);
        d = res.x; m = res.y;
        if (d < 0.01) { break; }
        t += d * 0.35;
        if (t > 35.0) { break; }
    }

    let c1 = #color "scene.bg_color";
    let bg_col = c1.rgb;
    let c2 = #color "scene.evil_raver_color";
    let raver_col = c2.rgb;
    let c3 = #color "scene.glow_color";
    let glow_col = c3.rgb;
    var color = bg_col;

    if (t <= 35.0) {
        let hit_pos = ro + rd * t;
        let n = get_normal(hit_pos, nod_angle);

        if (m == 1.0) {
            // ── HEAD MATERIAL (remaster: better fresnel, gradient, glow) ──
            let head_p = get_head_transform(hit_pos, scene.time, nod_angle);
            let nl = normalize(head_p);
            var base_col = raver_col;

            // Horn color gradient requested by user: Discolored Root -> White Middle -> Black Tip
            let dist_c = length(head_p);
            
            let root_col = vec3<f32>(0.35, 0.25, 0.15); // Discolored (brownish/dirty) root
            let mid_col = vec3<f32>(0.95, 0.95, 0.92);  // Bright white middle
            let tip_col = vec3<f32>(0.02, 0.02, 0.02);  // Pitch black tip
            
            // Progression along the horn (from base at ~1.7 to tip at ~6.0)
            let h_prog = smoothstep(1.7, 6.0, dist_c);
            
            // Blend from root to white middle over the first half
            let horn_stage1 = mix(root_col, mid_col, smoothstep(0.0, 0.45, h_prog));
            // Blend from white middle to black tip over the second half
            let horn_gradient = mix(horn_stage1, tip_col, smoothstep(0.4, 1.0, h_prog));
            
            // Only apply to the horns, cleanly fading from the base skull color
            base_col = mix(base_col, horn_gradient, smoothstep(1.6, 2.2, dist_c));

            // Spherical UV for sprite-sheet mapping
            let su = atan2(nl.x, -nl.z) / TAU + 0.5;
            let sv = -asin(nl.y) / PI + 0.5;
            let buv = vec2<f32>(su, sv);

            var eye_col = vec4<f32>(0.0);
            var mouth_col = vec4<f32>(0.0);

            let eye_uv = (buv - vec2<f32>(0.5, 0.40)) * 5.5 + 0.5;
            if (eye_uv.x >= 0.0 && eye_uv.x <= 1.0 && eye_uv.y >= 0.0 && eye_uv.y <= 1.0) {
                let et = floor(scene.time * 0.4 + sin(scene.time * 0.65) * 1.5);
                let re = floor(hash11(et + 12.3) * 8.0);
                let eye_rect = get_sprite_frame_rect(u32(re), 1u, 8u, 8u);
                let safe_eye_uv = get_sprite_safe_uv(eyes_tex, eye_rect, eye_uv);
                eye_col = textureSample(eyes_tex, eyes_sam, safe_eye_uv);
            }

            let mouth_uv = (buv - vec2<f32>(0.5, 0.60)) * 5.5 + 0.5;
            if (mouth_uv.x >= 0.0 && mouth_uv.x <= 1.0 && mouth_uv.y >= 0.0 && mouth_uv.y <= 1.0) {
                let mt = floor(scene.time * 0.25 + cos(scene.time * 0.45) * 2.0);
                let rm = floor(hash11(mt + 45.6) * 8.0);
                let mouth_rect = get_sprite_frame_rect(u32(rm), 1u, 8u, 8u);
                let safe_mouth_uv = get_sprite_safe_uv(mouth_tex, mouth_rect, mouth_uv);
                mouth_col = textureSample(mouth_tex, mouth_sam, safe_mouth_uv);
            }

            // Soft cel shading
            let diff = max(dot(nl, normalize(vec3<f32>(1.0, 1.0, -1.0))), 0.0);
            let toon = smoothstep(0.15, 0.30, diff) * 0.3 + smoothstep(0.50, 0.70, diff) * 0.7;
            var sc = base_col;

            if (mouth_col.a > 0.01) {
                let sa = smoothstep(0.1, 0.6, mouth_col.a);
                sc = mix(sc, mouth_col.rgb, sa);
            }

            var eye_glow = 0.0;
            if (eye_col.a > 0.01) {
                let sa = smoothstep(0.1, 0.6, eye_col.a);
                sc = mix(sc, eye_col.rgb, sa);
                let ep = smoothstep(0.5, 1.0, eye_col.a);
                let iw = smoothstep(0.8, 1.0, eye_col.r) * smoothstep(0.8, 1.0, eye_col.g) * smoothstep(0.8, 1.0, eye_col.b);
                eye_glow = iw * ep * (1.2 + beat * 2.0) * sa;
            }

            color = sc * (toon + 0.2);

            // Fresnel rim light — hue follows tunnel walls
            let fresnel = pow(1.0 - max(dot(n, normalize(ro - hit_pos)), 0.0), 3.0);
            let rim_col = hue_shift(glow_col, hit_pos.z * 0.02);
            color += rim_col * fresnel * (0.4 + rms * 0.6) * 0.5;

            // Emissive eye glow
            if (eye_glow > 0.0) { color += vec3<f32>(1.0) * eye_glow; }

            color *= exp(-t * 0.05);

        } else if (m == 2.0) {
            // ── TUNNEL MATERIAL ──
            // Rings at fixed Z positions; camera flight IS the scrolling
            let ring_z = hit_pos.z * 0.5;
            let rings_thick = smoothstep(0.5, 1.0, fract(ring_z)) * 0.8;
            let rings_thin = smoothstep(0.9, 1.0, fract(ring_z * 3.0)) * 0.4;

            // Angle for energy patches
            let path = tunnel_path(hit_pos.z);
            let lx = hit_pos.x - path.x;
            let ly = hit_pos.y - path.y;
            let angle = atan2(ly, lx);

            // Audio-reactive energy patches
            let noise_patch = smoothstep(0.6, 1.0, hash11(floor(ring_z * 2.0) + floor(angle * 4.0)));
            let energy = noise_patch * rms;

            // Progress motif: energy veins completing over song
            let vein_grid = fract((angle / TAU + 0.5) * 6.0 + hit_pos.z * 0.3);
            let vein_mask = smoothstep(0.92, 1.0, vein_grid);
            let vein_progress = smoothstep(0.0, max(progress, 0.01), fract(hit_pos.z * 0.08 + 0.3));
            let vein_glow = vein_mask * vein_progress * (0.5 + beat * 0.5);

            let grid = max(rings_thick, rings_thin);
            let base_bg = mix(bg_col, vec3<f32>(0.0), 0.5);
            var glow = hue_shift(glow_col, hit_pos.z * 0.02);

            color = mix(base_bg, glow * 2.0, grid * 0.3 + energy * 1.5);
            color += glow * vein_glow * 1.2;

            // Depth fog
            color = mix(bg_col * 0.08, color, exp(-t * 0.08));
        }
    } else {
        let star_grid = fract(rd.xy * 20.0 + scene.time);
        color += glow_col * smoothstep(0.95, 1.0, star_grid.x) * smoothstep(0.95, 1.0, star_grid.y) * 0.1;
    }

    let dither = (hash21(p * scene.resolution + scene.time) - 0.5) * scene.dither_strength * 0.01;
    color += vec3<f32>(dither);
    let c4 = #color "scene.bg_color";
    return encode_output_alpha(color, c4.a);
}


