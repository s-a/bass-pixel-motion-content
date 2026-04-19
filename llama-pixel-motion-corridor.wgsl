
#import <engine::bpm_kernel_bindings>



const TAU: f32 = 6.28318530718;
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
    var peak = 0.0;
    for (var sample_index = 0u; sample_index < sample_count; sample_index = sample_index + 1u) {
        let age = f32(sample_count - 1u - sample_index);
        let decayed = max(0.0, audio_history_value(index, sample_index) - max(age - 3.0, 0.0) * 0.05);
        peak = max(peak, decayed);
    }
    return clamp(peak, 0.0, 1.0);
}

fn saturate(x: f32) -> f32 {
    return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0, 3.0) - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var q = p;
    for (var i: i32 = 0; i < 4; i = i + 1) {
        value = value + amplitude * noise(q);
        q = q * 2.03 + vec2<f32>(3.3, 1.7);
        amplitude = amplitude * 0.5;
    }
    return value;
}

fn band(index: u32) -> f32 {
    return saturate(av(12u + index));
}

fn rect_alpha(point: vec2<f32>, center: vec2<f32>, half_size: vec2<f32>, feather: f32) -> f32 {
    let q = abs(point - center) - half_size;
    let dist = length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0);
    return 1.0 - smoothstep(0.0, feather, dist);
}

fn story_progress() -> f32 {
    return saturate(scene.timeline.z);
}

fn background_layer(
    scr: vec2<f32>,
    t: f32,
    progress: f32,
    energy: f32,
    bright: f32,
    bg_color: vec3<f32>,
    ice_color: vec3<f32>,
) -> vec3<f32> {
    let fog = fbm(scr * vec2<f32>(1.8, 2.8) + vec2<f32>(0.0, -t * 0.03));
    let dust = fbm(scr * 6.0 + vec2<f32>(t * 0.04, t * 0.02));
    let radius = length(scr * vec2<f32>(0.7, 1.0));
    let vignette = exp(-radius * 1.4);
    let roll = exp(-abs(fract((scr.y + t * 0.03) * 8.0) - 0.5) * 24.0) * 0.02;
    let columns = exp(-abs(fract(scr.x * 3.5 + 0.5) - 0.5) * 34.0) * (1.0 - smoothstep(-0.4, 0.46, scr.y)) * 0.03;
    let base = bg_color * (0.52 + vignette * 0.68) + vec3<f32>(0.002, 0.004, 0.008);
    let mist = mix(bg_color, ice_color, 0.16 + bright * 0.18) * smoothstep(0.26, 0.82, fog) * (0.16 + energy * 0.14);
    let sparkles = vec3<f32>(dust) * 0.028 * (0.4 + bright * 0.6);
    return base + mist + sparkles + ice_color * (roll + columns);
}

fn runway_layer(
    scr: vec2<f32>,
    horizon: f32,
    progress: f32,
    runway_width: f32,
    pulse: f32,
    phosphor_color: vec3<f32>,
    ice_color: vec3<f32>,
) -> vec3<f32> {
    var color = vec3<f32>(0.0);

    for (var i: i32 = 0; i < 24; i = i + 1) {
        let z = f32(i) / 23.0;
        let y = mix(horizon - 0.015, -0.96, pow(z, 1.66));
        let half_width = mix(0.035, runway_width, pow(z, 1.16));
        let reach = smoothstep(z - 0.09, z + 0.02, progress);
        let slice_thickness = mix(0.0018, 0.016, pow(z, 1.7));
        let stripe = exp(-abs(scr.y - y) / slice_thickness);
        let edge = exp(-abs(abs(scr.x) - half_width) * mix(240.0, 54.0, z));
        let center_dash = exp(-abs(scr.x) * mix(180.0, 42.0, z)) * stripe * (0.12 + pulse * 0.12);
        let tint = mix(phosphor_color, ice_color, 0.36 + z * 0.42);
        color = color + tint * reach * edge * (0.06 + pulse * 0.08);
        color = color + tint * reach * stripe * (0.08 + z * 0.1);
        color = color + mix(phosphor_color, ice_color, 0.7) * reach * center_dash;
    }

    let wall_guides = exp(-abs(abs(scr.x) - runway_width * 1.26) * 18.0)
        * (1.0 - smoothstep(-0.96, horizon, scr.y))
        * (0.03 + progress * 0.08);
    return color + ice_color * wall_guides;
}

