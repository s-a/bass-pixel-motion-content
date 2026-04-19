// ============================================================
// MOLTEN CRUCIBLE — Ultra-Realistic Fluid Magma (Top View)
//
// A volcanic caldera seen from directly above. Plates of
// cooling obsidian crust float atop rivers of incandescent
// lava. Music drives eruption intensity, flow dynamics,
// and surface sparks.
// ============================================================

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

// ---- Hash primitives ----

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let n = sin(vec2(
        dot(p, vec2(127.1, 311.7)),
        dot(p, vec2(269.5, 183.3))
    ));
    return fract(n * 43758.5453);
}

// ---- Value noise with quintic interpolation ----

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(
        mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

// ---- Voronoi convection cells ----

fn voronoi_cells(x: vec2<f32>) -> vec3<f32> {
    let n = floor(x);
    let f = fract(x);
    var d1 = 8.0;
    var d2 = 8.0;
    var cell = 0.0;

    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash22(n + g);
            let r = g - f + o;
            let d = dot(r, r);
            if d < d1 {
                d2 = d1;
                d1 = d;
                cell = hash21(n + g);
            } else if d < d2 {
                d2 = d;
            }
        }
    }
    // x: dist to nearest cell center
    // y: edge factor (dist to 2nd - 1st — small near edges)
    // z: random cell identity
    return vec3<f32>(sqrt(d1), sqrt(d2) - sqrt(d1), cell);
}

// ---- FBM with per-octave rotation (prevents grid artifacts) ----

fn fbm4(p: vec2<f32>) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var pos = p;
    let c = cos(0.8);
    let s = sin(0.8);

    for (var i = 0; i < 4; i++) {
        val += amp * vnoise(pos);
        pos = vec2(pos.x * c - pos.y * s, pos.x * s + pos.y * c) * 2.03;
        amp *= 0.49;
    }
    return val;
}

// ---- Double domain-warped FBM for organic fluid motion ----

fn magma_field(p: vec2<f32>, ft: f32) -> f32 {
    // First warp layer
    let q = vec2<f32>(
        fbm4(p + vec2(1.7, 5.2) + ft * 0.12),
        fbm4(p + vec2(8.3, 2.8) + ft * 0.09)
    );
    // Second warp layer
    let r = vec2<f32>(
        fbm4(p + 4.0 * q + vec2(3.2, 1.3) + ft * 0.07),
        fbm4(p + 4.0 * q + vec2(2.1, 7.9) + ft * 0.11)
    );
    return fbm4(p + 4.0 * r);
}

// ---- Blackbody-inspired magma color ramp ----
// Calibrated to real magma: deep crimson -> orange -> yellow-white

fn blackbody_magma(temp: f32) -> vec3<f32> {
    let t = saturate(temp);
    // Gradual: deep crimson at low heat -> orange midrange -> yellow-white at extreme
    let r = smoothstep(0.03, 0.3, t);
    let g = smoothstep(0.2, 0.7, t) * 0.65;
    let b = smoothstep(0.65, 1.0, t) * 0.2;
    // Smooth exponential emission: dim glow at low temp, intense at peak
    let emission = pow(t, 2.0) * 3.5;
    return vec3<f32>(r, g, b) * (0.03 + emission);
}

