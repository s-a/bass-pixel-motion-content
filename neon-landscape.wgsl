#import <engine::bpm_kernel_bindings>

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOut {
    var p = array<vec2<f32>, 3>(
        vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0)
    );
    var out: VertexOut;
    out.clip_position = vec4<f32>(p[vi], 0.0, 1.0);
    out.uv = p[vi] * 0.5 + 0.5;
    return out;
}

// ─── Deterministic hash (precision-safe, avoids sin-dot drift) ───────
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031 + vec3<f32>(0.71, 0.31, 0.82));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ─── Value noise 2D ──────────────────────────────────────────────────
fn noise2D(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// ─── FBM: 4 octaves with rotational warping for organic terrain ──────
fn fbm(p_in: vec2<f32>) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var pos = p_in;
    let r = mat2x2<f32>(0.8, -0.6, 0.6, 0.8);
    for (var i = 0u; i < 4u; i = i + 1u) {
        val += amp * noise2D(pos);
        pos = r * pos * 2.03 + vec2<f32>(4.2, 1.7);
        amp *= 0.5;
    }
    return val;
}

// ═════════════════════════════════════════════════════════════════════
// SDF: 100% STATIC — no time, no audio, no cam_speed.
// Geometry is a pure function of spatial position.
// Camera height is raised in fs_main() to prevent clipping — NOT here.
// ═════════════════════════════════════════════════════════════════════
fn map(p: vec3<f32>, scale: f32, height: f32) -> vec2<f32> {
    let terrain_uv = p.xz * scale;
    let n = fbm(terrain_uv);
    // Smooth organic displacement — NO clamp, NO ceiling.
    // Full Lipschitz-continuous terrain. Camera clipping is prevented
    // by elevating ro.y dynamically in fs_main, not by mutilating the SDF.
    let disp = (n - 0.5) * height;
    let d = p.y - disp;
    // Step reduction 0.35: safety margin for FBM gradient > 1.0
    return vec2<f32>(d * 0.35, n);
}

fn calc_normal(p: vec3<f32>, scale: f32, height: f32) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, scale, height).x - map(p - e.xyy, scale, height).x,
        map(p + e.yxy, scale, height).x - map(p - e.yxy, scale, height).x,
        map(p + e.yyx, scale, height).x - map(p - e.yyx, scale, height).x
    ));
}

