
#import <engine::bpm_kernel_bindings>

// ─── Constants ───────────────────────────────────────────────────────────────
const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const AUDIO_HISTORY_MAX_SAMPLES: u32 = 32u;
const RING_COUNT: i32 = 14;

// ─── Vertex ──────────────────────────────────────────────────────────────────
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

// ─── Audio Helpers ───────────────────────────────────────────────────────────
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

fn held(index: u32) -> f32 {
    let sample_count = audio_history_samples();
    var peak_val = 0.0;
    for (var s = 0u; s < sample_count; s = s + 1u) {
        let age = f32(sample_count - 1u - s);
        let decayed = max(0.0, audio_history_value(index, s) - max(age - 2.0, 0.0) * 0.07);
        peak_val = max(peak_val, decayed);
    }
    return clamp(peak_val, 0.0, 1.0);
}

// ─── Utility ─────────────────────────────────────────────────────────────────
fn saturate_f(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash11(x: f32) -> f32 {
    return fract(sin(x * 127.31 + 311.7) * 43758.5453123);
}

fn story_progress() -> f32 {
    return saturate_f(scene.timeline.z);
}

// ─── Signed Distance Helpers ─────────────────────────────────────────────────
fn sd_ring(p: vec2<f32>, radius: f32, thickness: f32) -> f32 {
    return abs(length(p) - radius) - thickness;
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER 1: VOID BACKGROUND — deep black with haze revealing speed and structure
// ═══════════════════════════════════════════════════════════════════════════════
fn render_void(
    scr: vec2<f32>,
    t: f32,
    progress: f32,
    low: f32,
    rms: f32,
    accent: vec3<f32>,
) -> vec3<f32> {
    let center_dist = length(scr);

    // Central pressure haze — reveals the vanishing point
    let haze = exp(-center_dist * (1.2 - low * 0.3)) * (0.06 + low * 0.08 + rms * 0.05);

    // Radial gradient — accent glow at center, void at edges
    let core_glow = exp(-center_dist * 2.5) * (0.04 + progress * 0.04 + rms * 0.03);

    var color = accent * haze * (0.6 + progress * 0.4);
    color = color + accent * core_glow;

    let vocal_sig = #audio "audio.stem.vocals.rms";
    let vocal = vocal_sig.clamped_safe;
    let vocal_glow = exp(-center_dist * 1.8) * vocal * 0.3;
    let vocal_color = vec3<f32>(0.85, 0.2, 0.95);
    color = color + vocal_color * vocal_glow;

    return color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER 2: CORRIDOR STRUCTURE — concentric rings, rails, mechanical ribs
// ═══════════════════════════════════════════════════════════════════════════════
fn render_corridor(
    scr: vec2<f32>,
    t: f32,
    progress: f32,
    corridor_speed: f32,
    ring_density: f32,
    low: f32,
    mid: f32,
    beat_phase: f32,
    kick: f32,
    bar_phase: f32,
    accent: vec3<f32>,
    highlight: vec3<f32>,
) -> vec3<f32> {
    var color = vec3<f32>(0.0);
    let center_dist = length(scr);
    let center_angle = atan2(scr.y, scr.x);

    // Forward scroll
    let scroll = t * corridor_speed * 2.2;

    // Metallic base tone — gunmetal derived from accent
    let gunmetal = accent * 0.12 + vec3<f32>(0.03, 0.035, 0.04);

    for (var i: i32 = 0; i < RING_COUNT; i = i + 1) {
        let fi = f32(i);
        let ring_z = fract(fi / f32(RING_COUNT) - scroll * ring_density * 0.12);
        let depth = pow(ring_z, 1.4);

        // Ring radius — foreshortens toward center
        let base_radius = mix(1.8, 0.04, depth);

        // Kick jolt — rings compress inward
        let kick_jolt = 1.0 - kick * 0.1 * (1.0 - depth);

        // Sub-bass structural breathing
        let breath = 1.0 + low * 0.05 * sin(fi * 0.7 + t * 1.2);

        let radius = base_radius * kick_jolt * breath;
        let thickness = mix(0.008, 0.002, depth);

        // Ring SDF with sharp metallic edges
        let ring_dist = sd_ring(scr, radius, thickness);
        let ring_alpha = exp(-max(ring_dist, 0.0) * (80.0 + depth * 160.0));

        // 12-segment mechanical gaps
        let seg = abs(fract(center_angle * 6.0 / TAU) - 0.5);
        let segment_mask = smoothstep(0.35, 0.42, seg);

        // Chain-reaction light stepping (rolling drums)
        let chain = fract(beat_phase + fi * 0.07);
        let chain_glow = exp(-abs(chain - 0.5) * 6.0) * 0.5;

        // Pressure rib emphasis every 3rd ring
        let rib_boost = select(1.0, 2.5, i % 3 == 0);

        // Ring color: gunmetal base with accent edge lighting
        let ring_color = gunmetal * (1.5 + depth * 0.5)
            + accent * (0.25 + chain_glow) * (1.0 - depth * 0.5);

        // Sharp white highlights on closest rings
        let specular = highlight * exp(-depth * 4.0) * 0.06;

        color = color + (ring_color + specular) * ring_alpha * segment_mask * rib_boost * (0.6 + progress * 0.4);
    }

    // Structural rail cross — bright accent rails converging to vanishing point
    let rail_a = abs(scr.x * 0.707 + scr.y * 0.707);
    let rail_b = abs(scr.x * 0.707 - scr.y * 0.707);
    let rail_c = abs(scr.x); // horizontal rail
    let rail_d = abs(scr.y); // vertical rail
    let rail_falloff = 1.0 - smoothstep(0.0, 1.6, center_dist);
    let rails = (exp(-rail_a * 120.0) + exp(-rail_b * 120.0)
               + exp(-rail_c * 160.0) + exp(-rail_d * 160.0)) * rail_falloff;
    color = color + mix(gunmetal * 2.0, accent * 0.4, 0.3) * rails * (mid * 1.5);

    return color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER 3: CONDUIT ENERGY — mid-bass rotating pressure bands + inner core
// ═══════════════════════════════════════════════════════════════════════════════
fn render_conduit_energy(
    scr: vec2<f32>,
    t: f32,
    progress: f32,
    mid: f32,
    rms: f32,
    accent: vec3<f32>,
    highlight: vec3<f32>,
) -> vec3<f32> {
    let center_dist = length(scr);
    let angle = atan2(scr.y, scr.x);

    // Rotating pressure bands — aggressive mid-bass energy
    let rotation = t * 1.4 + mid * 3.0;
    let band_angle = fract((angle + rotation) * 4.0 / TAU);
    let band_glow = exp(-abs(band_angle - 0.5) * 8.0) * mid;
    let band_mask = (1.0 - smoothstep(0.0, 0.7, center_dist));

    // Inner conduit ring — persistent glow at corridor core
    let core_r = 0.06 + progress * 0.06;
    let conduit = exp(-abs(center_dist - core_r) * 30.0) * (0.15 + mid * 0.25 + rms * 0.1);

    // Hotspot at absolute center
    let hotspot = exp(-center_dist * 12.0) * (0.08 + rms * 0.12);

    let energy_color = mix(accent, highlight, 0.15);
    return energy_color * (band_glow * band_mask * 0.35 + conduit + hotspot) * (0.6 + progress * 0.4);
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER 4: COMPRESSION WAVES — sub-bass radial pressure pulses
// ═══════════════════════════════════════════════════════════════════════════════
fn render_compression_waves(
    scr: vec2<f32>,
    t: f32,
    low: f32,
    pressure_depth: f32,
    kick_phase: f32,
    accent: vec3<f32>,
    highlight: vec3<f32>,
) -> vec3<f32> {
    let center_dist = length(scr);
    var wave_color = vec3<f32>(0.0);

    // Two pressure wave fronts expanding from center
    for (var w: i32 = 0; w < 2; w = w + 1) {
        let phase = fract(kick_phase * 0.5 + f32(w) * 0.5);
        let wave_r = phase * 1.6 * pressure_depth;
        let wave_w = 0.015 + phase * 0.02;
        let strength = (1.0 - phase) * low * pressure_depth;
        let ring = exp(-abs(center_dist - wave_r) / wave_w);
        wave_color = wave_color + mix(accent, highlight, 0.25) * ring * strength * 0.6;
    }

    // Persistent sub-bass core pressure
    let core = exp(-center_dist * (5.0 - low * 2.5)) * low * 0.2 * pressure_depth;
    wave_color = wave_color + accent * core;

    return wave_color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER 5: EDGE LIGHT STROBES — kick/snare hard impacts
// ═══════════════════════════════════════════════════════════════════════════════
fn render_strobes(
    scr: vec2<f32>,
    t: f32,
    kick: f32,
    snare: f32,
    impact: f32,
    beat: f32,
    strobe_intensity: f32,
    accent: vec3<f32>,
    highlight: vec3<f32>,
) -> vec3<f32> {
    var strobe = vec3<f32>(0.0);
    let center_dist = length(scr);

    // KICK: vertical aperture slash — bright center line
    let kick_slash = exp(-abs(scr.x) * 40.0) * kick * strobe_intensity;
    strobe = strobe + highlight * kick_slash * 1.2;

    // SNARE: lateral horizontal razor flash
    let snare_razor = exp(-abs(scr.y) * 50.0) * snare * strobe_intensity;
    strobe = strobe + mix(accent, highlight, 0.6) * snare_razor * 0.9;

    // IMPACT: full radial pressure burst — blinding white
    let burst = exp(-center_dist * 3.0) * impact * strobe_intensity;
    strobe = strobe + highlight * burst * 0.8;

    // BEAT: subtle full-frame flash
    let frame_flash = beat * 0.04 * strobe_intensity;
    strobe = strobe + highlight * frame_flash;

    // Edge light slits rotating with time
    let slit_a = abs(scr.x * 0.707 + scr.y * 0.707);
    let slit_b = abs(scr.x * 0.707 - scr.y * 0.707);
    let slit_mask = (exp(-slit_a * 140.0) + exp(-slit_b * 140.0))
                  * (1.0 - smoothstep(0.0, 1.0, center_dist));
    strobe = strobe + accent * slit_mask * (kick * 0.5 + snare * 0.3) * strobe_intensity;

    return strobe;
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER 6: PARTICLE DEBRIS — hi-hat micro-fragments + sparks
// ═══════════════════════════════════════════════════════════════════════════════
fn render_particles(
    scr: vec2<f32>,
    t: f32,
    high: f32,
    hihat: f32,
    flux: f32,
    brightness: f32,
    accent: vec3<f32>,
    highlight: vec3<f32>,
) -> vec3<f32> {
    var color = vec3<f32>(0.0);
    let center_dist = length(scr);

    // Grid-based particle field
    let p_uv = scr * 16.0;
    let p_cell = floor(p_uv);
    let p_frac = fract(p_uv) - 0.5;

    let cell_hash = hash21(p_cell + vec2<f32>(floor(t * 0.3)));
    let spark_pos = vec2<f32>(
        hash21(p_cell * 1.3 + vec2<f32>(7.0)) - 0.5,
        hash21(p_cell * 1.7 + vec2<f32>(13.0)) - 0.5
    );
    let dist_to_spark = length(p_frac - spark_pos * 0.35);

    let snare_sig = #audio "audio.stem.snares.peak";
    let snare_val = snare_sig.clamped_safe;

    // Needle glints — triggered by highs and snare
    let glint = exp(-dist_to_spark * 30.0) * (high * 0.8 + snare_val * 1.5);
    let glint_tint = mix(accent, highlight, 0.5 + brightness * 0.4);

    // Corridor-constrained (fade at edges)
    let mask = exp(-center_dist * 1.2);

    // High-frequency micro-flicker
    let flicker = step(0.88 - high * 0.2, cell_hash) * high * 0.2;

    color = color + glint_tint * (glint + flicker) * mask;

    return color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER 7: APERTURE GATE — progress motif (iris that opens with timeline)
// ═══════════════════════════════════════════════════════════════════════════════
fn render_aperture_gate(
    scr: vec2<f32>,
    t: f32,
    progress: f32,
    rms: f32,
    low: f32,
    kick: f32,
    accent: vec3<f32>,
    highlight: vec3<f32>,
) -> vec3<f32> {
    let center_dist = length(scr);
    let angle = atan2(scr.y, scr.x);

    // 8-blade iris aperture — opens from closed to wide
    let blade_angle = fract(angle * 8.0 / TAU + 0.5);
    let blade_width = mix(0.46, 0.08, progress);

    // Aperture radius grows with progress
    let aperture_r = mix(0.04, 0.55, pow(progress, 0.7));
    let breathing_r = aperture_r + low * 0.03;

    // Blade edge band
    let blade_edge = smoothstep(blade_width - 0.04, blade_width, abs(blade_angle - 0.5))
                   * (1.0 - smoothstep(blade_width, blade_width + 0.04, abs(blade_angle - 0.5)));

    // Radius edge band
    let radius_band = exp(-abs(center_dist - breathing_r) * 16.0);

    // Aperture ring glow
    let ring_glow = radius_band * (0.2 + kick * 0.4 + rms * 0.15);

    // Blade structure glow at the aperture edge
    let blade_structure = blade_edge * radius_band * (0.3 + progress * 0.2);

    let glow_color = mix(accent, highlight, 0.2 + kick * 0.3);

    var result = glow_color * blade_structure;
    result = result + accent * ring_glow;

    // Inner aperture bright center as it opens
    let inner_glow = exp(-center_dist * (8.0 - progress * 4.0)) * progress * 0.12;
    result = result + highlight * inner_glow;

    return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// FRAGMENT MAIN
// ═══════════════════════════════════════════════════════════════════════════════
@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    // ─── Colors ────────────────────────────────────────────────────────────
    let c_bg = #color "scene.bg_color";
    let bg_color = c_bg.rgb;
    let bg_alpha = c_bg.a;

    let c_accent = #color "scene.accent_color";
    let accent = c_accent.rgb;

    let c_highlight = #color "scene.highlight_color";
    let highlight = c_highlight.rgb;

    // ─── Parameters ────────────────────────────────────────────────────────
    let corridor_speed = clamp(#gui_param "scene.corridor_speed".x, 0.3, 2.5);
    let ring_density = clamp(#gui_param "scene.ring_density".x, 0.3, 1.2);
    let strobe_intensity = clamp(#gui_param "scene.strobe_intensity".x, 0.0, 1.5);
    let pressure_depth = clamp(#gui_param "scene.pressure_depth".x, 0.3, 2.0);

    // ─── Audio ─────────────────────────────────────────────────────────────
    let low = saturate_f(av(0u));
    let mid = saturate_f(av(1u));
    let high = saturate_f(av(2u));
    let rms = saturate_f(av(3u));
    let peak = saturate_f(av(4u));
    let beat = held(5u);
    let beat_phase = saturate_f(av(6u));
    let bar_phase = saturate_f(av(7u));
    let impact = held(8u);
    let kick_phase = saturate_f(av(9u));
    let kick_rms_sig = #audio "audio.stem.kicks.rms";
    let kick = kick_rms_sig.value;
    let snare = max(saturate_f(av(11u)), held(11u));
    let hihat = max(saturate_f(av(12u)), held(12u));
    let flux = saturate_f(av(13u));
    let brightness = saturate_f(av(14u));

    // ─── Timeline ──────────────────────────────────────────────────────────
    let progress = story_progress();
    let early = 1.0 - smoothstep(0.15, 0.35, progress);
    let late = smoothstep(0.65, 1.0, progress);
    let t = scene.time;

    // ─── Screen coordinates ────────────────────────────────────────────────
    var scr = vec2<f32>(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    scr.x = scr.x * (scene.resolution.x / scene.resolution.y);

    // Camera shake on impacts
    scr = scr + vec2<f32>(sin(t * 42.0) * impact * 0.01, cos(t * 37.0) * impact * 0.008);


    // ─── Composite ─────────────────────────────────────────────────────────
    let energy = saturate_f(low * 0.3 + mid * 0.2 + rms * 0.2 + kick * 0.2 + flux * 0.1);

    // Layer 1: Void
    var color = render_void(scr, t, progress, low, rms, accent);

    // Layer 2: Corridor structure
    color = color + render_corridor(
        scr, t, progress, corridor_speed, ring_density,
        low, mid, beat_phase, kick, bar_phase,
        accent, highlight
    );

    // Layer 3: Conduit energy
    color = color + render_conduit_energy(scr, t, progress, mid, rms, accent, highlight);

    // Layer 4: Compression waves
    color = color + render_compression_waves(scr, t, low, pressure_depth, kick_phase, accent, highlight);

    // Layer 5: Strobes
    color = color + render_strobes(scr, t, kick, snare, impact, beat, strobe_intensity, accent, highlight);

    // Layer 6: Particles
    color = color + render_particles(scr, t, high, hihat, flux, brightness, accent, highlight);

    // Layer 7: Aperture gate
    color = color + render_aperture_gate(scr, t, progress, rms, low, kick, accent, highlight);

    // ─── Timeline modulation ───────────────────────────────────────────────
    // Early phase: tighter, colder — but still visible
    color = color * mix(0.75, 1.0, 1.0 - early * 0.25);

    // Late phase: full blast
    color = color * (1.0 + late * 0.35);

    // Warmth shift across song
    color = color + vec3<f32>(progress * 0.015, progress * 0.005, 0.0) * energy;

    // ─── Vignette ──────────────────────────────────────────────────────────
    let vig = 1.0 - smoothstep(0.5, 2.4, length(scr * vec2<f32>(0.6, 0.8)));
    color = mix(vec3<f32>(0.0), color, vig);

    // ─── Dither ────────────────────────────────────────────────────────────
    let dither = (hash21(in.uv * scene.resolution.xy + vec2<f32>(t * 7.1, 3.0)) - 0.5) * scene.dither_strength * 0.04;
    color = color + vec3<f32>(dither);

    return encode_output_alpha(color, bg_alpha);
}

