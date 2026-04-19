// ---------------------------------------------------------------------------
// Sprite Sheet helpers — common operations for extracting and rendering sprites.
// Usage: #import <bpm/sprite_utils.wgsl>
// ---------------------------------------------------------------------------

struct BpmSpriteLayer {
    color: vec3<f32>,
    alpha: f32,
}

fn get_sprite_cell_size(cols: u32, rows: u32) -> vec2<f32> {
    return vec2<f32>(1.0 / f32(cols), 1.0 / f32(rows));
}

fn get_sprite_frame_origin(frame_index: u32, cols: u32, rows: u32, total_frames: u32) -> vec2<f32> {
    let index = frame_index % total_frames;
    return vec2<f32>(
        f32(index % cols) / f32(cols),
        f32(index / cols) / f32(rows),
    );
}

fn get_sprite_frame_rect(frame_index: u32, cols: u32, rows: u32, total_frames: u32) -> vec4<f32> {
    let origin = get_sprite_frame_origin(frame_index, cols, rows, total_frames);
    let cell = get_sprite_cell_size(cols, rows);
    return vec4<f32>(origin, origin + cell);
}

fn get_sprite_safe_uv(tex: texture_2d<f32>, frame_rect: vec4<f32>, frame_uv: vec2<f32>) -> vec2<f32> {
    let texel = 1.0 / vec2<f32>(textureDimensions(tex, 0));
    let min_uv = frame_rect.xy + texel * 0.5;
    let max_uv = frame_rect.zw - texel * 0.5;
    return mix(min_uv, max_uv, clamp(frame_uv, vec2<f32>(0.0), vec2<f32>(1.0)));
}

fn get_sprite_frame_background(tex: texture_2d<f32>, sam: sampler, frame_rect: vec4<f32>, frame_uv: vec2<f32>) -> vec3<f32> {
    let margin = vec2<f32>(0.08, 0.08);
    let tl = textureSampleLevel(tex, sam, get_sprite_safe_uv(tex, frame_rect, vec2<f32>(margin.x, margin.y)), 0.0).rgb;
    let tr = textureSampleLevel(tex, sam, get_sprite_safe_uv(tex, frame_rect, vec2<f32>(1.0 - margin.x, margin.y)), 0.0).rgb;
    let bl = textureSampleLevel(tex, sam, get_sprite_safe_uv(tex, frame_rect, vec2<f32>(margin.x, 1.0 - margin.y)), 0.0).rgb;
    let br = textureSampleLevel(tex, sam, get_sprite_safe_uv(tex, frame_rect, vec2<f32>(1.0 - margin.x, 1.0 - margin.y)), 0.0).rgb;
    return mix(mix(tl, tr, frame_uv.x), mix(bl, br, frame_uv.x), frame_uv.y);
}
