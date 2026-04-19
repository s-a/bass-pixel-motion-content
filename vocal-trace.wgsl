#import <engine::bpm_kernel_bindings>

const LINE_HALF_WIDTH: f32 = 0.3895;
const LINE_SOFTNESS_PX: f32 = 1.8;
const LINE_CURVE_SAMPLE_STEPS: u32 = 6u;
const LINE_SEGMENT_SEARCH_RADIUS: u32 = 2u;
const EYE_ENVELOPE_POWER: f32 = 0.93;
const LOCAL_SPECTRUM_SMOOTHNESS: f32 = 0.018;
const BASE_OSCILLATIONS: f32 = 9.5;
const MIRROR_SOFTNESS: f32 = 0.045;
const ATTACK_HZ: f32 = 28.0;

struct CurveState {
  curve: vec4<f32>,
  aux: vec4<f32>,
}

struct VertexOut {
  @builtin(position) position: vec4<f32>,
  @location(0) is_background: f32,
}

@group(0) @binding(1)
var<storage, read> state_in: array<CurveState>;

@group(0) @binding(2)
var<storage, read_write> state_out: array<CurveState>;

fn saturate(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
  return a + (b - a) * t;
}

fn compressed_audio_value(raw: f32) -> f32 {
  let input_gain_param = #gui_param "limiter_input_gain";
  return saturate(raw * clamp(input_gain_param.x, 0.0, 4.0));
}

fn mirrored_radius(u: f32) -> f32 {
  let soft = MIRROR_SOFTNESS;
  let raw = max(sqrt(u * u + soft * soft) - soft, 0.0);
  return saturate(raw / max(1.0 - soft, 0.0001));
}

fn form_envelope(r: f32) -> f32 {
  let c = cos(saturate(r) * 0.5 * 3.14159265);
  return pow(max(c * c, 0.0), EYE_ENVELOPE_POWER);
}

fn audio_band_position(r: f32) -> f32 {
  return pow(saturate(r), 0.52);
}

fn audio_detail_spread(r: f32) -> f32 {
  let center = 1.0 - saturate(r);
  return LOCAL_SPECTRUM_SMOOTHNESS * mix(0.35, 0.85, 1.0 - center * center);
}

fn sample_spectrum(bands: array<f32, 64>, t: f32) -> f32 {
  let clamped_t = saturate(t);
  let pos = clamped_t * 63.0;
  let i0 = u32(floor(pos));
  let i1 = min(i0 + 1u, 63u);
  let frac = pos - f32(i0);
  return lerp(bands[i0], bands[i1], frac);
}

