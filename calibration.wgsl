
#import <engine::bpm_kernel_bindings>
#import <bpm/video_fx/bloom_core.wgsl>

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}



const GRID_COUNT: u32 = 160u;
const DETAIL_COLUMNS: u32 = 3u;
const DETAIL_ROWS: u32 = 4u;
const DETAIL_COUNT: u32 = 9u;
const DISPLAY_COUNT: u32 = 13u;
const PAGE_SECONDS: f32 = 3.2;
const MAX_LABEL_CHARS: u32 = 40u;
const AUDIO_HISTORY_MAX_SAMPLES: u32 = 32u;
const FONT_ATLAS_COLS: u32 = 16u;
const FONT_ATLAS_ROWS: u32 = 6u;
const FONT_FIRST_GLYPH: u32 = 32u;



@group(1) @binding(0)
var font_texture: texture_2d<f32>;

@group(1) @binding(1)
var font_sampler: sampler;

@group(1) @binding(2)
var font_metrics_texture: texture_2d<f32>;

@group(1) @binding(3)
var font_metrics_sampler: sampler;

@group(1) @binding(4)
var preview_image_texture: texture_2d<f32>;

@group(1) @binding(5)
var preview_image_sampler: sampler;

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOut {
    var positions = array<vec2<f32>, 3>(vec2<f32>(-1.0, -1.0), vec2<f32>(3.0, -1.0), vec2<f32>(-1.0, 3.0));
    let position = positions[vertex_index];
    var out: VertexOut;
    out.clip_position = vec4<f32>(position, 0.0, 1.0);
    out.uv = position * 0.5 + vec2<f32>(0.5, 0.5);
    return out;
}

fn audio_value(index: u32) -> f32 {
    let slot = scene._raw_audio_scalars_do_not_use[u32(index / 4u)];
    let component = index % 4u;
    if component == 0u { return slot.x; }
    if component == 1u { return slot.y; }
    if component == 2u { return slot.z; }
    return slot.w;
}

