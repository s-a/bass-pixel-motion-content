#import <engine::bpm_kernel_bindings>
#import <engine::bpm_kernel_bindings_text>

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOut {
    var positions = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(3.0, -1.0),
        vec2<f32>(-1.0, 3.0)
    );
    let position = positions[vertex_index];
    var out: VertexOut;
    out.clip_position = vec4<f32>(position, 0.0, 1.0);
    out.uv = position * 0.5 + 0.5;
    return out;
}

fn draw_analyzer_column(uv: vec2<f32>, center_x: f32, width: f32, height: f32, color: vec3<f32>, 
                        low: f32, mid: f32, hi: f32, rms: f32, pk: f32, flux: f32, beat: f32, title: array<u32, 16>) -> vec3<f32> {
    
    let col_left = center_x - width * 0.5;
    let col_right = center_x + width * 0.5;
    let col_bottom = -height * 0.5;
    let col_top = height * 0.5;

    var col_rgb = vec3<f32>(0.0);
    let main_font = #font "hud_font";

    // Text rendering uses global uv, we can draw it regardless of bounds
    let title_center = vec2<f32>(center_x, col_bottom + height * 0.94);
    col_rgb += color * bpm_draw_text(title, main_font, uv, title_center, vec2<f32>(0.054, 0.105)) * 1.5;

    let vol_text = #string "VOL";
    let vol_center = vec2<f32>(col_left + width * 0.225, col_bottom + height * 0.05); // adjusted center so it doesn't clip
    col_rgb += color * bpm_draw_text(vol_text, main_font, uv, vol_center, vec2<f32>(0.024, 0.045)) * 0.5;

    let eq_text = #string "LMH";
    let eq_center = vec2<f32>(col_left + width * 0.675, col_bottom + height * 0.05); // adjusted center
    col_rgb += color * bpm_draw_text(eq_text, main_font, uv, eq_center, vec2<f32>(0.024, 0.045)) * 0.5;

    if uv.x < col_left || uv.x > col_right || uv.y < col_bottom || uv.y > col_top {
        return col_rgb;
    }

    col_rgb += color * 0.03; 
    
    let border = 0.005;
    if uv.x < col_left + border || uv.x > col_right - border || uv.y < col_bottom + border || uv.y > col_top - border {
        col_rgb = color * 0.4;
    }

    let local_x = (uv.x - col_left) / width;
    let local_y = (uv.y - col_bottom) / height;

    if local_y < 0.8 {
        let bar_y = local_y / 0.8;
        let track_bg = color * 0.1;

        // RMS / PEAK Meter
        if local_x >= 0.1 && local_x <= 0.35 {
            col_rgb += track_bg;
            if bar_y <= rms { col_rgb += color * 0.9; } 
            else if bar_y <= pk { col_rgb += color * 0.4; }
            if abs(bar_y - pk) < 0.015 { col_rgb += vec3<f32>(1.0); }
        }

        // EQ Bands (Low, Mid, High)
        if local_x >= 0.45 && local_x <= 0.9 {
            if local_x >= 0.45 && local_x <= 0.55 {
                col_rgb += track_bg;
                if bar_y <= low { col_rgb += color * 0.7; }
                if abs(bar_y - low) < 0.015 { col_rgb += color * 1.5; }
            }
            if local_x >= 0.625 && local_x <= 0.725 {
                col_rgb += track_bg;
                if bar_y <= mid { col_rgb += color * 0.7; }
                if abs(bar_y - mid) < 0.015 { col_rgb += color * 1.5; }
            }
            if local_x >= 0.8 && local_x <= 0.9 {
                col_rgb += track_bg;
                if bar_y <= hi { col_rgb += color * 0.7; }
                if abs(bar_y - hi) < 0.015 { col_rgb += color * 1.5; }
            }
        }
        
    } else {
        // Status Top (Beat & Flux)
        if local_y > 0.82 && local_y < 0.88 {
            let status_y = (local_y - 0.82) / 0.06;
            if local_x >= 0.1 && local_x <= 0.9 {
                col_rgb += color * 0.05;
                if status_y < clamp(flux * 0.1, 0.0, 1.0) { col_rgb += color * 0.5; }
                col_rgb += color * beat * 1.5 * exp(-abs(local_x - 0.5) * 5.0);
            }
        }
    }

    if fract(local_y * 0.8 * 10.0) < 0.05 && local_y < 0.8 {
        col_rgb += color * 0.2;
    }

    return col_rgb;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let uv = in.uv;
    let aspect = scene.resolution.x / scene.resolution.y;
    var uv_centered = uv * 2.0 - 1.0;
    uv_centered.x *= aspect;

    var out_rgb = vec3<f32>(0.0);
    let bg_color = #color "scene.bg_color";
    out_rgb += bg_color.rgb;

    let grid_uv = uv_centered * 4.0;
    let grid_line = max(
        1.0 - smoothstep(0.0, 0.05, abs(fract(grid_uv.x) - 0.5)),
        1.0 - smoothstep(0.0, 0.05, abs(fract(grid_uv.y) - 0.5))
    );
    out_rgb += vec3<f32>(0.5, 0.6, 0.7) * grid_line * 0.03;

    let c_k = (#color "scene.hud_color_kicks").rgb;
    let k_l = (#audio "audio.stem.kicks.band.low").clamped_safe;
    let k_m = (#audio "audio.stem.kicks.band.mid").clamped_safe;
    let k_h = (#audio "audio.stem.kicks.band.high").clamped_safe;
    let k_r = (#audio "audio.stem.kicks.rms").clamped_safe;
    let k_p = (#audio "audio.stem.kicks.peak").clamped_safe;
    let k_f = (#audio "audio.stem.kicks.flux").value;
    let k_b = (#audio "audio.stem.kicks.rhythm.beat").clamped_safe;
    let name_k = #string "KICK";

    let c_s = (#color "scene.hud_color_snares").rgb;
    let s_l = (#audio "audio.stem.snares.band.low").clamped_safe;
    let s_m = (#audio "audio.stem.snares.band.mid").clamped_safe;
    let s_h = (#audio "audio.stem.snares.band.high").clamped_safe;
    let s_r = (#audio "audio.stem.snares.rms").clamped_safe;
    let s_p = (#audio "audio.stem.snares.peak").clamped_safe;
    let s_f = (#audio "audio.stem.snares.flux").value;
    let s_b = (#audio "audio.stem.snares.rhythm.beat").clamped_safe;
    let name_s = #string "SNARE";

    let c_h = (#color "scene.hud_color_hihats").rgb;
    let h_l = (#audio "audio.stem.hihats.band.low").clamped_safe;
    let h_m = (#audio "audio.stem.hihats.band.mid").clamped_safe;
    let h_h = (#audio "audio.stem.hihats.band.high").clamped_safe;
    let h_r = (#audio "audio.stem.hihats.rms").clamped_safe;
    let h_p = (#audio "audio.stem.hihats.peak").clamped_safe;
    let h_f = (#audio "audio.stem.hihats.flux").value;
    let h_b = (#audio "audio.stem.hihats.rhythm.beat").clamped_safe;
    let name_h = #string "HIHAT";

    let c_b = (#color "scene.hud_color_bass").rgb;
    let b_l = (#audio "audio.stem.bass.band.low").clamped_safe;
    let b_m = (#audio "audio.stem.bass.band.mid").clamped_safe;
    let b_h = (#audio "audio.stem.bass.band.high").clamped_safe;
    let b_r = (#audio "audio.stem.bass.rms").clamped_safe;
    let b_p = (#audio "audio.stem.bass.peak").clamped_safe;
    let b_f = (#audio "audio.stem.bass.flux").value;
    let b_b = (#audio "audio.stem.bass.rhythm.beat").clamped_safe;
    let name_b = #string "BASS";

    let c_o = (#color "scene.hud_color_other").rgb;
    let o_l = (#audio "audio.stem.other.band.low").clamped_safe;
    let o_m = (#audio "audio.stem.other.band.mid").clamped_safe;
    let o_h = (#audio "audio.stem.other.band.high").clamped_safe;
    let o_r = (#audio "audio.stem.other.rms").clamped_safe;
    let o_p = (#audio "audio.stem.other.peak").clamped_safe;
    let o_f = (#audio "audio.stem.other.flux").value;
    let o_b = (#audio "audio.stem.other.rhythm.beat").clamped_safe;
    let name_o = #string "OTHER";

    let col_width = 0.45;
    let col_spacing = 0.55;
    let start_x = -2.0 * col_spacing;
    let box_height = 1.3;

    out_rgb += draw_analyzer_column(uv_centered, start_x + 0.0 * col_spacing, col_width, box_height, c_k, k_l, k_m, k_h, k_r, k_p, k_f, k_b, name_k);
    out_rgb += draw_analyzer_column(uv_centered, start_x + 1.0 * col_spacing, col_width, box_height, c_s, s_l, s_m, s_h, s_r, s_p, s_f, s_b, name_s);
    out_rgb += draw_analyzer_column(uv_centered, start_x + 2.0 * col_spacing, col_width, box_height, c_h, h_l, h_m, h_h, h_r, h_p, h_f, h_b, name_h);
    out_rgb += draw_analyzer_column(uv_centered, start_x + 3.0 * col_spacing, col_width, box_height, c_b, b_l, b_m, b_h, b_r, b_p, b_f, b_b, name_b);
    out_rgb += draw_analyzer_column(uv_centered, start_x + 4.0 * col_spacing, col_width, box_height, c_o, o_l, o_m, o_h, o_r, o_p, o_f, o_b, name_o);

    let glow = #gui_param "scene.glow_intensity";
    out_rgb *= max(glow.x, 0.1);

    let scanline = sin(uv.y * scene.resolution.y * 2.0) * 0.04;
    out_rgb *= (1.0 - scanline);

    let vignette = smoothstep(2.5, 0.5, length(uv_centered));
    out_rgb *= vignette;

    return encode_output_alpha(out_rgb, bg_color.a);
}