fn read_bands() -> array<f32, 64> {
  let b00s = #audio "audio.spectrum.band_00"; let b00 = compressed_audio_value(b00s.clamped_safe);
  let b01s = #audio "audio.spectrum.band_01"; let b01 = compressed_audio_value(b01s.clamped_safe);
  let b02s = #audio "audio.spectrum.band_02"; let b02 = compressed_audio_value(b02s.clamped_safe);
  let b03s = #audio "audio.spectrum.band_03"; let b03 = compressed_audio_value(b03s.clamped_safe);
  let b04s = #audio "audio.spectrum.band_04"; let b04 = compressed_audio_value(b04s.clamped_safe);
  let b05s = #audio "audio.spectrum.band_05"; let b05 = compressed_audio_value(b05s.clamped_safe);
  let b06s = #audio "audio.spectrum.band_06"; let b06 = compressed_audio_value(b06s.clamped_safe);
  let b07s = #audio "audio.spectrum.band_07"; let b07 = compressed_audio_value(b07s.clamped_safe);
  let b08s = #audio "audio.spectrum.band_08"; let b08 = compressed_audio_value(b08s.clamped_safe);
  let b09s = #audio "audio.spectrum.band_09"; let b09 = compressed_audio_value(b09s.clamped_safe);
  let b10s = #audio "audio.spectrum.band_10"; let b10 = compressed_audio_value(b10s.clamped_safe);
  let b11s = #audio "audio.spectrum.band_11"; let b11 = compressed_audio_value(b11s.clamped_safe);
  let b12s = #audio "audio.spectrum.band_12"; let b12 = compressed_audio_value(b12s.clamped_safe);
  let b13s = #audio "audio.spectrum.band_13"; let b13 = compressed_audio_value(b13s.clamped_safe);
  let b14s = #audio "audio.spectrum.band_14"; let b14 = compressed_audio_value(b14s.clamped_safe);
  let b15s = #audio "audio.spectrum.band_15"; let b15 = compressed_audio_value(b15s.clamped_safe);
  let b16s = #audio "audio.spectrum.band_16"; let b16 = compressed_audio_value(b16s.clamped_safe);
  let b17s = #audio "audio.spectrum.band_17"; let b17 = compressed_audio_value(b17s.clamped_safe);
  let b18s = #audio "audio.spectrum.band_18"; let b18 = compressed_audio_value(b18s.clamped_safe);
  let b19s = #audio "audio.spectrum.band_19"; let b19 = compressed_audio_value(b19s.clamped_safe);
  let b20s = #audio "audio.spectrum.band_20"; let b20 = compressed_audio_value(b20s.clamped_safe);
  let b21s = #audio "audio.spectrum.band_21"; let b21 = compressed_audio_value(b21s.clamped_safe);
  let b22s = #audio "audio.spectrum.band_22"; let b22 = compressed_audio_value(b22s.clamped_safe);
  let b23s = #audio "audio.spectrum.band_23"; let b23 = compressed_audio_value(b23s.clamped_safe);
  let b24s = #audio "audio.spectrum.band_24"; let b24 = compressed_audio_value(b24s.clamped_safe);
  let b25s = #audio "audio.spectrum.band_25"; let b25 = compressed_audio_value(b25s.clamped_safe);
  let b26s = #audio "audio.spectrum.band_26"; let b26 = compressed_audio_value(b26s.clamped_safe);
  let b27s = #audio "audio.spectrum.band_27"; let b27 = compressed_audio_value(b27s.clamped_safe);
  let b28s = #audio "audio.spectrum.band_28"; let b28 = compressed_audio_value(b28s.clamped_safe);
  let b29s = #audio "audio.spectrum.band_29"; let b29 = compressed_audio_value(b29s.clamped_safe);
  let b30s = #audio "audio.spectrum.band_30"; let b30 = compressed_audio_value(b30s.clamped_safe);
  let b31s = #audio "audio.spectrum.band_31"; let b31 = compressed_audio_value(b31s.clamped_safe);
  let b32s = #audio "audio.spectrum.band_32"; let b32 = compressed_audio_value(b32s.clamped_safe);
  let b33s = #audio "audio.spectrum.band_33"; let b33 = compressed_audio_value(b33s.clamped_safe);
  let b34s = #audio "audio.spectrum.band_34"; let b34 = compressed_audio_value(b34s.clamped_safe);
  let b35s = #audio "audio.spectrum.band_35"; let b35 = compressed_audio_value(b35s.clamped_safe);
  let b36s = #audio "audio.spectrum.band_36"; let b36 = compressed_audio_value(b36s.clamped_safe);
  let b37s = #audio "audio.spectrum.band_37"; let b37 = compressed_audio_value(b37s.clamped_safe);
  let b38s = #audio "audio.spectrum.band_38"; let b38 = compressed_audio_value(b38s.clamped_safe);
  let b39s = #audio "audio.spectrum.band_39"; let b39 = compressed_audio_value(b39s.clamped_safe);
  let b40s = #audio "audio.spectrum.band_40"; let b40 = compressed_audio_value(b40s.clamped_safe);
  let b41s = #audio "audio.spectrum.band_41"; let b41 = compressed_audio_value(b41s.clamped_safe);
  let b42s = #audio "audio.spectrum.band_42"; let b42 = compressed_audio_value(b42s.clamped_safe);
  let b43s = #audio "audio.spectrum.band_43"; let b43 = compressed_audio_value(b43s.clamped_safe);
  let b44s = #audio "audio.spectrum.band_44"; let b44 = compressed_audio_value(b44s.clamped_safe);
  let b45s = #audio "audio.spectrum.band_45"; let b45 = compressed_audio_value(b45s.clamped_safe);
  let b46s = #audio "audio.spectrum.band_46"; let b46 = compressed_audio_value(b46s.clamped_safe);
  let b47s = #audio "audio.spectrum.band_47"; let b47 = compressed_audio_value(b47s.clamped_safe);
  let b48s = #audio "audio.spectrum.band_48"; let b48 = compressed_audio_value(b48s.clamped_safe);
  let b49s = #audio "audio.spectrum.band_49"; let b49 = compressed_audio_value(b49s.clamped_safe);
  let b50s = #audio "audio.spectrum.band_50"; let b50 = compressed_audio_value(b50s.clamped_safe);
  let b51s = #audio "audio.spectrum.band_51"; let b51 = compressed_audio_value(b51s.clamped_safe);
  let b52s = #audio "audio.spectrum.band_52"; let b52 = compressed_audio_value(b52s.clamped_safe);
  let b53s = #audio "audio.spectrum.band_53"; let b53 = compressed_audio_value(b53s.clamped_safe);
  let b54s = #audio "audio.spectrum.band_54"; let b54 = compressed_audio_value(b54s.clamped_safe);
  let b55s = #audio "audio.spectrum.band_55"; let b55 = compressed_audio_value(b55s.clamped_safe);
  let b56s = #audio "audio.spectrum.band_56"; let b56 = compressed_audio_value(b56s.clamped_safe);
  let b57s = #audio "audio.spectrum.band_57"; let b57 = compressed_audio_value(b57s.clamped_safe);
  let b58s = #audio "audio.spectrum.band_58"; let b58 = compressed_audio_value(b58s.clamped_safe);
  let b59s = #audio "audio.spectrum.band_59"; let b59 = compressed_audio_value(b59s.clamped_safe);
  let b60s = #audio "audio.spectrum.band_60"; let b60 = compressed_audio_value(b60s.clamped_safe);
  let b61s = #audio "audio.spectrum.band_61"; let b61 = compressed_audio_value(b61s.clamped_safe);
  let b62s = #audio "audio.spectrum.band_62"; let b62 = compressed_audio_value(b62s.clamped_safe);
  let b63s = #audio "audio.spectrum.band_63"; let b63 = compressed_audio_value(b63s.clamped_safe);
  return array<f32, 64>(
    b00, b01, b02, b03, b04, b05, b06, b07,
    b08, b09, b10, b11, b12, b13, b14, b15,
    b16, b17, b18, b19, b20, b21, b22, b23,
    b24, b25, b26, b27, b28, b29, b30, b31,
    b32, b33, b34, b35, b36, b37, b38, b39,
    b40, b41, b42, b43, b44, b45, b46, b47,
    b48, b49, b50, b51, b52, b53, b54, b55,
    b56, b57, b58, b59, b60, b61, b62, b63
  );
}