fn audio_bounds(index: u32) -> vec2<f32> {
    let slot = scene.audio_bounds[index / 2u];
    if index % 2u == 0u {
        return vec2<f32>(slot.x, slot.y);
    }
    return vec2<f32>(slot.z, slot.w);
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

const EQ_PEAK_HOLD_SAMPLES: f32 = 6.0;
const EQ_PEAK_DECAY_PER_SAMPLE: f32 = 0.04;
const EQ_SCALAR_PANEL_COUNT: u32 = 4u;
const DETAIL_VISIBLE_COUNT: u32 = 76u;

fn audio_history_samples() -> u32 {
    return clamp(u32(scene.audio_meta.w + 0.5), 1u, AUDIO_HISTORY_MAX_SAMPLES);
}

fn audio_scalar_history_peak_value(index: u32) -> f32 {
    let sample_count = audio_history_samples();
    var peak = 0.0;
    for (var sample_index = 0u; sample_index < sample_count; sample_index = sample_index + 1u) {
        let age = f32(sample_count - 1u - sample_index);
        let raw = normalized_value(index, audio_history_value(index, sample_index));
        let decayed = max(0.0, raw - max(age - EQ_PEAK_HOLD_SAMPLES, 0.0) * EQ_PEAK_DECAY_PER_SAMPLE);
        peak = max(peak, decayed);
    }
    return peak;
}



fn scalar_band_source_index(panel_index: u32) -> u32 {
    if panel_index == 0u { return 0u; }
    if panel_index == 1u { return 1u; }
    if panel_index == 2u { return 2u; }
    return 3u;
}

fn scalar_band_title_char(panel_index: u32, column: u32) -> u32 {
    let t_0 = array<u32, 4>(70u, 85u, 76u, 76u);
    let t_1 = array<u32, 4>(76u, 79u, 87u, 0u);
    let t_2 = array<u32, 4>(77u, 73u, 68u, 0u);
    let t_3 = array<u32, 4>(72u, 73u, 71u, 72u);
    if column >= 4u { return 0u; }
    if panel_index == 0u { return t_0[column]; }
    if panel_index == 1u { return t_1[column]; }
    if panel_index == 2u { return t_2[column]; }
    return t_3[column];
}

fn detail_source_index(slot: u32) -> u32 {
    return slot + 4u;
}

fn show_production() -> bool {
    return #gui_param "scene.show_maturity_production".x >= 0.5;
}

fn show_research() -> bool {
    return #gui_param "scene.show_maturity_research".x >= 0.5;
}

fn is_production_feature(index: u32) -> bool {
    if index < 4u { return true; }
    if index == 12u { return true; }
    if index >= 13u && index <= 76u { return true; }
    
    if index == 77u { return true; }
    if index == 78u { return true; }
    if index == 79u { return true; }
    if index == 88u { return true; }
    if index == 89u { return true; }
    if index == 90u { return true; }
    if index == 91u { return true; }
    if index == 100u { return true; }
    if index == 101u { return true; }
    if index == 102u { return true; }
    if index == 103u { return true; }
    if index == 112u { return true; }
    if index == 113u { return true; }
    if index == 114u { return true; }
    if index == 115u { return true; }
    if index == 124u { return true; }
    if index == 125u { return true; }
    if index == 126u { return true; }
    if index == 127u { return true; }
    if index == 136u { return true; }
    if index == 137u { return true; }
    if index == 138u { return true; }
    if index == 139u { return true; }
    if index == 148u { return true; }
    return false;
}

fn is_research_feature(index: u32) -> bool {
    return !is_production_feature(index);
}

fn is_feature_visible(index: u32) -> bool {
    if is_production_feature(index) && !show_production() { return false; }
    if is_research_feature(index) && !show_research() { return false; }
    return true;
}

fn get_visible_source_index(visual_index: u32) -> u32 {
    var current = 0u;
    for (var i = 4u; i < 149u; i = i + 1u) {
        if i >= 13u && i <= 76u { continue; } // skip spectrum
        if is_feature_visible(i) {
            if current == visual_index {
                return i;
            }
            current = current + 1u;
        }
    }
    return 9999u;
}



fn visualizer_focus_index() -> i32 {
    let raw = #gui_param "scene.visualizer_focus_index".x;
    if raw < -0.5 {
        return -1;
    }
    return i32(round(raw));
}

fn timeline_current_seconds() -> f32 {
    return max(scene.timeline.x, 0.0);
}

fn timeline_total_seconds() -> f32 {
    return max(scene.timeline.y, 0.0);
}

fn timeline_progress() -> f32 {
    if timeline_total_seconds() <= 0.0 {
        return 0.0;
    }
    return clamp(scene.timeline.z, 0.0, 1.0);
}

fn audio_scope_params(index: u32) -> vec2<f32> {
    let slot = scene.audio_scope[index / 2u];
    if index % 2u == 0u {
        return vec2<f32>(slot.x, slot.y);
    }
    return vec2<f32>(slot.z, slot.w);
}

fn scope_display_level(index: u32, level: f32) -> f32 {
    let gain = max(audio_scope_params(index).y, 0.1);
    return clamp(level * gain, 0.0, 1.0);
}

fn scope_plot_y(min_px: vec2<f32>, max_px: vec2<f32>, level: f32) -> f32 {
    return mix(min_px.y, max_px.y, clamp(level, 0.0, 1.0));
}

fn eq_bar_top_y(min_y: f32, max_y: f32, level: f32) -> f32 {
    return mix(min_y, max_y, clamp(level, 0.0, 1.0));
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

fn category_color(index: u32) -> vec3<f32> {
    if index < 4u { return vec3<f32>(0.98, 0.58, 0.22); }
    if index < 8u { return vec3<f32>(0.98, 0.78, 0.30); }
    if index < 20u { return vec3<f32>(0.28, 0.80, 0.74); }
    if index < 25u { return vec3<f32>(0.28, 0.72, 0.98); }
    if index < 44u { return vec3<f32>(0.98, 0.38, 0.46); }
    if index < 48u { return vec3<f32>(0.98, 0.87, 0.34); }
    if index < 63u { return vec3<f32>(0.44, 0.84, 0.54); }
    if index < 80u { return vec3<f32>(0.48, 0.58, 0.98); }
    return vec3<f32>(0.74, 0.52, 0.98);
}

fn feature_scope_bounds(index: u32) -> vec2<f32> {
    let bounds = audio_bounds(index);
    if bounds.y > bounds.x {
        return bounds;
    }
    return vec2<f32>(0.0, 1.0);
}

fn feature_scope_uses_log_scale(index: u32) -> bool {
    _ = index;
    return false;
}

fn normalize_feature_bounds(raw: f32, bounds: vec2<f32>) -> f32 {
    let min_value = bounds.x;
    let max_value = max(bounds.y, min_value + 0.0001);
    return clamp((raw - min_value) / (max_value - min_value), 0.0, 1.0);
}

fn normalized_value(index: u32, raw: f32) -> f32 {
    let bounds = feature_scope_bounds(index);
    if feature_scope_uses_log_scale(index) {
        let safe = clamp(raw, bounds.x, bounds.y);
        return clamp(
            (log2(safe) - log2(bounds.x)) / (log2(bounds.y) - log2(bounds.x)),
            0.0,
            1.0,
        );
    }
    return normalize_feature_bounds(raw, bounds);
}

fn value_code(raw: f32, char_index: u32) -> u32 {
    if raw < 0.0 {
        let value = min(-raw, 1.0);
        let scaled = u32(round(value * 10.0));
        if char_index == 0u { return 45u; }
        if char_index == 1u { return 48u + scaled / 10u; }
        if char_index == 2u { return 44u; }
        if char_index == 3u { return 48u + scaled % 10u; }
        return 32u;
    }
    let value = max(raw, 0.0);
    if value < 10.0 {
        let scaled = u32(round(min(value, 9.99) * 100.0));
        if char_index == 0u { return 48u + scaled / 100u; }
        if char_index == 1u { return 44u; }
        if char_index == 2u { return 48u + (scaled / 10u) % 10u; }
        if char_index == 3u { return 48u + scaled % 10u; }
        return 32u;
    }
    if value < 100.0 {
        let scaled = u32(round(min(value, 99.9) * 10.0));
        if char_index == 0u { return 48u + scaled / 100u; }
        if char_index == 1u { return 48u + (scaled / 10u) % 10u; }
        if char_index == 2u { return 44u; }
        if char_index == 3u { return 48u + scaled % 10u; }
        return 32u;
    }
    let scaled = u32(round(min(value, 999.0)));
    if char_index == 0u { return select(32u, 48u + scaled / 100u, scaled >= 100u); }
    if char_index == 1u { return select(32u, 48u + (scaled / 10u) % 10u, scaled >= 10u); }
    if char_index == 2u { return 48u + scaled % 10u; }
    if char_index == 3u { return 32u; }
    return 32u;
}

fn is_punctuation(code: u32) -> bool {
    return code == 44u || code == 45u || code == 46u;
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

fn ui_text_base_color() -> vec3<f32> {
    let font_color = #color "scene.text.font_text_color";
    return clamp(font_color.rgb * debug_text_glow(), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ui_text_bright_color() -> vec3<f32> {
    return clamp(mix(ui_text_base_color(), vec3<f32>(1.0, 0.99, 0.95), 0.22), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ui_text_accent_color(accent: vec3<f32>) -> vec3<f32> {
    let tuned = apply_debug_accent(accent);
    return clamp(
        mix(ui_text_base_color(), tuned * 0.3 + vec3<f32>(0.92, 0.98, 0.94), 0.28),
        vec3<f32>(0.0),
        vec3<f32>(1.0),
    );
}

fn local_bloom_color(
    color: vec3<f32>,
    emission: vec3<f32>,
    mask: f32,
    intensity: f32,
    tint: vec3<f32>,
) -> vec3<f32> {
    let bloom_signal = emission * clamp(mask, 0.0, 1.0);
    return bloom_combine(color, bloom_signal, intensity * beat_phase_bloom_drive(), tint);
}

fn beat_phase_bloom_drive() -> f32 {
    let source_index = 29u;
    let phase = clamp(normalized_value(source_index, audio_value(source_index)), 0.0, 1.0);
    let head = 1.0 - smoothstep(0.0, 0.16, phase);
    let body = 1.0 - smoothstep(0.08, 0.48, phase);
    let pulse = max(head, body * 0.5);
    return mix(0.26, 1.65, pulse);
}

fn debug_show_underlay() -> bool {
    return #gui_param "scene.debug_show_underlay".x >= 0.5;
}

fn debug_band_limit() -> u32 {
    return clamp(u32(round(#gui_param "scene.debug_band_limit".x)), 8u, 128u);
}

fn debug_text_glow() -> f32 {
    return max(#gui_param "scene.debug_text_glow".x, 0.0);
}

fn debug_panel_offset() -> vec2<f32> {
    return #gui_param "scene.debug_panel_offset".xy * vec2<f32>(120.0, 80.0);
}

fn debug_accent_rgb() -> vec3<f32> {
    return clamp(#gui_param "scene.debug_accent_rgb".xyz, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn debug_frame_rgba() -> vec4<f32> {
    return clamp(#gui_param "scene.debug_frame_rgba", vec4<f32>(0.0), vec4<f32>(1.0));
}

fn scene_bg_color() -> vec3<f32> {
    let bg = #color "scene.bg_color";
    return clamp(bg.rgb, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn scene_bg_alpha() -> f32 {
    let bg = #color "scene.bg_color";
    return clamp(bg.a, 0.0, 1.0);
}

fn apply_debug_accent(accent: vec3<f32>) -> vec3<f32> {
    return mix(accent, debug_accent_rgb(), 0.38);
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

fn word_char(code_index: u32, word_index: u32, column: u32) -> u32 {
    if column != word_index {
        return 0u;
    }
    return code_index;
}

fn two_digit_char(value: u32, digit_index: u32) -> u32 {
    if digit_index == 0u { return 48u + value / 10u; }
    if digit_index == 1u { return 48u + value % 10u; }
    return 0u;
}

fn eq_panel_title_char(band_count: u32, column: u32) -> u32 {
    if band_count >= 1000u {
        if column == 0u { return 48u + band_count / 1000u; }
        if column == 1u { return 48u + (band_count / 100u) % 10u; }
        if column == 2u { return 48u + (band_count / 10u) % 10u; }
        if column == 3u { return 48u + band_count % 10u; }
        return 0u;
    }
    if band_count >= 100u {
        if column == 0u { return 48u + band_count / 100u; }
        if column == 1u { return 48u + (band_count / 10u) % 10u; }
        if column == 2u { return 48u + band_count % 10u; }
        return 0u;
    }
    if band_count >= 10u {
        if column == 0u { return 48u + band_count / 10u; }
        if column == 1u { return 48u + band_count % 10u; }
        return 0u;
    }
    if column == 0u { return 48u + band_count; }
    return 0u;
}


fn spec_frequency_char(spec_index: u32, column: u32) -> u32 {
    let sample_rate = max(scene.audio_meta.z, 0.0);
    if sample_rate < 1.0 {
        if column == 0u { return 83u; }
        if column == 1u { return 80u; }
        if column == 2u { return 69u; }
        if column == 3u { return 67u; }
        if column == 4u { return 32u; }
        return two_digit_char(spec_index, column - 5u);
    }
    let band_hz = sample_rate / 128.0;
    let center_hz = (f32(spec_index) + 0.5) * band_hz;
    if center_hz < 1000.0 {
        let hz = u32(round(center_hz));
        if column == 0u { return select(32u, 48u + hz / 100u, hz >= 100u); }
        if column == 1u { return select(32u, 48u + (hz / 10u) % 10u, hz >= 10u); }
        if column == 2u { return 48u + hz % 10u; }
        if column == 3u { return 72u; }
        if column == 4u { return 90u; }
        return 32u;
    }
    let tenths_khz = u32(round(center_hz / 100.0));
    let whole_khz = tenths_khz / 10u;
    let frac_khz = tenths_khz % 10u;
    if column == 0u { return select(32u, 48u + whole_khz / 10u, whole_khz >= 10u); }
    if column == 1u { return 48u + whole_khz % 10u; }
    if column == 2u { return 46u; }
    if column == 3u { return 48u + frac_khz; }
    if column == 4u { return 75u; }
    if column == 5u { return 72u; }
    if column == 6u { return 90u; }
    return 32u;
}

fn get_group_char(group: u32, column: u32) -> u32 {
    let g0 = array<u32, 6>(77u, 65u, 73u, 78u, 0u, 0u); // MAIN
    let g1 = array<u32, 6>(86u, 79u, 67u, 65u, 76u, 83u); // VOCALS
    let g2 = array<u32, 6>(66u, 65u, 83u, 83u, 0u, 0u); // BASS
    let g3 = array<u32, 6>(79u, 84u, 72u, 69u, 82u, 0u); // OTHER
    let g4 = array<u32, 6>(75u, 73u, 67u, 75u, 83u, 0u); // KICKS
    let g5 = array<u32, 6>(83u, 78u, 65u, 82u, 69u, 83u); // SNARES
    let g6 = array<u32, 6>(72u, 73u, 72u, 65u, 84u, 83u); // HIHATS
    if column >= 6u { return 0u; }
    if group == 0u { return g0[column]; }
    if group == 1u { return g1[column]; }
    if group == 2u { return g2[column]; }
    if group == 3u { return g3[column]; }
    if group == 4u { return g4[column]; }
    if group == 5u { return g5[column]; }
    if group == 6u { return g6[column]; }
    return 0u;
}

fn get_item_char(item: u32, column: u32) -> u32 {
    let c0 = array<u32, 10>(72u, 73u, 71u, 72u, 0u, 0u, 0u, 0u, 0u, 0u); // HIGH
    let c1 = array<u32, 10>(76u, 79u, 87u, 0u, 0u, 0u, 0u, 0u, 0u, 0u); // LOW
    let c2 = array<u32, 10>(77u, 73u, 68u, 0u, 0u, 0u, 0u, 0u, 0u, 0u); // MID
    let c3 = array<u32, 10>(82u, 77u, 83u, 0u, 0u, 0u, 0u, 0u, 0u, 0u); // RMS
    let c4 = array<u32, 10>(80u, 69u, 65u, 75u, 0u, 0u, 0u, 0u, 0u, 0u); // PEAK
    let c5 = array<u32, 10>(69u, 78u, 86u, 32u, 70u, 65u, 83u, 84u, 0u, 0u); // ENV FAST
    let c6 = array<u32, 10>(69u, 78u, 86u, 32u, 83u, 76u, 79u, 87u, 0u, 0u); // ENV SLOW
    let c7 = array<u32, 10>(70u, 76u, 85u, 88u, 0u, 0u, 0u, 0u, 0u, 0u); // FLUX
    let c8 = array<u32, 10>(66u, 82u, 73u, 71u, 72u, 84u, 78u, 69u, 83u, 83u); // BRIGHTNESS
    let c9 = array<u32, 10>(66u, 69u, 65u, 84u, 0u, 0u, 0u, 0u, 0u, 0u); // BEAT
    let c10 = array<u32, 10>(73u, 77u, 80u, 65u, 67u, 84u, 0u, 0u, 0u, 0u); // IMPACT
    let c11 = array<u32, 10>(80u, 73u, 84u, 67u, 72u, 0u, 0u, 0u, 0u, 0u); // PITCH
    if column >= 10u { return 0u; }
    if item == 0u { return c0[column]; }
    if item == 1u { return c1[column]; }
    if item == 2u { return c2[column]; }
    if item == 3u { return c3[column]; }
    if item == 4u { return c4[column]; }
    if item == 5u { return c5[column]; }
    if item == 6u { return c6[column]; }
    if item == 7u { return c7[column]; }
    if item == 8u { return c8[column]; }
    if item == 9u { return c9[column]; }
    if item == 10u { return c10[column]; }
    if item == 11u { return c11[column]; }
    return 0u;
}

fn group_label_char_code(group: u32, item: u32, column: u32) -> u32 {
    var g_len = 0u;
    for (var i = 0u; i < 6u; i = i + 1u) {
        if get_group_char(group, i) != 0u { g_len = i + 1u; }
    }
    if column < g_len {
        return get_group_char(group, column);
    }
    if column == g_len { return 32u; }
    if column == g_len + 1u { return 45u; }
    if column == g_len + 2u { return 32u; }
    return get_item_char(item, column - g_len - 3u);
}

fn get_group_and_item(source_index: u32) -> vec2<u32> {
    if source_index == 1u { return vec2<u32>(0u, 1u); } // low
    if source_index == 2u { return vec2<u32>(0u, 2u); } // mid
    if source_index == 3u { return vec2<u32>(0u, 0u); } // high
    if source_index >= 4u && source_index <= 12u { return vec2<u32>(0u, source_index - 1u); }
    if source_index >= 77u && source_index <= 148u {
        let offset = source_index - 77u;
        return vec2<u32>(offset / 12u + 1u, offset % 12u);
    }
    return vec2<u32>(999u, 999u);
}

fn get_feature_index(group: u32, item: u32) -> u32 {
    if group == 0u {
        if item == 0u { return 3u; }
        if item == 1u { return 1u; }
        if item == 2u { return 2u; }
        return item + 1u;
    }
    return 77u + (group - 1u) * 12u + item;
}

fn render_value(local_px: vec2<f32>, min_px: vec2<f32>, max_px: vec2<f32>, raw: f32) -> f32 {
    let style = text_style();
    let box_size = max_px - min_px;
    let base_height = box_size.y * 0.9 * style.y;
    let tracking = style.z;
    let punctuation_scale = style.w;
    var total_advance = 0.0;
    for (var i = 0u; i < 4u; i = i + 1u) {
        let code = value_code(raw, i);
        let advance_scale = select(1.0, punctuation_scale, is_punctuation(code));
        total_advance += max(glyph_layout(code).z, 0.22) * base_height * tracking * advance_scale;
    }
    let base_y = min_px.y + (box_size.y - base_height) * 0.5;
    var x_cursor = min_px.x + (box_size.x - total_advance) * 0.5;
    var ink = 0.0;
    for (var i = 0u; i < 4u; i = i + 1u) {
        let code = value_code(raw, i);
        let metrics = glyph_layout(code);
        let punctuation = is_punctuation(code);
        let glyph_height = select(base_height, base_height * punctuation_scale, punctuation);
        let glyph_y = base_y + select(0.0, base_height * 0.28, punctuation);
        let visible_width = max((metrics.y - metrics.x) * glyph_height, glyph_height * 0.08);
        let glyph_min = vec2<f32>(x_cursor + metrics.x * glyph_height, glyph_y);
        let glyph_max = vec2<f32>(glyph_min.x + visible_width, glyph_y + glyph_height);
        ink = max(ink, render_font_char(local_px, glyph_min, glyph_max, code));
        let advance_scale = select(1.0, punctuation_scale, punctuation);
        x_cursor += max(metrics.z, 0.22) * base_height * tracking * advance_scale;
    }
    return ink;
}

fn timecode_char(total_seconds: f32, column: u32) -> u32 {
    let clamped_seconds = u32(round(clamp(total_seconds, 0.0, 5999.0)));
    let minutes = (clamped_seconds / 60u) % 100u;
    let seconds = clamped_seconds % 60u;
    if column == 0u { return 48u + minutes / 10u; }
    if column == 1u { return 48u + minutes % 10u; }
    if column == 2u { return 58u; }
    if column == 3u { return 48u + seconds / 10u; }
    if column == 4u { return 48u + seconds % 10u; }
    return 0u;
}

fn info_label_char(label_index: u32, column: u32) -> u32 {
    if label_index == 0u {
        if column == 0u { return 80u; }
        if column == 1u { return 79u; }
        if column == 2u { return 83u; }
        return 0u;
    }
    if column == 0u { return 76u; }
    if column == 1u { return 69u; }
    if column == 2u { return 78u; }
    return 0u;
}

fn render_info_label(label_index: u32, local_px: vec2<f32>, min_px: vec2<f32>, max_px: vec2<f32>) -> f32 {
    if local_px.x < min_px.x || local_px.y < min_px.y || local_px.x > max_px.x || local_px.y > max_px.y {
        return 0.0;
    }
    let box_size = max_px - min_px;
    let style = text_style();
    let glyph_height = box_size.y * 1.08 * style.x;
    let base_y = min_px.y + (box_size.y - glyph_height) * 0.5;
    var x_cursor = min_px.x;
    var ink = 0.0;
    for (var i = 0u; i < 3u; i = i + 1u) {
        let code = info_label_char(label_index, i);
        if code == 0u {
            break;
        }
        let metrics = glyph_layout(code);
        let visible_width = max((metrics.y - metrics.x) * glyph_height, glyph_height * 0.05);
        let glyph_min = vec2<f32>(x_cursor + metrics.x * glyph_height, base_y);
        let glyph_max = vec2<f32>(glyph_min.x + visible_width, base_y + glyph_height);
        ink = max(ink, render_font_char(local_px, glyph_min, glyph_max, code));
        x_cursor += max(metrics.z, 0.22) * glyph_height * style.z;
    }
    return ink;
}

fn render_timecode(local_px: vec2<f32>, min_px: vec2<f32>, max_px: vec2<f32>, total_seconds: f32) -> f32 {
    if local_px.x < min_px.x || local_px.y < min_px.y || local_px.x > max_px.x || local_px.y > max_px.y {
        return 0.0;
    }
    let box_size = max_px - min_px;
    let style = text_style();
    let glyph_height = box_size.y * 1.02 * style.x;
    let base_y = min_px.y + (box_size.y - glyph_height) * 0.5;
    var total_advance = 0.0;
    for (var i = 0u; i < 5u; i = i + 1u) {
        let code = timecode_char(total_seconds, i);
        total_advance += max(glyph_layout(code).z, 0.22) * glyph_height * style.z;
    }
    var x_cursor = min_px.x + (box_size.x - total_advance) * 0.5;
    var ink = 0.0;
    for (var i = 0u; i < 5u; i = i + 1u) {
        let code = timecode_char(total_seconds, i);
        let metrics = glyph_layout(code);
        let visible_width = max((metrics.y - metrics.x) * glyph_height, glyph_height * 0.05);
        let glyph_min = vec2<f32>(x_cursor + metrics.x * glyph_height, base_y);
        let glyph_max = vec2<f32>(glyph_min.x + visible_width, base_y + glyph_height);
        ink = max(ink, render_font_char(local_px, glyph_min, glyph_max, code));
        x_cursor += max(metrics.z, 0.22) * glyph_height * style.z;
    }
    return ink;
}

fn current_section_kind() -> u32 {
    return 5u;
}

fn section_info_char(kind: u32, column: u32) -> u32 {
    if column == 7u {
        return 32u;
    }
    if column == 0u { return 83u; }
    if column == 1u { return 69u; }
    if column == 2u { return 67u; }
    if column == 3u { return 84u; }
    if column == 4u { return 73u; }
    if column == 5u { return 79u; }
    if column == 6u { return 78u; }
    let name_column = column - 8u;
    if kind == 0u {
        if name_column == 0u { return 73u; }
        if name_column == 1u { return 78u; }
        if name_column == 2u { return 84u; }
        if name_column == 3u { return 82u; }
        if name_column == 4u { return 79u; }
        return 0u;
    }
    if kind == 1u {
        if name_column == 0u { return 86u; }
        if name_column == 1u { return 69u; }
        if name_column == 2u { return 82u; }
        if name_column == 3u { return 83u; }
        if name_column == 4u { return 69u; }
        return 0u;
    }
    if kind == 2u {
        if name_column == 0u { return 67u; }
        if name_column == 1u { return 72u; }
        if name_column == 2u { return 79u; }
        if name_column == 3u { return 82u; }
        if name_column == 4u { return 85u; }
        if name_column == 5u { return 83u; }
        return 0u;
    }
    if kind == 3u {
        if name_column == 0u { return 66u; }
        if name_column == 1u { return 82u; }
        if name_column == 2u { return 69u; }
        if name_column == 3u { return 65u; }
        if name_column == 4u { return 75u; }
        return 0u;
    }
    if kind == 4u {
        if name_column == 0u { return 79u; }
        if name_column == 1u { return 85u; }
        if name_column == 2u { return 84u; }
        if name_column == 3u { return 82u; }
        if name_column == 4u { return 79u; }
        return 0u;
    }
    if name_column == 0u { return 85u; }
    if name_column == 1u { return 78u; }
    if name_column == 2u { return 75u; }
    if name_column == 3u { return 78u; }
    if name_column == 4u { return 79u; }
    if name_column == 5u { return 87u; }
    if name_column == 6u { return 78u; }
    return 0u;
}

fn render_section_info(local_px: vec2<f32>, min_px: vec2<f32>, max_px: vec2<f32>, kind: u32) -> f32 {
    if local_px.x < min_px.x || local_px.y < min_px.y || local_px.x > max_px.x || local_px.y > max_px.y {
        return 0.0;
    }
    let box_size = max_px - min_px;
    let style = text_style();
    let glyph_height = box_size.y * 1.04 * style.x;
    let base_y = min_px.y + (box_size.y - glyph_height) * 0.5;
    var total_advance = 0.0;
    var char_count = 0u;
    for (var i = 0u; i < 16u; i = i + 1u) {
        let code = section_info_char(kind, i);
        if code == 0u {
            break;
        }
        total_advance += max(glyph_layout(code).z, 0.22) * glyph_height * style.z;
        char_count = i + 1u;
    }
    var x_cursor = min_px.x + (box_size.x - total_advance) * 0.5;
    var ink = 0.0;
    for (var i = 0u; i < 16u; i = i + 1u) {
        if i >= char_count {
            break;
        }
        let code = section_info_char(kind, i);
        let metrics = glyph_layout(code);
        let visible_width = max((metrics.y - metrics.x) * glyph_height, glyph_height * 0.05);
        let glyph_min = vec2<f32>(x_cursor + metrics.x * glyph_height, base_y);
        let glyph_max = vec2<f32>(glyph_min.x + visible_width, base_y + glyph_height);
        ink = max(ink, render_font_char(local_px, glyph_min, glyph_max, code));
        x_cursor += max(metrics.z, 0.22) * glyph_height * style.z;
    }
    return ink;
}

fn render_project_text_line(
    local_px: vec2<f32>,
    min_px: vec2<f32>,
    max_px: vec2<f32>,
    start_index: u32,
) -> f32 {
    if local_px.x < min_px.x || local_px.y < min_px.y || local_px.x > max_px.x || local_px.y > max_px.y {
        return 0.0;
    }
    let box_size = max_px - min_px;
    let style = text_style();
    let glyph_height = box_size.y * 0.9 * style.x;
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
    var x_cursor = min_px.x + (box_size.x - total_advance) * 0.5;
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
    }
    return ink;
}

fn render_row_text(group: u32, item: u32, local_px: vec2<f32>, min_px: vec2<f32>, max_px: vec2<f32>) -> f32 {
    if local_px.x < min_px.x || local_px.y < min_px.y || local_px.x > max_px.x || local_px.y > max_px.y {
        return 0.0;
    }
    let box_size = max_px - min_px;
    let style = text_style();
    let glyph_height = box_size.y * 0.82 * style.x;
    let base_y = min_px.y + (box_size.y - glyph_height) * 0.5;
    var x_cursor = min_px.x + 8.0;
    var ink = 0.0;
    for (var i = 0u; i < 20u; i = i + 1u) {
        let code = group_label_char_code(group, item, i);
        if code == 0u {
            break;
        }
        let metrics = glyph_layout(code);
        let visible_width = max((metrics.y - metrics.x) * glyph_height, glyph_height * 0.05);
        let glyph_min = vec2<f32>(x_cursor + metrics.x * glyph_height, base_y);
        let glyph_max = vec2<f32>(glyph_min.x + visible_width, base_y + glyph_height);
        ink = max(ink, render_font_char(local_px, glyph_min, glyph_max, code));
        x_cursor += max(metrics.z, 0.22) * glyph_height * style.z;
        if x_cursor > max_px.x {
            break;
        }
    }
    return ink;
}

fn render_row_text_halo(group: u32, item: u32, local_px: vec2<f32>, min_px: vec2<f32>, max_px: vec2<f32>) -> f32 {
    let base = render_row_text(group, item, local_px, min_px, max_px);
    let offsets = array<vec2<f32>, 8>(
        vec2<f32>(-1.4, 0.0),
        vec2<f32>(1.4, 0.0),
        vec2<f32>(0.0, -1.4),
        vec2<f32>(0.0, 1.4),
        vec2<f32>(-1.1, -1.1),
        vec2<f32>(1.1, -1.1),
        vec2<f32>(-1.1, 1.1),
        vec2<f32>(1.1, 1.1),
    );
    var halo = 0.0;
    for (var i = 0u; i < 8u; i = i + 1u) {
        halo = max(halo, render_row_text(group, item, local_px + offsets[i], min_px, max_px));
    }
    return clamp(halo - base, 0.0, 1.0);
}

fn history_spline(p0: f32, p1: f32, p2: f32, p3: f32, t: f32, tension: f32) -> f32 {
    let t2 = t * t;
    let t3 = t2 * t;
    let cr = 0.5 * (
        (2.0 * p1) +
        (-p0 + p2) * t +
        (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
        (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
    );
    return mix(mix(p1, p2, t), clamp(cr, 0.0, 1.0), tension);
}

fn history_scope_emission(
    local_px: vec2<f32>,
    min_px: vec2<f32>,
    max_px: vec2<f32>,
    accent: vec3<f32>,
    index: u32,
) -> vec3<f32> {
    if local_px.x < min_px.x || local_px.y < min_px.y || local_px.x > max_px.x || local_px.y > max_px.y {
        return vec3<f32>(0.0, 0.0, 0.0);
    }
    let scope_size = max(max_px - min_px, vec2<f32>(1.0, 1.0));
    let norm = (local_px - min_px) / scope_size;
    let sample_count = audio_history_samples();
    let step_seconds = 0.045;
    let shift_fraction = fract(scene.timeline.x / step_seconds);
    let visual_span = max(1u, sample_count - 2u);
    let sample_position = norm.x * f32(visual_span) + shift_fraction;
    let left_index = min(u32(floor(sample_position)), sample_count - 1u);
    let right_index = min(left_index + 1u, sample_count - 1u);
    let sample_mix = fract(sample_position);
    let scope_style = u32(audio_scope_params(index).x + 0.5);
    
    let p0_idx = select(left_index - 1u, 0u, left_index == 0u);
    let p3_idx = min(right_index + 1u, sample_count - 1u);
    let p0 = scope_display_level(index, normalized_value(index, audio_history_value(index, p0_idx)));
    let p1 = scope_display_level(index, normalized_value(index, audio_history_value(index, left_index)));
    let p2 = scope_display_level(index, normalized_value(index, audio_history_value(index, right_index)));
    let p3 = scope_display_level(index, normalized_value(index, audio_history_value(index, p3_idx)));
    let smooth_level = history_spline(p0, p1, p2, p3, sample_mix, scene.timeline.w);
    let line_level = select(smooth_level, fract(sample_position), scope_style == 1u);
    let line_y = scope_plot_y(min_px, max_px, line_level);
    let distance = abs(local_px.y - line_y);
    let line_core = 1.0 - smoothstep(0.0, 2.0, distance);
    let line_glow = 1.0 - smoothstep(0.0, 8.0, distance);
    let fade = mix(0.68, 1.0, norm.x);
    let glow = (accent * 0.82 + vec3<f32>(0.08, 0.16, 0.15)) * line_glow * 0.48 * fade;
    let core = (accent * 1.05 + vec3<f32>(0.92, 0.98, 0.96)) * line_core * fade;
    
    let current_pos = f32(visual_span) + shift_fraction;
    let dot_left_idx = min(u32(floor(current_pos)), sample_count - 1u);
    let dot_right_idx = min(dot_left_idx + 1u, sample_count - 1u);
    let dot_mix = fract(current_pos);
    let dot_p0_idx = select(dot_left_idx - 1u, 0u, dot_left_idx == 0u);
    let dot_p3_idx = min(dot_right_idx + 1u, sample_count - 1u);
    let dot_p0 = scope_display_level(index, normalized_value(index, audio_history_value(index, dot_p0_idx)));
    let dot_p1 = scope_display_level(index, normalized_value(index, audio_history_value(index, dot_left_idx)));
    let dot_p2 = scope_display_level(index, normalized_value(index, audio_history_value(index, dot_right_idx)));
    let dot_p3 = scope_display_level(index, normalized_value(index, audio_history_value(index, dot_p3_idx)));
    let dot_smooth = history_spline(dot_p0, dot_p1, dot_p2, dot_p3, dot_mix, scene.timeline.w);
    let current_level = select(dot_smooth, dot_mix, scope_style == 1u);
    let point_x = max_px.x - 2.6;
    let point_y = scope_plot_y(min_px, max_px, current_level);
    let point = round_rect_alpha(
        local_px,
        vec2<f32>(point_x - 3.2, point_y - 3.2),
        vec2<f32>(point_x + 3.2, point_y + 3.2),
        3.2,
        1.0,
    );
    let point_glow = round_rect_alpha(
        local_px,
        vec2<f32>(point_x - 7.0, point_y - 7.0),
        vec2<f32>(point_x + 7.0, point_y + 7.0),
        7.0,
        1.4,
    );
    return glow + core + accent * point_glow * 0.6 + (accent + vec3<f32>(0.95, 1.0, 0.97)) * point;
}

fn render_equalizer_resolution_panel(
    local_px: vec2<f32>,
    panel_size: vec2<f32>,
    band_count: u32,
    panel_mix: f32,
) -> vec3<f32> {
    let accent = apply_debug_accent(
        mix(vec3<f32>(0.30, 0.76, 0.98), vec3<f32>(0.78, 0.96, 0.38), panel_mix),
    );
    let panel_alpha = round_rect_alpha(local_px, vec2<f32>(0.0, 0.0), panel_size, 10.0, 1.0);
    let bg = scene_bg_color();
    var color = mix(bg + vec3<f32>(0.008), bg + vec3<f32>(0.016), panel_alpha);
    let frame = round_rect_alpha(local_px, vec2<f32>(0.0, 0.0), panel_size, 10.0, 1.0)
        - round_rect_alpha(local_px, vec2<f32>(2.0, 2.0), panel_size - vec2<f32>(2.0, 2.0), 8.0, 1.0);
    color = mix(color, accent * 0.4 + vec3<f32>(0.08, 0.12, 0.14), clamp(frame, 0.0, 1.0));
    let inner_min = vec2<f32>(8.0, 10.0);
    let inner_max = panel_size - vec2<f32>(8.0, 10.0);
    let inner_alpha = round_rect_alpha(local_px, inner_min, inner_max, 8.0, 1.0);
    color = mix(color, vec3<f32>(0.0, 0.005, 0.009), inner_alpha);
    if local_px.x >= inner_min.x && local_px.x <= inner_max.x && local_px.y >= inner_min.y && local_px.y <= inner_max.y {
        let norm_x = clamp((local_px.x - inner_min.x) / max(inner_max.x - inner_min.x, 1.0), 0.0, 0.999999);
        let band_index = min(u32(floor(norm_x * f32(band_count))), band_count - 1u);
        let level = clamp(audio_eq_level_value(band_index, band_count), 0.0, 1.0);
        let peak_level = max(level, clamp(audio_eq_peak_value(band_index, band_count), 0.0, 1.0));
        let bar_top = eq_bar_top_y(inner_min.y, inner_max.y, level);
        let peak_top = clamp(
            max(eq_bar_top_y(inner_min.y, inner_max.y, peak_level), bar_top + 2.6),
            inner_min.y + 1.8,
            inner_max.y - 1.8,
        );
        let tint = mix(accent, vec3<f32>(0.94, 0.98, 0.80), f32(band_index) / max(f32(band_count - 1u), 1.0));
        let column = 1.0 - smoothstep(0.0, 0.9, abs(fract(norm_x * f32(band_count)) - 0.5) * 2.0);
        let body = (1.0 - smoothstep(bar_top - 1.0, bar_top + 1.0, local_px.y)) * column;
        let glow = (1.0 - smoothstep(0.0, 8.0, abs(local_px.y - bar_top))) * column;
        let cap_width = mix(
            1.0 - smoothstep(0.52, 1.0, abs(fract(norm_x * f32(band_count)) - 0.5) * 2.0),
            1.0,
            clamp((f32(band_count) - 64.0) / 448.0, 0.0, 1.0),
        );
        let cap_distance = abs(local_px.y - peak_top);
        let peak_shadow = (1.0 - smoothstep(0.0, 3.8, cap_distance)) * cap_width;
        let peak_line = (1.0 - smoothstep(0.0, 1.05, cap_distance)) * cap_width;
        let peak_glow = (1.0 - smoothstep(0.0, 8.0, cap_distance)) * cap_width;
        color += tint * body * 0.82;
        color += tint * glow * 0.28;
        color = mix(color, vec3<f32>(0.0, 0.0, 0.0), peak_shadow * 0.18);
        color += vec3<f32>(1.0, 0.08, 0.12) * peak_line * 1.45;
        color += vec3<f32>(0.92, 0.10, 0.14) * peak_glow * 0.28;
    }
    let label_min = vec2<f32>(max(10.0, panel_size.x - 46.0), 6.0);
    let label_max = vec2<f32>(panel_size.x - 8.0, 28.0);
    let label_bg = round_rect_alpha(local_px, label_min, label_max, 6.0, 1.0);
    color = mix(color, vec3<f32>(0.022, 0.034, 0.046), label_bg * 0.9);
    let style = text_style();
    let glyph_height = (label_max.y - label_min.y) * 1.45 * style.x;
    let base_y = label_min.y + ((label_max.y - label_min.y) - glyph_height) * 0.5;
    var total_advance = 0.0;
    var char_count = 0u;
    for (var i = 0u; i < 4u; i = i + 1u) {
        let code = eq_panel_title_char(band_count, i);
        if code == 0u {
            break;
        }
        total_advance += max(glyph_layout(code).z, 0.22) * glyph_height * style.z;
        char_count = i + 1u;
    }
    var x_cursor = label_max.x - total_advance - 4.0;
    var ink = 0.0;
    for (var i = 0u; i < 4u; i = i + 1u) {
        if i >= char_count {
            break;
        }
        let code = eq_panel_title_char(band_count, i);
        let metrics = glyph_layout(code);
        let visible_width = max((metrics.y - metrics.x) * glyph_height, glyph_height * 0.05);
        let glyph_min = vec2<f32>(x_cursor + metrics.x * glyph_height, base_y);
        let glyph_max = vec2<f32>(glyph_min.x + visible_width, base_y + glyph_height);
        ink = max(ink, render_font_char(local_px, glyph_min, glyph_max, code));
        x_cursor += max(metrics.z, 0.22) * glyph_height * style.z;
    }
    color = mix(color, ui_text_accent_color(accent), ink);
    return color;
}

fn render_scalar_band_panel(
    local_px: vec2<f32>,
    panel_size: vec2<f32>,
    panel_index: u32,
    panel_mix: f32,
) -> vec3<f32> {
    let accent = apply_debug_accent(
        mix(vec3<f32>(0.98, 0.60, 0.20), vec3<f32>(0.30, 0.84, 0.98), panel_mix),
    );
    let source_index = scalar_band_source_index(panel_index);
    let panel_alpha = round_rect_alpha(local_px, vec2<f32>(0.0, 0.0), panel_size, 10.0, 1.0);
    let bg = scene_bg_color();
    var color = mix(bg + vec3<f32>(0.010), bg + vec3<f32>(0.018), panel_alpha);
    let frame = round_rect_alpha(local_px, vec2<f32>(0.0, 0.0), panel_size, 10.0, 1.0)
        - round_rect_alpha(local_px, vec2<f32>(2.0, 2.0), panel_size - vec2<f32>(2.0, 2.0), 8.0, 1.0);
    color = mix(color, accent * 0.38 + vec3<f32>(0.08, 0.12, 0.14), clamp(frame, 0.0, 1.0));
    let inner_min = vec2<f32>(10.0, 12.0);
    let inner_max = panel_size - vec2<f32>(10.0, 12.0);
    let level = clamp(normalized_value(source_index, audio_value(source_index)), 0.0, 1.0);
    let peak_level = max(level, clamp(audio_scalar_history_peak_value(source_index), 0.0, 1.0));
    let bar_half_width = max((inner_max.x - inner_min.x) * 0.22, 8.0);
    let bar_center_x = mix(inner_min.x, inner_max.x, 0.5);
    let inner_height = max(inner_max.y - inner_min.y, 1.0);
    let bar_height = level * inner_height;
    let peak_height = peak_level * inner_height;
    let bar_top = clamp(inner_min.y + bar_height, inner_min.y, inner_max.y);
    let peak_top = clamp(
        max(inner_min.y + peak_height, bar_top + 3.0),
        inner_min.y + 1.8,
        inner_max.y - 1.8,
    );
    let bar_min = vec2<f32>(bar_center_x - bar_half_width, inner_min.y);
    let bar_max = vec2<f32>(bar_center_x + bar_half_width, bar_top);
    let bar_alpha = round_rect_alpha(local_px, bar_min, bar_max, 6.0, 1.0);
    color = mix(color, accent * 0.82 + vec3<f32>(0.16, 0.18, 0.12), bar_alpha);
    let glow = round_rect_alpha(local_px, bar_min - vec2<f32>(8.0, 8.0), bar_max + vec2<f32>(8.0, 8.0), 12.0, 2.0);
    color += accent * glow * 0.12;
    let cap_min = vec2<f32>(bar_center_x - bar_half_width - 2.0, peak_top - 1.1);
    let cap_max = vec2<f32>(bar_center_x + bar_half_width + 2.0, peak_top + 1.1);
    let cap_alpha = round_rect_alpha(local_px, cap_min, cap_max, 2.0, 1.0);
    let cap_glow = round_rect_alpha(local_px, cap_min - vec2<f32>(6.0, 5.0), cap_max + vec2<f32>(6.0, 5.0), 7.0, 1.4);
    color = mix(color, vec3<f32>(1.0, 0.08, 0.12), cap_alpha);
    color += vec3<f32>(0.92, 0.10, 0.14) * cap_glow * 0.18;
    return color;
}

fn render_equalizer_panel(local_px: vec2<f32>, panel_size: vec2<f32>) -> vec3<f32> {
    let panel_counts = array<u32, 4>(128u, 64u, 32u, 16u);
    let gap = 8.0;
    let total_panels = EQ_SCALAR_PANEL_COUNT + 4u;
    let width = (panel_size.x - gap * f32(total_panels - 1u)) / f32(total_panels);
    var color = vec3<f32>(0.0, 0.0, 0.0);
    for (var panel_index = 0u; panel_index < total_panels; panel_index = panel_index + 1u) {
        let panel_min = vec2<f32>(f32(panel_index) * (width + gap), 0.0);
        let panel_max = panel_min + vec2<f32>(width, panel_size.y);
        if local_px.x < panel_min.x || local_px.y < panel_min.y || local_px.x > panel_max.x || local_px.y > panel_max.y {
            continue;
        }
        if panel_index < EQ_SCALAR_PANEL_COUNT {
            color += render_scalar_band_panel(
                local_px - panel_min,
                vec2<f32>(width, panel_size.y),
                panel_index,
                f32(panel_index) / max(f32(total_panels - 1u), 1.0),
            );
        } else {
            let resolution_index = panel_index - EQ_SCALAR_PANEL_COUNT;
            color += render_equalizer_resolution_panel(
                local_px - panel_min,
                vec2<f32>(width, panel_size.y),
                min(panel_counts[resolution_index], debug_band_limit()),
                f32(panel_index) / max(f32(total_panels - 1u), 1.0),
            );
        }
    }
    return color;
}

fn render_bottom_bar(local_px: vec2<f32>, panel_size: vec2<f32>) -> vec3<f32> {
    let accent = apply_debug_accent(vec3<f32>(0.98, 0.82, 0.22));
    let bar_alpha = round_rect_alpha(local_px, vec2<f32>(0.0, 0.0), panel_size, 8.0, 1.0);
    let bg = scene_bg_color();
    var color = mix(bg + vec3<f32>(0.010), bg + vec3<f32>(0.020), bar_alpha);
    let frame = round_rect_alpha(local_px, vec2<f32>(0.0, 0.0), panel_size, 8.0, 1.0)
        - round_rect_alpha(local_px, vec2<f32>(1.5, 1.5), panel_size - vec2<f32>(1.5, 1.5), 6.5, 1.0);
    color = mix(color, accent * 0.24 + vec3<f32>(0.08, 0.10, 0.12), clamp(frame, 0.0, 1.0));
    let current_seconds = timeline_current_seconds();
    let total_seconds = timeline_total_seconds();
    let label_color = ui_text_base_color();
    let value_color = ui_text_bright_color();
    let gap = 8.0;
    let logo_side = clamp(panel_size.y - 24.0, 24.0, 30.0);
    let logo_box_max = vec2<f32>(panel_size.x - 8.0, panel_size.y - 11.0);
    let logo_box_min = logo_box_max - vec2<f32>(logo_side, logo_side);
    let content_right = logo_box_min.x - gap;
    let row_min_y = 15.0;
    let row_max_y = 31.0;
    let pos_box_min = vec2<f32>(12.0, row_min_y);
    let pos_box_max = vec2<f32>(118.0, row_max_y);
    let pos_bg = round_rect_alpha(local_px, pos_box_min, pos_box_max, 5.0, 1.0);
    let pos_label = render_info_label(0u, local_px, pos_box_min + vec2<f32>(8.0, 1.0), pos_box_min + vec2<f32>(34.0, 15.0));
    let pos_value = render_timecode(local_px, pos_box_min + vec2<f32>(34.0, 0.0), pos_box_max - vec2<f32>(6.0, 0.0), current_seconds);
    color = mix(color, bg + vec3<f32>(0.020), pos_bg * 0.92);
    color = mix(color, label_color, pos_label * 0.94);
    color = mix(color, value_color, pos_value);
    let len_box_min = vec2<f32>(pos_box_max.x + gap, row_min_y);
    let len_box_max = vec2<f32>(234.0, row_max_y);
    let len_bg = round_rect_alpha(local_px, len_box_min, len_box_max, 5.0, 1.0);
    let len_label = render_info_label(1u, local_px, len_box_min + vec2<f32>(8.0, 1.0), len_box_min + vec2<f32>(34.0, 15.0));
    let len_value = render_timecode(local_px, len_box_min + vec2<f32>(34.0, 0.0), len_box_max - vec2<f32>(6.0, 0.0), total_seconds);
    color = mix(color, bg + vec3<f32>(0.020), len_bg * 0.92);
    color = mix(color, label_color, len_label * 0.94);
    color = mix(color, value_color, len_value);
    let section_width = select(0.0, 112.0, debug_show_underlay());
    let title_right = content_right - select(0.0, section_width + gap, debug_show_underlay());
    let text_min_x = len_box_max.x + gap;
    let text_span = max(title_right - text_min_x, 180.0);
    let band_width = clamp(text_span * 0.28, 80.0, 128.0);
    let band_box_min = vec2<f32>(text_min_x, row_min_y);
    let band_box_max = vec2<f32>(band_box_min.x + band_width, row_max_y);
    let band_bg = round_rect_alpha(local_px, band_box_min, band_box_max, 5.0, 1.0);
    let band_ink = render_project_text_line(local_px, band_box_min + vec2<f32>(10.0, 1.0), band_box_max - vec2<f32>(10.0, 1.0), 0u);
    color = mix(color, bg + vec3<f32>(0.020), band_bg * 0.92);
    color = mix(color, ui_text_base_color(), band_ink);
    let title_box_min = vec2<f32>(band_box_max.x + gap, row_min_y);
    let title_box_max = vec2<f32>(title_right, row_max_y);
    if title_box_max.x > title_box_min.x + 36.0 {
        let title_bg = round_rect_alpha(local_px, title_box_min, title_box_max, 5.0, 1.0);
        let title_ink = render_project_text_line(local_px, title_box_min + vec2<f32>(10.0, 1.0), title_box_max - vec2<f32>(10.0, 1.0), 16u);
        color = mix(color, bg + vec3<f32>(0.020), title_bg * 0.92);
        color = mix(color, ui_text_bright_color(), title_ink);
    }
    if debug_show_underlay() {
        let section_box_min = vec2<f32>(content_right - section_width, row_min_y);
        let section_box_max = vec2<f32>(content_right, row_max_y);
        let section_bg = round_rect_alpha(local_px, section_box_min, section_box_max, 5.0, 1.0);
        color = mix(color, bg + vec3<f32>(0.020), section_bg * 0.92);
        let section_ink = render_section_info(local_px, section_box_min, section_box_max, current_section_kind());
        color = mix(color, ui_text_accent_color(vec3<f32>(0.38, 0.86, 0.74)), section_ink);
    }
    let logo_card = round_rect_alpha(local_px, logo_box_min, logo_box_max, 6.5, 1.0);
    let logo_frame = round_rect_alpha(local_px, logo_box_min - vec2<f32>(1.0, 1.0), logo_box_max + vec2<f32>(1.0, 1.0), 7.5, 1.0)
        - round_rect_alpha(local_px, logo_box_min + vec2<f32>(2.0, 2.0), logo_box_max - vec2<f32>(2.0, 2.0), 4.5, 1.0);
    let logo_glow = round_rect_alpha(local_px, logo_box_min - vec2<f32>(8.0, 8.0), logo_box_max + vec2<f32>(8.0, 8.0), 13.0, 2.0)
        - logo_card;
    let logo_inner_min = logo_box_min + vec2<f32>(3.0, 3.0);
    let logo_inner_max = logo_box_max - vec2<f32>(3.0, 3.0);
    let logo_inner = round_rect_alpha(local_px, logo_inner_min, logo_inner_max, 4.0, 1.0);
    let logo_uv = clamp(
        (local_px - logo_inner_min) / max(logo_inner_max - logo_inner_min, vec2<f32>(1.0, 1.0)),
        vec2<f32>(0.0),
        vec2<f32>(1.0),
    );
    let logo_sample = textureSampleLevel(preview_image_texture, preview_image_sampler, logo_uv, 0.0);
    let logo_checker =
        select(0.07, 0.11, (u32(floor(local_px.x / 8.0) + floor(local_px.y / 8.0)) % 2u) == 0u);
    color = mix(color, bg + vec3<f32>(0.018), logo_card * 0.94);
    color = mix(color, accent * 0.46 + vec3<f32>(0.10, 0.12, 0.14), clamp(logo_frame, 0.0, 1.0));
    color += mix(accent, vec3<f32>(1.0, 0.97, 0.90), 0.26) * logo_glow * 0.08;
    color = mix(color, vec3<f32>(logo_checker), logo_inner * 0.96);
    color = mix(color, logo_sample.rgb, logo_inner * logo_sample.a);
    return color;
}

fn render_header(local_px: vec2<f32>, panel_size: vec2<f32>, page_index: u32, page_count: u32) -> vec3<f32> {
    _ = page_index;
    _ = page_count;
    let header_min = vec2<f32>(18.0, 18.0);
    let header_max = vec2<f32>(panel_size.x - 18.0, 58.0);
    let header_alpha = round_rect_alpha(local_px, header_min, header_max, 12.0, 1.5);
    let bg = scene_bg_color();
    var color = mix(bg + vec3<f32>(0.004), bg + vec3<f32>(0.012), header_alpha);
    let header_inner = round_rect_alpha(local_px, vec2<f32>(24.0, 24.0), vec2<f32>(panel_size.x - 24.0, 52.0), 9.0, 1.0);
    let header_line = round_rect_alpha(local_px, vec2<f32>(32.0, 38.0), vec2<f32>(panel_size.x - 32.0, 39.5), 1.0, 0.8);
    color = mix(color, bg + vec3<f32>(0.018), header_inner * 0.82);
    color = mix(color, bg + vec3<f32>(0.12), header_line * 0.9);
    return color;
}

fn render_row(group: u32, item: u32, index: u32, local_px: vec2<f32>, row_size: vec2<f32>) -> vec3<f32> {
    let accent = apply_debug_accent(category_color(index));
    let pulse = 0.45 + 0.55 * (0.5 + 0.5 * sin(scene.time * 3.1 + f32(index) * 0.19));
    let stripe_width = clamp(row_size.x * 0.012, 4.0, 7.0);
    let block_inset = clamp(row_size.y * 0.11, 3.0, 6.0);
    let lane_gap = clamp(row_size.x * 0.014, 6.0, 10.0);
    let row_alpha = round_rect_alpha(local_px, vec2<f32>(0.0, 0.0), row_size, 8.0, 1.0);
    let bg = scene_bg_color();
    var color = mix(bg + vec3<f32>(0.006), bg + vec3<f32>(0.018), row_alpha);

    let stripe = round_rect_alpha(local_px, vec2<f32>(0.0, 0.0), vec2<f32>(stripe_width, row_size.y), 4.0, 1.0);
    color = mix(color, accent * 0.95, stripe);
    let row_glow = round_rect_alpha(local_px, vec2<f32>(2.0, 2.0), row_size - vec2<f32>(2.0, 2.0), 8.0, 1.8);
    color += accent * row_glow * 0.045 * (0.65 + 0.35 * pulse);

    let is_large = row_size.y > 100.0;
    var scope_min: vec2<f32>;
    var scope_max: vec2<f32>;
    var text_min: vec2<f32>;
    var text_max: vec2<f32>;

    if is_large {
        let text_height = min(row_size.y * 0.1, 40.0);
        let header_inset = max(block_inset, 10.0);
        text_min = vec2<f32>(stripe_width + 10.0, header_inset);
        text_max = vec2<f32>(row_size.x - 12.0, header_inset + text_height);
        
        scope_min = vec2<f32>(stripe_width + 10.0, header_inset + text_height + 10.0);
        scope_max = vec2<f32>(row_size.x - 12.0, row_size.y - header_inset);
    } else {
        let scope_size = min(row_size.y - block_inset * 2.0, clamp(row_size.x * 0.18, 42.0, 62.0));
        scope_min = vec2<f32>(stripe_width + 10.0, block_inset);
        scope_max = scope_min + vec2<f32>(scope_size, scope_size);
        text_min = vec2<f32>(scope_max.x + lane_gap, block_inset + 1.0);
        text_max = vec2<f32>(row_size.x - 12.0, row_size.y - block_inset);
    }

    let scope_alpha = round_rect_alpha(local_px, scope_min, scope_max, 7.0, 1.0);
    color = mix(color, bg + vec3<f32>(0.008), scope_alpha);
    let scope_frame = round_rect_alpha(local_px, scope_min - vec2<f32>(1.0, 1.0), scope_max + vec2<f32>(1.0, 1.0), 8.0, 1.0)
        - round_rect_alpha(local_px, scope_min + vec2<f32>(1.0, 1.0), scope_max - vec2<f32>(1.0, 1.0), 6.5, 1.0);
    color = mix(color, accent * 0.5 + vec3<f32>(0.08, 0.12, 0.14), clamp(scope_frame, 0.0, 1.0));
    let scope_inner_min = scope_min + vec2<f32>(3.0, 3.0);
    let scope_inner_max = scope_max - vec2<f32>(3.0, 3.0);
    let inner_alpha = round_rect_alpha(local_px, scope_inner_min, scope_inner_max, 5.0, 1.0);
    color = mix(color, bg * 0.5, inner_alpha);
    color += history_scope_emission(local_px, scope_inner_min, scope_inner_max, accent, index) * inner_alpha;

    let text_bg = round_rect_alpha(local_px, text_min - vec2<f32>(4.0, 1.0), text_max + vec2<f32>(3.0, 1.0), 7.0, 1.0);
    color = mix(color, bg + vec3<f32>(0.015), text_bg);
    let row_text_ink = render_row_text(group, item, local_px, text_min, text_max);
    let row_text_halo = render_row_text_halo(group, item, local_px, text_min, text_max);
    color = mix(color, ui_text_accent_color(accent), row_text_ink);
    color = local_bloom_color(
        color,
        ui_text_accent_color(accent),
        row_text_halo,
        0.56,
        mix(accent, vec3<f32>(1.0, 0.96, 0.86), 0.35),
    );
    return color;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let centered = in.uv * 2.0 - vec2<f32>(1.0, 1.0);
    let vignette = 1.0 - clamp(dot(centered, centered) * 0.4, 0.0, 0.58);
    let bg = scene_bg_color();
    var color = mix(bg * 0.5, bg, 1.0 - in.uv.y);
    color = color * vignette;
    color += bg * (1.0 - in.uv.x) * 0.18;

    let panel_min = vec2<f32>(12.0, 10.0);
    let panel_max = scene.resolution - vec2<f32>(12.0, 10.0);
    let panel_alpha = round_rect_alpha(in.uv * scene.resolution, panel_min, panel_max, 18.0, 2.0);
    let frame_rgba = debug_frame_rgba();
    let panel_frame = round_rect_alpha(in.uv * scene.resolution, panel_min, panel_max, 18.0, 2.0)
        - round_rect_alpha(in.uv * scene.resolution, panel_min + vec2<f32>(4.0, 4.0), panel_max - vec2<f32>(4.0, 4.0), 14.0, 1.0);
    let panel_frame_glow = round_rect_alpha(
        in.uv * scene.resolution,
        panel_min - vec2<f32>(8.0, 8.0),
        panel_max + vec2<f32>(8.0, 8.0),
        24.0,
        3.0,
    ) - panel_alpha;
    let base_bg = scene_bg_color();
    color = mix(color, base_bg + vec3<f32>(0.004), panel_alpha * 0.95);
    color = mix(
        color,
        mix(base_bg + vec3<f32>(0.004), frame_rgba.rgb, 0.72),
        panel_alpha * frame_rgba.a * 0.18,
    );
    color = mix(color, frame_rgba.rgb, clamp(panel_frame * frame_rgba.a, 0.0, 1.0));
    color += frame_rgba.rgb * panel_frame_glow * frame_rgba.a * 0.34;

    let active_count = min(GRID_COUNT, u32(scene.audio_meta.x + 0.5));
    let display_count = min(DISPLAY_COUNT, select(active_count, DETAIL_COUNT + 1u, active_count >= GRID_COUNT));
    if display_count > 0u {
        var total_visible_details = 0u;
        for (var i = 4u; i < 149u; i = i + 1u) {
            if i >= 13u && i <= 76u { continue; } // skip spectrum
            if is_feature_visible(i) {
                total_visible_details = total_visible_details + 1u;
            }
        }
        let is_stems = active_count > 77u;
        let GROUPS = select(1u, 7u, is_stems);
        let page_count = 1u;
        let page_index = 0u;
        let panel_px = in.uv * scene.resolution - panel_min - debug_panel_offset();
        let panel_size = panel_max - panel_min;
        color = mix(color, render_header(panel_px, panel_size, page_index, page_count), panel_alpha);

        let rows_top = 64.0;
        let rows_bottom = panel_size.y - 8.0;
        let column_gap = 10.0;
        let row_gap = 4.0;
        let content_min = vec2<f32>(8.0, rows_top);
        let content_size = vec2<f32>(panel_size.x - 16.0, rows_bottom - rows_top);
        let local = panel_px - content_min;
        if local.x >= 0.0 && local.y >= 0.0 && local.x <= content_size.x && local.y <= content_size.y {
            let detail_height = (content_size.y - row_gap * 2.0) * 0.74;
            let cols = select(3u, 5u, is_stems);
            let rows = select(4u, 12u, is_stems);
            let detail_cell_width = (content_size.x - column_gap * f32(cols - 1u)) / f32(cols);
            let detail_cell_height = (detail_height - row_gap * f32(rows - 1u)) / f32(rows);
            let eq_min = vec2<f32>(0.0, detail_height + row_gap * 2.0);
            let eq_size = vec2<f32>(content_size.x, content_size.y - eq_min.y);
            if local.y < detail_height {
                let focus = visualizer_focus_index();
                if focus >= 0 {
                    let source_index = u32(focus);
                    if is_feature_visible(source_index) && source_index < active_count {
                        let gi = get_group_and_item(source_index);
                        color = mix(
                            color,
                            render_row(
                                gi.x,
                                gi.y,
                                source_index,
                                local,
                                vec2<f32>(content_size.x, detail_height),
                            ),
                            0.995,
                        );
                    }
                } else {
                    let column_span = detail_cell_width + column_gap;
                    let row_span = detail_cell_height + row_gap;

                    let column = u32(local.x / column_span);
                    let row = u32(local.y / row_span);
                    if column < cols && row < rows {
                        let cell_origin = vec2<f32>(f32(column) * column_span, f32(row) * row_span);
                        let cell_local = local - cell_origin;
                        if cell_local.x >= 0.0 && cell_local.x <= detail_cell_width && cell_local.y >= 0.0 && cell_local.y <= detail_cell_height {      
                            var target_group = 999u;
                            var target_item = 999u;
                            if is_stems {
                                if column < 4u {
                                    target_group = column;
                                    target_item = row;
                                } else if column == 4u {
                                    if row == 0u { target_group = 4u; target_item = 4u; }
                                    else if row == 1u { target_group = 5u; target_item = 4u; }
                                    else if row == 2u { target_group = 6u; target_item = 4u; }
                                }
                            } else {
                                let flat_index = row * cols + column;
                                if flat_index < 12u {
                                    target_group = 0u;
                                    target_item = flat_index;
                                }
                            }

                            if target_group != 999u {
                                let source_index = get_feature_index(target_group, target_item);
                                if source_index < active_count && get_group_and_item(source_index).x != 999u {
                                    color = mix(
                                        color,
                                        render_row(
                                            target_group,
                                            target_item,
                                            source_index,
                                            cell_local,
                                            vec2<f32>(detail_cell_width, detail_cell_height),
                                        ),
                                        0.995,
                                    );
                                }
                            }
                        }
                    }
                }
            } else {
                let eq_local = local - eq_min;
                if eq_local.x >= 0.0 && eq_local.y >= 0.0 && eq_local.x <= eq_size.x && eq_local.y <= eq_size.y {
                    color = mix(color, render_equalizer_panel(eq_local, eq_size), 0.995);
                }
            }
        }
    }

    let bottom_bar_min = vec2<f32>(12.0, 8.0);
    let bottom_bar_max = vec2<f32>(scene.resolution.x - 12.0, 60.0);
    let bottom_bar_size = bottom_bar_max - bottom_bar_min;
    let bottom_bar_local = in.uv * scene.resolution - bottom_bar_min;
    if bottom_bar_local.x >= 0.0
        && bottom_bar_local.y >= 0.0
        && bottom_bar_local.x <= bottom_bar_size.x
        && bottom_bar_local.y <= bottom_bar_size.y
    {
        color = mix(color, render_bottom_bar(bottom_bar_local, bottom_bar_size), 0.995);
    }

    return encode_output_alpha(color, scene_bg_alpha());
}

