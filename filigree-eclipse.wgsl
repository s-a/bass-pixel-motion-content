
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

fn audio_peak_hold(index: u32) -> f32 {
    let sample_count = audio_history_samples();
    var peak = 0.0;
    for (var sample_index = 0u; sample_index < sample_count; sample_index = sample_index + 1u) {
        let age = f32(sample_count - 1u - sample_index);
        let decayed = max(0.0, audio_history_value(index, sample_index) - max(age - 4.0, 0.0) * 0.042);
        peak = max(peak, decayed);
    }
    return clamp(peak, 0.0, 1.0);
}

fn saturate(x: f32) -> f32 {
    return clamp(x, 0.0, 1.0);
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
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
        q = rot(0.58) * q * 2.03 + vec2<f32>(4.2, 1.7);
        amplitude = amplitude * 0.5;
    }
    return value;
}

fn phase_from_angle(angle: f32) -> f32 {
    return fract(angle / TAU + 0.25 + 1.0);
}

fn phase_distance(a: f32, b: f32) -> f32 {
    let d = abs(a - b);
    return min(d, 1.0 - d);
}

fn arc_progress_gate(phase: f32, progress: f32) -> f32 {
    return smoothstep(-0.004, 0.006, progress - phase);
}

fn background_layer(
    uv: vec2<f32>,
    t: f32,
    progress: f32,
    energy: f32,
    bright: f32,
    mist_color: vec3<f32>,
    trim_color: vec3<f32>,
) -> vec3<f32> {
    let drift = rot(0.08 * t + progress * 0.7) * uv;
    let n1 = fbm(drift * (1.6 + energy * 0.5) + vec2<f32>(t * 0.025, -t * 0.016));
    let n2 = fbm(rot(-0.54) * drift * (3.0 + bright * 1.4) - vec2<f32>(0.0, t * 0.04));
    let radius = length(uv);
    let haze = smoothstep(0.22, 0.84, mix(n1, n2, 0.5));
    let vignette = exp(-radius * (1.02 - progress * 0.16));
    let base = mist_color * (0.38 + vignette * 0.75) + vec3<f32>(0.004, 0.004, 0.006);
    let bloom = mix(mist_color, trim_color, 0.22 + bright * 0.26) * haze * vignette * (0.14 + energy * 0.24);
    return base + bloom;
}

fn halo_scaffold(radius: f32, main_radius: f32, halo_width: f32, progress: f32) -> f32 {
    let band = exp(-abs(radius - main_radius) / max(halo_width * 0.72, 0.001));
    return band * mix(0.08, 0.16, 1.0 - smoothstep(0.0, 0.28, progress));
}

fn progress_halo(
    radius: f32,
    phase: f32,
    progress: f32,
    main_radius: f32,
    halo_width: f32,
    pulse: f32,
    kick_flash: f32,
) -> vec3<f32> {
    let band = exp(-abs(radius - main_radius) / max(halo_width * 0.52, 0.001));
    let core = exp(-abs(radius - main_radius) / max(halo_width * 0.18, 0.001));
    let completed = arc_progress_gate(phase, progress);
    let head = exp(-phase_distance(phase, progress) * (210.0 + kick_flash * 120.0))
        * exp(-abs(radius - main_radius) * (84.0 + kick_flash * 42.0));
    let aura = exp(-phase_distance(phase, progress) * 54.0)
        * exp(-abs(radius - (main_radius + halo_width * 0.7)) * 28.0);
    return vec3<f32>(
        band * completed * (0.46 + pulse * 0.52),
        core * completed * (0.86 + pulse * 0.5),
        head * (1.05 + pulse * 0.7) + aura * (0.18 + pulse * 0.16)
    );
}