fn pillar_pair(
    scr: vec2<f32>,
    x_center: f32,
    base_y: f32,
    width: f32,
    height: f32,
    tint: vec3<f32>,
    pulse: f32,
) -> vec3<f32> {
    let center = vec2<f32>(x_center, base_y + height * 0.5);
    let alpha = rect_alpha(scr, center, vec2<f32>(width, height * 0.5), 0.012 + width * 0.24);
    let glow = rect_alpha(scr, center, vec2<f32>(width * 1.8, height * 0.56 + 0.02), 0.07);
    let cap = exp(-abs(scr.y - (base_y + height)) * 120.0) * exp(-abs(scr.x - x_center) * 48.0);
    return tint * alpha * (0.22 + pulse * 0.16)
        + tint * glow * 0.06
        + mix(tint, vec3<f32>(1.0, 0.98, 0.9), 0.3) * cap * 0.12;
}

fn corridor_pillars(
    scr: vec2<f32>,
    horizon: f32,
    pillar_height: f32,
    t: f32,
    progress: f32,
    pulse: f32,
    bright: f32,
    phosphor_color: vec3<f32>,
    ice_color: vec3<f32>,
) -> vec3<f32> {
    var color = vec3<f32>(0.0);

    for (var i = 0u; i < 8u; i = i + 1u) {
        let z = f32(i) / 7.0;
        let depth = pow(z, 1.18);
        let base_y = mix(horizon - 0.005, -0.96, pow(z, 1.58));
        let x_center = mix(0.12, 1.26, depth);
        let width = mix(0.01, 0.12, pow(z, 1.26));
        let left_value = band(i);
        let right_value = band(i + 8u);
        let scale = mix(0.24, 1.0, depth);
        
        // Removed minimum stub, doubled the reactivity to make them spike dramatically (Vollausschlag)
        let left_height = (left_value * pillar_height * 2.2 + pulse * 0.06) * scale;
        let right_height = (right_value * pillar_height * 2.2 + pulse * 0.06) * scale;
        
        let shimmer = 0.8 + 0.2 * sin(t * 0.8 + f32(i) * 0.7 + bright * 2.0);
        let left_tint = mix(phosphor_color, ice_color, 0.22 + depth * 0.48) * shimmer;
        let right_tint = mix(phosphor_color, ice_color, 0.42 + depth * 0.44) * shimmer;
        let progress_gate = smoothstep(0.0, 0.16 + z * 0.1, progress + 0.18);
        
        // Main pillars going UP
        color = color + pillar_pair(scr, -x_center, base_y, width, left_height, left_tint, pulse) * progress_gate;
        color = color + pillar_pair(scr, x_center, base_y, width, right_height, right_tint, pulse) * progress_gate;
        
        // Let them hit the floor! (Reflection extending DOWN into the glass floor)
        color = color + pillar_pair(scr, -x_center, base_y - left_height, width, left_height, left_tint, pulse) * progress_gate * 0.25;
        color = color + pillar_pair(scr, x_center, base_y - right_height, width, right_height, right_tint, pulse) * progress_gate * 0.25;
    }

    return color;
}

