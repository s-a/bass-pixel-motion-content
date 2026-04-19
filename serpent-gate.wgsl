
#import <engine::bpm_kernel_bindings>

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const AUDIO_HISTORY_MAX_SAMPLES: u32 = 32u;

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOut {
    var p = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(3.0, -1.0),
        vec2<f32>(-1.0, 3.0),
    );
    var out: VertexOut;
    out.clip_position = vec4<f32>(p[vi], 0.0, 1.0);
    out.uv = p[vi] * 0.5 + 0.5;
    return out;
}

// ─── utility ───────────────────────────────────────────────────────
fn saturate_f(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }
fn saturate_v3(v: vec3<f32>) -> vec3<f32> { return clamp(v, vec3<f32>(0.0), vec3<f32>(1.0)); }

fn av(index: u32) -> f32 {
    let slot = scene._raw_audio_scalars_do_not_use[u32(index / 4u)];
    let component = index % 4u;
    if component == 0u { return slot.x; }
    if component == 1u { return slot.y; }
    if component == 2u { return slot.z; }
    return slot.w;
}

fn audio_history_value(index: u32, sample_index: u32) -> f32 {
    let flat_index = index * AUDIO_HISTORY_MAX_SAMPLES + sample_index;
    let slot = scene.audio_history[flat_index / 4u];
    let component = flat_index % 4u;
    if component == 0u { return slot.x; }
    if component == 1u { return slot.y; }
    if component == 2u { return slot.z; }
    return slot.w;
}

fn audio_history_samples() -> u32 {
    return clamp(u32(scene.audio_meta.w + 0.5), 1u, AUDIO_HISTORY_MAX_SAMPLES);
}

fn audio_peak_hold(index: u32) -> f32 {
    let sample_count = audio_history_samples();
    var peak_val = 0.0;
    for (var s = 0u; s < sample_count; s = s + 1u) {
        let age = f32(sample_count - 1u - s);
        let decayed = max(0.0, audio_history_value(index, s) - max(age - 4.0, 0.0) * 0.042);
        peak_val = max(peak_val, decayed);
    }
    return clamp(peak_val, 0.0, 1.0);
}

fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash31(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453123);
}

fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0) - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm4(p_in: vec2<f32>) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var q = p_in;
    let r = mat2x2<f32>(0.8, -0.6, 0.6, 0.8);
    for (var i = 0; i < 4; i = i + 1) {
        val = val + amp * noise2(q);
        q = r * q * 2.03 + vec2<f32>(4.2, 1.7);
        amp = amp * 0.5;
    }
    return val;
}

fn fbm6(p_in: vec2<f32>) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var q = p_in;
    let r = mat2x2<f32>(0.8, -0.6, 0.6, 0.8);
    for (var i = 0; i < 6; i = i + 1) {
        val = val + amp * noise2(q);
        q = r * q * 2.03 + vec2<f32>(4.2, 1.7);
        amp = amp * 0.5;
    }
    return val;
}

// ─── voronoi for scale patterns ────────────────────────────────────
fn voronoi(p: vec2<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var min_dist = 8.0;
    var second_dist = 8.0;
    for (var j = -1; j <= 1; j = j + 1) {
        for (var i = -1; i <= 1; i = i + 1) {
            let g = vec2<f32>(f32(i), f32(j));
            let cell_id = n + g;
            let cell_center = g + vec2<f32>(
                hash21(cell_id) * 0.8 + 0.1,
                hash21(cell_id + vec2<f32>(43.0, 17.0)) * 0.8 + 0.1,
            ) - f;
            let d = dot(cell_center, cell_center);
            if d < min_dist {
                second_dist = min_dist;
                min_dist = d;
            } else if d < second_dist {
                second_dist = d;
            }
        }
    }
    return vec2<f32>(sqrt(min_dist), sqrt(second_dist));
}

// ─── pupil slit SDF ────────────────────────────────────────────────
fn pupil_slit_sdf(p: vec2<f32>, dilation: f32) -> f32 {
    // Vertical slit: thin horizontally, tall vertically
    // dilation 0..1 controls the horizontal width
    let slit_width = mix(0.008, 0.12, dilation);
    let slit_height = 0.34;
    // Superellipse-like shape for organic slit
    let px = abs(p.x);
    let py = abs(p.y);
    let nx = px / max(slit_width, 0.001);
    let ny = py / max(slit_height, 0.001);
    // Exponent controls sharpness of the slit tips
    let exponent = mix(3.0, 2.0, dilation);
    return pow(pow(nx, exponent) + pow(ny, exponent), 1.0 / exponent) - 1.0;
}

