
#import <engine::bpm_kernel_bindings>
#import <bpm/sprite_utils.wgsl>

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}




const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const AUDIO_HISTORY_MAX_SAMPLES: u32 = 32u;
const AUDIO_LOW: u32 = 0u;
const AUDIO_MID: u32 = 1u;
const AUDIO_HIGH: u32 = 2u;
const AUDIO_RMS: u32 = 3u;
const AUDIO_BEAT: u32 = 4u;
const AUDIO_KICK_COUNT: u32 = 5u;
const AUDIO_BEAT_STEP: u32 = 6u;
const AUDIO_IMPACT: u32 = 7u;
const AUDIO_KICK_IMPACT: u32 = 8u;
const AUDIO_FLUX: u32 = 9u;
const AUDIO_BRIGHTNESS: u32 = 10u;

const DANCER_HALF_HEIGHT: f32 = 0.36;
const DANCER_HALF_WIDTH: f32 = 0.41;
const GHOST_HALF_HEIGHT: f32 = 0.34;
const GHOST_HALF_WIDTH: f32 = 0.385;
const SPRITE_SHEET_COLS: u32 = 9u;
const SPRITE_SHEET_ROWS: u32 = 3u;
const SPRITE_SHEET_FRAMES: u32 = 27u;
const ACTIVE_SPRITE_FRAMES: u32 = 27u;



@group(1) @binding(0)
var sprite_sheet_texture: texture_2d<f32>;

@group(1) @binding(1)
var sprite_sheet_sampler: sampler;

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

fn saturate(value: f32) -> f32 {
    return clamp(value, 0.0, 1.0);
}