fn audio_mapped_amplitude(bands: array<f32, 64>, r: f32) -> f32 {
  let band_t = audio_band_position(r);
  let spread = audio_detail_spread(r);
  let s0 = sample_spectrum(bands, max(band_t - spread * 2.0, 0.0));
  let s1 = sample_spectrum(bands, max(band_t - spread, 0.0));
  let s2 = sample_spectrum(bands, band_t);
  let s3 = sample_spectrum(bands, min(band_t + spread, 1.0));
  let s4 = sample_spectrum(bands, min(band_t + spread * 2.0, 1.0));
  let smooth_value = s0 * 0.06 + s1 * 0.16 + s2 * 0.56 + s3 * 0.16 + s4 * 0.06;
  return pow(apply_limiter(smooth_value), 0.84);
}

fn left_target_curve(bands: array<f32, 64>, r: f32) -> f32 {
  let amplitude = audio_mapped_amplitude(bands, r) * form_envelope(r);
  let carrier = sin(r * BASE_OSCILLATIONS * 3.14159265);
  return carrier * amplitude;
}

fn mirrored_target_curve(bands: array<f32, 64>, u: f32) -> f32 {
  let r = mirrored_radius(u);
  let left_curve = left_target_curve(bands, r);
  if (u <= 0.0) {
    return left_curve;
  }
  return -left_curve;
}