// ─── iris fiber pattern ────────────────────────────────────────────
fn iris_fibers(angle: f32, radius: f32, t: f32, detail: f32, mid: f32, high: f32) -> f32 {
    // Radial streak pattern simulating muscle fibers
    let fiber_freq = 48.0 * detail;
    let fiber_a = sin(angle * fiber_freq + radius * 22.0 - t * 0.08) * 0.5 + 0.5;
    let fiber_b = sin(angle * fiber_freq * 0.7 - radius * 18.0 + t * 0.12 + 2.1) * 0.5 + 0.5;
    // Micro fibers for extreme detail
    let micro = sin(angle * fiber_freq * 3.4 + radius * 60.0 + t * 0.2 * high) * 0.5 + 0.5;
    let combined = pow(fiber_a, 2.6) * 0.6 + pow(fiber_b, 3.0) * 0.3 + pow(micro, 5.0) * 0.1 * detail;
    // Modulate with mid-frequency audio for shimmer
    return combined * (0.8 + mid * 0.3 + high * 0.15);
}

// ─── iris crypts (dark spots between fibers) ───────────────────────
fn iris_crypts(p: vec2<f32>, detail: f32) -> f32 {
    let vor = voronoi(p * (6.0 + detail * 4.0));
    let edge = smoothstep(0.02, 0.18, vor.y - vor.x);
    return edge;
}

// ─── iris ring structure ───────────────────────────────────────────
fn iris_rings(radius: f32, iris_inner: f32, iris_outer: f32, t: f32, detail: f32) -> f32 {
    let normalized = (radius - iris_inner) / max(iris_outer - iris_inner, 0.001);
    // Concentric ring bands (collarette, pupillary zone, ciliary zone)
    let ring1 = exp(-pow((normalized - 0.3) * 18.0, 2.0)) * 0.6;
    let ring2 = exp(-pow((normalized - 0.55) * 22.0, 2.0)) * 0.4;
    let ring3 = exp(-pow((normalized - 0.78) * 26.0, 2.0)) * 0.3;
    // Fine concentric ripples
    let ripple = pow(saturate_f(0.5 + 0.5 * sin(normalized * 80.0 * detail + t * 0.06)), 6.0) * 0.2;
    return ring1 + ring2 + ring3 + ripple;
}

// ─── scale texture for skin ────────────────────────────────────────
fn scale_pattern(p: vec2<f32>, scale_size: f32) -> f32 {
    let vor = voronoi(p * scale_size);
    let cell_edge = smoothstep(0.0, 0.12, vor.y - vor.x);
    let cell_bump = 1.0 - smoothstep(0.0, 0.25, vor.x);
    return cell_edge * 0.7 + cell_bump * 0.3;
}

// ─── blood vessel network ──────────────────────────────────────────
fn vessel_network(p: vec2<f32>, t: f32) -> f32 {
    let warp = vec2<f32>(
        fbm4(p * 3.0 + vec2<f32>(t * 0.02, 0.0)),
        fbm4(p * 3.0 + vec2<f32>(0.0, t * 0.015 + 5.0)),
    );
    let warped = p + warp * 0.3;
    let n = fbm6(warped * 6.0);
    // Threshold to create vein-like ridges
    let veins = smoothstep(0.42, 0.52, n) * (1.0 - smoothstep(0.52, 0.62, n));
    return veins;
}

// ─── specular highlight ────────────────────────────────────────────
fn cornea_specular(p: vec2<f32>, t: f32, beat: f32) -> f32 {
    // Primary light source reflection
    let light1_pos = vec2<f32>(-0.12, 0.18);
    let light1_size = 0.04 + beat * 0.008;
    let d1 = length(p - light1_pos);
    let spec1 = exp(-d1 * d1 / (light1_size * light1_size));
    // Secondary smaller highlight
    let light2_pos = vec2<f32>(0.08, 0.14);
    let light2_size = 0.018;
    let d2 = length(p - light2_pos);
    let spec2 = exp(-d2 * d2 / (light2_size * light2_size)) * 0.6;
    // Soft window reflection (rectangular shape)
    let window_p = p - vec2<f32>(-0.06, 0.1);
    let window_d = max(abs(window_p.x / 0.06), abs(window_p.y / 0.04));
    let spec_window = exp(-pow(max(window_d - 0.7, 0.0) * 8.0, 2.0)) * 0.25;
    return spec1 + spec2 + spec_window;
}

