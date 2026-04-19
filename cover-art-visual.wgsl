
#import <engine::bpm_kernel_bindings>

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}



const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const AUDIO_HISTORY_MAX_SAMPLES: u32 = 32u;
const FONT_ATLAS_COLS: u32 = 16u;
const FONT_ATLAS_ROWS: u32 = 6u;
const FONT_FIRST_GLYPH: u32 = 32u;
const EQ_RENDER_BANDS: u32 = 48u;
const PARTICLE_COUNT: u32 = 28u;
const AUDIO_LOW: u32 = 0u;
const AUDIO_MID: u32 = 1u;
const AUDIO_HIGH: u32 = 2u;
const AUDIO_RMS: u32 = 3u;
const AUDIO_PEAK: u32 = 4u;
const AUDIO_BEAT: u32 = 5u;
const AUDIO_IMPACT: u32 = 6u;
const AUDIO_BRIGHTNESS: u32 = 7u;
const AUDIO_SPECTRUM_START: u32 = 8u;



@group(1) @binding(0)
var cover_image_texture: texture_2d<f32>;

@group(1) @binding(1)
var cover_image_sampler: sampler;

@group(1) @binding(2)
var font_texture: texture_2d<f32>;

@group(1) @binding(3)
var font_sampler: sampler;

@group(1) @binding(4)
var font_metrics_texture: texture_2d<f32>;

@group(1) @binding(5)
var font_metrics_sampler: sampler;

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOut {
    var positions = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(3.0, -1.0),
        vec2<f32>(-1.0, 3.0),
    );
    let position = positions[vertex_index];
    var out: VertexOut;
    out.clip_position = vec4<f32>(position, 0.0, 1.0);
    out.uv = position * 0.5 + vec2<f32>(0.5, 0.5);
    return out;
}

fn saturate(value: f32) -> f32 {
    return clamp(value, 0.0, 1.0);
}