fn vector_runner(
    scr: vec2<f32>,
    horizon: f32,
    progress: f32,
    corridor_depth: f32,
    t: f32,
    pulse: f32,
    phosphor_color: vec3<f32>,
    ice_color: vec3<f32>,
) -> vec3<f32> {
    let sample_count = audio_history_samples();
    let denom = max(f32(sample_count - 1u), 1.0);
    var color = vec3<f32>(0.0);

    for (var sample_index = 0u; sample_index < AUDIO_HISTORY_MAX_SAMPLES; sample_index = sample_index + 1u) {
        if sample_index >= sample_count {
            continue;
        }

        let trail = f32(sample_index) / denom;
        let fresh = pow(trail, 0.88);
        let low_h = saturate(audio_history_value(0u, sample_index));
        let mid_h = saturate(audio_history_value(1u, sample_index));
        let high_h = saturate(audio_history_value(2u, sample_index));
        let rms_h = saturate(audio_history_value(3u, sample_index));
        let beat_h = saturate(audio_history_value(5u, sample_index));

        let y = mix(horizon + 0.01, -0.94, pow(fresh, 1.22));
        let swing = sin(trail * TAU * (1.5 + progress * 2.8) + t * (0.56 + high_h * 0.42) + low_h * 1.6);
        let wobble = sin(trail * TAU * 6.0 - t * 0.24) * 0.03 * high_h;
        let x = (swing * (0.12 + mid_h * 0.32 + rms_h * 0.12) * mix(0.3, corridor_depth * 1.18, fresh)) + wobble;
        let point = vec2<f32>(x, y);
        let ghost = vec2<f32>(x * 0.46 + sin(t * 0.7 + trail * 10.0) * 0.03, y + 0.02 + high_h * 0.02);
        let dist_main = length(scr - point);
        let dist_ghost = length(scr - ghost);
        let beam = exp(-dist_main * (86.0 + high_h * 34.0 + fresh * 28.0));
        let after = exp(-dist_ghost * (54.0 + mid_h * 18.0));
        let spark = exp(-dist_main * 220.0) * (0.12 + beat_h * 0.34 + pulse * 0.14);
        let sweep = exp(-abs(scr.y - y) * 90.0) * exp(-abs(scr.x - x) * 12.0) * (0.014 + rms_h * 0.024);
        let tint = mix(phosphor_color, ice_color, 0.2 + fresh * 0.68);
        color = color + tint * beam * (0.028 + rms_h * 0.07 + fresh * 0.05);
        color = color + mix(phosphor_color, ice_color, 0.82) * after * (0.008 + high_h * 0.03);
        color = color + mix(ice_color, vec3<f32>(1.0, 0.98, 0.9), 0.28) * spark * 0.06;
        color = color + mix(phosphor_color, ice_color, 0.36) * sweep;
    }

    let spine = exp(-abs(scr.x) * 110.0) * (1.0 - smoothstep(-0.96, horizon, scr.y)) * (0.008 + progress * 0.02);
    return color + mix(phosphor_color, ice_color, 0.3) * spine;
}

fn horizon_gate(
    scr: vec2<f32>,
    horizon: f32,
    progress: f32,
    pulse: f32,
    bright: f32,
    phosphor_color: vec3<f32>,
    ice_color: vec3<f32>,
) -> vec3<f32> {
    let aspect = scene.resolution.x / scene.resolution.y;
    let width = mix(0.09, aspect * 0.88, progress);
    let gate = rect_alpha(scr, vec2<f32>(0.0, horizon + 0.06), vec2<f32>(width, 0.03 + bright * 0.02), 0.04);
    let glow = rect_alpha(scr, vec2<f32>(0.0, horizon + 0.06), vec2<f32>(width * 1.16, 0.08 + bright * 0.03), 0.11);
    let ray = exp(-abs(scr.x) * 44.0) * exp(-abs(scr.y - (horizon + 0.05)) * 18.0) * (0.02 + pulse * 0.05);
    return mix(phosphor_color, ice_color, 0.72) * gate * (0.22 + pulse * 0.16)
        + ice_color * glow * 0.08
        + mix(ice_color, vec3<f32>(1.0, 0.98, 0.9), 0.22) * ray;
}