// ─── progress gate ring (song progress motif) ──────────────────────
fn progress_gate_ring(
    radius: f32,
    angle: f32,
    progress: f32,
    t: f32,
    pulse: f32,
    detail: f32,
) -> vec3<f32> {
    // Ring positioned at the collarette zone of the iris
    let gate_radius = 0.24;
    let gate_width = 0.008;
    let ring_band = exp(-abs(radius - gate_radius) / gate_width);
    // Phase from angle (-PI..PI -> 0..1), starting from the top
    let phase = fract((-angle + PI * 0.5) / TAU + 1.0);
    let arc_fill = smoothstep(-0.006, 0.006, progress - phase);
    // Ornamental notch marks along the ring
    let notches = pow(saturate_f(0.5 + 0.5 * cos(angle * (24.0 + detail * 8.0))), 12.0);
    // Completed portion: warm gold glow
    let filled_lum = ring_band * arc_fill * (0.5 + pulse * 0.4);
    // Head of the progress: bright flash
    let head_dist = abs(phase - progress);
    let head_wrap = min(head_dist, 1.0 - head_dist);
    let head_glow = exp(-head_wrap * (160.0 + pulse * 80.0))
        * exp(-abs(radius - gate_radius) * (60.0 + pulse * 30.0));
    // Unfilled portion: subtle dark etching
    let unfilled = ring_band * (1.0 - arc_fill) * 0.08 * (0.6 + notches * 0.4);
    return vec3<f32>(filled_lum + notches * filled_lum * 0.3, head_glow, unfilled);
}

// ─── subsurface scattering approximation ───────────────────────────
fn sss_approx(radius: f32, iris_outer: f32, low: f32) -> f32 {
    let edge_zone = smoothstep(iris_outer - 0.06, iris_outer + 0.02, radius);
    let inner_glow = exp(-(radius - iris_outer) * 8.0) * (1.0 - edge_zone);
    return inner_glow * (0.2 + low * 0.15);
}

// ─── caustic refraction pattern inside pupil ───────────────────────
fn pupil_caustics(p: vec2<f32>, t: f32) -> f32 {
    let q = p * 12.0 + vec2<f32>(t * 0.3, -t * 0.2);
    let n1 = noise2(q);
    let n2 = noise2(q * 1.7 + vec2<f32>(n1 * 2.0, 0.0));
    let caustic = pow(saturate_f(n2), 3.0);
    return caustic;
}