fn saturate3(value: vec3<f32>) -> vec3<f32> {
    return clamp(value, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn audio_value(index: u32) -> f32 {
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

fn audio_recent_value(index: u32, steps_back: u32) -> f32 {
    let sample_count = audio_history_samples();
    let clamped_steps = min(steps_back, sample_count - 1u);
    let sample_index = sample_count - 1u - clamped_steps;
    return audio_history_value(index, sample_index);
}

fn audio_eq_summary_offset(band_count: u32) -> u32 {
    if band_count >= 128u { return 0u; }
    if band_count >= 64u { return 128u; }
    if band_count >= 32u { return 192u; }
    return 224u;
}

fn audio_eq_level_value(index: u32, band_count: u32) -> f32 {
    let flat_index = audio_eq_summary_offset(band_count) + index;
    let slot = scene.audio_eq_levels[flat_index / 4u];
    let component = flat_index % 4u;
    if component == 0u { return slot.x; }
    if component == 1u { return slot.y; }
    if component == 2u { return slot.z; }
    return slot.w;
}

fn audio_eq_peak_value(index: u32, band_count: u32) -> f32 {
    let flat_index = audio_eq_summary_offset(band_count) + index;
    let slot = scene.audio_eq_peaks[flat_index / 4u];
    let component = flat_index % 4u;
    if component == 0u { return slot.x; }
    if component == 1u { return slot.y; }
    if component == 2u { return slot.z; }
    return slot.w;
}

fn project_text_char(index: u32) -> u32 {
    let slot = scene.project_text[index / 4u];
    let component = index % 4u;
    if component == 0u { return u32(slot.x + 0.5); }
    if component == 1u { return u32(slot.y + 0.5); }
    if component == 2u { return u32(slot.z + 0.5); }
    return u32(slot.w + 0.5);
}

fn hash11(value: f32) -> f32 {
    return fract(sin(value * 127.1 + 311.7) * 43758.5453123);
}

fn hash21(value: vec2<f32>) -> f32 {
    return fract(sin(dot(value, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn noise21(value: vec2<f32>) -> f32 {
    let cell = floor(value);
    let frac = fract(value);
    let interp = frac * frac * (vec2<f32>(3.0, 3.0) - 2.0 * frac);
    let a = hash21(cell);
    let b = hash21(cell + vec2<f32>(1.0, 0.0));
    let c = hash21(cell + vec2<f32>(0.0, 1.0));
    let d = hash21(cell + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, interp.x), mix(c, d, interp.x), interp.y);
}

fn sd_round_rect(local_px: vec2<f32>, min_px: vec2<f32>, max_px: vec2<f32>, radius: f32) -> f32 {
    let center = (min_px + max_px) * 0.5;
    let half_extent = (max_px - min_px) * 0.5 - vec2<f32>(radius, radius);
    let q = abs(local_px - center) - half_extent;
    return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

fn round_rect_alpha(local_px: vec2<f32>, min_px: vec2<f32>, max_px: vec2<f32>, radius: f32, feather: f32) -> f32 {
    return 1.0 - smoothstep(0.0, feather, sd_round_rect(local_px, min_px, max_px, radius));
}

fn glyph_layout(code: u32) -> vec3<f32> {
    if code < FONT_FIRST_GLYPH || code >= FONT_FIRST_GLYPH + FONT_ATLAS_COLS * FONT_ATLAS_ROWS {
        return vec3<f32>(0.0, 0.0, 0.0);
    }
    return textureLoad(font_metrics_texture, vec2<i32>(i32(code - FONT_FIRST_GLYPH), 1), 0).rgb;
}

fn text_style() -> vec4<f32> {
    let style = textureLoad(font_metrics_texture, vec2<i32>(0, 3), 0);
    return vec4<f32>(
        max(style.x * 2.0, 0.1),
        max(style.y * 2.0, 0.1),
        max(style.z * 2.0, 0.1),
        max(style.w, 0.1),
    );
}

fn render_font_char(local_px: vec2<f32>, min_px: vec2<f32>, max_px: vec2<f32>, code: u32) -> f32 {
    if code < FONT_FIRST_GLYPH || code >= FONT_FIRST_GLYPH + FONT_ATLAS_COLS * FONT_ATLAS_ROWS {
        return 0.0;
    }
    if local_px.x < min_px.x || local_px.y < min_px.y || local_px.x > max_px.x || local_px.y > max_px.y {
        return 0.0;
    }
    let uv = (local_px - min_px) / max(max_px - min_px, vec2<f32>(1.0, 1.0));
    let glyph_index = code - FONT_FIRST_GLYPH;
    let sample_bounds = textureLoad(font_metrics_texture, vec2<i32>(i32(glyph_index), 0), 0);
    if sample_bounds.z <= sample_bounds.x || sample_bounds.w <= sample_bounds.y {
        return 0.0;
    }
    let atlas_col = glyph_index % FONT_ATLAS_COLS;
    let atlas_row = glyph_index / FONT_ATLAS_COLS;
    let atlas_uv = vec2<f32>(
        (f32(atlas_col) + mix(sample_bounds.x, sample_bounds.z, uv.x)) / f32(FONT_ATLAS_COLS),
        (f32(atlas_row) + mix(sample_bounds.w, sample_bounds.y, uv.y)) / f32(FONT_ATLAS_ROWS),
    );
    return textureSampleLevel(font_texture, font_sampler, atlas_uv, 0.0).a;
}

fn render_project_text_line(
    local_px: vec2<f32>,
    min_px: vec2<f32>,
    max_px: vec2<f32>,
    start_index: u32,
    scale_factor: f32,
) -> f32 {
    if local_px.x < min_px.x || local_px.y < min_px.y || local_px.x > max_px.x || local_px.y > max_px.y {
        return 0.0;
    }
    let box_size = max_px - min_px;
    let style = text_style();
    let glyph_height = box_size.y * 0.9 * style.x * scale_factor;
    let base_y = min_px.y + (box_size.y - glyph_height) * 0.5;
    var total_advance = 0.0;
    var char_count = 0u;
    for (var i = 0u; i < 16u; i = i + 1u) {
        let code = project_text_char(start_index + i);
        if code == 0u {
            break;
        }
        total_advance += max(glyph_layout(code).z, 0.22) * glyph_height * style.z;
        char_count = i + 1u;
    }
    var x_cursor = min_px.x;
    var ink = 0.0;
    for (var i = 0u; i < 16u; i = i + 1u) {
        if i >= char_count {
            break;
        }
        let code = project_text_char(start_index + i);
        let metrics = glyph_layout(code);
        let visible_width = max((metrics.y - metrics.x) * glyph_height, glyph_height * 0.05);
        let glyph_min = vec2<f32>(x_cursor + metrics.x * glyph_height, base_y);
        let glyph_max = vec2<f32>(glyph_min.x + visible_width, base_y + glyph_height);
        ink = max(ink, render_font_char(local_px, glyph_min, glyph_max, code));
        x_cursor += max(metrics.z, 0.22) * glyph_height * style.z;
        if x_cursor > max_px.x + glyph_height {
            break;
        }
    }
    _ = total_advance;
    return ink;
}

fn fallback_band_char(column: u32) -> u32 {
    let chars = array<u32, 16>(66u, 65u, 83u, 83u, 32u, 80u, 73u, 88u, 69u, 76u, 0u, 0u, 0u, 0u, 0u, 0u);
    if column >= 16u { return 0u; }
    return chars[column];
}

fn fallback_song_char(column: u32) -> u32 {
    let chars = array<u32, 16>(67u, 79u, 86u, 69u, 82u, 32u, 65u, 82u, 84u, 32u, 86u, 73u, 83u, 85u, 65u, 76u);
    if column >= 16u { return 0u; }
    return chars[column];
}

fn render_literal_line(
    local_px: vec2<f32>,
    min_px: vec2<f32>,
    max_px: vec2<f32>,
    line_id: u32,
    scale_factor: f32,
) -> f32 {
    if local_px.x < min_px.x || local_px.y < min_px.y || local_px.x > max_px.x || local_px.y > max_px.y {
        return 0.0;
    }
    let box_size = max_px - min_px;
    let style = text_style();
    let glyph_height = box_size.y * 0.9 * style.x * scale_factor;
    let base_y = min_px.y + (box_size.y - glyph_height) * 0.5;
    var x_cursor = min_px.x;
    var ink = 0.0;
    for (var i = 0u; i < 16u; i = i + 1u) {
        let code = select(fallback_band_char(i), fallback_song_char(i), line_id == 1u);
        if code == 0u {
            break;
        }
        let metrics = glyph_layout(code);
        let visible_width = max((metrics.y - metrics.x) * glyph_height, glyph_height * 0.05);
        let glyph_min = vec2<f32>(x_cursor + metrics.x * glyph_height, base_y);
        let glyph_max = vec2<f32>(glyph_min.x + visible_width, base_y + glyph_height);
        ink = max(ink, render_font_char(local_px, glyph_min, glyph_max, code));
        x_cursor += max(metrics.z, 0.22) * glyph_height * style.z;
        if x_cursor > max_px.x + glyph_height {
            break;
        }
    }
    return ink;
}

fn font_text_color() -> vec3<f32> {
    let c = #color "scene.text.font_text_color";
    return saturate3(c.rgb);
}

fn bg_color() -> vec3<f32> {
    let c = #color "scene.bg_color";
    return saturate3(c.rgb);
}

fn accent_color() -> vec3<f32> {
    let c = #color "scene.accent_color";
    return saturate3(c.rgb);
}

fn progress_thickness() -> f32 {
    return 9.95;
}

fn eq_gain() -> f32 {
    return 1.05;
}

fn particle_density() -> f32 {
    return clamp(#gui_param "scene.particle_density".x, 0.0, 1.5);
}

fn particle_lifetime() -> f32 {
    return clamp(#gui_param "scene.particle_lifetime".x, 0.2, 1.4);
}

fn motion_amount() -> f32 {
    return 0.3;
}

fn cover_glow() -> f32 {
    return 0.22;
}

fn cover_frame_opacity() -> f32 {
    return 0.72;
}

fn timeline_progress() -> f32 {
    if scene.timeline.y <= 0.0 {
        return 0.0;
    }
    return clamp(scene.timeline.z, 0.0, 1.0);
}

fn line_has_text(start_index: u32) -> bool {
    return project_text_char(start_index) > 0u;
}

// Generates an infinitely smooth, domain-warped noise field
fn get_smooth_fog(p_in: vec2<f32>, time_offset: f32) -> f32 {
    var p = p_in;
    var fog = 0.0;
    var amp = 0.5;
    let FBM_R = mat2x2<f32>(0.8, -0.6, 0.6, 0.8);
    for (var i = 0u; i < 3u; i = i + 1u) {
        let swirl = vec2<f32>(sin(p.y + time_offset), cos(p.x - time_offset));
        fog += amp * sin(p.x + swirl.x) * cos(p.y + swirl.y);
        p = FBM_R * p * 1.8;
        amp *= 0.5;
    }
    return saturate(fog * 0.8 + 0.5);
}

fn render_background(frag_px: vec2<f32>, uv: vec2<f32>, progress: f32, rms: f32, brightness: f32) -> vec3<f32> {
    let aspect = scene.resolution.x / max(scene.resolution.y, 1.0);
    let p = vec2<f32>((uv.x * 2.0 - 1.0) * aspect, uv.y * 2.0 - 1.0);
    let motion = motion_amount();
    let base = bg_color();
    
    // Create a really deep, cinematic vignette and gradient
    let upper = base + accent_color() * 0.05;
    let lower = base * 0.3; // Much darker at the bottom for dramatic contrast
    var color = mix(upper, lower, saturate(uv.y * 1.2));
    
    // Abstract background dust
    let dust = noise21(uv * vec2<f32>(scene.resolution.x / 400.0, scene.resolution.y / 300.0) + vec2<f32>(scene.time * 0.005, -scene.time * 0.002));
    
    // EXTREME DEPTH PARALLAX: 3 distinct volumetric planes moving at different speeds!
    // 'progress * 0.4' subtly morphs the internal swirls over the entire song duration
    let t = scene.time * 0.05 * motion + progress * 0.4;
    
    // Microscopic sink drift: extremely gentle sinking over the entire track (won't scroll off-screen!)
    let sink = vec2<f32>(0.0, -progress * 0.15);
    
    // 1. BACK LAYER (Very deep horizon, small structures)
    let fog_back = get_smooth_fog(p * 5.0 + vec2<f32>(t * 0.1, -t * 0.05) + sink * 0.1, t);
    let density_back = pow(fog_back, 1.2);
    
    // 2. MID LAYER (Medium distance: structured background clouds)
    let fog_mid = get_smooth_fog(p * 2.8 + vec2<f32>(-t * 0.3, t * 0.2) + sink * 0.3, t * 1.2);
    let density_mid = pow(fog_mid, 2.5);
    
    // 3. FRONT LAYER (Scaled to clearly remain in the background, not intersecting the UI plane)
    let fog_front = get_smooth_fog(p * 1.4 + vec2<f32>(t * 0.9, t * 0.6) + sink * 1.2, t * 2.0);
    let density_front = pow(fog_front, 3.8); // High exponent leaves only distinct floating clumps
    
    // DENSITY PROGRESSION: Smooth quadratic bezier curve
    // Starts subtly (0.1), peaks exactly in the middle of the song (1.0), and fades out at the end
    let bezier_envelope = 4.0 * progress * (1.0 - progress);
    let song_density = 0.1 + bezier_envelope * 0.9;
    
    // Deepen the background color so foreground pops harder
    let color_back = accent_color() * 0.05;
    let color_mid = mix(accent_color(), vec3<f32>(0.7, 0.65, 0.6), 0.4) * 0.14;
    let color_front = vec3<f32>(1.0, 0.98, 0.95) * 0.16;
    
    // Composite from back to front with precise lighting and progression opacity
    color += color_back * density_back * song_density;
    color += color_mid * density_mid * song_density;
    color += color_front * density_front * song_density;
    
    color += vec3<f32>(0.02, 0.018, 0.015) * dust * 0.04;
    
    let vignette = clamp(1.2 - dot(uv - 0.5, uv - 0.5) * 1.8, 0.3, 1.0);
    return color * vignette;
}

fn render_cover(frag_px: vec2<f32>, center: vec2<f32>, side: f32, low: f32, rms: f32, beat: f32, progress: f32) -> vec3<f32> {
    let half_side = side * 0.5;
    let cover_min = center - vec2<f32>(half_side);
    let cover_max = center + vec2<f32>(half_side);
    
    // Subtle breathing drift (purely time-based, no flashing!)
    let pulse = 0.5 + 0.5 * sin(scene.time * (0.3 + motion_amount() * 0.2) + progress * PI);
    let drift = vec2<f32>(0.002, -0.001) * motion_amount() * 0.4;
    
    // Deep, ethereal drop shadow / bloom behind the cover (completely static alpha)
    let dist_to_center = length(frag_px - center);
    let glow_radius = side * (0.8 + pulse * 0.1);
    let glow_alpha = exp(-dist_to_center / glow_radius) * cover_glow();
    
    // No more RMS audio reactivity! It stays perfectly gentle and constant.
    var color = mix(accent_color(), vec3<f32>(1.0, 0.95, 0.9), 0.5) * glow_alpha * 0.4;
    
    // Sharp drop shadow
    let shadow_alpha = round_rect_alpha(frag_px, cover_min + vec2<f32>(10.0, 20.0), cover_max + vec2<f32>(10.0, 20.0), 12.0, 30.0);
    color = mix(color, vec3<f32>(0.0), shadow_alpha * 0.8);
    
    // Cover image without clunky frames
    let corner_radius = max(side * 0.03, 4.0);
    let cover_alpha = round_rect_alpha(frag_px, cover_min, cover_max, corner_radius, 1.0);
    
    let cover_uv = clamp((frag_px - cover_min) / max(vec2<f32>(side), vec2<f32>(1.0)), vec2<f32>(0.0), vec2<f32>(1.0));
    let sample_uv = clamp(
        vec2<f32>(
            mix(0.01, 0.99, cover_uv.x) + drift.x,
            1.0 - mix(0.01, 0.99, cover_uv.y) + drift.y,
        ),
        vec2<f32>(0.0), vec2<f32>(1.0)
    );
    let cover_sample = textureSampleLevel(cover_image_texture, cover_image_sampler, sample_uv, 0.0).rgb;
    
    color = mix(color, cover_sample, cover_alpha);
    
    return color;
}

fn render_inline_progress(frag_px: vec2<f32>, x_min: f32, x_max: f32, y_center: f32, progress: f32, beat: f32, rms: f32) -> vec3<f32> {
    if frag_px.x < x_min || frag_px.x > x_max { return vec3<f32>(0.0); }
    let width_total = x_max - x_min;
    
    let dist_y = abs(frag_px.y - y_center);
    let prog_x = x_min + width_total * progress;
    let dist_x = max(0.0, frag_px.x - prog_x);
    
    // Height thickness reduced by 50%
    let track_glow = exp(-dist_y / 1.0) * 0.05 * accent_color();
    // Blink animation (size) reduced by 70%
    let fill_glow = exp(-dist_y / (0.75 + rms * 0.2)) * exp(-dist_x / 5.0);
    
    var color = track_glow;
    // Blink animation (intensity) reduced by 70%
    color += mix(accent_color(), vec3<f32>(1.0), 0.3) * fill_glow * (0.6 + rms * 0.2) * step(frag_px.x, prog_x + 10.0);
    
    let head_dist = length(frag_px - vec2<f32>(prog_x, y_center));
    // Head size reduced by 50%, head blink animation reduced by 70%
    let head_glow = exp(-head_dist / (2.0 + beat * 1.2));
    // Head intensity animation reduced by 70%
    color += vec3<f32>(1.0, 0.99, 0.98) * head_glow * (0.6 + beat * 0.3);
    
    return color;
}

fn render_inline_eq(frag_px: vec2<f32>, x_min: f32, x_max: f32, base_y: f32, max_height: f32, beat: f32, brightness: f32) -> vec3<f32> {
    if frag_px.x < x_min || frag_px.x > x_max { return vec3<f32>(0.0); }
    let width = x_max - x_min;
    
    let band_step = width / f32(EQ_RENDER_BANDS);
    let band_idx = u32((frag_px.x - x_min) / band_step);
    if band_idx >= EQ_RENDER_BANDS { return vec3<f32>(0.0); }
    
    let eq_index = min(band_idx, 63u);
    let level = pow(saturate(audio_eq_level_value(eq_index, 64u) * eq_gain() * 0.7), 0.85);
    let peak = pow(saturate(audio_eq_peak_value(eq_index, 64u) * eq_gain() * 0.7), 0.85);

    let target_y = base_y + level * max_height;
    let peak_y = base_y + peak * max_height;
    
    let bar_center_x = x_min + (f32(band_idx) + 0.5) * band_step;
    let dist_x = abs(frag_px.x - bar_center_x);
    
    // Create sharp horizontal boundaries for a solid bar (width ~60% of step)
    let bar_half_width = band_step * 0.3;
    let body_mask = 1.0 - smoothstep(bar_half_width - 0.5, bar_half_width + 0.5, dist_x);
    // Subtle ambient glow
    let ambient_glow = exp(-dist_x / (band_step * 0.4)) * 0.05;
    
    // Sharp vertical boundary
    let active_bar = step(base_y, frag_px.y) * (1.0 - smoothstep(target_y - 0.5, target_y + 0.5, frag_px.y));
    let bar_color = mix(accent_color(), vec3<f32>(0.9, 0.95, 1.0), f32(band_idx) / f32(EQ_RENDER_BANDS));
    
    // Base color uses the solid sharp mask, dimmed down to sit elegantly in the composition
    var color = bar_color * active_bar * (body_mask + ambient_glow) * (0.25 + brightness * 0.15);
    
    // Sharp, thin horizontal cap line for the peak, also dimmed
    let cap_mask = body_mask * (1.0 - smoothstep(1.0, 2.0, abs(frag_px.y - peak_y)));
    color += mix(bar_color, vec3<f32>(1.0), 0.5) * cap_mask * (0.35 + beat * 0.25);

    let floor_glow = exp(-(frag_px.y - base_y) / (max_height * 0.2)) * level * step(base_y, frag_px.y);
    color += bar_color * floor_glow * (body_mask * 0.5 + ambient_glow) * 0.25;

    return color;
}

fn render_particles_fullscreen(frag_px: vec2<f32>, res: vec2<f32>, accent: vec3<f32>, eq_x_min: f32, eq_x_max: f32, eq_y: f32) -> vec3<f32> {
    var color = vec3<f32>(0.0);
    
    // Boost particle count significantly for professional volumetric ash feel
    let ASH_COUNT = 96u;
    
    for (var i = 0u; i < ASH_COUNT; i = i + 1u) {
        let particle_id = f32(i);
        let band = (i * 11u) % 32u;
        
        let seed = hash11(particle_id * 1.23);
        // Long life duration: 5 to 15 seconds! They will float extremely slowly.
        let life_duration = mix(5.0, 15.0, seed) * (0.5 + particle_lifetime());
        
        // Use subtraction so particles are born at age=0 AFTER scene.time = 0!
        let time_offset = hash11(particle_id * 4.56) * life_duration;
        let total_time = scene.time * 0.8 - time_offset;
        
        // Do not render if particle hasn't been born yet (prevents mid-air starting at 0:00)
        if total_time < 0.0 { continue; }
        
        let cycle_id = floor(total_time / life_duration);
        let age = fract(total_time / life_duration); // 0.0 to 1.0 over full lifetime
        
        let cycle_seed = hash11(cycle_id * 13.0 + particle_id * 7.0);
        let cycle_intensity = hash11(cycle_id * 17.0 + particle_id * 3.0);
        
        // Density culling
        if cycle_seed > clamp(particle_density(), 0.1, 1.0) { continue; }
        
        // Evaluate CURRENT audio for explosive hits
        let current_amp = saturate(audio_value(AUDIO_SPECTRUM_START + band) * eq_gain() * 1.2);
        
        let lane = (f32(band) + hash11(particle_id * 0.73)) / 32.0;
        let origin_x = mix(eq_x_min, eq_x_max, lane);
        
        // They spawn exactly at the tip of the CURRENT EQ bar height
        let emit_height = pow(saturate(current_amp * 0.8), 0.85) * 70.0;
        
        // Snaps to the bar when born (age ~0.0), then detaches cleanly as it travels up
        let attached = smoothstep(0.04, 0.0, age);
        let origin_y = eq_y + emit_height * attached;
        
        // Parabolic physics: Less weight!
        let v0 = mix(2.0, 4.0, hash11(particle_id * 2.2)); 
        // Gravity is only barely stronger than initial velocity, so they float much lighter
        let gravity = v0 + mix(0.1, 0.5, hash11(particle_id * 8.8));
        let height_curve = (v0 * age) - (gravity * age * age);
        
        // Scale it so they fly sufficiently high before falling gently
        let drift_y = height_curve * res.y * 0.65;
        
        // As they fall, they disperse out much wider horizontally
        let drift_x = (hash11(particle_id * 9.1) - 0.5) * res.x * 0.45 * age * motion_amount();
        
        // Fluid, light ash air-current physics
        let turbulence = noise21(vec2<f32>(origin_x * 0.01, total_time * 0.3));
        let wind_sway = (turbulence - 0.5) * res.x * 0.15 * age * motion_amount();
        let sway = sin(scene.time * 0.4 + particle_id * 1.2 + age * TAU) * 15.0 * motion_amount();
        
        let center = vec2<f32>(origin_x + drift_x + wind_sway + sway, origin_y + drift_y);
        
        // Modulate visibility: brightly lit when emitted near a hard bass hit, dies down to a soft glowing spark over time
        let near_eq = smoothstep(0.1, 0.0, age);
        let emit_boost = smoothstep(0.3, 0.7, current_amp) * near_eq;
        
        // Tie baseline ash to global audio RMS so it doesn't just auto-spawn in dead silence!
        let global_activity = smoothstep(0.0, 0.3, audio_value(AUDIO_RMS));
        let base_ash = cycle_intensity * 0.3 * global_activity;
        
        let energy = max(base_ash, emit_boost) * particle_density();
        if energy <= 0.0 { continue; }
        
        // Plump sparks when near source, tiny flakes when far
        let size = mix(1.0, 4.5, hash11(particle_id * 13.7)) * (0.6 + energy + emit_boost * 0.5);
        let dust = exp(-length(frag_px - center) / size);
        
        let ember_color = vec3<f32>(1.0, 0.8, 0.3); // Bright hot ember
        let cool_ash_color = mix(vec3<f32>(0.6, 0.5, 0.45), accent, 0.5); // Warm dark ash
        
        // Sparks glow intensely orange at start, then cool out into the base ash color
        let active_color = mix(cool_ash_color, ember_color, emit_boost + smoothstep(0.8, 0.0, age) * cycle_intensity);
        
        color += active_color * dust * energy * smoothstep(1.0, 0.8, age) * 0.85;
    }
    return color;
}

fn render_typography(frag_px: vec2<f32>, anchor: vec2<f32>, max_w: f32, progress: f32) -> vec3<f32> {
    // anchor is bottom-left of the typography block
    // Y=0 is bottom, so subtract to go DOWN, add to go UP
    
    // Band on top
    let band_box_max = vec2<f32>(anchor.x + max_w, anchor.y);
    let band_box_min = vec2<f32>(anchor.x, anchor.y - 24.0);
    
    // Song in middle
    let song_box_max = vec2<f32>(anchor.x + max_w, anchor.y - 36.0);
    let song_box_min = vec2<f32>(anchor.x, anchor.y - 72.0);
    
    // Album on bottom
    let album_box_max = vec2<f32>(anchor.x + max_w, anchor.y - 84.0);
    let album_box_min = vec2<f32>(anchor.x, anchor.y - 108.0);
    
    let band_ink = select(render_literal_line(frag_px, band_box_min, band_box_max, 0u, 0.9), render_project_text_line(frag_px, band_box_min, band_box_max, 0u, 0.9), line_has_text(0u));
    let song_ink = select(render_literal_line(frag_px, song_box_min, song_box_max, 1u, 0.85), render_project_text_line(frag_px, song_box_min, song_box_max, 16u, 0.85), line_has_text(16u));
    let album_ink = render_project_text_line(frag_px, album_box_min, album_box_max, 32u, 0.85);
    
    var color = vec3<f32>(0.0);
    color = mix(color, mix(font_text_color(), accent_color(), 0.3), band_ink);
    color = mix(color, vec3<f32>(1.0, 0.99, 0.97), song_ink);
    if line_has_text(32u) {
        color = mix(color, mix(font_text_color(), accent_color(), 0.4), album_ink);
    }
    
    return color;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let frag_px = in.uv * scene.resolution;
    let progress = timeline_progress();
    
    let low = audio_value(AUDIO_LOW);
    let mid = audio_value(AUDIO_MID);
    let rms = audio_value(AUDIO_RMS);
    let peak = audio_value(AUDIO_PEAK);
    let beat = audio_value(AUDIO_BEAT);
    let impact = audio_value(AUDIO_IMPACT);
    let brightness = audio_value(AUDIO_BRIGHTNESS);

    var color = render_background(frag_px, in.uv, progress, rms, brightness);

    // Layout
    let margin_x = scene.resolution.x * 0.1;
    let gap = scene.resolution.x * 0.05;
    
    // Calculate cover size based on resolution to ensure it fits beautifully
    let cover_side = max(scene.resolution.y * 0.4, min(scene.resolution.y * 0.55, 600.0));
    // Center it on Y=0.5
    let cover_center = vec2<f32>(margin_x + cover_side * 0.5, scene.resolution.y * 0.5);
    
    // In BPM, Y=0 is the bottom! cover_min.y is the bottom edge, cover_max.y is the top edge!
    let cover_bottom = cover_center.y - (cover_side * 0.5);
    let cover_top = cover_center.y + (cover_side * 0.5);
    
    let text_anchor_x = margin_x + cover_side + gap;
    let text_width = scene.resolution.x - margin_x - text_anchor_x;
    
    // Typography starts from the TOP edge of the cover and goes downwards
    let typography_top_anchor = vec2<f32>(text_anchor_x, cover_top);
    
    // Progress laser shifted up from bottom of cover
    let prog_y = cover_bottom + 42.0;
    // EQ strictly slightly above laser
    let eq_y = prog_y + 15.0;

    // Particles flowing over the whole canvas
    color += render_particles_fullscreen(frag_px, scene.resolution, accent_color(), text_anchor_x, text_anchor_x + text_width, eq_y);

    // Cover floating on top
    color += render_cover(frag_px, cover_center, cover_side, low, rms, beat, progress);
    
    // Clean Typography floating next to it (growing down from anchor)
    color += render_typography(frag_px, typography_top_anchor, text_width, progress);
    
    // Inline EQ below text
    color += render_inline_eq(frag_px, text_anchor_x, text_anchor_x + text_width, eq_y, 70.0, beat, brightness);

    // Inline progress laser aligned at bottom of cover
    color += render_inline_progress(frag_px, text_anchor_x, text_anchor_x + text_width, prog_y, progress, beat + impact * 0.4, rms + peak * 0.3);

    // Subtle atmospheric mid-tone reacting
    let ambience = noise21(frag_px / vec2<f32>(200.0, 250.0) + vec2<f32>(scene.time * 0.015 * motion_amount(), scene.time * 0.01));
    color += vec3<f32>(0.01) * ambience * (0.3 + mid * 0.7);

    // Dither to prevent banding
    let dither = (hash21(frag_px + vec2<f32>(scene.time * 7.0, 13.0)) - 0.5) * scene.dither_strength * 0.035;
    color += vec3<f32>(dither);
    
    let c_bg = #color "scene.bg_color";
    return encode_output_alpha(color, c_bg.a);
}