fn halo_filaments(
    radius: f32,
    phase: f32,
    t: f32,
    progress: f32,
    density: f32,
    high: f32,
    hat_flash: f32,
) -> f32 {
    let complexity = smoothstep(0.1, 0.96, progress);
    var sum = 0.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        let fi = f32(i);
        let ring_radius = 0.43 + fi * 0.07 + sin(t * (0.09 + fi * 0.015) + fi * 1.4) * 0.006;
        let band = exp(-abs(radius - ring_radius) * (126.0 + fi * 18.0));
        let weave = pow(
            saturate(
                0.5 + 0.5 * cos(
                    TAU * phase * (density * (1.1 + fi * 0.26) + 4.0)
                    + radius * (18.0 + fi * 6.0)
                    - t * (0.24 + high * 0.8 + hat_flash * 1.6)
                )
            ),
            8.0 + fi * 2.0,
        );
        let lace = pow(
            saturate(
                0.5 + 0.5 * sin(
                    TAU * phase * (density * 3.2 + fi * 2.4)
                    - radius * 42.0
                    + t * (0.3 + hat_flash * 2.6)
                )
            ),
            14.0,
        );
        let gate = arc_progress_gate(phase, progress + fi * 0.004);
        sum = sum + band * gate * (0.18 + 0.72 * weave + 0.14 * lace);
    }
    return sum * mix(0.03, 0.46, complexity);
}

fn radial_ornaments(
    radius: f32,
    angle: f32,
    phase: f32,
    t: f32,
    progress: f32,
    density: f32,
    snare_flash: f32,
    hat_flash: f32,
) -> f32 {
    let spokes = density * 1.8 + 14.0 + snare_flash * 10.0;
    let spoke_wave = pow(
        saturate(0.5 + 0.5 * cos(angle * spokes - radius * 9.0 + t * (0.2 + snare_flash * 3.4))),
        11.0,
    );
    let micro = pow(
        saturate(0.5 + 0.5 * sin(angle * (spokes * 2.2) + radius * 36.0 - t * (0.7 + hat_flash * 4.0))),
        15.0,
    );
    let gate = smoothstep(0.34, 0.76, radius) * (1.0 - smoothstep(1.1, 1.42, radius));
    let progress_gate = mix(0.2, 1.0, arc_progress_gate(phase, progress));
    return gate * (spoke_wave + micro * 0.16) * progress_gate * (0.08 + snare_flash * 0.42 + hat_flash * 0.24);
}

fn progress_ticks(
    radius: f32,
    phase: f32,
    main_radius: f32,
    progress: f32,
    density: f32,
) -> f32 {
    let tick_band = exp(-abs(radius - (main_radius - 0.034)) * 180.0);
    let tick_wave = pow(saturate(0.5 + 0.5 * cos(TAU * phase * (density * 2.6 + 26.0))), 22.0);
    let finished = mix(0.24, 1.0, arc_progress_gate(phase, progress));
    return tick_band * tick_wave * finished * 0.28;
}

fn light_architecture(
    uv: vec2<f32>,
    t: f32,
    progress: f32,
    density: f32,
    arch_height: f32,
    bass_low: f32,
    mid: f32,
    pulse: f32,
) -> f32 {
    let rise = mix(0.16, arch_height, smoothstep(0.0, 1.0, progress));
    let spacing = mix(0.19, 0.1, progress * 0.75);
    var sum = 0.0;

    for (var i: i32 = 0; i < 5; i = i + 1) {
        let fi = f32(i);
        let x = (fi - 2.0) * spacing;
        let column = exp(-abs(uv.x - x) * (176.0 + fi * 22.0 + pulse * 52.0));
        let column_gate = smoothstep(-1.08, -0.92, uv.y) * (1.0 - smoothstep(rise - fi * 0.05, rise - fi * 0.05 + 0.08, uv.y));
        let shimmer = 0.74 + 0.26 * sin(t * (0.56 + mid * 0.7) + fi * 0.92 + uv.y * 11.0);
        sum = sum + column * column_gate * shimmer * (0.18 + bass_low * 0.52);

        let arch_radius = 0.26 + fi * 0.088 + progress * 0.045;
        let arch_center_y = -0.86 + fi * 0.07;
        let upper = max(uv.y - arch_center_y, 0.0);
        let arch = exp(-abs(length(vec2<f32>(uv.x, upper)) - arch_radius) * (136.0 + fi * 20.0));
        let arch_gate = smoothstep(arch_center_y, arch_center_y + 0.016, uv.y)
            * (1.0 - smoothstep(rise + 0.02, rise + 0.2, uv.y));
        let tracery = pow(
            saturate(0.5 + 0.5 * cos(uv.x * (density * 9.0 + fi * 4.0) + uv.y * 12.0 - t * 0.22)),
            6.0,
        );
        sum = sum + arch * arch_gate * (0.1 + 0.22 * tracery) * (0.34 + progress * 0.74);
    }

    let spine = exp(-abs(uv.x) * (170.0 + pulse * 54.0))
        * smoothstep(-1.06, -0.9, uv.y)
        * (1.0 - smoothstep(rise + 0.03, rise + 0.12, uv.y));
    return sum + spine * (0.18 + pulse * 0.4);
}