// ─── main composition ──────────────────────────────────────────────
@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    // Read user colors
    let c_iris = #color "scene.iris_color";
    let iris_col = c_iris.rgb;
    let c_slit = #color "scene.slit_glow";
    let slit_col = c_slit.rgb;
    let c_skin = #color "scene.skin_color";
    let skin_col = c_skin.rgb;
    let c_bg = #color "scene.bg_color";
    let bg_col = c_bg.rgb;

    // Read user parameters
    let pupil_react = clamp(#gui_param "scene.pupil_reactivity".x, 0.1, 1.5);
    let iris_detail = clamp(#gui_param "scene.iris_detail".x, 0.3, 2.0);
    let glow_str = clamp(#gui_param "scene.glow_intensity".x, 0.2, 1.8);

    // Audio
    let low = saturate_f(av(0u));
    let mid = saturate_f(av(1u));
    let high = saturate_f(av(2u));
    let rms = saturate_f(av(3u));
    let peak_val = saturate_f(av(4u));
    let beat = saturate_f(av(5u));
    let impact = saturate_f(av(6u));
    let bright = saturate_f(av(7u));
    let flux = saturate_f(av(8u));

    let beat_phase_sig = #audio "audio.rhythm.beat_phase";
    let beat_phase = beat_phase_sig.clamped_safe;
    let kick_phase_sig = #audio "audio.rhythm.kick_phase";
    let kick_phase = kick_phase_sig.clamped_safe;

    let beat_hold = audio_peak_hold(5u);
    let impact_hold = audio_peak_hold(6u);
    let pulse = saturate_f(beat_hold * 0.5 + impact_hold * 0.6 + peak_val * 0.2);

    let progress = saturate_f(scene.timeline.z);
    let t = scene.time;

    // Coordinate setup
    let aspect = scene.resolution.x / max(scene.resolution.y, 1.0);
    var uv = in.uv * 2.0 - vec2<f32>(1.0);
    uv.x = uv.x * aspect;

    // Subtle organic breathing motion
    let breathe = sin(t * 0.4 + kick_phase * PI) * 0.006 * pupil_react;
    let shake_x = sin(t * 7.3 + impact * 12.0) * impact_hold * 0.008;
    let shake_y = cos(t * 6.1 + impact * 8.0) * impact_hold * 0.006;
    uv = uv + vec2<f32>(shake_x, shake_y + breathe);

    let radius = length(uv);
    let angle = atan2(uv.y, uv.x);

    // ─── eye geometry parameters ───────────────────────────────
    let iris_outer = 0.38 + low * 0.02 * pupil_react;
    let iris_inner = 0.14 + low * 0.02 * pupil_react;
    let pupil_dilation = saturate_f(0.25 + low * 0.45 * pupil_react - beat * 0.12 * pupil_react);
    let sclera_outer = 0.58;

    // ─── BACKGROUND: deep void ─────────────────────────────────
    var color = bg_col * (0.3 + 0.7 * exp(-radius * 1.2));

    // ─── SKIN / SCLERA layer ───────────────────────────────────
    let skin_zone = smoothstep(sclera_outer + 0.06, sclera_outer - 0.04, radius);
    let scales = scale_pattern(uv * 3.8 + vec2<f32>(t * 0.01), 14.0);
    let fine_scales = scale_pattern(uv * 6.0 + vec2<f32>(-t * 0.008, t * 0.006), 22.0);
    let veins = vessel_network(uv * 1.5, t);
    let skin_n = fbm4(uv * 8.0 + vec2<f32>(t * 0.02, -t * 0.015));

    let skin_base = skin_col * (0.6 + scales * 0.3 + fine_scales * 0.15 + skin_n * 0.2);
    let vein_color = vec3<f32>(0.35, 0.08, 0.06) * veins * (0.4 + rms * 0.3);
    let sclera_col = mix(skin_col * 1.4, vec3<f32>(0.85, 0.82, 0.75), 0.3);
    let sclera_blend = smoothstep(sclera_outer, iris_outer + 0.08, radius);
    let eye_surface = mix(sclera_col * (0.7 + skin_n * 0.15), skin_base, sclera_blend) + vein_color;

    color = mix(color, eye_surface, skin_zone);

    // ─── IRIS layer ────────────────────────────────────────────
    let iris_zone = smoothstep(iris_outer + 0.01, iris_outer - 0.02, radius)
        * (1.0 - smoothstep(iris_inner + 0.02, iris_inner - 0.01, radius));

    // Iris color gradient: rich amber in the middle, darker at edges and inner rim
    let iris_norm = saturate_f((radius - iris_inner) / max(iris_outer - iris_inner, 0.001));
    // Bell-curve: dark near pupil, brightest mid-iris, dark at limbus
    let iris_brightness = sin(iris_norm * PI) * 0.6 + 0.2;
    let iris_base = iris_col * iris_brightness;

    // Brightness-driven color temperature shift
    let warm = iris_col;
    let cold = mix(iris_col, slit_col, 0.4);
    let temp_iris = mix(warm, cold, bright * 0.5);

    // Fiber detail
    let fibers = iris_fibers(angle, radius, t, iris_detail, mid, high);
    // Crypt cells
    let polar_for_crypts = vec2<f32>(angle * 3.0, radius * 12.0);
    let crypts = iris_crypts(polar_for_crypts, iris_detail);
    // Ring structure
    let rings = iris_rings(radius, iris_inner, iris_outer, t, iris_detail);

    // Domain-warped iris texture with higher contrast
    let iris_warp = fbm4(vec2<f32>(angle * 2.0, radius * 8.0) + vec2<f32>(t * 0.03));
    let iris_tex = saturate_f(
        fibers * 0.45 + crypts * 0.3 + rings * 0.2 + iris_warp * 0.12
    );

    // Use iris_tex to modulate between dark crypts and bright fiber highlights
    let iris_dark = iris_base * 0.25;
    let iris_bright = temp_iris * 0.85;
    let iris_surface = mix(iris_dark, iris_bright, iris_tex);

    // Subsurface at iris-sclera boundary
    let sss = sss_approx(radius, iris_outer, low);
    let sss_color = mix(iris_col, vec3<f32>(0.8, 0.3, 0.1), 0.5) * sss;

    color = mix(color, iris_surface + sss_color, iris_zone);

    // Iris limbal ring (dark edge ring)
    let limbal = exp(-pow((radius - iris_outer) * 40.0, 2.0)) * 0.5;
    color = color - vec3<f32>(limbal * 0.3);

    // ─── PUPIL layer ───────────────────────────────────────────
    let pupil_dist = pupil_slit_sdf(uv, pupil_dilation);
    let pupil_alpha = 1.0 - smoothstep(-0.03, 0.01, pupil_dist);

    // Pupil interior: deep black with subtle caustics
    let caustics = pupil_caustics(uv, t);
    let pupil_interior = vec3<f32>(0.005) + vec3<f32>(0.02) * caustics * (0.3 + rms * 0.4);

    color = mix(color, pupil_interior, pupil_alpha);

    // Pupil slit edge glow — pulled back to avoid overexposure
    let edge_glow_raw = exp(-max(pupil_dist, 0.0) * (50.0 + pulse * 20.0));
    let edge_glow = edge_glow_raw * (0.25 + pulse * 0.35 + beat * 0.2) * glow_str;
    color = color + slit_col * edge_glow * 0.4;

    // Inner iris ring glow (close to pupil) — subtle, not blinding
    let inner_ring = exp(-pow((radius - iris_inner) * 32.0, 2.0));
    color = color + mix(slit_col, iris_col, 0.5) * inner_ring * (0.08 + low * 0.12) * glow_str;

    // ─── PROGRESS GATE (song progress motif) ───────────────────
    let gate = progress_gate_ring(radius, angle, progress, t, pulse, iris_detail);
    // filled arc
    let gate_warm = mix(iris_col, vec3<f32>(1.0, 0.9, 0.7), 0.3);
    color = color + gate_warm * gate.x * glow_str;
    // head flash
    color = color + mix(slit_col, vec3<f32>(1.0, 1.0, 0.95), 0.5) * gate.y * 0.8 * glow_str;
    // unfilled etch
    color = color + skin_col * gate.z;

    // ─── SPECULAR HIGHLIGHTS (wet cornea) ──────────────────────
    let spec = cornea_specular(uv, t, beat);
    let spec_mask = smoothstep(sclera_outer + 0.02, iris_inner, radius);
    color = color + vec3<f32>(1.0, 0.98, 0.95) * spec * spec_mask * (0.7 + pulse * 0.3);

    // ─── ATMOSPHERIC depth effects ─────────────────────────────
    // Volumetric haze around the eye
    let haze_noise = fbm4(uv * 2.0 + vec2<f32>(t * 0.05, -t * 0.03));
    let haze_ring = exp(-pow((radius - sclera_outer) * 3.5, 2.0));
    let haze = haze_ring * haze_noise * (0.08 + rms * 0.1 + flux * 0.06);
    color = color + mix(skin_col, iris_col, 0.3) * haze;

    // Beat flash over the entire iris
    let flash_zone = smoothstep(iris_outer + 0.02, iris_inner - 0.02, radius);
    let flash = beat * 0.12 * flash_zone;
    color = color + mix(iris_col, slit_col, 0.4) * flash;

    // ─── VIGNETTE ──────────────────────────────────────────────
    let vig = 1.0 - smoothstep(0.5, 1.6, radius);
    color = color * vig;

    // ─── TIMELINE DRAMATURGY ───────────────────────────────────
    // Opening: eye is darker, more closed feel
    let opening = 1.0 - smoothstep(0.0, 0.2, progress);
    // Climax: intensified colors and glow
    let climax = smoothstep(0.4, 0.7, progress) * (1.0 - smoothstep(0.85, 1.0, progress));
    // Finale: slight desaturation and fade
    let finale = smoothstep(0.85, 1.0, progress);

    let drama_dim = mix(0.6, 1.0, 1.0 - opening * 0.5);
    let drama_boost = 1.0 + climax * 0.2;
    let drama_fade = mix(1.0, 0.85, finale);
    color = color * drama_dim * drama_boost * drama_fade;

    // Climax: extra rim light
    let rim_radius = iris_outer + 0.02;
    let rim = exp(-pow((radius - rim_radius) * 20.0, 2.0)) * climax * 0.3;
    color = color + mix(iris_col, slit_col, 0.6) * rim * glow_str;

    // ─── DITHER ────────────────────────────────────────────────
    let dither = (hash21(in.uv * scene.resolution + vec2<f32>(t * 7.0, 13.0)) - 0.5) * scene.dither_strength * 0.035;
    color = color + vec3<f32>(dither);

    return encode_output_alpha(color, c_bg.a);
}