fn saturate3(value: vec3<f32>) -> vec3<f32> {
    return clamp(value, vec3<f32>(0.0), vec3<f32>(1.0));
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

fn rotate(value: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(value.x * c - value.y * s, value.x * s + value.y * c);
}

fn rect_mask(p: vec2<f32>, center: vec2<f32>, half_size: vec2<f32>) -> f32 {
    let delta = abs(p - center);
    return select(0.0, 1.0, delta.x <= half_size.x && delta.y <= half_size.y);
}

fn disk_mask(p: vec2<f32>, center: vec2<f32>, radius: f32) -> f32 {
    return 1.0 - smoothstep(radius, radius + 0.012, length(p - center));
}

fn band_mask(distance: f32, width: f32, feather: f32) -> f32 {
    return 1.0 - smoothstep(width, width + feather, abs(distance));
}

fn segment_mask(p: vec2<f32>, joint: vec2<f32>, length_value: f32, thickness: f32, angle: f32) -> f32 {
    let local = rotate(p - joint, -angle);
    return rect_mask(local, vec2<f32>(length_value * 0.5, 0.0), vec2<f32>(length_value * 0.5, thickness));
}

fn segment_end(joint: vec2<f32>, length_value: f32, angle: f32) -> vec2<f32> {
    return joint + vec2<f32>(cos(angle), sin(angle)) * length_value;
}

fn polar_angle(value: vec2<f32>) -> f32 {
    let safe_x = select(value.x, 0.0001, abs(value.x) < 0.0001);
    var angle = atan(value.y / safe_x);
    if value.x < 0.0 {
        angle = angle + select(-PI, PI, value.y >= 0.0);
    }
    return angle;
}

fn primary_neon_color() -> vec3<f32> {
    let c = #color "scene.primary_neon_color";
    return c.rgb;
}

fn secondary_neon_color() -> vec3<f32> {
    let c = #color "scene.secondary_neon_color";
    return c.rgb;
}

fn sky_top_color() -> vec3<f32> {
    let c = #color "scene.bg_color";
    return c.rgb;
}

fn floor_glow_color() -> vec3<f32> {
    let c = #color "scene.floor_glow_color";
    return c.rgb;
}

fn neon_gain() -> f32 {
    return clamp(#gui_param "scene.neon_gain".x, 0.2, 2.0);
}

fn rain_amount() -> f32 {
    return clamp(#gui_param "scene.rain_amount".x, 0.0, 1.0);
}

fn pixel_scale() -> f32 {
    return clamp(#gui_param "scene.pixel_scale".x, 160.0, 640.0);
}

fn progress_thickness() -> f32 {
    return clamp(#gui_param "scene.progress_thickness".x, 0.02, 0.2);
}

fn timeline_progress() -> f32 {
    if scene.timeline.y <= 0.0 {
        return 0.0;
    }
    return clamp(scene.timeline.z, 0.0, 1.0);
}

fn arena_horizon(progress: f32) -> f32 {
    return -0.08 + progress * 0.06;
}

fn render_sky(p: vec2<f32>, progress: f32, rms: f32, flux: f32, brightness: f32) -> vec3<f32> {
    let upper = mix(sky_top_color(), vec3<f32>(0.18, 0.05, 0.15), progress * 0.7);
    let lower = mix(vec3<f32>(0.12, 0.02, 0.12), floor_glow_color() * 0.22 + vec3<f32>(0.02, 0.01, 0.05), 0.7);
    let gradient = saturate((p.y + 1.0) * 0.52);
    var color = mix(lower, upper, gradient);
    let haze = exp(-max(p.y + 0.08, 0.0) * 3.4);
    let aurora = noise21(vec2<f32>(p.x * 1.4 + scene.time * 0.035, p.y * 3.0 - scene.time * 0.02));
    color += vec3<f32>(0.02, 0.04, 0.06) * aurora * (0.4 + flux * 0.8);
    color += vec3<f32>(0.07, 0.03, 0.08) * haze * (0.22 + rms * 0.55);
    color += vec3<f32>(0.02, 0.05, 0.08) * brightness * (1.0 - gradient) * 0.25;
    return color;
}

fn render_sun_disc(p: vec2<f32>, center: vec2<f32>, progress: f32, brightness: f32) -> vec3<f32> {
    let radius = 0.28;
    let dist = length(p - center);
    let disc = 1.0 - smoothstep(radius, radius + 0.018, dist);
    let stripe = select(0.0, 1.0, abs(fract((p.y - center.y + radius) * 18.0) - 0.5) < 0.28);
    let warm = mix(vec3<f32>(1.0, 0.22, 0.2), vec3<f32>(1.0, 0.76, 0.34), saturate((p.y - center.y + radius) / (radius * 2.0)));
    return warm * disc * (0.32 + 0.38 * stripe + 0.18 * progress + 0.18 * brightness);
}

fn render_progress_ring(
    p: vec2<f32>,
    center: vec2<f32>,
    progress: f32,
    beat: f32,
    impact: f32,
) -> vec3<f32> {
    let delta = p - center;
    let radius = 0.42;
    let thickness_value = progress_thickness();
    let dist = length(delta);
    let ring = band_mask(dist - radius, 0.0, thickness_value * 0.34);
    let halo = band_mask(dist - radius, thickness_value * 1.8, thickness_value * 3.8);
    let angle = fract(0.25 - polar_angle(delta) / TAU + 1.0);
    let segments = select(0.0, 1.0, abs(fract(angle * 28.0) - 0.5) < 0.33);
    let ring_fill = select(0.0, 1.0, angle <= progress);
    let passive_color = mix(primary_neon_color(), secondary_neon_color(), 0.5);
    let active_color = mix(floor_glow_color(), secondary_neon_color(), 0.25);
    return passive_color * ring * segments * 0.16
        + active_color * ring * segments * ring_fill * (0.42 + beat * 0.65 + impact * 0.35)
        + active_color * halo * ring_fill * 0.08;
}

fn render_skyline_layer(
    p: vec2<f32>,
    horizon: f32,
    density: f32,
    min_height: f32,
    max_height: f32,
    drift: f32,
    seed: f32,
    body_color: vec3<f32>,
    light_color: vec3<f32>,
    brightness: f32,
) -> vec3<f32> {
    let x = (p.x + 2.3 + drift) * density;
    let cell = floor(x);
    let local = fract(x) - 0.5;
    let width = mix(0.2, 0.48, hash11(cell * 1.37 + seed * 9.0));
    let height = mix(min_height, max_height, hash11(cell * 2.11 + seed * 5.1));
    let top = horizon + height;
    let building = select(0.0, 1.0, abs(local) < width && p.y <= top && p.y >= horizon - 0.04);
    let win_u = (local / max(width, 0.001)) * 0.5 + 0.5;
    let win_v = (p.y - horizon) / max(height, 0.001);
    let cols = floor(win_u * 4.0);
    let rows = floor(win_v * 18.0);
    let window_hash = hash21(vec2<f32>(cell * 1.41 + cols, rows + seed * 17.0));
    let wx = abs(fract(win_u * 4.0) - 0.5);
    let wy = abs(fract(win_v * 18.0) - 0.5);
    let lit = select(0.0, 1.0, window_hash > 0.42 - brightness * 0.12);
    let window = select(0.0, 1.0, wx < 0.22 && wy < 0.22) * lit * building;
    let edge = select(0.0, 1.0, building > 0.0 && (abs(abs(local) - width) < 0.03 || abs(p.y - top) < 0.02));
    return body_color * building + light_color * window * (0.3 + 0.9 * brightness) + light_color * edge * 0.05;
}

fn render_billboard(p: vec2<f32>, center: vec2<f32>, half_size: vec2<f32>, color: vec3<f32>, pulse: f32) -> vec3<f32> {
    let local = abs(p - center);
    let panel = select(0.0, 1.0, local.x <= half_size.x && local.y <= half_size.y);
    let border = select(0.0, 1.0, panel > 0.0 && (local.x > half_size.x - 0.02 || local.y > half_size.y - 0.02));
    let scan = select(0.0, 1.0, panel > 0.0 && abs(fract((p.y - center.y) * 46.0) - 0.5) < 0.14);
    return color * panel * 0.035 + color * border * (0.18 + pulse * 0.22) + color * scan * 0.08;
}

fn render_rain(p: vec2<f32>, high: f32, amount: f32) -> vec3<f32> {
    let skew = vec2<f32>(p.x * 15.0 + p.y * 4.4, p.y * 9.5);
    let lane = floor(skew.x);
    let lane_pos = abs(fract(skew.x) - 0.5);
    let speed = 1.0 + hash11(lane * 7.3) * 2.4 + high * 0.8;
    let drop = fract(skew.y - scene.time * speed);
    let streak = (1.0 - smoothstep(0.0, 0.32, drop)) * (1.0 - smoothstep(0.02, 0.12, lane_pos));
    let tint = mix(vec3<f32>(0.08, 0.18, 0.32), primary_neon_color(), 0.25);
    return tint * streak * amount * 0.33;
}

fn render_floor(p: vec2<f32>, horizon: f32, low: f32, high: f32, progress: f32) -> vec3<f32> {
    if p.y > horizon {
        return vec3<f32>(0.0);
    }

    let depth = max(horizon - p.y, 0.02);
    let perspective = 1.0 / depth;
    let x_line = abs(fract(p.x * perspective * 4.2 + scene.time * 0.025) - 0.5);
    let y_line = abs(fract(depth * 15.0 - scene.time * 0.015) - 0.5);
    let grid_x = 1.0 - smoothstep(0.02, 0.09 + depth * 0.1, x_line);
    let grid_y = 1.0 - smoothstep(0.04, 0.16, y_line);
    let pulse = 0.7 + low * 1.4;
    let base = mix(vec3<f32>(0.02, 0.015, 0.03), floor_glow_color() * 0.14, saturate(depth * 1.8));
    let platform = 1.0 - smoothstep(0.0, 0.035, abs(p.y - (horizon - 0.16)));
    let lane = 1.0 - smoothstep(0.0, 0.03, abs(p.x) - (0.72 + progress * 0.18));
    var color = base + floor_glow_color() * (grid_x * 0.16 + grid_y * 0.11) * pulse;
    color += mix(primary_neon_color(), secondary_neon_color(), 0.5) * platform * lane * (0.14 + high * 0.24);
    return color;
}

fn render_dancer(
    p: vec2<f32>,
    center: vec2<f32>,
    primary_color: vec3<f32>,
    secondary_color: vec3<f32>,
    low: f32,
    mid: f32,
    high: f32,
    beat: f32,
    impact: f32,
    progress: f32,
    phase_shift: f32,
) -> BpmSpriteLayer {
    let scale = 158.0;
    let rhythm = scene.time * (1.45 + mid * 1.25) + phase_shift;
    let frame_phase = fract(rhythm / TAU + 1.0);
    let bounce = sin(rhythm * TAU) * 0.25;
    let kick_boost = saturate(impact * 1.1 + beat * 0.45 + high * 0.2);
    let bob = sin(scene.time * (1.1 + low * 0.8) + phase_shift) * 0.35;
    var q = floor((p - center) * scale + vec2<f32>(0.5, 0.5));
    q.x = q.x + bounce * 0.8;
    q.y = q.y - bob;

    var pose_id = 0u;
    if frame_phase > 0.2 { pose_id = 1u; }
    if frame_phase > 0.42 { pose_id = 2u; }
    if frame_phase > 0.72 { pose_id = 3u; }

    let groove = saturate(0.26 + impact * 0.7 + beat * 0.45 + kick_boost * 0.25);
    var upper_front_arm_angle = 0.12;
    var lower_front_arm_angle = -0.2;
    var upper_back_arm_angle = PI - 0.74;
    var lower_back_arm_angle = PI - 0.9;
    var upper_front_leg_angle = -1.02;
    var lower_front_leg_angle = -1.12;
    var upper_back_leg_angle = -1.66;
    var lower_back_leg_angle = -1.3;

    if pose_id == 1u {
        upper_front_arm_angle = 0.02;
        lower_front_arm_angle = -0.04;
        upper_back_arm_angle = PI - 0.58;
        lower_back_arm_angle = PI - 0.84;
        upper_front_leg_angle = -0.98;
        lower_front_leg_angle = -1.04;
        upper_back_leg_angle = -1.76;
        lower_back_leg_angle = -1.38;
    }
    if pose_id == 2u {
        upper_front_arm_angle = 0.06;
        lower_front_arm_angle = -0.02;
        upper_back_arm_angle = PI - 0.46;
        lower_back_arm_angle = PI - 1.08;
        upper_front_leg_angle = 0.24 + kick_boost * 0.08;
        lower_front_leg_angle = 0.02;
        upper_back_leg_angle = -1.88;
        lower_back_leg_angle = -1.02;
    }
    if pose_id == 3u {
        upper_front_arm_angle = 0.22;
        lower_front_arm_angle = -0.26;
        upper_back_arm_angle = PI - 0.86;
        lower_back_arm_angle = PI - 0.98;
        upper_front_leg_angle = -1.24;
        lower_front_leg_angle = -1.08;
        upper_back_leg_angle = -1.46;
        lower_back_leg_angle = -1.18;
    }

    let shoulder_front = vec2<f32>(4.7, 12.5);
    let shoulder_back = vec2<f32>(-2.4, 11.8);
    let hip_front = vec2<f32>(2.8, 3.5);
    let hip_back = vec2<f32>(-1.7, 3.2);

    let front_elbow = segment_end(shoulder_front, 5.5, upper_front_arm_angle);
    let back_elbow = segment_end(shoulder_back, 5.5, upper_back_arm_angle);
    let front_wrist = segment_end(front_elbow, 4.5, lower_front_arm_angle);
    let front_knee = segment_end(hip_front, 7.0, upper_front_leg_angle);
    let back_knee = segment_end(hip_back, 7.0, upper_back_leg_angle);
    let front_foot = segment_end(front_knee, 6.0, lower_front_leg_angle);
    let back_foot = segment_end(back_knee, 6.0, lower_back_leg_angle);

    var outline = 0.0;
    var gi = 0.0;
    var skin = 0.0;
    var primary_trim = 0.0;
    var secondary_trim = 0.0;

    let head_center = vec2<f32>(1.1, 20.4);
    let torso_center = vec2<f32>(0.9, 11.3);
    let hip_center = vec2<f32>(0.9, 3.8);

    outline = max(outline, rect_mask(q, head_center, vec2<f32>(3.9, 3.7)));
    outline = max(outline, rect_mask(q, torso_center, vec2<f32>(6.0, 7.0)));
    outline = max(outline, rect_mask(q, hip_center, vec2<f32>(5.3, 3.0)));
    outline = max(outline, segment_mask(q, shoulder_front, 5.5, 2.0, upper_front_arm_angle));
    outline = max(outline, segment_mask(q, front_elbow, 4.5, 1.8, lower_front_arm_angle));
    outline = max(outline, segment_mask(q, shoulder_back, 5.5, 2.0, upper_back_arm_angle));
    outline = max(outline, segment_mask(q, back_elbow, 4.5, 1.8, lower_back_arm_angle));
    outline = max(outline, segment_mask(q, hip_front, 7.0, 2.0, upper_front_leg_angle));
    outline = max(outline, segment_mask(q, front_knee, 6.0, 1.8, lower_front_leg_angle));
    outline = max(outline, segment_mask(q, hip_back, 7.0, 2.0, upper_back_leg_angle));
    outline = max(outline, segment_mask(q, back_knee, 6.0, 1.8, lower_back_leg_angle));
    outline = max(outline, rect_mask(q, front_wrist, vec2<f32>(1.2, 1.2)));
    outline = max(outline, rect_mask(q, front_foot, vec2<f32>(1.5, 1.2)));
    outline = max(outline, rect_mask(q, back_foot, vec2<f32>(1.5, 1.2)));

    let nose = rect_mask(q, head_center + vec2<f32>(3.0, 0.1), vec2<f32>(0.5, 0.5));
    let face = rect_mask(q, head_center + vec2<f32>(0.8, -0.15), vec2<f32>(2.5, 2.75));
    skin = max(skin, face);
    skin = max(skin, nose);
    skin = max(skin, rect_mask(q, front_wrist, vec2<f32>(0.8, 0.8)));
    gi = max(gi, rect_mask(q, torso_center, vec2<f32>(4.9, 6.0)));
    gi = max(gi, rect_mask(q, hip_center, vec2<f32>(4.3, 2.2)));
    gi = max(gi, segment_mask(q, shoulder_front, 5.5, 1.1, upper_front_arm_angle));
    gi = max(gi, segment_mask(q, front_elbow, 4.5, 1.0, lower_front_arm_angle));
    gi = max(gi, segment_mask(q, shoulder_back, 5.5, 1.1, upper_back_arm_angle));
    gi = max(gi, segment_mask(q, back_elbow, 4.5, 1.0, lower_back_arm_angle));
    gi = max(gi, segment_mask(q, hip_front, 7.0, 1.2, upper_front_leg_angle));
    gi = max(gi, segment_mask(q, front_knee, 6.0, 1.1, lower_front_leg_angle));
    gi = max(gi, segment_mask(q, hip_back, 7.0, 1.2, upper_back_leg_angle));
    gi = max(gi, segment_mask(q, back_knee, 6.0, 1.1, lower_back_leg_angle));

    let belt_center = vec2<f32>(0.8, 6.8);
    let hair_center = vec2<f32>(0.4, 22.5);
    let face_shadow = rect_mask(q, vec2<f32>(-0.6, 20.6), vec2<f32>(0.8, 1.5));
    primary_trim = max(primary_trim, rect_mask(q, belt_center, vec2<f32>(5.0, 0.95)));
    primary_trim = max(primary_trim, rect_mask(q, belt_center + vec2<f32>(3.4, -1.1), vec2<f32>(0.8, 2.2)));
    primary_trim = max(primary_trim, rect_mask(q, belt_center + vec2<f32>(1.9, -1.2), vec2<f32>(0.55, 1.8)));
    secondary_trim = max(secondary_trim, rect_mask(q, hair_center, vec2<f32>(3.2, 0.8)));
    secondary_trim = max(secondary_trim, rect_mask(q, vec2<f32>(-1.8, 21.0), vec2<f32>(1.1, 1.4)));
    secondary_trim = max(secondary_trim, rect_mask(q, front_foot, vec2<f32>(1.3, 0.95)));
    secondary_trim = max(secondary_trim, rect_mask(q, back_foot, vec2<f32>(1.3, 0.95)));

    let alpha = max(outline, max(gi, max(skin, max(primary_trim, secondary_trim))));
    let outline_color = vec3<f32>(0.05, 0.05, 0.08);
    let gi_color = mix(vec3<f32>(0.95, 0.95, 0.96), vec3<f32>(0.9, 0.92, 0.95), progress * 0.08);
    let skin_color = vec3<f32>(0.92, 0.75, 0.58);
    let hair_color = vec3<f32>(0.08, 0.06, 0.08);

    var color = vec3<f32>(0.0);
    color = mix(color, outline_color, outline * 0.96);
    color = mix(color, gi_color, gi);
    color = mix(color, skin_color, skin);
    color = mix(color, primary_color, primary_trim);
    color = mix(color, hair_color, secondary_trim);
    color = mix(color, hair_color * 0.9, face_shadow * 0.55);

    let front_foot_world = center + front_foot / scale;
    let front_wrist_world = center + front_wrist / scale;
    let spark_foot = disk_mask(p, front_foot_world, 0.07) * groove * (0.18 + high * 0.42);
    let spark_hand = disk_mask(p, front_wrist_world, 0.06) * groove * (0.14 + beat * 0.36);
    color += secondary_color * spark_foot * 0.78;
    color += primary_color * spark_hand * 0.62;

    return BpmSpriteLayer(color, alpha);
}

fn render_sprite_sheet_character(
    p: vec2<f32>,
    center: vec2<f32>,
    frame_index: u32,
    half_size: vec2<f32>,
    primary_color: vec3<f32>,
    secondary_color: vec3<f32>,
    beat: f32,
    impact: f32,
) -> BpmSpriteLayer {
    let local = (p - center) / half_size;
    if abs(local.x) > 1.0 || abs(local.y) > 1.0 {
        return BpmSpriteLayer(vec3<f32>(0.0), 0.0);
    }

    let frame_uv = vec2<f32>(local.x * 0.5 + 0.5, 1.0 - (local.y * 0.5 + 0.5));
    let frame_rect = get_sprite_frame_rect(frame_index, SPRITE_SHEET_COLS, SPRITE_SHEET_ROWS, SPRITE_SHEET_FRAMES);
    let sheet_uv = get_sprite_safe_uv(sprite_sheet_texture, frame_rect, frame_uv);
    let sample = textureSampleLevel(sprite_sheet_texture, sprite_sheet_sampler, sheet_uv, 0.0);
    let bg = get_sprite_frame_background(sprite_sheet_texture, sprite_sheet_sampler, frame_rect, frame_uv);
    let delta = sample.rgb - bg;
    let max_delta = max(abs(delta.r), max(abs(delta.g), abs(delta.b)));
    let alpha = sample.a;

    let edge_energy = smoothstep(0.08, 0.18, max_delta) * (0.25 + beat * 0.45 + impact * 0.25);
    let glow = mix(primary_color, secondary_color, frame_uv.x) * edge_energy * 0.18;
    let color = sample.rgb + glow;
    return BpmSpriteLayer(color, alpha);
}

fn dance_frame(global_beat: u32) -> u32 {
    let slot = global_beat % 8u;
    if slot == 0u { return 1u; }
    if slot == 1u { return 3u; }
    if slot == 2u { return 6u; }
    if slot == 3u { return 8u; }
    if slot == 4u { return 11u; }
    if slot == 5u { return 14u; }
    if slot == 6u { return 17u; }
    return 20u;
}

fn staggered_frame(step_index: u32) -> u32 {
    let cycle = step_index / 3u;
    let phase = step_index % 3u;
    let base = cycle * 2u;
    if phase == 0u { return base % ACTIVE_SPRITE_FRAMES; }
    if phase == 1u { return (base + 1u) % ACTIVE_SPRITE_FRAMES; }
    return base % ACTIVE_SPRITE_FRAMES;
}

fn fighter_shadow(p: vec2<f32>, center: vec2<f32>, width_value: f32, strength: f32) -> f32 {
    let dx = (p.x - center.x) / width_value;
    let dy = (p.y - center.y) / 0.06;
    return exp(-(dx * dx * 2.6 + dy * dy * 5.2)) * strength;
}

fn palette_reduce(color: vec3<f32>, levels: f32) -> vec3<f32> {
    return floor(max(color, vec3<f32>(0.0)) * levels) / levels;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let resolution_y = max(scene.resolution.y, 1.0);
    let aspect = scene.resolution.x / resolution_y;
    let virtual_resolution = vec2<f32>(pixel_scale() * aspect, pixel_scale());
    let pixel_uv = (floor(in.uv * virtual_resolution) + vec2<f32>(0.5, 0.5)) / virtual_resolution;
    let p = vec2<f32>((pixel_uv.x * 2.0 - 1.0) * aspect, pixel_uv.y * 2.0 - 1.0);

    let low = audio_value(AUDIO_LOW);
    let mid = audio_value(AUDIO_MID);
    let high = audio_value(AUDIO_HIGH);
    let rms = audio_value(AUDIO_RMS);
    let beat = audio_value(AUDIO_BEAT);
    let impact = audio_value(AUDIO_IMPACT);
    let flux = audio_value(AUDIO_FLUX);
    let brightness = audio_value(AUDIO_BRIGHTNESS);
    let progress = timeline_progress();
    let horizon = arena_horizon(progress);

    var base = render_sky(p, progress, rms, flux, brightness);
    var emission = vec3<f32>(0.0);

    let sun_center = vec2<f32>(0.0, 0.32 + progress * 0.06);
    emission += render_sun_disc(p, sun_center, progress, brightness);

    let back_skyline = render_skyline_layer(
        p,
        horizon - 0.02,
        8.0,
        0.18,
        0.42,
        scene.time * 0.01,
        1.0,
        vec3<f32>(0.02, 0.03, 0.06),
        primary_neon_color() * 0.55,
        brightness,
    );
    let front_skyline = render_skyline_layer(
        p,
        horizon - 0.04,
        11.0,
        0.12,
        0.3,
        -scene.time * 0.014,
        2.0,
        vec3<f32>(0.04, 0.03, 0.07),
        secondary_neon_color() * 0.65,
        brightness,
    );
    base += back_skyline + front_skyline;

    emission += render_billboard(
        p,
        vec2<f32>(-0.82, horizon + 0.25),
        vec2<f32>(0.12, 0.08),
        primary_neon_color(),
        high,
    );
    emission += render_billboard(
        p,
        vec2<f32>(0.82, horizon + 0.28),
        vec2<f32>(0.14, 0.09),
        secondary_neon_color(),
        flux,
    );

    emission += render_rain(p, high, rain_amount());
    base += render_floor(p, horizon, low, high, progress);

    let kick_count = u32(floor(max(audio_value(AUDIO_KICK_COUNT), 0.0) + 0.5));
    let dancer_center = vec2<f32>(0.0, horizon - 0.2);
    let ring_center = vec2<f32>(0.0, 0.1 + progress * 0.04);
    let shadow_center_y = horizon - 0.28;
    base = mix(base, vec3<f32>(0.0), fighter_shadow(p, vec2<f32>(dancer_center.x, shadow_center_y), 0.22, 0.34));
    base += render_progress_ring(p, ring_center, progress, beat, impact);

    let random_clock = scene.time * 2.6
        + sin(scene.time * 0.83 + 1.7) * 0.55
        + sin(scene.time * 1.91 + 4.2) * 0.22;
    let random_window = floor(random_clock);
    let step_index = u32(max(random_window, 0.0));
    let frame_index = staggered_frame(step_index);
    let dancer = render_sprite_sheet_character(
        p,
        dancer_center,
        frame_index,
        vec2<f32>(DANCER_HALF_WIDTH, DANCER_HALF_HEIGHT),
        primary_neon_color(),
        secondary_neon_color(),
        beat,
        impact,
    );
    base = mix(base, dancer.color, dancer.alpha);

    let base_quantized = palette_reduce(base, 7.0);
    var color = base_quantized + emission * neon_gain();
    let scan = 0.95 + 0.05 * sin(pixel_uv.y * virtual_resolution.y * PI * 1.15);
    let vignette = clamp(1.18 - dot(pixel_uv - vec2<f32>(0.5, 0.5), pixel_uv - vec2<f32>(0.5, 0.5)) * 1.4, 0.65, 1.15);
    let dither = (hash21(pixel_uv * virtual_resolution + vec2<f32>(scene.time * 7.0, 13.0)) - 0.5) * scene.dither_strength * 0.05;
    color = color * scan * vignette + vec3<f32>(dither);

    let bg = #color "scene.bg_color";
    return encode_output_alpha(color, bg.a);
}