fn scanline_overlay(color: vec3<f32>, uv: vec2<f32>, t: f32, mix_amount: f32) -> vec3<f32> {
    let scan = 0.94 + 0.06 * sin(uv.y * scene.resolution.y * 1.15 + t * 7.0);
    let mask = vec3<f32>(
        0.97 + 0.03 * sin(uv.x * scene.resolution.x * 0.94),
        0.97 + 0.03 * sin(uv.x * scene.resolution.x * 0.94 + 2.1),
        0.97 + 0.03 * sin(uv.x * scene.resolution.x * 0.94 + 4.2),
    );
    return color * mix(vec3<f32>(1.0), mask * scan, mix_amount);
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let c1 = #color "scene.color_phosphor";
    let phosphor_color = c1.rgb;
    let c2 = #color "scene.color_ice";
    let ice_color = c2.rgb;
    let bg = #color "scene.bg_color";
    let bg_color = bg.rgb;
    let bg_alpha = bg.a;
    let corridor_depth = clamp(#gui_param "scene.corridor_depth".x, 0.65, 1.65);
    let pillar_height = clamp(#gui_param "scene.pillar_height".x, 0.24, 0.6);
    let runway_width = clamp(#gui_param "scene.runway_width".x, 0.12, 0.75);
    let scanline_mix = clamp(#gui_param "scene.scanline_mix".x, 0.0, 1.0);
    let pulse_gain = clamp(#gui_param "scene.pulse_gain".x, 0.4, 2.2);

    let low = saturate(av(0u));
    let mid = saturate(av(1u));
    let high = saturate(av(2u));
    let rms = saturate(av(3u));
    let peak = saturate(av(4u));
    let bright = saturate(av(7u));
    let flux = saturate(av(8u));
    let kick_rms_sig = #audio "audio.stem.kicks.rms";
    let kick = kick_rms_sig.value;
    let snare = max(saturate(av(10u)), held(10u));
    let _hat = max(saturate(av(11u)), held(11u));
    let beat = held(5u);
    let impact = held(6u);

    let progress = story_progress();
    let early = 1.0 - smoothstep(0.18, 0.42, progress);
    let late = smoothstep(0.62, 1.0, progress);
    let energy = saturate(low * 0.24 + mid * 0.18 + rms * 0.18 + kick * 0.34 + flux * 0.08);
    let pulse = saturate((beat * 0.32 + impact * 0.44 + kick * 0.72 + snare * 0.24 + peak * 0.16) * pulse_gain);
    let t = scene.time;

    var scr = vec2<f32>(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    scr.x = scr.x * (scene.resolution.x / scene.resolution.y);
    let horizon = 0.16 + early * 0.06 - low * 0.03;



    var color = background_layer(scr, t, progress, energy, bright, bg_color, ice_color);
    
    // Mask out the dark background if bg_alpha is transparent, but keep the glow
    color = mix(color - (bg_color * 0.52), color, bg_alpha);

    color = color + runway_layer(scr, horizon, progress, runway_width, pulse, phosphor_color, ice_color);
    color = color + corridor_pillars(scr, horizon, pillar_height, t, progress, pulse, bright, phosphor_color, ice_color);
    color = color + vector_runner(scr, horizon, progress, corridor_depth, t, pulse, phosphor_color, ice_color);
    color = color + horizon_gate(scr, horizon, progress, pulse, bright, phosphor_color, ice_color);

    let far_bloom = exp(-abs(scr.y - (horizon + 0.03)) * 10.0) * exp(-abs(scr.x) * 2.8) * (0.04 + late * 0.1);
    let impact_flash = exp(-length(scr - vec2<f32>(0.0, horizon + 0.02)) * 16.0) * (0.04 + impact * 0.16);
    let side_fog = exp(-abs(abs(scr.x) - (runway_width * 1.4 + 0.18)) * 4.0) * (1.0 - smoothstep(-0.96, horizon, scr.y)) * 0.06;

    color = color + mix(phosphor_color, ice_color, 0.62) * far_bloom;
    color = color + mix(ice_color, vec3<f32>(1.0, 0.98, 0.9), 0.24) * impact_flash;
    color = color + mix(bg_color * side_fog * bg_alpha, vec3<f32>(0.0), 1.0 - bg_alpha); // side fog scales with alpha

    let vignette = 1.0 - smoothstep(0.26, 2.0, length(scr * vec2<f32>(0.7, 1.0)));
    color = mix(mix(bg_color * 0.14, vec3<f32>(0.0), 1.0 - bg_alpha), color, vignette); // vignette is transparent when bg_alpha is 0
    color = color * mix(0.72, 1.0, 1.0 - early * 0.22);
    color = color * mix(0.96, 1.12, late * 0.6);
    color = scanline_overlay(color, in.uv, t, scanline_mix * 0.68);

    return encode_output_alpha(color, bg_alpha);
}