fn attack_mix(dt: f32) -> f32 {
  return saturate(1.0 - exp(-dt * ATTACK_HZ));
}

fn release_mix(dt: f32) -> f32 {
  let falloff_param = #gui_param "falloff_ms";
  let falloff_ms = clamp(falloff_param.x, 1.0, 1000.0);
  let tau = falloff_ms * 0.001;
  return saturate(1.0 - exp(-dt / tau));
}

fn is_bottom_motion(curve: f32) -> bool {
  return curve > 0.0;
}

fn line_thickness_px() -> f32 {
  let thickness_param = #gui_param "line_thickness";
  return clamp(thickness_param.x, 0.5, 20.0);
}

fn color_rgb_unpremul(c: BpmColor) -> vec3<f32> {
  return select(c.rgb / max(c.a, 0.0001), vec3<f32>(0.0), c.a <= 0.0001);
}

fn internal_render_resolution() -> vec2<f32> {
  return vec2<f32>(
    1.0 / max(params.texel_size.x, 0.000001),
    1.0 / max(params.texel_size.y, 0.000001),
  );
}

fn output_resolution() -> vec2<f32> {
  return max(params.resolution, vec2<f32>(1.0, 1.0));
}

fn render_to_output_scale() -> vec2<f32> {
  return internal_render_resolution() / output_resolution();
}

fn apply_limiter(value: f32) -> f32 {
  let threshold_param = #gui_param "limiter_threshold";
  let ratio_param = #gui_param "limiter_ratio";
  let threshold = clamp(threshold_param.x, 0.0, 1.0);
  let ratio = mix(1.0, 20.0, clamp(ratio_param.x, 0.0, 1.0));
  let limited = select(value, threshold + (value - threshold) / ratio, value > threshold);
  return saturate(limited);
}

fn curve_amplitude_px(res: vec2<f32>, render_scale: vec2<f32>) -> f32 {
  let render_line_thickness = line_thickness_px() * render_scale.y;
  let render_softness = LINE_SOFTNESS_PX * render_scale.y;
  let margin = render_line_thickness * 0.5 + render_softness + 6.0;
  return max(res.y * 0.5 - margin, 1.0);
}

fn curve_point_px(point: CurveState, center: vec2<f32>, res: vec2<f32>, render_scale: vec2<f32>) -> vec2<f32> {
  let amplitude_px = curve_amplitude_px(res, render_scale);
  return vec2<f32>(
    center.x + point.curve.x * LINE_HALF_WIDTH * res.x,
    center.y + point.curve.y * amplitude_px,
  );
}

fn extrapolated_curve_point(anchor: vec2<f32>, neighbor: vec2<f32>) -> vec2<f32> {
  return anchor + (anchor - neighbor);
}