// ---- Fragment shader ----

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    // --- UV with aspect correction ---
    let raw_uv = in.uv;
    var uv = in.uv * 2.0 - 1.0;
    let aspect = scene.resolution.x / max(scene.resolution.y, 1.0);
    uv.x *= aspect;

    // --- Color bindings (two-line pattern per contract) ---
    let col_magma = #color "magma_color";
    let col_crust = #color "crust_color";
    let col_glow = #color "glow_color";
    let col_bg = #color "bg_color";

    // --- Audio bindings ---
    let a_low = #audio "audio.band.low";
    let bass = a_low.clamped_safe;

    let a_rms = #audio "audio.rms";
    let rms = a_rms.clamped_safe;

    let a_kick = #audio "audio.stem.kicks.peak";
    let kick = a_kick.value; // raw for explosive eruption peaks

    let a_phase = #audio "audio.rhythm.beat_phase";
    let beat_phase = a_phase.clamped_safe;

    let a_mid = #audio "audio.band.mid";
    let mid = a_mid.clamped_safe;

    let a_high = #audio "audio.band.high";
    let high = a_high.clamped_safe;

    // --- Timing ---
    let t = scene.time;
    let progress = scene.timeline.z;

    // --- GUI params ---
    let flow_speed = (#gui_param "flow_speed").x;
    let heat = (#gui_param "heat_intensity").x;
    let crust_sc = (#gui_param "crust_scale").x;
    let turb = (#gui_param "turbulence").x;

    let flow_t = t * flow_speed * 0.4;
    let center_dist = length(uv);

    // ==========================================================
    // LAYER 1 — Voronoi convection cell structure
    // ==========================================================
    let cell_scale = 2.5 * crust_sc;
    // Slow convective rotation for realistic drift
    let conv_a = flow_t * 0.08;
    let ca = cos(conv_a);
    let sa = sin(conv_a);
    let cell_uv = vec2<f32>(
        uv.x * ca - uv.y * sa,
        uv.x * sa + uv.y * ca
    ) * cell_scale;

    let vor = voronoi_cells(cell_uv + flow_t * 0.15);
    let cell_dist = vor.x;  // distance to cell center
    let edge_dist = vor.y;  // small near cell boundaries
    let cell_id = vor.z;    // random per-cell identity

    // Crack intensity — sharp exponential falloff from boundaries.
    // edge_dist is small at cell edges. This creates thin, bright cracks.
    let crack_sharpness = 8.0 + turb * 4.0;
    let crack = exp(-edge_dist * crack_sharpness);

    // Cell interior darkness — plates are cool obsidian, only edges glow.
    // cell_dist grows from 0 at center to ~0.5 at edge.
    // We want inner regions to be solidified (cold).
    let plate_solidity = smoothstep(0.05, 0.25, edge_dist);

    // ==========================================================
    // LAYER 2 — Flowing magma under the crust
    // ==========================================================
    let magma_uv = uv * (1.5 + turb * 0.5);
    let magma_val = magma_field(magma_uv, flow_t);

    // Fine detail noise for crust surface texture
    let detail = fbm4(uv * 8.0 + flow_t * 0.2);

    // ==========================================================
    // LAYER 3 — Temperature field assembly
    // ==========================================================
    // Temperature is HIGH in cracks (exposed magma) and LOW on plates (cooled crust).
    // The crack function already does this: high near edges, low in cell interior.

    // Primary: crack glow (the rivers of lava between plates)
    var temp = crack * 0.85;

    // Subsurface glow: magma visible dimly through thin crust areas
    // Only shows at edges and where noise thins the crust
    let subsurface = magma_val * 0.15 * (1.0 - plate_solidity * 0.8);
    temp += subsurface;

    // Per-cell random temperature: some plates are recently solidified (warmer)
    let cell_warmth = cell_id * 0.12;
    temp += cell_warmth * (1.0 - plate_solidity) * 0.3;

    // Thin crust hotspots where magma almost breaks through
    let hotspot = smoothstep(0.55, 0.7, detail) * (1.0 - plate_solidity) * 0.2;
    temp += hotspot;

    // ==========================================================
    // LAYER 4 — Audio reactivity (fragment-only, no geometry)
    // ==========================================================
    // Bass: global magma heat pump — raises temperature everywhere
    temp += bass * 0.15 * heat;

    // Kick: concentric eruption shockwave from center
    let wave_r = beat_phase * 2.5;
    let wave_w = 0.25 + saturate(kick) * 0.15;
    let eruption_wave = exp(-pow(center_dist - wave_r, 2.0) / (wave_w * wave_w));
    temp += saturate(kick) * eruption_wave * 0.4;

    // Mids: localized surface disturbance along existing cracks
    let mid_heat = vnoise(uv * 12.0 + t * 1.5) * mid * 0.12 * crack;
    temp += mid_heat;

    // Scale by heat parameter
    temp *= heat;
    temp = saturate(temp);

    // ==========================================================
    // LAYER 5 — Song progress motif: Obsidian Rim
    // ==========================================================
    // A rim of solidified obsidian grows inward as the song progresses.
    // Start: fully open molten field. End: narrow molten eye of fire.
    let rim_base = mix(2.2, 0.45, smoothstep(0.0, 0.9, progress));
    // Jagged noise edge for geological realism
    let rim_noise = fbm4(uv * 3.0 + vec2(0.0, flow_t * 0.05)) * 0.35;
    let rim_radius = rim_base + rim_noise;
    let rim_mask = smoothstep(rim_radius - 0.12, rim_radius + 0.04, center_dist);

    // Rim cools temperature drastically
    temp *= (1.0 - rim_mask * 0.95);
    // Faint fissures glow through the obsidian rim
    let rim_fissures = fbm4(uv * 14.0 + t * 0.03) * rim_mask * 0.04;
    temp += rim_fissures;

    // ==========================================================
    // COLOR COMPOSITING
    // ==========================================================

    // --- Crust layer (cool obsidian surface with micro-texture) ---
    let crust_noise = fbm4(uv * 18.0) * 0.4 + 0.6;
    let crust_rough = vnoise(uv * 35.0) * 0.25 + 0.75;
    let crust_base = col_crust.rgb * crust_noise * crust_rough;
    // Per-cell variation and warm residual heat undertone
    let crust_warmth = col_magma.rgb * 0.03 * (1.0 - plate_solidity * 0.5);
    let crust_darkened = crust_base * (0.35 + cell_id * 0.45) + crust_warmth;

    // --- Magma layer (glowing lava in cracks) ---
    let bb = blackbody_magma(temp);
    // Blend blackbody with user magma color for artistic control
    let magma_tinted = mix(bb, col_magma.rgb * (0.5 + temp * 3.0), 0.3);

    // --- Composite: crust on top, magma visible in cracks ---
    // plate_solidity is high inside cells (cool), low at edges (hot)
    // temp drives the overall blending
    let magma_reveal = smoothstep(0.05, 0.25, temp);
    var color = mix(crust_darkened, magma_tinted, magma_reveal);

    // --- Glow accent in the hottest zones ---
    let glow_mask = smoothstep(0.5, 0.85, temp);
    color += col_glow.rgb * glow_mask * 0.8;

    // --- HDR bloom seeds: white-hot core in the most extreme cracks ---
    let white_hot = smoothstep(0.8, 1.0, temp);
    color += vec3<f32>(1.0, 0.95, 0.8) * white_hot * 0.5;

    // --- High-frequency sparks driven by hi-hats/highs ---
    let spark = vnoise(uv * 50.0 + t * 3.0);
    let spark_mask = smoothstep(0.94, 0.99, spark) * high * 1.2;
    color += col_glow.rgb * spark_mask;

    // --- Ember particles floating on the surface ---
    let ember_cell = floor(uv * 14.0);
    let ember_phase = fract(hash21(ember_cell) + t * 0.25);
    let ember_offset = hash22(ember_cell) - fract(uv * 14.0);
    let ember_dot = smoothstep(0.08, 0.0, length(ember_offset));
    let ember_life = smoothstep(1.0, 0.6, ember_phase) * smoothstep(0.0, 0.15, ember_phase);
    color += col_glow.rgb * ember_dot * ember_life * high * 0.5;

    // --- RMS-driven global emission ---
    color *= (0.85 + rms * 0.3);

    // ==========================================================
    // FINISHING PASSES
    // ==========================================================

    // Subsurface scattering halo — warm glow around crack edges
    let sss_band = smoothstep(0.03, 0.15, temp) * (1.0 - smoothstep(0.15, 0.35, temp));
    color += col_magma.rgb * sss_band * 0.08;

    // Heat shimmer — subtle luminance ripple in hot regions
    let shimmer = sin(uv.x * 30.0 + t * 4.0) * sin(uv.y * 30.0 + t * 3.7);
    color += vec3<f32>(0.5, 0.3, 0.1) * shimmer * 0.015 * temp;

    // Cinematic vignette
    let vig_d = length(raw_uv - 0.5) * 1.5;
    let vignette = 1.0 - smoothstep(0.45, 1.15, vig_d);
    color *= mix(0.15, 1.0, vignette);

    // Obsidian rim inner glow — faint magma shimmer at the boundary
    let rim_glow_band = smoothstep(0.18, 0.0, abs(center_dist - rim_radius)) * rim_mask;
    color += col_magma.rgb * rim_glow_band * 0.25 * (0.4 + bass * 0.6);

    return encode_output_alpha(color, col_bg.a);
}