fn inner_tracery(
    uv: vec2<f32>,
    t: f32,
    progress: f32,
    density: f32,
    snare_flash: f32,
    hat_flash: f32,
) -> f32 {
    let gate = smoothstep(-0.82, -0.12, uv.y) * (1.0 - smoothstep(0.2, 0.66, length(uv + vec2<f32>(0.0, 0.06))));
    let ribs = pow(
        saturate(0.5 + 0.5 * cos(uv.x * (density * 8.4 + 22.0) - t * (0.14 + hat_flash * 1.2))),
        18.0,
    );
    let mid_arch = exp(-abs(length(vec2<f32>(uv.x * 1.28, max(uv.y + 0.18, 0.0))) - 0.22) * 118.0);
    let lower_arch = exp(-abs(length(vec2<f32>(uv.x * 1.56, max(uv.y + 0.34, 0.0))) - 0.17) * 132.0);
    let shimmer = 0.82 + 0.18 * sin(t * 0.22 + uv.y * 8.0 + snare_flash * 2.0);
    return gate * (ribs * 0.14 + mid_arch * 0.22 + lower_arch * 0.18) * shimmer * smoothstep(0.08, 1.0, progress);
}

fn interior_haze(
    radius: f32,
    t: f32,
    low: f32,
    bright: f32,
    flux: f32,
) -> f32 {
    let swirl = fbm(vec2<f32>(radius * 8.0 - t * 0.08, radius * 3.0 + bright * 2.8 + flux * 3.6));
    let gate = 1.0 - smoothstep(0.22, 0.86, radius);
    return smoothstep(0.28, 0.84, swirl) * gate * (0.12 + low * 0.2 + bright * 0.12);
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let c1 = #color "scene.color_core";
    let core_color = c1.rgb;
    let c2 = #color "scene.color_trim";
    let trim_color = c2.rgb;
    let c3 = #color "scene.color_mist";
    let mist_color = c3.rgb;
    let halo_width = clamp(#gui_param "scene.halo_width".x, 0.015, 0.08);
    let density = clamp(#gui_param "scene.filigree_density".x, 4.0, 20.0);
    let arch_height = clamp(#gui_param "scene.arch_height".x, 0.2, 1.0);
    let pulse_gain = clamp(#gui_param "scene.pulse_gain".x, 0.4, 2.2);

    let low = saturate(av(0u));
    let mid = saturate(av(1u));
    let high = saturate(av(2u));
    let rms = saturate(av(3u));
    let peak = saturate(av(4u));
    let beat = saturate(av(5u));
    let impact = saturate(av(6u));
    let bright = saturate(av(7u));
    let flux = saturate(av(8u));
    let kick_peak = saturate(av(9u));
    let snare_peak = saturate(av(10u));
    let hihat_peak = saturate(av(11u));
    let bass_low = saturate(av(12u));

    let beat_flash = audio_peak_hold(5u);
    let impact_flash = audio_peak_hold(6u);
    let kick_flash = max(audio_peak_hold(9u), kick_peak);
    let snare_flash = max(audio_peak_hold(10u), snare_peak);
    let hat_flash = max(audio_peak_hold(11u), hihat_peak);

    let pulse = saturate((beat_flash * 0.42 + impact_flash * 0.54 + kick_flash * 0.72 + peak * 0.18) * pulse_gain);
    let progress = saturate(scene.timeline.z);
    let complexity = smoothstep(0.12, 1.0, progress);
    let opening_tension = 1.0 - smoothstep(0.14, 0.4, progress);
    let finale = smoothstep(0.62, 1.0, progress);
    let energy = saturate(low * 0.24 + mid * 0.16 + rms * 0.18 + kick_flash * 0.38);
    let t = scene.time;

    var uv = in.uv * 2.0 - vec2<f32>(1.0, 1.0);
    uv.x = uv.x * (scene.resolution.x / scene.resolution.y);
    let base_uv = uv;

    let kick_phase_sig = #audio "audio.rhythm.kick_phase";
    let phase_sig = kick_phase_sig.clamped_safe;
    let rhythmic_spin = sin(phase_sig * 3.14159) * 0.06;
    uv = rot(t * 0.014 + snare_flash * 0.08 + hat_flash * 0.02 + rhythmic_spin) * uv;
    uv = uv + vec2<f32>(0.0, -0.05);
    let center = vec2<f32>(0.0, -0.01 + progress * 0.02);
    let p = uv - center;
    let radius = length(p);
    let angle = atan2(p.y, p.x);
    let phase = phase_from_angle(angle);

    let kick_rms_sig = #audio "audio.stem.kicks.rms";
    let kick_rms_val = kick_rms_sig.value;
    let main_radius = 0.56 + bass_low * 0.02 + kick_rms_val * 0.02;

    var color = background_layer(base_uv, t, progress, energy, bright, mist_color, trim_color);

    let architecture = light_architecture(base_uv, t, progress, density, arch_height, bass_low, mid, pulse);
    let scaffold = halo_scaffold(radius, main_radius, halo_width, progress);
    let halo = progress_halo(radius, phase, progress, main_radius, halo_width, pulse, kick_flash);
    let filaments = halo_filaments(radius, phase, t, progress, density, high, hat_flash);
    let ornaments = radial_ornaments(radius, angle, phase, t, progress, density, snare_flash, hat_flash);
    let ticks = progress_ticks(radius, phase, main_radius, progress, density);
    let inner = interior_haze(radius, t, low, bright, flux);
    let tracery = inner_tracery(base_uv, t, progress, density, snare_flash, hat_flash);

    let head_beam_angle = progress * TAU - TAU * 0.25;
    let beam_dir = vec2<f32>(cos(head_beam_angle), sin(head_beam_angle));
    let beam_dist = abs(dot(p, vec2<f32>(-beam_dir.y, beam_dir.x)));
    let beam_along = dot(p, beam_dir);
    let progress_beam = exp(-beam_dist * (150.0 + kick_flash * 80.0))
        * smoothstep(0.0, 0.16, beam_along)
        * (1.0 - smoothstep(main_radius + 0.02, main_radius + 0.18, beam_along))
        * (0.08 + pulse * 0.16);

    let outer_aureole = exp(-abs(radius - (main_radius + 0.08 + pulse * 0.018)) * 22.0)
        * smoothstep(0.18, 0.78, progress)
        * (1.0 - smoothstep(1.0, 1.34, radius));

    let head_crown = exp(-phase_distance(phase, progress) * (62.0 + kick_flash * 24.0))
        * exp(-abs(radius - (main_radius + 0.03)) * 38.0)
        * (0.24 + pulse * 0.32);

    color = color + mist_color * architecture * (0.38 + progress * 0.4);
    color = color + mix(core_color, trim_color, 0.16 + bright * 0.12) * scaffold;
    color = color + core_color * halo.x;
    color = color + mix(core_color, trim_color, 0.55 + bright * 0.12) * halo.y;
    color = color + mix(trim_color, vec3<f32>(1.0, 0.97, 0.92), 0.44) * halo.z;
    color = color + mix(core_color, trim_color, 0.36) * filaments;
    color = color + mix(core_color, trim_color, 0.72) * ornaments;
    color = color + mix(core_color, trim_color, 0.22) * ticks;
    color = color + mix(mist_color, trim_color, 0.62) * tracery;
    color = color + mix(core_color, trim_color, 0.62) * progress_beam;
    color = color + mix(trim_color, vec3<f32>(1.0, 0.98, 0.94), 0.5) * head_crown;
    color = color + mix(core_color, trim_color, 0.2) * outer_aureole * (0.2 + finale * 0.54);
    color = color + mix(mist_color, core_color, 0.24 + bright * 0.12) * inner;

    let lower_fog = exp(-abs(base_uv.y + 0.78) * 4.6) * (0.08 + bass_low * 0.12 + complexity * 0.08);
    color = color + mist_color * lower_fog;

    let edge = smoothstep(1.88, 0.26, length(base_uv));
    let c4 = #color "scene.bg_color";
    color = mix(c4.rgb, color, edge);
    color = color * mix(0.92, 1.0, complexity) * mix(0.88, 1.08, finale) * mix(0.78, 1.0, 1.0 - opening_tension * 0.45);

    let c5 = #color "scene.bg_color";
    return encode_output_alpha(color, c5.a);
}