fn catmull_rom_point(
  p0: vec2<f32>,
  p1: vec2<f32>,
  p2: vec2<f32>,
  p3: vec2<f32>,
  t: f32,
) -> vec2<f32> {
  let t2 = t * t;
  let t3 = t2 * t;
  return 0.5 * (
    (2.0 * p1) +
    (-p0 + p2) * t +
    (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
    (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
  );
}

fn closest_point_on_segment(point: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let ab = b - a;
  let denom = max(dot(ab, ab), 0.0001);
  let t = clamp(dot(point - a, ab) / denom, 0.0, 1.0);
  let closest = a + ab * t;
  return vec2<f32>(distance(point, closest), t);
}

fn conservative_line_bounds_px(
  center: vec2<f32>,
  res: vec2<f32>,
  render_scale: vec2<f32>,
) -> vec4<f32> {
  let render_line_thickness = line_thickness_px() * render_scale.y;
  let render_softness = LINE_SOFTNESS_PX * render_scale.y;
  let padding = render_line_thickness * 0.5 + render_softness + 4.0;
  let amplitude_px = curve_amplitude_px(res, render_scale);
  return vec4<f32>(
    center.x - LINE_HALF_WIDTH * res.x - padding,
    center.y - amplitude_px - padding,
    center.x + LINE_HALF_WIDTH * res.x + padding,
    center.y + amplitude_px + padding,
  );
}

@compute @workgroup_size(64)
fn ff_init(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  let cap = u32(params.runtime_meta.x);
  if (idx >= cap) {
    return;
  }
  let denom = max(f32(cap - 1u), 1.0);
  let x_local = lerp(-1.0, 1.0, f32(idx) / denom);
  state_out[idx] = CurveState(
    vec4<f32>(x_local, 0.0, 1.0, 0.0),
    vec4<f32>(0.0, 0.0, 0.0, 0.0),
  );
}

@compute @workgroup_size(64)
fn ff_update(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  let cap = u32(params.runtime_meta.x);
  if (idx >= cap) {
    return;
  }
  let bands = read_bands();
  var s = state_in[idx];
  let u = s.curve.x;
  let current = s.curve.y;
  let target_curve = mirrored_target_curve(bands, u);
  let dt = max(params.runtime_meta.w, 0.000001);
  let release = release_mix(dt);
  let use_attack = abs(target_curve) > abs(current) || target_curve * current < 0.0;
  let allow_bottom_release = is_bottom_motion(current) && is_bottom_motion(target_curve);
  s.curve.y = select(
    select(target_curve, lerp(current, target_curve, release), allow_bottom_release),
    target_curve,
    use_attack,
  );
  state_out[idx] = s;
}

@vertex
fn ff_vs(
  @builtin(vertex_index) vi: u32,
  @builtin(instance_index) ii: u32,
) -> VertexOut {
  var out: VertexOut;
  let clip_quad = array<vec2<f32>, 6>(
    vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0),
    vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, 1.0), vec2<f32>(-1.0, 1.0),
  );
  let uv_quad = array<vec2<f32>, 6>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(1.0, 1.0),
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 1.0), vec2<f32>(0.0, 1.0),
  );
  if (ii == 0u) {
    let p = clip_quad[vi];
    out.position = vec4<f32>(p, 0.0, 1.0);
    out.is_background = 1.0;
    return out;
  }
  if (ii != 1u) {
    out.position = vec4<f32>(2.0, 2.0, 0.0, 1.0);
    out.is_background = 0.0;
    return out;
  }
  let res = internal_render_resolution();
  let render_scale = render_to_output_scale();
  let center = res * 0.5;
  let bounds = conservative_line_bounds_px(center, res, render_scale);
  let uv = uv_quad[vi];
  let pos_px = vec2<f32>(
    lerp(bounds.x, bounds.z, uv.x),
    lerp(bounds.y, bounds.w, uv.y),
  );
  out.position = vec4<f32>(
    pos_px.x / res.x * 2.0 - 1.0,
    pos_px.y / res.y * 2.0 - 1.0,
    0.0,
    1.0,
  );
  out.is_background = 0.0;
  return out;
}