// ═════════════════════════════════════════════════════════════════════
// FRAGMENT: ALL dynamics — audio, speed, glow, timeline
// ═════════════════════════════════════════════════════════════════════
@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    // ─── GUI Parameters ──────────────────────────────────────────
    let speed_p = #gui_param "cam_speed";
    let speed = speed_p.x;

    let scale_p = #gui_param "terrain_scale";
    let scale = scale_p.x;

    let height_p = #gui_param "terrain_height";
    let height = height_p.x;

    let glow_int_p = #gui_param "glow_intensity";
    let glow_int = glow_int_p.x;

    // ─── Colors ──────────────────────────────────────────────────
    let col_bg_raw = #color "bg_color";
    let col_bg = col_bg_raw.rgb;
    let bg_alpha = col_bg_raw.a;

    let col_accent_raw = #color "accent_color";
    let col_accent = col_accent_raw.rgb;

    // ─── Audio: surface/fragment ONLY — never geometry ───────────
    let sig_bass = #audio "audio.stem.bass.rms";
    let bass = sig_bass.value;

    let sig_kick = #audio "audio.stem.kicks.peak";
    let kick = sig_kick.value;

    // ─── Timeline & render time ──────────────────────────────────
    let progress = scene.timeline.z;
    let t = scene.time;

    // ─── Screen coordinates ──────────────────────────────────────
    let uv = in.uv * 2.0 - 1.0;
    let aspect = scene.resolution.x / scene.resolution.y;

    // ═══ CAMERA: Treadmill flight ═════════════════════════════════
    // cam_y: enough clearance for safe rendering, but NOT so proportional
    // that height changes cancel visually. 0.55 factor + 0.6 base.
    let cam_y = height * 0.55 + 0.6;
    // Camera Z uses FIXED internal speed for SDF stability.
    // cam_speed ONLY controls the emission scroll (optical illusion).
    let cam_z_internal = t * 0.5 + 5000.0;

    // Organic drone sway (time-driven only, never audio!)
    let sway_x = sin(t * 0.3) * 0.12;
    let sway_y = sin(t * 0.4 + 1.0) * 0.06;
    let ro = vec3<f32>(sway_x, cam_y + sway_y, cam_z_internal);

    // Look-at: forward (+Z), gaze tilted toward terrain surface
    let look_at = vec3<f32>(sway_x * 0.5, cam_y - 0.9, cam_z_internal + 7.0);
    let cz = normalize(look_at - ro);
    let cx = normalize(cross(cz, vec3<f32>(0.0, 1.0, 0.0)));
    let cy = cross(cx, cz);
    let rd = normalize(cx * uv.x * aspect + cy * uv.y + cz * 1.5);

    // ═══ RAYMARCHING ════════════════════════════════════════════
    // SDF is evaluated on CAMERA-RELATIVE coords (p_rel) so that
    // terrain shape is independent of camera position and cam_speed.
    // The fixed offset avoids origin singularity in FBM.
    let terrain_offset = vec3<f32>(1234.5, cam_y, 6789.1);
    var t_ray = 0.0;
    let max_steps = 60;
    let max_dist = 45.0;
    var hit = false;

    for (var i = 0; i < max_steps; i++) {
        let p_rel = rd * t_ray + terrain_offset;
        let res = map(p_rel, scale, height);
        if (res.x < 0.005) { hit = true; break; }
        if (t_ray > max_dist) { break; }
        t_ray += res.x;
    }

    // ─── Atmospheric fog palette (accent-tinted, progress-evolving) ──
    let fog_warm = mix(col_accent, col_accent * vec3<f32>(1.3, 0.85, 0.5), progress * 0.5);
    let fog_color = mix(col_bg * 0.5, fog_warm * 0.15, 0.5 + progress * 0.25);

    // ─── Sky base ────────────────────────────────────────────────
    // Subtle sky gradient so upper screen is never pure black
    let sky_grad = exp(-max(rd.y, 0.0) * 2.5);
    var final_color = mix(col_bg * 0.04, fog_color * 0.3, sky_grad * 0.4);

    // Atmospheric horizon band — powerful, defines the landscape mood
    let horiz_band = exp(-abs(rd.y + 0.12) * 4.0);
    final_color += fog_warm * horiz_band * glow_int * (0.25 + bass * 0.25 + progress * 0.12);

    if (hit) {
        // p_rel for stable normals (camera-relative)
        let p_rel_hit = rd * t_ray + terrain_offset;
        // hit_p_abs for emission scroll (absolute world coords = treadmill!)
        let hit_p = ro + rd * t_ray;
        let normal = calc_normal(p_rel_hit, scale, height);

        // ─── Dark terrain base: subtle diffuse + rim accent ──────
        let sun_dir = normalize(vec3<f32>(0.3, 0.8, 0.2));
        let diffuse = max(dot(normal, sun_dir), 0.0);
        let rim = pow(1.0 - max(dot(normal, normalize(-rd)), 0.0), 3.0);
        let terrain_base = col_bg * (0.02 + diffuse * 0.06)
                         + col_accent * rim * 0.03;

        // ═══ NEON EMISSION: on ABSOLUTE world coordinates ════════
        // hit_p.xz shifts via cam_z_internal → base treadmill.
        // cam_speed adds EXTRA emission scroll on top → user-controlled speed.
        let scroll_offset = t * speed;
        let emiss_xz = hit_p.xz + vec2<f32>(0.0, scroll_offset);

        // Layer 1: Organic contour lines tracing terrain topology
        let world_uv = emiss_xz * scale;
        let terrain_n = fbm(world_uv);
        let contour_raw = fract(terrain_n * 10.0);
        let contour = exp(-abs(contour_raw - 0.5) * (14.0 + kick * 25.0));

        // Layer 2: XZ directional grid (Tron-like precision overlay)
        let gf = 2.5;
        let gx = abs(fract(emiss_xz.x * gf) - 0.5);
        let gz = abs(fract(emiss_xz.y * gf) - 0.5);
        let grid = exp(-min(gx, gz) * (16.0 + kick * 28.0));

        // Layer 3: Elevation contour bands (horizontal strata)
        let h_raw = fract(hit_p.y * 6.0);
        let h_contour = exp(-abs(h_raw - 0.5) * 14.0) * 0.3;

        // Combine emission layers with EXPLOSIVE audio reactivity
        let emission = contour * 0.55 + grid * 0.35 + h_contour;
        let neon_pump = glow_int * (1.0 + kick * 4.0 + bass * 2.0);

        // Timeline color evolution: cool accent → warmer with song progress
        let time_accent = mix(col_accent, col_accent * vec3<f32>(1.4, 0.9, 0.6), progress * 0.4);
        let neon = time_accent * emission * neon_pump;

        final_color = terrain_base + neon;

        // ─── Exponential distance fog (dense, atmospheric) ────────
        let fog_t = 1.0 - exp(-t_ray * t_ray * 0.0018);
        final_color = mix(final_color, fog_color, fog_t);

        // Accent haze (subsurface-like scattering at distance)
        final_color += col_accent * (1.0 - exp(-t_ray * 0.04)) * 0.06;
    } else {
        // Miss → atmospheric fog
        final_color = mix(final_color, fog_color * 0.4, 0.5);
    }

    // ─── Audio-reactive ambient bloom ────────────────────────────
    let center_dist = length(uv);
    final_color += col_accent * kick * 0.2 * exp(-center_dist * 1.2);

    // ─── Song progress motif: ascending horizon dawn ─────────────
    // A warm neon band rises from the screen bottom toward the horizon
    // as the song unfolds — organic, non-HUD progress visualization.
    let dawn_y = mix(-0.8, 0.3, progress);
    let dawn_band = exp(-pow((uv.y - dawn_y) * 5.0, 2.0)) * progress;
    let dawn_tint = col_accent * vec3<f32>(1.3, 0.7, 0.4);
    final_color += dawn_tint * dawn_band * 0.12 * (1.0 + bass * 0.5);

    // ─── Timeline dramaturgy ─────────────────────────────────────
    // Intro: build energy from a dimmer starting point
    let intro = smoothstep(0.0, 0.15, progress);
    final_color *= mix(0.55, 1.0, intro);

    // Climax: peak energy boost mid-song
    let climax = smoothstep(0.45, 0.75, progress) * (1.0 - smoothstep(0.88, 1.0, progress));
    final_color *= 1.0 + climax * 0.2;

    // ─── Cinematic vignette ──────────────────────────────────────
    final_color *= 1.0 - smoothstep(0.5, 1.8, center_dist);

    // ─── Dither (anti color-banding) ─────────────────────────────
    let dither_seed = in.uv * vec2<f32>(scene.resolution.x, scene.resolution.y)
                    + vec2<f32>(t * 7.0, 13.0);
    let dither = (hash21(dither_seed) - 0.5) * scene.dither_strength * 0.04;
    final_color += vec3<f32>(dither);

    return encode_output_alpha(final_color, bg_alpha);
}