@fragment
fn ff_fs(in: VertexOut) -> @location(0) vec4<f32> {
  let bg = #color "scene.bg_color";
  if (in.is_background > 0.5) {
    return vec4<f32>(color_rgb_unpremul(bg), bg.a);
  }
  let cap = u32(params.runtime_meta.x);
  if (cap < 2u) {
    return vec4<f32>(0.0);
  }
  let frag_px = in.position.xy;
  let res = internal_render_resolution();
  let render_scale = render_to_output_scale();
  let center = res * 0.5;
  let x_min = center.x - LINE_HALF_WIDTH * res.x;
  let x_span = max(LINE_HALF_WIDTH * res.x * 2.0, 0.0001);
  let curve_u = saturate((frag_px.x - x_min) / x_span);
  let segment_f = curve_u * f32(cap - 1u);
  let approx_segment = min(u32(floor(segment_f)), cap - 2u);
  let search_start = approx_segment - min(approx_segment, LINE_SEGMENT_SEARCH_RADIUS);
  let search_end = min(approx_segment + LINE_SEGMENT_SEARCH_RADIUS, cap - 2u);
  let wave_1 = #color "scene.wave_color";
  let wave_2 = #color "scene.wave_2";
  let line_thickness = line_thickness_px();
  let render_line_thickness = line_thickness * render_scale.y;
  let render_softness = LINE_SOFTNESS_PX * render_scale.y;
  let core_radius = render_line_thickness * 0.5;
  let outer_radius = core_radius + render_softness;
  var min_dist = 1e20;
  var closest_fill_u = 0.0;
  var segment_idx = search_start;
  loop {
    let p1 = curve_point_px(state_in[segment_idx], center, res, render_scale);
    let p2 = curve_point_px(state_in[segment_idx + 1u], center, res, render_scale);
    var p0 = extrapolated_curve_point(p1, p2);
    if (segment_idx > 0u) {
      p0 = curve_point_px(state_in[segment_idx - 1u], center, res, render_scale);
    }
    var p3 = extrapolated_curve_point(p2, p1);
    if (segment_idx + 2u < cap) {
      p3 = curve_point_px(state_in[segment_idx + 2u], center, res, render_scale);
    }
    let fill_u0 = state_in[segment_idx].curve.x * 0.5 + 0.5;
    let fill_u1 = state_in[segment_idx + 1u].curve.x * 0.5 + 0.5;
    var prev_curve = catmull_rom_point(p0, p1, p2, p3, 0.0);
    var step_idx = 1u;
    loop {
      let step_t = f32(step_idx) / f32(LINE_CURVE_SAMPLE_STEPS);
      let curr_curve = catmull_rom_point(p0, p1, p2, p3, step_t);
      let hit = closest_point_on_segment(frag_px, prev_curve, curr_curve);
      if (hit.x < min_dist) {
        min_dist = hit.x;
        let prev_t = f32(step_idx - 1u) / f32(LINE_CURVE_SAMPLE_STEPS);
        let curve_t = lerp(prev_t, step_t, hit.y);
        closest_fill_u = lerp(fill_u0, fill_u1, curve_t);
      }
      prev_curve = curr_curve;
      if (step_idx >= LINE_CURVE_SAMPLE_STEPS) {
        break;
      }
      step_idx += 1u;
    }
    if (segment_idx >= search_end) {
      break;
    }
    segment_idx += 1u;
  }
  let alpha = 1.0 - smoothstep(core_radius, outer_radius, min_dist);
  let progress = saturate(params.timeline.z);
  let output_res = output_resolution();
  let feather = max(6.0 / output_res.x, 0.0015);
  let fill = 1.0 - smoothstep(progress - feather, progress + feather, closest_fill_u);
  let wave_rgb = mix(color_rgb_unpremul(wave_1), color_rgb_unpremul(wave_2), fill);
  let wave_alpha = mix(wave_1.a, wave_2.a, fill);
  return vec4<f32>(wave_rgb, alpha * wave_alpha);
}
